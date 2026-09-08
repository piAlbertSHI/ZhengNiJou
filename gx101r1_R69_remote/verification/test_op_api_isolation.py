"""Negative controls for the isolated OP evidence auditor."""
from copy import deepcopy
import unittest

from Audit_HeatDriveECC_OPAPIIsolation import ARMS, COMMITS, validate


def sample():
    def observed(times, temperature=340, memory=7.25):
        return dict(time_s=times, memory_time_s=times, temperature_K=[temperature]*2, memory=[memory]*2)
    cases = []
    for name in ARMS:
        row = dict(name=name, computation_complete=name != ARMS[1],
                   error_message='strict model mismatch' if name == ARMS[1] else '',
                   target_temperature_K=400 if name == ARMS[1] else 340,
                   public_assignment_completed=name in ARMS[2:],
                   requested_memory=8.25 if name == ARMS[2] else 7.25,
                   state_before=7.25 if name == ARMS[2] else (340 if name == ARMS[3] else []),
                   state_after=8.25 if name == ARMS[2] else (400 if name == ARMS[3] else []))
        if name != ARMS[1]:
            row['observed'] = observed([2000.001, 2000.002], 400 if name == ARMS[3] else 340,
                                       8.25 if name == ARMS[2] else 7.25)
        cases.append(row)
    return dict(schema='heatdrive_ecc_op_api_isolation_v1', execution_commit=COMMITS['v2'],
                matlab_release='2025b', collection_complete=True, error_message='',
                production_model_loaded=False, production_checkpoint_loaded=False,
                production_recovery_allowed=False, cases=cases,
                low_seed=observed([2000, 2000.001]), high_seed=observed([2000, 2000.001], 400))


class TestOPAPIIsolation(unittest.TestCase):
    def test_expected_observations(self):
        validate(sample(), 'v2')

    def test_missing_and_duplicate_arms(self):
        data = sample(); data['cases'].pop()
        with self.assertRaises(ValueError): validate(data, 'v2')
        data = sample(); data['cases'][2] = deepcopy(data['cases'][0])
        with self.assertRaises(ValueError): validate(data, 'v2')

    def test_assignment_readback_not_physical_proof(self):
        data = sample(); data['cases'][3]['observed']['temperature_K'] = [340, 340]
        with self.assertRaises(ValueError): validate(data, 'v2')

    def test_inactive_memory_edit_rejected(self):
        data = sample(); data['cases'][2]['observed']['memory'] = [7.25, 7.25]
        with self.assertRaises(ValueError): validate(data, 'v2')

    def test_target_confound_rejected(self):
        data = sample(); data['cases'][2]['target_temperature_K'] = 400
        with self.assertRaises(ValueError): validate(data, 'v2')

    def test_failed_arm_cannot_have_trajectory(self):
        data = sample(); data['cases'][1]['observed'] = deepcopy(data['cases'][0]['observed'])
        with self.assertRaises(ValueError): validate(data, 'v2')

    def test_grid_and_finite_checks(self):
        for name, values in (('time_s', [2000.001, 2000.003]), ('temperature_K', [340, float('nan')])):
            data = sample(); data['cases'][0]['observed'][name] = values
            with self.assertRaises(ValueError): validate(data, 'v2')

    def test_no_production_promotion(self):
        data = sample(); data['production_recovery_allowed'] = True
        with self.assertRaises(ValueError): validate(data, 'v2')

    def test_version_and_source_identity(self):
        for name, value in (('matlab_release', '2026a'), ('execution_commit', 'unknown')):
            data = sample(); data[name] = value
            with self.assertRaises(ValueError): validate(data, 'v2')


if __name__ == '__main__':
    unittest.main()
