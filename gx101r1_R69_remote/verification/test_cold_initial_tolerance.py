import unittest
from Audit_HeatDriveECC_ColdInitialTolerance import BASE, check_settings, coordinates


class ColdInitialToleranceTests(unittest.TestCase):
    def sample(self):
        return [dict(path='pipe/T_I', priority='High', unit='K', value=300.)], [dict(
            path='pipe/T_I', priority='High', unit='K', native_unit='K', expected=300.,
            actual=300., native_value=300., source_time_s=0)]

    def test_only_declared_changes(self):
        check_settings('default', BASE, BASE)
        check_settings('tight', BASE, dict(BASE, ConsistencyTolSource='LOCAL', ConsistencyAbsTol='1e-9', ConsistencyRelTol='1e-9'))
        check_settings('residual', BASE, dict(BASE, ResidualTolerance='1e-9'))
        with self.assertRaises(ValueError): check_settings('tight', BASE, dict(BASE, ResidualTolerance='1e-9'))

    def test_step_change_rejected(self):
        with self.assertRaises(ValueError): check_settings('default', BASE, dict(BASE, LocalSolverSampleTime='0.0001'))

    def test_measured_error_not_target_priority_decides(self):
        targets, rows = self.sample()
        self.assertTrue(coordinates(rows, targets)[0]['within_strict_comparison'])
        rows[0]['actual'] = rows[0]['native_value'] = 300.00001
        self.assertFalse(coordinates(rows, targets)[0]['within_strict_comparison'])

    def test_duplicate_or_missing_rejected(self):
        targets, rows = self.sample()
        with self.assertRaises(ValueError): coordinates(rows*2, targets)
        with self.assertRaises(ValueError): coordinates([], targets)

    def test_changed_target_time_or_units_rejected(self):
        for key, value in [('expected', 301.), ('source_time_s', .001), ('native_unit', 'degC')]:
            targets, rows = self.sample(); rows[0][key] = value
            with self.assertRaises(ValueError): coordinates(rows, targets)

    def test_nonfinite_measurement_rejected(self):
        targets, rows = self.sample(); rows[0]['actual'] = rows[0]['native_value'] = float('inf')
        with self.assertRaises(ValueError): coordinates(rows, targets)


if __name__ == '__main__': unittest.main()
