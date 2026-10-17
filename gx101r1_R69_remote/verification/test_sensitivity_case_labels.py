import unittest

from Analyze_HeatDriveECC_SensitivityControlWindows import qualification_flags
from Plot_HeatDriveECC_SensitivityColdCase import case_label


class SensitivityCaseLabelTests(unittest.TestCase):
    def test_nominal_label_and_compatibility_flag(self):
        self.assertEqual(case_label(0), 'nominal cold control')
        self.assertTrue(qualification_flags(0, True)['finite_precision_nominal_control_qualified'])

    def test_factor_rows_are_never_nominal_controls(self):
        for index in range(1, 9):
            self.assertIn(f'L8 row {index}', case_label(index))
            flags = qualification_flags(index, True)
            self.assertFalse(flags['finite_precision_nominal_control_qualified'])
            self.assertTrue(flags['finite_precision_case_response_qualified'])
            self.assertFalse(qualification_flags(index, False)['finite_precision_case_response_qualified'])

    def test_unknown_or_boolean_index_cannot_be_relabelled(self):
        for index in (-1, 9, True, 1.0, '1'):
            with self.assertRaises(ValueError):
                case_label(index)
            with self.assertRaises(ValueError):
                qualification_flags(index, True)


if __name__ == '__main__':
    unittest.main()
