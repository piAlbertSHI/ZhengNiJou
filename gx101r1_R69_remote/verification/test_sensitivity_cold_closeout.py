import json
from pathlib import Path
import tempfile
import unittest

from Close_HeatDriveECC_SensitivityColdCase import close, execution_budget


class SensitivityCloseoutTests(unittest.TestCase):
    def timing_fixture(self,root,count=10):
        folder=root/'native/sensitivity_cold_case'
        for k in range(count):
            p=folder/f'packet_C{2*k+2:03d}';p.mkdir(parents=True)
            (p/'simulation_timing.json').write_text(json.dumps(dict(window_s=[20*k,20*k+20],
                metadata_available=True,simulation_settings_changed=False,timing_is_physical_gate=False,
                sim_call_wall_s=100,vendor_timing=dict(InitializationElapsedWallTime=3,
                    ExecutionElapsedWallTime=95,TerminationElapsedWallTime=2))),encoding='utf-8')

    def test_timing_budget_is_not_a_scientific_gate(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);self.timing_fixture(root);out=root/'budget.json'
            execution_budget(root,out);r=json.loads(out.read_text())
            self.assertEqual(r['totals_s']['execution_s'],950)
            self.assertEqual(r['execution_fraction_of_sim_call'],.95)
            self.assertFalse(r['acceleration_validated']);self.assertFalse(r['timing_is_physical_gate'])
            with self.assertRaises(FileExistsError):execution_budget(root,out)

    def test_incomplete_timing_cannot_support_cost_claim(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);self.timing_fixture(root,9)
            with self.assertRaises(ValueError):execution_budget(root,root/'budget.json')

    def test_probe_cannot_be_sealed_as_twenty_cycles(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);p=root/'native/sensitivity_cold_case';p.mkdir(parents=True)
            (p/'case_result.json').write_text(json.dumps(dict(
                schema='heatdrive_ecc_runtime_sensitivity_cold_result_v1',probe_only=True)),encoding='utf-8')
            output=Path(__file__).resolve().parents[1]/'outputs_storage_audit'/'__unused_sensitivity_unit_test'
            self.assertFalse(output.exists())
            with self.assertRaises(ValueError):close(root,output)
            self.assertFalse(output.exists())


if __name__=='__main__':unittest.main()
