import unittest

from HeatDriveECC_PublicPeriodicity import PUBLIC_PREDICATES, audit_public_statistics


class PublicPredicateTests(unittest.TestCase):
    def record(self):
        r=dict(periodic_window_cycles=10,periodic_steady_state=True,
               last_cycle_same_phase_temperature_drift_K=100,last_cycle_same_phase_phase_drift=100)
        for _,value,limit in PUBLIC_PREDICATES:r[value]=.5;r[limit]=1.
        return r

    def test_diagnostic_maximum_cannot_create_a_seventh_gate(self):
        r=audit_public_statistics(self.record())
        self.assertTrue(r['original_public_flag']);self.assertEqual(len(r['predicates']),6)
        self.assertFalse(r['thresholds_changed'])

    def test_each_real_predicate_can_reject_without_changed_threshold(self):
        for _,field,_ in PUBLIC_PREDICATES:
            r=self.record();r[field]=1.1;r['periodic_steady_state']=False
            self.assertFalse(audit_public_statistics(r)['original_public_flag'])

    def test_inconsistent_recorded_pass_is_rejected(self):
        r=self.record();r['last_cycle_phase_drift']=2.
        with self.assertRaises(ValueError):audit_public_statistics(r)


if __name__=='__main__':unittest.main()
