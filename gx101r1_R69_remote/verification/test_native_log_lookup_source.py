"""Guard exact node authority; runtime comparison must supply physical evidence."""
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parent


class NativeLookupSourceTests(unittest.TestCase):
    def test_fast_path_requires_actual_sid_and_literal_hierarchy(self):
        source=(ROOT/'Find_HeatDriveECC_NativeLogNode.m').read_text(encoding='utf-8')
        for text in ('Simulink.ID.getSID(block)',"strcmp(tags{2,index},sid)",
                     'identified>0','simscape.logging.findNode(log,block)'):
            self.assertIn(text,source)
        self.assertNotIn('makeValidName',source)

    def test_runtime_comparison_checks_values_tags_and_time(self):
        source=(ROOT/'Verify_HeatDriveECC_NativeLogLookup.m').read_text(encoding='utf-8')
        for text in ('isequal(a.tags,b.tags)','isequal(time(x),time(y))',
                     'isequal(values(x),values(y))','official_lookup_seconds'):
            self.assertIn(text,source)

    def test_unproved_lookup_optimization_not_used_by_exporters(self):
        for name in ('Extract_HeatDriveECC_NativeStorageTraces.m',
                     'Extract_HeatDriveECC_BoundaryTraces.m','Export_HeatDriveECC_FailedColdObservations.m'):
            self.assertNotIn('Find_HeatDriveECC_NativeLogNode(', (ROOT/name).read_text(encoding='utf-8'))
            self.assertIn('simscape.logging.findNode(', (ROOT/name).read_text(encoding='utf-8'))
