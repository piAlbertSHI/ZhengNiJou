import copy
import unittest

import numpy as np

from Audit_HeatDriveECC_TLDomainInventory import (
    DOMAIN, PIPE, SETTINGS, density_table, literal_vector, resolve_domains,
)


def topology():
    blocks, vertices = [], []
    for name, source, ports, kind in [
        ("m/Pipe1", PIPE, 2, "SimscapeBlock"),
        ("m/Settings1", SETTINGS, 1, "SimscapeBlock"),
        ("m/Pipe2", PIPE, 2, "SimscapeBlock"),
        ("m/Settings2", SETTINGS, 1, "SimscapeBlock"),
        ("m/SharedSubsystem", "", 2, "SubSystem"),
    ]:
        indices = []
        for k in range(ports):
            vertices.append(dict(key=f"{name}:{k}", block_path=name, domain=DOMAIN))
            indices.append(len(vertices))
        blocks.append(dict(block_path=name, source_file=source, vertex_indices=indices, block_type=kind))
    return dict(schema="heatdrive_ecc_tl_connectivity_v2", source_model_modified=False,
                domain=DOMAIN, vertices=vertices, blocks=blocks,
                edges=[dict(a=a, b=b, kind="physical_wire_net") for a, b in [(1, 3), (4, 6), (2, 7), (5, 8)]])


def parameters():
    return dict(table_dimensions="1", rho_parameterization_1D="1",
                T_TLU="[300;400]", T_TLU_unit="K", T_min_1D="300", T_max_1D="400",
                rho_TLU_4="[1000;900]", rho_TLU_4_unit="kg/m^3",
                p_min_1D="1", p_max_1D="4", p_min_1D_unit="MPa", p_max_1D_unit="MPa",
                p_ref_4="1", p_ref_4_unit="MPa", beta_const_4="2", beta_const_4_unit="GPa")


class TLDomainTests(unittest.TestCase):
    def test_shared_subsystem_does_not_merge_channels(self):
        assigned, count = resolve_domains(topology())
        self.assertEqual(count, 2)
        self.assertEqual(assigned["m/Pipe1"], "m/Settings1")
        self.assertEqual(assigned["m/Pipe2"], "m/Settings2")
        self.assertNotIn("m/SharedSubsystem", assigned)

    def test_cross_fluid_wire_rejected(self):
        data = topology()
        data["edges"].append(dict(a=2, b=5, kind="physical_wire_net"))
        with self.assertRaisesRegex(ValueError, "Two property settings"):
            resolve_domains(data)

    def test_missing_branch_rejected(self):
        data = topology()
        data["edges"].pop()
        with self.assertRaisesRegex(ValueError, "isolated"):
            resolve_domains(data)

    def test_unregistered_primitive_rejected(self):
        data = topology()
        data["blocks"][0]["source_file"] = "unknown.multi_channel_device"
        with self.assertRaisesRegex(ValueError, "Unregistered"):
            resolve_domains(data)

    def test_wrong_port_count_rejected(self):
        data = topology()
        data["blocks"][0]["vertex_indices"] = [1]
        with self.assertRaisesRegex(ValueError, "port count"):
            resolve_domains(data)

    def test_duplicate_and_mixed_domain_rejected(self):
        for mutate in (
            lambda d: d["blocks"].append(copy.deepcopy(d["blocks"][0])),
            lambda d: d["vertices"][0].update(domain="foundation.thermal.thermal"),
            lambda d: d.update(schema="heatdrive_ecc_tl_connectivity_v1"),
        ):
            data = topology()
            mutate(data)
            with self.assertRaises(ValueError):
                resolve_domains(data)

    def test_scalar_vertex_index_from_matlab_json(self):
        data = topology()
        data["blocks"][1]["vertex_indices"] = 3
        self.assertEqual(resolve_domains(data)[1], 2)

    def test_literal_parser_no_eval(self):
        np.testing.assert_equal(literal_vector("[1; -2.5e+2, .03]"), [1, -250, .03])
        for text in ("ones(2)", "1:3", "[NaN;1]", "[1,Inf]", "1;system('x')", "", "1e999"):
            with self.assertRaises(ValueError):
                literal_vector(text)

    def test_pressure_grid_bilinear_not_direct_exponential(self):
        lookup = density_table(parameters())
        grid = np.logspace(6, np.log10(4e6), 30)
        pressure = .35 * grid[10] + .65 * grid[11]
        expected = 950 * (.35 * np.exp((grid[10] - 1e6) / 2e9)
                          + .65 * np.exp((grid[11] - 1e6) / 2e9))
        self.assertAlmostEqual(float(lookup([[350, pressure]])[0]), expected, places=10)
        self.assertGreater(abs(expected - 950 * np.exp((pressure - 1e6) / 2e9)), 1e-8)

    def test_bounds_and_unsupported_modes_fail(self):
        with self.assertRaises(ValueError):
            density_table(parameters())([[290, 2e6]])
        for key, value in [("table_dimensions", "2"), ("rho_parameterization_1D", "2"),
                           ("T_TLU_unit", "degC"), ("beta_const_4", "0"),
                           ("T_min_1D", "310"), ("rho_TLU_4", "[1000;-1]")]:
            p = parameters()
            p[key] = value
            with self.assertRaises(ValueError):
                density_table(p)


if __name__ == "__main__":
    unittest.main()
