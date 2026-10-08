from pathlib import Path
import unittest


class NativeSeriesAccessSourceTests(unittest.TestCase):
    def test_hot_reader_does_not_query_points(self):
        source = (Path(__file__).parent/'Read_HeatDriveECC_NativeSeries.m').read_text()
        code = '\n'.join(line.split('%')[0] for line in source.splitlines())
        self.assertNotIn('series.points', code)
        self.assertIn('points=numel(t)', code)
        self.assertIn('double(values(series))', code)
        self.assertIn('series.unit', code)

    def test_actual_vendor_fixture_checks_every_coordinate(self):
        source = (Path(__file__).parent/'Verify_HeatDriveECC_NativeSeriesAccess.m').read_text()
        for check in ('points==numel(t)', 'isequaln(t,classic_time)',
                      'isequaln(data,classic_data)', 'strcmp(unit,classic_unit)',
                      'empty_timing.points==0', "'full_plant_speedup_measured',false"):
            self.assertIn(check, source)
