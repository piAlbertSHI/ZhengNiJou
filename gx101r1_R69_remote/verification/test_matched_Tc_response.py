import copy
import json
from pathlib import Path
import tempfile
import unittest

from Analyze_HeatDriveECC_MatchedTcResponse import same_experiment, response, configuration_origin, current_measured_window, METRICS
from Audit_HeatDriveECC_SegmentedEvidence import sha256


class MatchedTcResponseTests(unittest.TestCase):
    def fixtures(self):
        q=dict(schema='heatdrive_ecc_runtime_Tc_candidate_endpoint_v1',
            all_original_packet_mechanism_flow_phase_energy_gates_pass=True,all_four_memories_bitwise_preserved=True,
            original_public_thermal_periodic_pass=True,transition_excluded=True,source_state_edited=False,old_model_OP_imported=False,
            boundary_trial=dict(candidate_Tc_K=276.85,plant_recipe_sha256='A',source_complete_OP_sha256='C28'),
            current_window_s=[300,400],snapshot_time_s=400,temperature_K=276.85)
        h=copy.deepcopy(q);h['temperature_K']=277.05;h['boundary_trial'].update(candidate_Tc_K=277.05,plant_recipe_sha256='B')
        a=dict(window_s=[300,400],sample_count=100001,active_SE_mass_kg=.0418,fluid_cp_J_per_kgK=3600,
            performance={k:1. for k in METRICS},cycles=[dict(cycle=31+k,window_s=[300+10*k,310+10*k],
                **{name:1. for name in METRICS}) for k in range(10)])
        b=copy.deepcopy(a);b['performance'].update(cooling_power_eq10_W=1.4,temperature_lift_eq9_K=.8,SCP_W_per_g=1.2)
        for row in b['cycles']:row.update(cooling_power_eq10_W=1.4,temperature_lift_eq9_K=.8,SCP_W_per_g=1.2)
        lr=dict(output_root='low',diagnostic_observation_options=dict(Tc=276.85),physics=dict(mass=1))
        rr=dict(output_root='high',diagnostic_observation_options=dict(Tc=277.05),physics=dict(mass=1))
        return q,h,a,b,lr,rr

    def test_common_contract_and_finite_response_are_not_a_root(self):
        values=self.fixtures();same_experiment(*values)
        result=response(*values[:4])
        self.assertAlmostEqual(result['metrics']['cooling_power_eq10_W']['finite_step_response_per_K'],2.)
        self.assertFalse(result['zero_load_SCP_bracketed']);self.assertFalse(result['zero_lift_bracketed'])
        self.assertFalse(result['root_found']);self.assertFalse(result['outer_solve_eligible'])
        self.assertEqual(result['zero_load_local_direction'],'decrease_Tc')
        self.assertEqual(result['zero_lift_local_direction'],'increase_Tc')

    def test_no_substitution_of_source_state_or_physical_recipe(self):
        values=self.fixtures();values[1]['boundary_trial']['source_complete_OP_sha256']='different'
        with self.assertRaises(ValueError):same_experiment(*values)
        values=self.fixtures();values[5]['physics']['mass']=2
        with self.assertRaises(ValueError):same_experiment(*values)

    def test_no_comparison_across_old_windows_or_mass_bases(self):
        for key,value in [('window_s',[180,280]),('active_SE_mass_kg',.0836),('fluid_cp_J_per_kgK',4200)]:
            values=self.fixtures();values[3][key]=value
            with self.assertRaises(ValueError):same_experiment(*values)

    def test_scientifically_failed_candidate_never_enters_comparison(self):
        values=self.fixtures();values[1]['original_public_thermal_periodic_pass']=False
        with self.assertRaises(ValueError):same_experiment(*values)

    def test_retirement_is_limited_to_superseded_packets_and_preserves_current_dependencies(self):
        source=(Path(__file__).parent/'Retire_HeatDriveECC_C22SupersededRaw.ps1').read_text()
        self.assertIn('foreach ($cycle in @(14,16,18))',source)
        self.assertIn("@('native\\observations.mat','observed_states.mat')",source)
        self.assertLess(source.index('$protected.Contains($path)'),source.index('Remove-Item -LiteralPath $target.path'))
        self.assertIn('ReparsePoint',source)
        self.assertNotIn('Remove-Item -Recurse',source)
        self.assertIn('old_C22_qualification_now_historical_not_a_recovery_source=$true',source)

    def ancestry(self,root):
        def write(name,data):
            p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(data));return p
        def entry(p):return dict(path=str(p),sha256=sha256(p))
        cmp=write('base/runtime_Tc_recipe_comparison.json',dict(only_declared_change=True,
            numeric_validation_thresholds_equal=True,reference_configuration_sha256='common_C28'))
        op=root/'state.mat';op.write_bytes(b'unit-test-state-not-a-vendor-op')
        parent=dict(same_Tc_continuation=False,temperature_K=276.85,boundary_trial=dict(original_source='C28'),
            snapshot_time_s=400,operating_point_path=str(op),operating_point_sha256=sha256(op),files=[entry(cmp)])
        parentfile=write('parent.json',parent)
        result=write('next/collection_result.json',dict(continuation=dict(source_qualification_sha256=sha256(parentfile),
            source_OP_sha256=sha256(op),source_snapshot_s=400)))
        newcmp=write('next/runtime_Tc_recipe_comparison.json',dict(only_declared_change=True,
            numeric_validation_thresholds_equal=True,reference_options_field='plant_build_options',reference_configuration_sha256='different_Tc_labelled_MAT'))
        child=dict(same_Tc_continuation=True,temperature_K=276.85,boundary_trial=parent['boundary_trial'],snapshot_time_s=520,
            files=[entry(parentfile),entry(result),entry(newcmp)])
        return child,cmp

    def test_continuation_compares_shared_plant_ancestry_not_different_analysis_MAT_bytes(self):
        with tempfile.TemporaryDirectory() as d:
            child,_=self.ancestry(Path(d));self.assertEqual(configuration_origin(child),'common_C28')
            child['boundary_trial']=dict(original_source='unrelated')
            with self.assertRaises(ValueError):configuration_origin(child)

    def test_ancestral_receipts_remain_sha_bound(self):
        with tempfile.TemporaryDirectory() as d:
            child,cmp=self.ancestry(Path(d));cmp.write_text('{}')
            with self.assertRaises(ValueError):configuration_origin(child)

    def window_fixture(self,root):
        result=root/'collection_result.json';result.write_text('{}')
        q=dict(current_window_s=[420,520],temperature_K=276.85,snapshot_time_s=520)
        data=dict(schema='heatdrive_ecc_measured_ten_cycle_collection_v1',window_s=[420,520],
            candidate_Tc_K=276.85,total_cycles=52,sample_count=100001,collection_result_sha256=sha256(result))
        files=[result]
        for name,window in [('ancestor',[300,400]),('current',[420,520])]:
            p=root/name/'measured_window.json';p.parent.mkdir()
            value=dict(data,window_s=window,total_cycles=window[-1]/10);p.write_text(json.dumps(value));files.append(p)
        return q,data,files

    def test_select_current_window_without_rejecting_retained_ancestor(self):
        with tempfile.TemporaryDirectory() as d:
            q,_,files=self.window_fixture(Path(d))
            self.assertEqual(current_measured_window(q,files),files[-1])

    def test_reject_current_window_with_wrong_collection_temperature_or_samples(self):
        with tempfile.TemporaryDirectory() as d:
            q,data,files=self.window_fixture(Path(d))
            for key,value in [('collection_result_sha256','other'),('candidate_Tc_K',277.05),('sample_count',99999)]:
                files[-1].write_text(json.dumps(dict(data,**{key:value})))
                with self.assertRaises(ValueError):current_measured_window(q,files)

    def test_reject_duplicate_current_window(self):
        with tempfile.TemporaryDirectory() as d:
            q,data,files=self.window_fixture(Path(d));p=Path(d)/'duplicate'/'measured_window.json'
            p.parent.mkdir();p.write_text(json.dumps(data));files.append(p)
            with self.assertRaises(ValueError):current_measured_window(q,files)


if __name__=='__main__':unittest.main()
