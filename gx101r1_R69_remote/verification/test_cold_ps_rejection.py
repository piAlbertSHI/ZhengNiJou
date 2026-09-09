import unittest
from Audit_HeatDriveECC_ColdPSControllerRejection import reject_state_promotion, check_connections


class ColdPSRejectionTests(unittest.TestCase):
    def test_frozen_flow_has_distinct_failure_signature(self):
        r = dict(inspection_pass=False, stage='initialization_state_logging', states=[],
                 c200_state_imported=False, failed_terminal_state_imported=False,
                 checkpoint_saved=False, production_recovery_allowed=False,
                 error_message=' '.join(f'SMA_Pump{side}ConnectingPipeVolume.stored_{state}'
                                        for side in ('Inlet', 'Outlet') for state in ('mass', 'energy')))
        self.assertEqual(len(reject_state_promotion(r, True)), 4)
        with self.assertRaises(ValueError):
            reject_state_promotion(r)
        r['error_message'] += ' ColdSMAPSController.error_lag.Y'
        with self.assertRaises(ValueError):
            reject_state_promotion(r, True)

    def test_wrong_error_is_not_an_accepted_rejection(self):
        r = dict(inspection_pass=False, stage='initialization_state_logging', states=[],
                 c200_state_imported=False, failed_terminal_state_imported=False,
                 checkpoint_saved=False, production_recovery_allowed=False, error_message='unrelated failure')
        with self.assertRaises(ValueError):
            reject_state_promotion(r)

    def test_failed_states_cannot_be_promoted(self):
        with self.assertRaises(ValueError):
            reject_state_promotion(dict(inspection_pass=True))

    def test_boundary_differences_and_duplicates_rejected(self):
        rows = [dict(block='b', port=str(k), domain='thermal') for k in range(1183)]
        c = dict(physical_connections_before=rows, physical_connections_after=rows,
                 physical_connections_unchanged=True)
        self.assertEqual(check_connections(c), 1183)
        c['physical_connections_after'] = rows[:-1]
        with self.assertRaises(ValueError):
            check_connections(c)
        c['physical_connections_before'] = [rows[0]] * 1183
        c['physical_connections_after'] = c['physical_connections_before']
        with self.assertRaises(ValueError):
            check_connections(c)


if __name__ == '__main__':
    unittest.main()
