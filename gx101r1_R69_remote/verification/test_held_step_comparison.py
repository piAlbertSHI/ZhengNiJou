import copy
import unittest
from Compare_HeatDriveECC_HeldSteps import compare, trend, CHAMBERS, BUFFERS


class HeldStepComparisonTests(unittest.TestCase):
    def fixture(self):
        results = []
        for count in (41, 81, 161):
            rows = [dict(block_path='heatdrive_ecc_coupled_se21/' + name,
                         mass_limit_kg=1e-15, energy_limit_J=1e-8,
                         mass_max_abs_residual_kg=2e-15, energy_max_abs_residual_J=2e-8,
                         mass_closure_pass=False, energy_closure_pass=False,
                         mass_endpoint_change_kg=0, energy_endpoint_change_J=0,
                         simpson_mass_max_abs_residual_kg=2e-15,
                         simpson_energy_max_abs_residual_J=2e-8) for name in CHAMBERS | BUFFERS]
            results.append(dict(evidence_audit_pass=True, observed_interval_s=[0, .04],
                exported_sample_count=count, initial_coordinate_audit={'strict_initial_coordinate_gate': True},
                compiled_inventory_gate=True, compiled_algebraic_loops=0,
                production_recovery_allowed=False, table4_reproduction_claim=False,
                local_balances=rows, passing_local_balances=0, local_balance_gate=False))
        return results

    def test_decay_does_not_promote_science_pass(self):
        r = trend([8e-13, 4e-13, 2e-13])
        self.assertEqual(r['empirical_residual_decay_exponents'], [1, 1])
        self.assertFalse(r['extrapolated_pass'])
        c = compare(self.fixture())
        self.assertEqual(c['measured_local_balance_pass'], [False]*3)
        self.assertFalse(c['unique_root_cause_verified'])

    def test_nonmonotone_and_zero_values_are_explicit(self):
        self.assertFalse(trend([1, 2, 1])['monotone_nonincreasing'])
        self.assertEqual(trend([0, 1, 0])['empirical_residual_decay_exponents'], [None, None])
        for values in ([1, 2], [1, float('nan'), 1], [-1, 1, 1]):
            with self.assertRaises(ValueError): trend(values)

    def test_changed_gates_or_missing_component_are_rejected(self):
        for mutation in ('threshold', 'duplicate', 'falsepass', 'count'):
            r = copy.deepcopy(self.fixture())
            if mutation == 'threshold': r[1]['local_balances'][0]['mass_limit_kg'] = 1e-12
            elif mutation == 'duplicate': r[1]['local_balances'][0] = r[1]['local_balances'][1]
            elif mutation == 'falsepass': r[1]['local_balance_gate'] = True
            else: r[1]['exported_sample_count'] = 41
            with self.assertRaises(ValueError): compare(r)
