"""Independent CV boundary reconstruction for the reduced thermal graph.

No pressure, wall inventory or Qian material qualification is supplied. Boundary
powers are rebuilt from physical ports, not obtained by summing cell RHS values.
The solid inventory includes -m*L*xM, consistent with this reduced energy law.
"""
import numpy as np

from Reference_HeatDriveECC_CaloricCoupling import compatibility, reduced_phase_rates
from Reference_HeatDriveECC_TwoWayPhase import shared_surface_rates


class LocalBoundaries:
    def __init__(self, model):
        self.model = model
        self.names = (*model.components, "SMA_total", "SE_total", "water_return",
                      "hot_chamber", "cold_chamber", "bus_source", "bus_hot", "bus_cold", "load_sensor")
        self.index = {name: i for i, name in enumerate(self.names)}
        self.energy_weights = np.zeros((len(self.names), model.size))
        self.mass_weights = np.zeros_like(self.energy_weights)
        for name in model.components:
            self.energy_weights[self.index[name], model.slices[name]] = 1.
        for name, material, solid, phase in (("SMA_total", "SMA", "solid_a", "phase_a"),
                ("SE_total", "SE", "solid_r", "phase_r")):
            row = self.energy_weights[self.index[name]]
            row[model.slices[solid]] = 1.
            row[model.slices[phase]] = -model.c["solid_mass_kg"][material]*model.c["materials"][material]["Delta_h_J_per_kg"]/model.n
        for j, name in enumerate(("water_return", "hot_chamber", "cold_chamber")):
            self.energy_weights[self.index[name], model.slices["buffer_H"].start+j] = 1.
            if j:
                self.mass_weights[self.index[name], model.slices["buffer_mass_change"].start+j-1] = 1.
        for j, name in enumerate(("bus_source", "bus_hot", "bus_cold", "load_sensor")):
            self.energy_weights[self.index[name], model.slices["bus_E"].start+j] = 1.
        self.edges = [
            ("source_heat", None, "bus_source"), ("hot_ambient_heat", None, "bus_hot"),
            ("cold_ambient_leak", None, "bus_cold"), ("imposed_load", None, "load_sensor"),
            ("load_to_cold_bus", "load_sensor", "bus_cold"),
            ("SMA_to_fluid", "SMA_total", "bed_a"), ("SE_to_fluid", "SE_total", "bed_r"),
            ("source_bus_to_shex", "bus_source", "shex"), ("hot_bus_to_hhex_a", "bus_hot", "hhex_a"),
            ("hot_bus_to_hhex_r", "bus_hot", "hhex_r"), ("cold_bus_to_chex", "bus_cold", "chex"),
            ("SMA_to_SE_work", "SMA_total", "SE_total"),
            ("water_to_shex", "water_return", "shex"), ("shex_to_SMA", "shex", "bed_a"),
            ("water_to_hhex_a", "water_return", "hhex_a"), ("hhex_a_to_SMA", "hhex_a", "bed_a"),
            ("SMA_to_water", "bed_a", "water_return"),
            ("cold_to_SE", "cold_chamber", "bed_r"), ("SE_to_hhex_r", "bed_r", "hhex_r"),
            ("hhex_r_to_hot", "hhex_r", "hot_chamber"),
            ("hot_to_SE", "hot_chamber", "bed_r"), ("SE_to_chex", "bed_r", "chex"),
            ("chex_to_cold", "chex", "cold_chamber")]
        self.edge_index = {row[0]: i for i, row in enumerate(self.edges)}
        self.incidence = np.zeros((len(self.names), len(self.edges)))
        for j, (_, source, target) in enumerate(self.edges):
            if source is not None:
                self.incidence[self.index[source], j] = -1.
            self.incidence[self.index[target], j] = 1.

    @staticmethod
    def outlet(h, direction):
        """MC outlet has equal forward/back slopes: reconstruct independently.

        Fixed physical coordinates are never reversed in stored state. Only
        the outlet formula changes with flow sign; cell conduction ends insulated.
        """
        return 1.5*h[-1]-.5*h[-2] if direction > 0 else 1.5*h[0]-.5*h[1]

    def boundary_rates(self, y, stage):
        if stage not in (1, 2, 3, 4):
            raise ValueError("Unknown stage")
        m, c = self.model, self.model.c
        p = m.unpack(y)
        energy, mass = np.zeros(len(self.edges)), np.zeros(len(self.edges))

        def put(name, power, flow=0.):
            j = self.edge_index[name]
            energy[j], mass[j] = power, flow

        b = p["bus_T"]
        put("source_heat", c["source_UA_W_K"]*(c["source_K"]-b[0]))
        put("hot_ambient_heat", c["ambient_UA_W_K"]*(c["ambient_K"]-b[1]))
        put("cold_ambient_leak", c["chex_leak_UA_W_K"]*(c["ambient_K"]-b[2]))
        put("imposed_load", c["cold_load_W"])
        put("load_to_cold_bus", c["cold_load_UA_W_K"]*(b[3]-b[2]))
        for name, material, solid in (("bed_a", "SMA", "Ta"), ("bed_r", "SE", "Tr")):
            item = c["fluid_components"][name]
            tf = p["T"][name]
            k = m.fluids[material].conductivity(tf)
            ua = (3.66*k*item["surface_m2"]/item["Dh_m"] if material == "SMA" or stage in (2, 4)
                  else np.full(m.n, c["se_natural_h_W_m2K"]*item["surface_m2"]))
            put(material+"_to_fluid", float(np.dot(ua, p[solid]-tf)/m.n))
        for name, edge in (("shex", "source_bus_to_shex"), ("hhex_a", "hot_bus_to_hhex_a"),
                ("hhex_r", "hot_bus_to_hhex_r"), ("chex", "cold_bus_to_chex")):
            item = c["fluid_components"][name]
            put(edge, item["UA_W_K"]*(b[item["bus_index"]]-p["T"][name].mean()))
        mechanical = compatibility(p["xa"], p["xr"], c["geometry"], c["materials"])
        if c.get("phase_operator") == "stage_free_shared_surface":
            rates = shared_surface_rates(p, mechanical, c)
        else:
            rates = reduced_phase_rates(p["Ta"], p["Tr"], p["xa"], p["xr"], mechanical,
                                        c["materials"], c["kinetics"], stage)
        # Independent common-displacement velocity, not cell energy derivative.
        g, a, r = c["geometry"], c["materials"]["SMA"], c["materials"]["SE"]
        compliance = g["L_a_m"]*(g["S_r_m2"]/g["S_a_m2"])/a["E_m_Pa"]+g["L_r_m"]/r["E_m_Pa"]
        dsigma = -(g["L_a_m"]*a["epsilon_T"]*np.mean(rates[0])+g["L_r_m"]*r["epsilon_T"]*np.mean(rates[1]))/compliance
        velocity = g["L_r_m"]*(r["epsilon_T"]*np.mean(rates[1])+dsigma/r["E_m_Pa"])
        put("SMA_to_SE_work", mechanical["sigma_r_Pa"]*g["S_r_m2"]*velocity)
        ma, mr = c["mass_flow_kg_s"]["SMA"], c["mass_flow_kg_s"]["SE"]
        hx = "shex" if stage in (1, 2) else "hhex_a"
        put("water_to_"+hx, ma*p["buffer_h"][0], ma)
        put(hx+"_to_SMA", ma*self.outlet(p["h"][hx], 1), ma)
        put("SMA_to_water", ma*self.outlet(p["h"]["bed_a"], 1 if stage in (1, 2) else -1), ma)
        if stage == 2:
            put("cold_to_SE", mr*p["buffer_h"][2], mr)
            put("SE_to_hhex_r", mr*self.outlet(p["h"]["bed_r"], -1), mr)
            put("hhex_r_to_hot", mr*self.outlet(p["h"]["hhex_r"], 1), mr)
        elif stage == 4:
            put("hot_to_SE", mr*p["buffer_h"][1], mr)
            put("SE_to_chex", mr*self.outlet(p["h"]["bed_r"], 1), mr)
            put("chex_to_cold", mr*self.outlet(p["h"]["chex"], 1), mr)
        if not np.isfinite(np.r_[energy, mass]).all():
            raise ValueError("Nonfinite reconstructed boundary flux")
        return energy, mass

    def residual(self, states, edge_energy, edge_mass):
        de = (states-states[0])@self.energy_weights.T
        dm = (states-states[0])@self.mass_weights.T
        return de-edge_energy@self.incidence.T, dm-edge_mass@self.incidence.T

    def contract(self):
        return {"CV_names": list(self.names),
            "edges": [{"name": name, "positive_from": source or "external", "positive_to": target,
                       "power_unit": "W", "flow_unit": "kg/s"} for name, source, target in self.edges],
            "inventory_energy": "fluid m*h; solid sensible-m*L*xM; buffer H; bus C*(T-Tref)",
            "flow_energy": "signed mdot*h at a single shared reconstructed physical port",
            "solid_latent_energy_not_double_counted": True,
            "insulated_component_end_conduction": True,
            "not_covered": ["individual-cell truncation error", "connecting pipe walls", "pressure/pump work",
                            "compressible EOS equivalence", "material calorimetry", "native SLX equivalence"],
            "global_cancellation_is_not_local_pass": True}


class ObservedCycle:
    """Append passive edge integrals without changing physical coordinates."""
    def __init__(self, model):
        self.base, self.boundaries = model, LocalBoundaries(model)
        self.c, self.slices = model.c, dict(model.slices)
        self.edge_count = len(self.boundaries.edges)
        self.size = model.size+2*self.edge_count
        self.controlled_size = model.size
        self.slices["boundary_energy"] = slice(model.size, model.size+self.edge_count)
        self.slices["boundary_mass"] = slice(model.size+self.edge_count, self.size)

    def initial_state(self):
        return np.r_[self.base.initial_state(), np.zeros(2*self.edge_count)]

    def unpack(self, y):
        return self.base.unpack(y[:self.base.size])

    def evaluate(self, y, stage):
        state = y[:self.base.size]
        derivative, physical, mechanical = self.base.evaluate(state, stage)
        energy, mass = self.boundaries.boundary_rates(state, stage)
        return np.r_[derivative, energy, mass], physical, mechanical

    def balance(self, y, initial):
        return self.base.balance(y[:self.base.size], initial[:self.base.size])
