"""Compare a strictly restored C200 sample with the frozen physical endpoint."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field


def compare(a, b):
    a, b = np.asarray(a).reshape(-1), np.asarray(b).reshape(-1)
    if a.shape != b.shape or not a.size or not np.isfinite([a,b]).all():
        raise ValueError('Unpaired or nonfinite endpoint channel')
    error = np.abs(a-b)
    bound = 1e-10 + 1e-11*np.maximum(abs(a),abs(b))
    return dict(channel_count=len(a), max_abs_error=float(error.max()),
                max_scaled_error=float((error/bound).max()), pass_endpoint_match=bool(np.all(error<=bound)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--probe', choices=('archived_source_probe_v3','archived_source_probe_v4'), default='archived_source_probe_v3')
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Do not overwrite evidence')
    authority = json.loads((args.repo/'verification/c200_mainline_freeze_contract.json').read_text(encoding='utf-8-sig'))
    root = args.repo/'outputs_storage_audit/c200_source_compatibility_20260907'
    probe = root/args.probe
    metadata_path = probe/'source_restore_audit.json'
    metadata = json.loads(metadata_path.read_text(encoding='utf-8-sig'))
    if (not metadata['strict_restore_pass'] or not metadata['observation_complete']
            or not all(metadata['physical_options_unchanged'].values()) or metadata['source_operating_point_edited']
            or metadata['partial_restore_executed'] or metadata['cold_start_executed']
            or metadata['production_recovery_allowed'] or metadata['error_message']
            or metadata['snapshot_time_s']!=2000 or metadata['final_snapshot_time_s']!=2000.001
            or metadata['builder_settings']['SimscapeLogDataHistory']!=5000):
        raise ValueError('Strict archival restore contract changed')
    source = args.repo/authority['result_relative_path']
    raw_path = probe/'restored_step_signals.mat'
    if sha256(source)!=authority['result_sha256']:
        raise ValueError('Frozen physical evidence changed')
    direct = dict(SMA_T_21_K='SMA_Tx21_internal',SE_T_21_K='SE_Tx21_internal',
                  SHEX_T_K='SHEX_hot_sink_temp_out',HHEX_T_K='hot_sink_temp_out',CHEX_T_K='cold_sink_temp_out',
                  SHEX_buffer_T_K='shex_buffer_temp_out',HHEX_buffer_T_K='hot_buffer_temp_out',
                  SMA_HHEX_buffer_T_K='sma_hot_buffer_temp_out',CHEX_buffer_T_K='cold_buffer_temp_out',
                  pressure_command_SMA_MPa='pressure_command_sma_MPa',pressure_command_SE_MPa='pressure_command_se_MPa',
                  Q_SMA_constitutive_21_W='ECC_Q_SMA_constitutive_W',Q_SE_constitutive_21_W='ECC_Q_SE_constitutive_W',
                  mdot_SMA_kgps='mass_flow_sma_stage13_kgps',mdot_SMA_stage1_route_kgps='mass_flow_sma_stage1_route_kgps',
                  mdot_SMA_stage3_route_kgps='mass_flow_sma_stage3_route_kgps',mdot_SE_stage2_in_kgps='mass_flow_v1_cold_inlet_kgps',
                  mdot_SE_stage2_out_kgps='mass_flow_v3_sma_to_hot_kgps',mdot_SE_stage4_in_kgps='mass_flow_v4_hot_inlet_kgps',
                  mdot_SE_stage4_out_kgps='mass_flow_v6_sma_to_chip_cold_kgps')
    rows, native_rows = [], []
    with h5py.File(source,'r') as frozen, h5py.File(raw_path,'r') as restored:
        physical, signals = frozen['physical'], restored['signals']
        if len(signals)!=161 or float(physical['time_s'][0,-1])!=2000:
            raise ValueError('Unexpected signal coverage or frozen endpoint')
        for name, signal in signals.items():
            t, y = signal['time_s'][:].reshape(-1), signal['values'][:]
            if t.shape!=(2,) or not np.array_equal(t,[2000,2000.001]) or y.shape[-1]!=2 or not np.isfinite(y).all():
                raise ValueError('Wrong physical sample window')
        for name, signal in direct.items():
            rows.append(dict(physical_field=name,signal=signal,**compare(physical[name][:,-1],signals[signal]['values'][:,0])))
        constitutive_fields = ('xM_SMA_21','xM_SE_21','sigma_SMA_21_Pa','sigma_SE_21_Pa','epsilon_SMA_21',
                               'epsilon_SE_21','drive_SMA_21_Pa','drive_SE_21_Pa','rate_xM_SMA_21_per_s','rate_xM_SE_21_per_s')
        for i,name in enumerate(constitutive_fields):
            values = signals['ECC_constitutive21_output']['values'][42+i*21:42+(i+1)*21,0]
            rows.append(dict(physical_field=name,signal=f'ECC_constitutive21_output[{42+i*21}:{42+(i+1)*21}]',
                             **compare(physical[name][:,-1],values)))
        for name, field in physical['probes'].items():
            if name not in signals:
                raise ValueError('Frozen probe missing after restore')
            rows.append(dict(physical_field='probes/'+name,signal=name,**compare(field[:,-1],signals[name]['values'][:,0])))
        seen = set()
        for ref in restored['native'][:].flat:
            trace = restored[ref]
            path,name = text_field(trace['block_path']),text_field(trace['state_name'])
            key = (path,name)
            t,y = trace['time_s'][:].reshape(-1),trace['values'][:]
            if key in seen or not np.array_equal(t,[2000,2000.001]) or y.shape[-1]!=2 or not np.isfinite(y).all():
                raise ValueError('Duplicate, nonfinite or off-grid native inventory')
            seen.add(key)
            native_rows.append(dict(block_path=path,state_name=name,unit=text_field(trace['unit']),
                                    channel_count=y.shape[0],initial_values=y[:,0].tolist(),final_values=y[:,-1].tolist()))
    if len(native_rows)!=1240 or len({r['block_path'] for r in native_rows})!=119:
        raise ValueError('Native storage component coverage changed')
    result = dict(schema='heatdrive_ecc_c200_restored_endpoint_audit_v1',computation_complete=True,
                  strict_archival_restore_pass=True,endpoint_comparisons=rows,
                  all_observed_endpoint_match=all(r['pass_endpoint_match'] for r in rows),
                  compared_channel_count=sum(r['channel_count'] for r in rows),
                  native_trace_count=len(native_rows),native_storage_component_count=119,native_inventory=native_rows,
                  absolute_tolerance=1e-10,relative_tolerance=1e-11,
                  original_logged_states_exposes_simscape_state=False,complete_hidden_state_mapping_verified=False,
                  new_model_recovery_allowed=False,whole_model_first_law_verified=False,table4_reproduction_claim=False,
                  input_sha256=dict(restored_signals=sha256(raw_path),restore_metadata=sha256(metadata_path),frozen_result=authority['result_sha256']))
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('endpoint_comparisons','native_inventory','input_sha256')},indent=2))


if __name__=='__main__':
    main()
