import copy
from pathlib import Path
import unittest

from Analyze_HeatDriveECC_MatchedTcResponse import same_experiment, response, METRICS


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


if __name__=='__main__':unittest.main()
