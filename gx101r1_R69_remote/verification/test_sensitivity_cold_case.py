import copy
import json
from pathlib import Path
import tempfile
import unittest

import h5py
import numpy as np

from HeatDriveECC_SensitivityCase import LEVELS, FRACTIONS, NAMES, FIELD_FACTORS, design, audit_case
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Verify_HeatDriveECC_ObservationPacket import validate_manifest


class ColdSensitivityTests(unittest.TestCase):
    def manifest(self):
        return dict(schema='heatdrive_ecc_split_observation_packet_v1',window_s=[0,20],
            source_snapshot_s=0,history_cap_cycles=2,state_history_cap_cycles=11,
            simulation_returned_without_error=True,source_state_edited=False,production_recovery_allowed=False,
            strict_vendor_restore=False,packet_role='runtime_sensitivity_cold',
            independent_cold_start=True,parent_complete_OP_sha256='',checksum_policy='error/error',
            sensitivity_case_scope_only=True,sensitivity_case_contract_sha256='B'*64,command_horizon_cycles=200,
            temperature_configurability='runtime',prescribed_Tc_K=276.95)

    def test_exact_cold_comparison_scope(self):
        self.assertEqual(validate_manifest(self.manifest()), (0,20))
        for key,value in (('strict_vendor_restore',True),('window_s',[20,40]),('parent_complete_OP_sha256','A'*64),
                          ('prescribed_Tc_K',274.85),('sensitivity_case_scope_only',False)):
            m=self.manifest();m[key]=value
            with self.assertRaises(ValueError):validate_manifest(m)

    def test_balanced_orthogonal_design_and_27_fields(self):
        np.testing.assert_array_equal(LEVELS.T@LEVELS,8*np.eye(6))
        np.testing.assert_array_equal(LEVELS.sum(axis=0),np.zeros(6))
        self.assertEqual(len(FIELD_FACTORS),27)
        for index in range(9):
            levels=np.zeros(6) if index==0 else LEVELS[index-1]
            row=dict(run_index=index,levels=levels.tolist(),fractions=FRACTIONS.tolist())
            row.update(zip(NAMES,1+levels*FRACTIONS))
            np.testing.assert_array_equal(design(row),1+levels*FRACTIONS)
            bad=copy.deepcopy(row);bad['UA_multiplier']+=.001
            with self.assertRaises(ValueError):design(bad)

    def test_transient_retains_same_case_and_strict_complete_state(self):
        m=self.manifest()
        m.update(packet_role='runtime_sensitivity_transient',window_s=[20,40],source_snapshot_s=20,
                 strict_vendor_restore=True,independent_cold_start=False,parent_complete_OP_sha256='A'*64)
        self.assertEqual(validate_manifest(m),(20,40))
        for key,value in (('source_snapshot_s',0),('window_s',[200,220]),('strict_vendor_restore',False),
                          ('independent_cold_start',True),('sensitivity_case_contract_sha256',''),
                          ('prescribed_Tc_K',274.85),('parent_complete_OP_sha256','')):
            bad=copy.deepcopy(m);bad[key]=value
            with self.assertRaises(ValueError):validate_manifest(bad)

    def test_actual_parameter_contract_and_tamper_rejection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary);native=root/'native';native.mkdir()
            source=root/'source';(source/'native').mkdir(parents=True)
            original=source/'native/configuration.mat';actual=native/'configuration.mat'
            row=dict(run_index=2,levels=LEVELS[1].tolist(),fractions=FRACTIONS.tolist())
            row.update(zip(NAMES,1+LEVELS[1]*FRACTIONS));scales=design(row);parameters=[]
            with h5py.File(original,'w') as a,h5py.File(actual,'w') as b:
                for k,(field,factor) in enumerate(FIELD_FACTORS.items()):
                    before=float(k+1);after=before*scales[factor];key=field.replace('.','/')
                    a.create_dataset('plant_build_options/'+key,data=[[before]])
                    b.create_dataset('options/'+key,data=[[after]])
                    parameters.append(dict(field=field,before=before,after=after))
                b.create_dataset('options/validation/sensitivity_mode',data=[[1]])
                b.create_dataset('options/validation/mechanism_gate_start_cycle',data=[[1]])
                references=[]
                for k,field in enumerate(FIELD_FACTORS):
                    char=b.create_dataset(f'#refs#/field{k}',data=np.array([ord(c) for c in field],dtype='uint16')[:,None])
                    references.append(char.ref)
                for name in ('validation/sensitivity_declared_transition_fields','simulation/checkpoint_transition_fields'):
                    b.create_dataset('options/'+name,data=np.array([references],dtype=h5py.ref_dtype))
            qualification=root/'qualification.json'
            qualification.write_text(json.dumps(dict(schema='heatdrive_ecc_runtime_Tc_candidate_endpoint_v1',
                source_packet_root=str(source),all_original_packet_mechanism_flow_phase_energy_gates_pass=True,
                original_public_thermal_periodic_pass=True,source_state_edited=False,production_recovery_allowed=False,
                files=[dict(path=str(original),sha256=sha256(original))])),encoding='utf-8')
            fresh=root/'fresh.mat';fresh.write_bytes(b'same-case fixture, not simulation evidence')
            contract=dict(schema='heatdrive_ecc_runtime_sensitivity_cold_case_v1',design=row,parameters=parameters,
                fixed_Tc_K=276.95,source_state_imported=False,C200_gap_attribution_authorized=False,
                orthogonal_effects_evaluated=False,production_recovery_allowed=False,
                original_scientific_thresholds_changed=False,source_qualification_path=str(qualification),
                source_qualification_sha256=sha256(qualification),parameter_source_configuration_sha256=sha256(original),
                fresh_native_source_path=str(fresh),fresh_native_source_sha256=sha256(fresh))
            path=native/'sensitivity_case_contract.json';path.write_text(json.dumps(contract),encoding='utf-8')
            self.assertEqual(audit_case(root)['independently_checked_parameter_fields'],27)
            with h5py.File(actual,'a') as f:
                field=next(iter(FIELD_FACTORS));f['options/'+field.replace('.','/')][0,0]+=.01
            with self.assertRaisesRegex(ValueError,'actual stored construction'):audit_case(root)

    def test_nominal_control_is_not_a_ninth_orthogonal_factor_run(self):
        row=dict(run_index=0,levels=[-1]*6,fractions=FRACTIONS.tolist())
        row.update(zip(NAMES,1-FRACTIONS))
        with self.assertRaises(ValueError):design(row)

    def test_old_authority_still_guards_legacy_runner(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_Table4_Sensitivity.m').read_text()
        self.assertIn('~authority.sensitivity_run_authorized',source)
        self.assertIn('Build_HeatDriveECC_SensitivityOverrides(',source)

    def test_preflight_cannot_load_as_an_old_family_checkpoint(self):
        source=(Path(__file__).parent/'Load_HeatDriveECC_GatedObservationPacket.m').read_text()
        self.assertIn('strcmp(manifest.sensitivity_case_contract_sha256,expected_case_sha256)',source)
        self.assertIn("if nargin<3,expected_case_sha256='';end",source)

    def test_source_is_fresh_and_probe_has_no_saved_OP(self):
        source=(Path(__file__).parent/'Capture_HeatDriveECC_FreshSensitivityNative.m').read_text()
        self.assertIn("'LoadInitialState','off','SimscapeUseOperatingPoints','off'",source)
        self.assertIn("'SaveFinalState','off','SaveOperatingPoint','off'",source)
        self.assertNotIn('setInitialState(',source)
        self.assertIn("'Solver',options.simulation.solver",source)

    def test_existing_coordinate_comparison_is_not_relaxed(self):
        source=(Path(__file__).parent/'Verify_HeatDriveECC_SensitivityColdCase.m').read_text()
        self.assertIn('limit=1e-10+1e-11*abs(target.value)',source)
        self.assertIn('numel(targets)==204',source)
        self.assertIn('record.full_cycle_gates_evaluated=true',source)


if __name__=='__main__':unittest.main()
