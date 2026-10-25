import copy
from pathlib import Path
import unittest

import numpy as np

from Reference_HeatDriveECC_CaloricCoupling import CaloricFluid, CaloricCycle, compatibility, reduced_phase_rates
from Run_HeatDriveECC_CaloricCycle import load_network, simulate


class CaloricTests(unittest.TestCase):
    def setUp(self):
        self.fluid = CaloricFluid([270., 300., 330., 410.], [4100., 4200., 4190., 4250.], [.5, .6, .61, .7], 998.)

    def test_reference_and_inverse_at_knots_and_interior(self):
        self.assertAlmostEqual(float(self.fluid.enthalpy(303.15)), 0., places=8)
        t = np.r_[self.fluid.t, np.linspace(270, 410, 500)]
        np.testing.assert_allclose(self.fluid.temperature(self.fluid.enthalpy(t)), t, atol=1e-12, rtol=0)

    def test_integrated_cp_not_cp_times_temperature(self):
        f = self.fluid
        derivative = (f.enthalpy(np.array([280., 310., 390.])+1e-4)-f.enthalpy(np.array([280., 310., 390.])-1e-4))/.0002
        np.testing.assert_allclose(derivative, np.interp([280., 310., 390.], f.t, f.cp), rtol=1e-9)
        self.assertGreater(abs(float(f.enthalpy(400.))-float(np.interp(400., f.t, f.cp))*(400.-303.15)), 100.)

    def test_bounds_rejected_not_clipped(self):
        for t in (269., 411., np.nan):
            with self.assertRaises(ValueError):
                self.fluid.enthalpy(t)
        for h in (self.fluid.h_knots[0]-1, self.fluid.h_knots[-1]+1, np.nan):
            with self.assertRaises(ValueError):
                self.fluid.temperature(h)

    def test_invalid_tables_rejected(self):
        for cp in ([1., 0.], [1., np.nan]):
            with self.assertRaises(ValueError):
                CaloricFluid([300., 310.], cp, [1., 1.], 1000.)


class CoupledTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # These are actual sealed input parameters, not a saved state or OP.
        cls.model, cls.contract = load_network(
            Path("C:/tmp/se21_conservative_transport_r1_20261025"),
            Path("C:/tmp/se21_single_pipe_global_ode3_ledger_r1_20261025/single_pipe_execution.json"),
            Path("C:/tmp/se21_v74_layered_cold_20c_r1_20261025/conservative/inventory_metadata.json"))

    def varied_state(self):
        m = self.model
        y = m.initial_state()
        for name, item in m.components.items():
            temperature = np.linspace(295., 335., item["nodes"])
            y[m.slices[name]] = m.masses[name]*m.fluids[item["fluid"]].enthalpy(temperature)
        y[m.slices["solid_a"]] = m.capacities["SMA"]*np.linspace(5., 50., m.n)
        y[m.slices["solid_r"]] = m.capacities["SE"]*np.linspace(-15., 5., m.n)
        y[m.slices["phase_a"]] = np.linspace(.2, .7, m.n)
        y[m.slices["phase_r"]] = np.linspace(.1, .9, m.n)
        y[m.slices["buffer_mass_change"]] = [.002, -.002]
        masses = np.array([.1, .102, .098])
        y[m.slices["buffer_H"]] = masses*np.array([m.fluids[k].enthalpy(t) for k, t in
                                                  zip(("SMA", "SE", "SE"), (315., 320., 280.))])
        y[m.slices["bus_E"]] = m.bus_capacity*np.array([40., 3., -10., -8.])
        return y

    def test_force_displacement_and_power_cancel_without_fudged_heat(self):
        m = self.model
        p = m.unpack(self.varied_state())
        for stage in (1, 2, 3, 4):
            mech = compatibility(p["xa"], p["xr"], m.c["geometry"], m.c["materials"])
            rates = reduced_phase_rates(p["Ta"], p["Tr"], p["xa"], p["xr"], mech, m.c["materials"], m.c["kinetics"], stage)
            mech = compatibility(p["xa"], p["xr"], m.c["geometry"], m.c["materials"], rates)
            self.assertLess(abs(mech["force_residual_N"]), 1e-9)
            self.assertLess(abs(mech["displacement_residual_m"]), 1e-15)
            self.assertLess(abs(mech["displacement_rate_residual_m_s"]), 1e-14)
            self.assertLess(abs(mech["mechanical_a_W"].sum()+mech["mechanical_r_W"].sum()), 1e-9)

    def test_total_mass_energy_rates_telescope_all_four_stages(self):
        m, y = self.model, self.varied_state()
        weights = np.zeros(m.size)
        for key in (*m.components, "solid_a", "solid_r", "buffer_H", "bus_E"):
            weights[m.slices[key]] = 1.
        for material, key in (("SMA", "phase_a"), ("SE", "phase_r")):
            weights[m.slices[key]] = -m.c["solid_mass_kg"][material]*m.c["materials"][material]["Delta_h_J_per_kg"]/m.n
        for stage in (1, 2, 3, 4):
            rate, _, _ = m.evaluate(y, stage)
            external = rate[m.slices["ledgers"]][:3].sum()
            self.assertLess(abs(weights@rate-external), 2e-9)
            self.assertEqual(rate[m.slices["buffer_mass_change"]].sum(), 0.)

    def test_chambers_swap_mass_but_never_mix_fluids(self):
        m, y = self.model, self.varied_state()
        for stage, expected in ((1, [0., 0.]), (2, [.0032, -.0032]), (3, [0., 0.]), (4, [-.0032, .0032])):
            d, _, _ = m.evaluate(y, stage)
            np.testing.assert_allclose(d[m.slices["buffer_mass_change"]], expected, rtol=0, atol=0)
        self.assertEqual(m.components["hhex_a"]["fluid"], "SMA")
        self.assertEqual(m.components["hhex_r"]["fluid"], "SE")

    def test_stage_change_is_pure_and_keeps_one_bed_inventory(self):
        m, y = self.model, self.varied_state()
        old = y.copy()
        for stage in (1, 2, 3, 4):
            m.evaluate(y, stage)
            np.testing.assert_array_equal(y, old)
        self.assertEqual(m.slices["bed_a"].stop-m.slices["bed_a"].start, 21)
        self.assertEqual(m.slices["bed_r"].stop-m.slices["bed_r"].start, 21)

    def test_dwell_retains_and_exchanges_SE_fluid_not_constant_temperature(self):
        m = self.model
        y = m.initial_state()
        y[m.slices["solid_r"]] = m.capacities["SE"]*10.
        for stage in (1, 3):
            d, _, _ = m.evaluate(y, stage)
            self.assertGreater(d[m.slices["bed_r"]].min(), 0.)
            self.assertAlmostEqual(d[m.slices["bed_r"]].sum(), m.c["se_natural_h_W_m2K"]*
                                   m.components["bed_r"]["surface_m2"]*10., places=10)

    def test_phase_invalidity_and_chamber_exhaustion_are_rejected(self):
        m = self.model
        for key, value in (("phase_a", -1e-5), ("phase_r", 1.01), ("buffer_mass_change", -.2)):
            y = m.initial_state()
            y[m.slices[key]] = value
            with self.assertRaises(ValueError):
                m.evaluate(y, 1)

    def test_uniform_ambient_equilibrium_when_external_drive_off(self):
        c = copy.deepcopy(self.contract)
        c["source_K"] = c["ambient_K"]
        m = CaloricCycle(c, self.model.fluids)
        for stage in (1, 2, 3, 4):
            rate = m.evaluate(m.initial_state(), stage)[0]
            # An isothermal piston still transfers mass in stages 2/4.
            # Only the thermal and phase coordinates are stationary.
            thermal = np.ones(m.size, dtype=bool)
            thermal[m.slices["buffer_mass_change"]] = False
            np.testing.assert_allclose(rate[thermal], 0., rtol=0, atol=0)

    def test_latent_sign_and_initial_cold_geometry(self):
        m = self.model
        y = m.initial_state()
        p = m.unpack(y)
        for name in ("Ta", "Tr", "buffer_T", "bus_T"):
            np.testing.assert_array_equal(p[name], np.full_like(p[name], 303.15))
        self.assertEqual(float(m.inventory_energy(y)), -m.c["solid_mass_kg"]["SMA"]*10000.)
        # Heating SMA consumes latent energy (dxM<0), loading SE releases it.
        y[m.slices["solid_a"]] += 80.*m.capacities["SMA"]
        rate, _, _ = m.evaluate(y, 1)
        self.assertLess(rate[m.slices["ledgers"]][3], 0.)


if __name__ == "__main__":
    unittest.main()
