"""Quantify finite buffer storage alongside Eq.9; never correct cooling by unrelated CV terms."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Cycle import metrics
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_NativeMappedBufferDrift import states
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_ObservationWindow import window_indices


BUFFER_SIGNALS={'ColdFluidBuffer':'cold_buffer_temp_out','HotFluidBuffer':'hot_buffer_temp_out',
                'SHEXFluidBuffer':'shex_buffer_temp_out','SMAHotFluidBuffer':'sma_hot_buffer_temp_out'}


def storage_metrics(mass_change,energy_change,mass,area,gravity,period=10):
    if not np.isfinite([mass_change,energy_change,mass,area,gravity,period]).all() or min(mass,area,period)<=0 or gravity<0:
        raise ValueError('Invalid physical buffer quantities')
    return dict(mass_change_kg=float(mass_change),relative_inventory_change=float(mass_change/mass),
        stored_energy_change_J=float(energy_change),stored_energy_rate_W=float(energy_change/period),
        port_hydrostatic_pressure_change_Pa=float(gravity*mass_change/area),period_s=period)


def analyze(root,drift_path):
    drift=json.loads(drift_path.read_text(encoding='utf-8-sig'))
    if (Path(drift['source_root']).resolve()!=root or drift['independent_exact_identity_count']!=121 or
            drift['buffer_comparison_window_s']!=[320,420] or drift['periodic_gate_assigned']):
        raise ValueError('Require the crosschecked C42 buffer observation')
    mapping_path=Path(__file__).resolve().parents[1]/'outputs_storage_audit/v42_native_state_mapping_exploration_20261015.json'
    if sha256(mapping_path)!=drift['input_sha256']['mapping']:
        raise ValueError('Mapping proof changed')
    mapping=json.loads(mapping_path.read_text(encoding='utf-8-sig'))
    for relative,key in (('native/observations.mat','native_observation'),('native/diagnostic_state_observation.mat','history')):
        if sha256(root/relative)!=mapping['input_sha256'][key]:
            raise ValueError('Current actual observation changed')
    contracts=json.loads((root/'native/buffer_replacement_contract.json').read_text(encoding='utf-8-sig'))
    contracts={r['block_path'].rsplit('/',1)[-1]:r for r in contracts['buffers']}
    cycle_results=[];buffer_results={};temperature_comparisons={}
    with h5py.File(root/'native/observations.mat') as f,h5py.File(root/'native/configuration.mat') as cfg, \
            h5py.File(root/'native/diagnostic_state_observation.mat') as h:
        numerical=states(h);native=named_rows(f,f['native'])
        for name,signal_name in BUFFER_SIGNALS.items():
            c=contracts[name]
            row=f['signals/'+signal_name];time=row['time_s'][:].ravel();temperature=row['values'][:].ravel()
            selected=window_indices(time,400,420)
            raw=native['heatdrive_ecc_coupled_se21/'+name,'T_I']
            reference=scalar_series(raw,'K')[window_indices(raw['time_s'][:],400,420)]
            port_temperature=temperature[selected]
            if port_temperature.shape!=reference.shape or not np.isfinite([port_temperature,reference]).all():
                raise ValueError('Invalid temperature comparison')
            temperature_comparisons[name]=dict(actual_window_s=[400,420],
                public_signal=signal_name,public_coordinate='conserving port temperature, not internal T_I',
                max_abs_port_minus_internal_K=float(abs(port_temperature-reference).max()),
                internal_last_cycle_endpoint_change_K=float(reference[-1]-reference[10000]),
                internal_ten_cycle_temperature_available=False)
            mapped=[m for m in mapping['matches'] if m['block_path'].endswith('/'+name) and m['variable']=='mass_offset']
            if len(mapped)!=1:
                raise ValueError('Incomplete buffer mass correspondence')
            index=mapped[0]['coordinate'];state=numerical[index['block_path'],index['state_name']]
            state_time=state['time_s'][:].ravel();offset=state['values'][index['coordinate_1based']-1,:]
            endpoints=[]
            for t in np.arange(320,421,10):
                i=int(np.argmin(abs(state_time-t)));j=int(np.argmin(abs(time-t)))
                if abs(state_time[i]-t)>1e-9 or abs(time[j]-t)>1e-9:
                    raise ValueError('Actual cycle endpoint missing')
                endpoints.append((float(c['initial_mass_kg']+offset[i]),float(temperature[j])))
            buffer_results[name]=[dict(global_cycle=cycle,
                port_temperature_endpoint_change_K=endpoints[cycle-32][1]-endpoints[cycle-33][1],
                **storage_metrics(drift['buffers'][name][cycle-33]['mass_offset_change_kg'],
                    drift['buffers'][name][cycle-33]['stored_energy_change_J'],endpoints[cycle-33][0],
                    c['tank_area_m2'],c['gravity_m_s2'])) for cycle in range(33,43)]
        for cycle in range(33,43):
            start=(cycle-1)*10;stop=cycle*10;time=start+np.arange(10001)*.001
            signals={name:row['values'][:,window_indices(row['time_s'][:],start,stop)] for name,row in f['signals'].items()}
            performance,_,_=metrics(signals,cfg['options'],time,origin=start)
            signed=sum(buffer_results[name][cycle-33]['stored_energy_rate_W'] for name in BUFFER_SIGNALS)
            absolute=sum(abs(buffer_results[name][cycle-33]['stored_energy_rate_W']) for name in BUFFER_SIGNALS)
            cycle_results.append(dict(global_cycle=cycle,performance=performance,
                four_buffer_signed_storage_rate_W=signed,four_buffer_absolute_storage_rate_sum_W=absolute,
                signed_storage_to_Eq9_cooling_ratio=signed/performance['cooling_power_W'],
                absolute_storage_to_Eq9_cooling_ratio=absolute/performance['cooling_power_W']))
    return dict(schema='heatdrive_ecc_buffer_performance_window_impact_v1',source_root=str(root),
        actual_window_s=[320,420],cycles=cycle_results,buffers=buffer_results,
        ten_cycle_Eq9_mean_cooling_W=float(np.mean([r['performance']['cooling_power_W'] for r in cycle_results])),
        ten_cycle_Eq9_mean_SCP_W_g=float(np.mean([r['performance']['SCP_W_g'] for r in cycle_results])),
        ten_cycle_CHEX_sensor_mean_W=float(np.mean([r['performance']['CHEX_heat_sensor_mean_W'] for r in cycle_results])),
        temperature_coordinate_comparisons=temperature_comparisons,
        public_port_temperature_used_as_internal_temperature=False,
        hydrostatic_pressure_basis='A.p=p_environment+gravity*M/tank_area; fixed p_I does not imply fixed port pressure',
        storage_rates_are_different_control_volumes_not_cooling_corrections=True,
        storage_to_cooling_ratios_are_comparison_scales_not_causal_bias_bounds=True,
        periodic_tolerances_changed=False,periodic_gate_assigned=False,source_state_edited=False,
        simulation_executed=False,operating_point_loaded=False,outer_solve_eligible=False,
        table4_reproduction_claim=False,input_sha256={'buffer_drift_audit':sha256(drift_path),
            'configuration':sha256(root/'native/configuration.mat'),
            'buffer_contract':sha256(root/'native/buffer_replacement_contract.json')})


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment-root',type=Path,required=True)
    parser.add_argument('--buffer-drift-audit',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():raise FileExistsError('Never overwrite impact evidence')
    result=analyze(args.experiment_root.resolve(),args.buffer_drift_audit.resolve())
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps(dict(ten_cycle_Eq9_mean_cooling_W=result['ten_cycle_Eq9_mean_cooling_W'],
        ten_cycle_Eq9_mean_SCP_W_g=result['ten_cycle_Eq9_mean_SCP_W_g'],
        ten_cycle_CHEX_sensor_mean_W=result['ten_cycle_CHEX_sensor_mean_W'],last_cycle=result['cycles'][-1],
        buffer_last_cycles={name:rows[-1] for name,rows in result['buffers'].items()}),indent=2))
