"""Cold integration must reject lost signals and incomplete time grids."""
import copy
from pathlib import Path
import unittest
from unittest.mock import patch

import numpy as np

from Audit_HeatDriveECC_ColdBufferCoupled import (
    CONTROL_VOLUME_SEED_PRODUCER,
    ENDPOINT_CHAMBER_PRODUCERS,
    ZERO_BASED_OFFSET_PRODUCERS,
    audit,
    calibration_reference_matches,
    evidence_path_key,
    port_contract,
    topology_check,
)
from Audit_HeatDriveECC_ColdChamberCycle import checked_rows


class ColdBufferCoupledTests(unittest.TestCase):
    def contract(self):
        return dict(original_conserving_ports=[
            dict(name='A', interface_type='Domain', side='LConn', index=1,
                 domain='foundation.thermal_liquid.thermal_liquid', connected=True),
            dict(name='H', interface_type='Domain', side='RConn', index=1,
                 domain='foundation.thermal.thermal', connected=False)],
            removed_unconnected_outputs=[dict(name=n, interface_type='Output', domain='', connected=False)
                                         for n in ('L_out', 'T_out', 'V_out')])

    def test_explicit_unconnected_outputs(self):
        port_contract(self.contract())

    def test_each_connected_output_rejected(self):
        for i in range(3):
            c = self.contract(); c['removed_unconnected_outputs'][i]['connected'] = True
            with self.assertRaises(ValueError): port_contract(c)

    def test_missing_or_unknown_output_rejected(self):
        c = self.contract(); c['removed_unconnected_outputs'].pop()
        with self.assertRaises(ValueError): port_contract(c)
        c = self.contract(); c['removed_unconnected_outputs'][0]['name'] = 'control'
        with self.assertRaises(ValueError): port_contract(c)

    def test_thermal_connection_cannot_disappear(self):
        c = self.contract(); c['original_conserving_ports'][1]['connected'] = True
        with self.assertRaises(ValueError): port_contract(c)

    def test_domain_or_side_change_rejected(self):
        for field, value in [('side', 'LConn'), ('domain', 'wrong'), ('index', 2)]:
            c = self.contract(); c['original_conserving_ports'][1][field] = value
            with self.assertRaises(ValueError): port_contract(c)

    def rows(self, stop):
        t = np.arange(round(stop/.001)+1)*.001
        return {('buffer', 'T_I'): {'time_s': t.reshape(1, -1), 'values': np.ones((1, t.size))}}

    @patch('Audit_HeatDriveECC_ColdChamberCycle.named_rows')
    def test_short_and_default_cycle_grids(self, named):
        named.return_value = self.rows(.01)
        checked_rows({'native': None}, 'native', 1, stop=.01)
        with self.assertRaises(ValueError): checked_rows({'native': None}, 'native', 1)
        named.return_value = self.rows(10)
        checked_rows({'native': None}, 'native', 1)
        named.return_value = self.rows(.2)
        checked_rows({'native': None}, 'native', 1, stop=.2)
        with self.assertRaises(ValueError): checked_rows({'native': None}, 'native', 1, stop=.01)

    @patch('Audit_HeatDriveECC_ColdChamberCycle.named_rows')
    def test_leading_warmup_sample_requires_explicit_window_contract(self, named):
        t = np.arange(-.001, .011, .001)
        named.return_value = {('buffer', 'T_I'): {
            'time_s': t.reshape(1, -1), 'values': np.ones((1, t.size))}}
        with self.assertRaises(ValueError):
            checked_rows({'native': None}, 'native', 1, stop=.01, start=0)
        rows = checked_rows({'native': None}, 'native', 1, stop=.01, start=0,
                            allow_leading_warmup=True)
        self.assertEqual(rows['buffer', 'T_I']['time_s'].shape, (1, 11))
        self.assertAlmostEqual(float(rows['buffer', 'T_I']['time_s'][0, 0]), 0.0)

    def test_onset_cannot_be_full_cycle(self):
        with self.assertRaises(ValueError): audit(None, full_cycle=True, specific_onset=True)

    def test_unknown_chamber_source_rejected(self):
        with self.assertRaises(ValueError): topology_check({}, {}, 'unreviewed_component')

    def test_nonlinear_cycle_entry_is_explicit_and_cold_only(self):
        source = (Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn('if nargin<12, nonlinear_inventory=false; end', source)
        self.assertIn('(~nonlinear_inventory || specific_inventory)', source)
        self.assertIn('Apply_HeatDriveECC_NonlinearColdInventory(repo,model,targets,output_root)', source)
        self.assertIn("'translated_target_count', ...\n                        12*double(nonlinear_inventory)", source)
        self.assertIn("record.nonlinear_buffer_source_file='ecc_nonlinear_buffer.conservative_buffer'", source)

    def test_initial_flux_compensation_is_separate_and_explicit(self):
        source = (Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn('if nargin<13, initial_flux_compensation=false; end', source)
        self.assertIn('specific_inventory && ~nonlinear_inventory', source)
        self.assertIn('Build_HeatDriveECC_ColdInitialFluxCompensation(repo,model,prior.native,targets)', source)
        with self.assertRaises(ValueError):
            audit(None, nonlinear_inventory=True, initial_flux_compensation=True)

    def test_zero_based_offset_buffer_is_explicitly_registered(self):
        target_builder = (Path(__file__).parent/'Build_HeatDriveECC_ColdInventoryTargets.m').read_text(encoding='utf-8')
        runner = (Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        component = (Path(__file__).parent/'simscape_buffer_coupled_offset'/'+ecc_buffer_coupled_offset'/'conservative_buffer.ssc').read_text(encoding='utf-8')
        self.assertIn("ecc_buffer_coupled_offset.conservative_buffer", target_builder)
        self.assertIn("buffer_mass_formulation='direct'", runner)
        self.assertIn("'zero_based_offset'", runner)
        self.assertIn('der(mass_offset) == mdot_A;', component)
        self.assertIn('stored_mass == initial_stored_mass + mass_offset;', component)

    def test_multi_cycle_cold_runner_is_explicitly_bounded(self):
        source = (Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn('ismember(cycle_count,[1 2 20])', source)
        self.assertIn('A multi-cycle diagnostic must span exactly cycle_count*10 s.', source)
        self.assertIn("overrides.cycle_count=cycle_count", source)
        self.assertIn("ismember(simulation_mode,{'normal','accelerator'})", source)
        self.assertIn("log_window_cycles=min(cycle_count,2)", source)

    def test_cold_kp_transition_is_explicit_and_preflight_bounded(self):
        source = (Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn("'se_stage4_pressure_pi_transition_start_s'", source)
        self.assertIn("'se_stage4_pressure_pi_transition_duration_s'", source)
        self.assertIn("'A cold Kp transition requires explicit start, duration, initial Kp, and final Kp.'", source)
        self.assertIn('transition_horizon_s = 10.0 * min(cycle_count,2)', source)
        self.assertIn("'A cold Kp transition must finish within the audited preflight horizon.'", source)

    def test_short_cold_window_requires_full_command_coverage(self):
        source = (Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn('abs(v.Time(end)-options.schedule.total_time_s)<=1.0e-9', source)
        self.assertIn('v.Time(end)>=duration-1.0e-9', source)
        self.assertNotIn('abs(v.Time(end)-duration)<=1.0e-9', source)

    def test_zero_based_offset_audit_contract_is_explicit(self):
        source = (Path(__file__).parent/'Audit_HeatDriveECC_ColdBufferCoupled.py').read_text(encoding='utf-8')
        self.assertIn("ecc_buffer_coupled_offset.conservative_buffer", source)
        self.assertIn("ZERO_BASED_OFFSET_PRODUCER", source)
        self.assertIn("--zero-based-offset", source)
        self.assertIn("mass_formulation == 'zero_based_offset'", source)
        self.assertIn("differential_variables=('mass_offset', 'stored_energy')", source)

    def test_control_volume_seed_producer_is_exactly_allow_listed(self):
        self.assertIn(CONTROL_VOLUME_SEED_PRODUCER, ZERO_BASED_OFFSET_PRODUCERS)
        self.assertNotIn('c7e028d', ZERO_BASED_OFFSET_PRODUCERS)
        self.assertIn('d85609098cb210962a4bd2ee8966db76d0c614da', ZERO_BASED_OFFSET_PRODUCERS)

    def test_stage4_log_closure_execution_is_exactly_allow_listed(self):
        self.assertIn('43bec659dde7384a5543c96886f89130c2480bd0',
                      ENDPOINT_CHAMBER_PRODUCERS)

    def test_stage4_ki_is_an_explicit_negative_diagnostic_override(self):
        source = (Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn("'se_stage4_pressure_pi_ki_MPa_per_kgps_s'", source)
        self.assertIn("'Cold diagnostic Kp/Ki overrides must be negative.'", source)

    def test_stage4_precharge_and_periodic_blend_overrides_are_bounded(self):
        source = (Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn("'se_stage4_commutation_precharge_fraction'", source)
        self.assertIn("'se_stage4_endpoint_viscosity_blend_periodic'", source)
        self.assertIn("'Stage4 commutation precharge fraction must be within [0,1].'", source)
        self.assertIn("'Periodic Stage4 viscosity-blend override must be a logical scalar.'", source)

    def test_stage4_precharge_must_reach_the_simulation_grid(self):
        source = (Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text(encoding='utf-8')
        self.assertIn('SE_stage4_pressure_integrator_enable_command', source)
        self.assertIn('precharge_values > 0.0 & precharge_values < 1.0', source)

    def test_control_volume_seed_accepts_only_matching_audit_mirror_tail(self):
        canonical = Path('main/outputs_storage_audit/calibration/cold_buffer_coupled_audit.json')
        mirror = Path('worktree/outputs_storage_audit/calibration/cold_buffer_coupled_audit.json')
        wrong = Path('worktree/outputs_storage_audit/other/cold_buffer_coupled_audit.json')
        self.assertTrue(calibration_reference_matches(CONTROL_VOLUME_SEED_PRODUCER, mirror, canonical))
        self.assertFalse(calibration_reference_matches(CONTROL_VOLUME_SEED_PRODUCER, wrong, canonical))
        self.assertFalse(calibration_reference_matches('unreviewed', mirror, canonical))

    def test_external_experiment_evidence_key_is_stable(self):
        repo = Path.cwd()/'repo'
        root = Path.cwd()/'tmp'/'experiment'
        self.assertEqual(evidence_path_key(repo/'verification'/'contract.json', repo, root),
                         str(Path('verification')/'contract.json'))
        self.assertEqual(evidence_path_key(root/'native'/'observations.mat', repo, root),
                         str(Path('experiment_root')/'native'/'observations.mat'))
        external = Path.cwd().parent.parent/'untrusted_external'/'file.mat'
        with self.assertRaises(ValueError):
            evidence_path_key(external, repo, root)

    @patch('Audit_HeatDriveECC_ColdChamberCycle.named_rows')
    def test_nonfinite_or_missing_sample_rejected(self, named):
        rows = self.rows(.01); rows['buffer', 'T_I']['values'][0, 5] = np.nan
        named.return_value = rows
        with self.assertRaises(ValueError): checked_rows({'native': None}, 'native', 1, stop=.01)
        rows = copy.deepcopy(self.rows(.01)); rows['buffer', 'T_I']['time_s'][0, 5] += .0002
        named.return_value = rows
        with self.assertRaises(ValueError): checked_rows({'native': None}, 'native', 1, stop=.01)


if __name__ == '__main__':
    unittest.main()
