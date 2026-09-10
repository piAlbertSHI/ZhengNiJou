import unittest
from pathlib import Path


class ProfilerSDISourceTests(unittest.TestCase):
    def test_archive_reload_is_read_only_and_requires_empty_session(self):
        source=(Path(__file__).parent/'Audit_HeatDriveECC_SDIArchiveReload.m').read_text(encoding='utf-8')
        self.assertLess(source.index('assert(isempty(before)'),source.index('Simulink.sdi.load(archive)'))
        for forbidden in ('Simulink.sdi.clear','deleteRun','sim(','load_system(','profileModel('):
            self.assertNotIn(forbidden,source)
        self.assertIn('numel(required)==1420',source)
        self.assertIn('isequal(double(v.Data(:)),old.values)',source)
        self.assertIn("'production_recovery_allowed',false",source)

    def test_only_new_owned_runs_are_exported_without_clear(self):
        source=(Path(__file__).parent/'Export_HeatDriveECC_ProfilerSDI.m').read_text(encoding='utf-8')
        self.assertIn("setdiff(ids_after,ids_before,'stable')",source)
        self.assertIn('if ~row.ownership_verified',source)
        self.assertNotIn('Simulink.sdi.clear',source)
        self.assertNotIn('deleteRun',source)
        self.assertIn('record.prior_runs_preserved',source)
        self.assertIn("'full_native_coverage_verified',false",source)
        self.assertIn("'science_gate_pass',false",source)

    def test_snapshot_precedes_single_profiler_call(self):
        source=(Path(__file__).parent/'Profile_HeatDriveECC_DeclaredHeldFailure.m').read_text(encoding='utf-8')
        self.assertLess(source.index('ids_before=Simulink.sdi.getAllRunIDs'),source.index('solverprofiler.profileModel('))
        self.assertEqual(source.count('solverprofiler.profileModel('),1)
        self.assertIn('record.capture_pass=record.capture_pass && record.sdi.export_pass',source)
