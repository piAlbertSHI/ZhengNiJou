import unittest
from pathlib import Path
from Audit_HeatDriveECC_CompiledInventoryStates import decode_tags, component_inventory_preserved


class CompiledInventoryStateTests(unittest.TestCase):
    def tags(self, differential='FALSE'):
        keys = ['isStateValue', 'isDifferential', 'isRetained', 'context']
        return dict(tag_names=keys, tag_values=[keys, ['TRUE', differential, 'TRUE', 'Simscape']])

    def test_retained_is_not_differential(self):
        r = decode_tags(self.tags())
        self.assertTrue(r['isRetained']); self.assertFalse(r['isDifferential'])

    def test_string_false_not_truthy(self):
        self.assertFalse(decode_tags(self.tags())['isDifferential'])
        self.assertTrue(decode_tags(self.tags('TRUE'))['isDifferential'])

    def test_unknown_boolean_rejected(self):
        with self.assertRaises(ValueError): decode_tags(self.tags('true'))

    def test_duplicate_tag_rejected(self):
        r = self.tags(); r['tag_values'][0][1] = 'isRetained'
        with self.assertRaises(ValueError): decode_tags(r)

    def test_algebraic_inventory_cannot_pass(self):
        rows = [dict(block_name='chamber', variable_name=v, isDifferential=v in ('T_I', 'p_I'), isRetained=True)
                for v in ('stored_mass', 'stored_energy', 'T_I', 'p_I')]
        self.assertFalse(component_inventory_preserved(rows, {'chamber'}))
        for row in rows: row['isDifferential'] = row['variable_name'] in ('stored_mass', 'stored_energy')
        self.assertTrue(component_inventory_preserved(rows, {'chamber'}))
        with self.assertRaises(ValueError): component_inventory_preserved(rows[:-1], {'chamber'})

    def test_priority_variant_has_identical_equations(self):
        root = Path(__file__).resolve().parent
        a = (root/'simscape_inventory/+ecc_inventory/conservative_chamber.ssc').read_text(encoding='utf-8')
        b = (root/'simscape_inventory_priorities/+ecc_inventory_priority/conservative_chamber.ssc').read_text(encoding='utf-8')
        expected = a.replace('priority = priority.high', 'priority = priority.low')
        expected = expected.replace("stored_mass = {0.0016, 'kg'};", "stored_mass = {value = {0.0016, 'kg'}, priority = priority.high};")
        expected = expected.replace("stored_energy = {160, 'J'};", "stored_energy = {value = {160, 'J'}, priority = priority.high};")
        self.assertEqual(expected, b)

    def test_specific_variant_only_rewrites_inventory_relations(self):
        root = Path(__file__).resolve().parent
        original = (root/'simscape_inventory/+ecc_inventory/conservative_chamber.ssc').read_text(encoding='utf-8')
        variant = (root/'simscape_inventory_specific/+ecc_inventory_specific/conservative_chamber.ssc').read_text(encoding='utf-8')
        expected = original.replace('stored_mass == volume * rho_I;', 'rho_I == stored_mass / volume;')
        expected = expected.replace('stored_energy == stored_mass * u_I;', 'u_I == stored_energy / stored_mass;')
        self.assertEqual(expected, variant)

    def test_specific_inventory_equivalence_on_positive_mass_domain(self):
        for volume in (1e-6, 1.6084954386379741e-6, 1e-4):
            for rho in (700., 997., 1100.):
                for u in (-1e4, 0., 1e5):
                    mass = volume*rho
                    energy = mass*u
                    self.assertAlmostEqual(mass/volume, rho, places=10)
                    self.assertAlmostEqual(energy/mass, u, places=9)


if __name__ == '__main__': unittest.main()
