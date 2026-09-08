"""Do not confuse zero-duration public readback with physical restoration."""
from copy import deepcopy
import unittest

from Audit_HeatDriveECC_AdvancedSeedControl import SEED_COMMITS, summarize, validate_isolation
from Audit_HeatDriveECC_C200RestoredSignals import compare
from test_op_api_isolation import sample


def fixture(mode):
    data = sample()
    data.update(execution_commit=SEED_COMMITS[mode], seed_mode=mode)
    data['low_seed'] = dict(time_s=2000.001, memory_time_s=2000.001, temperature_K=340, memory=7.25)
    if mode == 'zero_duration':
        data['high_seed'] = dict(time_s=2000.001, memory_time_s=2000.001, temperature_K=400, memory=7.25)
    row = data['cases'][3]
    row.update(state_before=0, state_after=0 if mode == 'zero_duration' else 400)
    row['observed']['temperature_K'] = [340, 340]
    return data


class TestAdvancedSeedControl(unittest.TestCase):
    def test_isolation_modes(self):
        for mode in SEED_COMMITS:
            validate_isolation(fixture(mode), mode)

    def test_readback_not_temperature(self):
        mode = 'zero_duration_advanced_donor'; data = fixture(mode)
        data['cases'][3]['observed']['temperature_K'] = [400, 400]
        with self.assertRaises(ValueError): validate_isolation(data, mode)

    def test_donor_must_have_advanced(self):
        mode = 'zero_duration_advanced_donor'; data = fixture(mode)
        data['high_seed'] = deepcopy(fixture('zero_duration')['high_seed'])
        with self.assertRaises(ValueError): validate_isolation(data, mode)

    def test_no_seed_scope_promotion(self):
        mode = 'zero_duration'; data = fixture(mode); data['production_recovery_allowed'] = True
        with self.assertRaises(ValueError): validate_isolation(data, mode)

    def test_tolerance_pass_is_not_bitwise_pass(self):
        result = summarize([dict(comparisons=[compare([1], [1 + 1e-12])] * 2, exact=[False, False])])
        self.assertTrue(result['all_observations_pass'])
        self.assertEqual(result['exact_one_step_groups'], 0)
        self.assertLess(result['max_scaled_error'], 1)


if __name__ == '__main__':
    unittest.main()
