"""Quantify finite-window metric variation against existing outer numerical precision."""
import argparse
import json
import math
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read
from Close_HeatDriveECC_RuntimeWarmup import packet_cycles


def precision(cycles):
    if len(cycles)!=10 or any(b['cycle']!=a['cycle']+1 for a,b in zip(cycles,cycles[1:])):
        raise ValueError('Require ten consecutive measured cycles')
    if any(not math.isfinite(r[key]) for r in cycles for key in ('temperature_lift_eq9_K','SCP_W_per_g')):
        raise ValueError('Nonfinite target metric')
    span=lambda key:max(r[key] for r in cycles)-min(r[key] for r in cycles)
    lift,scp=span('temperature_lift_eq9_K'),span('SCP_W_per_g')
    return dict(lift_span_K=lift,SCP_span_W_per_g=scp,lift_limit_K=.1,SCP_limit_W_per_g=.01,
        precision_pass=bool(lift<=.1 and scp<=.01),
        finite_window_variation_only=True,asymptotic_error_bound_claim=False,
        new_physical_tolerance_imposed=False,complete_internal_state_periodicity_claim=False)


def measure(index,output,Tc):
    if output.exists():raise FileExistsError('Never overwrite target-window evidence')
    data=read(index);start,stop=data['window_s'];cycles=[];sources=[]
    if stop-start!=100 or data['sample_count']!=100001 or len(data['packets'])!=5:
        raise ValueError('Require the exact rolling ten-cycle window')
    for k,row in enumerate(data['packets']):
        root=Path(row['packet_root']);m=read(root/'packet_manifest.json')
        if (m['window_s']!=[start+20*k,start+20*(k+1)] or m['prescribed_Tc_K']!=Tc or
                m['packet_role'] not in ('runtime_boundary_Tc_candidate','runtime_boundary_Tc_continuation','runtime_sensitivity_cold','runtime_sensitivity_transient') or
                m['source_state_edited'] or sha256(Path(row['observation_path']))!=row['observation_sha256'] or
                sha256(Path(row['configuration_path']))!=row['configuration_sha256']):
            raise ValueError('Changed, mixed-temperature or incomplete current window')
        cycles.extend(packet_cycles(root));sources.append(dict(path=str(root/'packet_manifest.json'),sha256=sha256(root/'packet_manifest.json')))
    result=dict(schema='heatdrive_ecc_target_window_precision_v1',window_s=[start,stop],temperature_K=Tc,
        measured_window_sha256=sha256(index),cycles=cycles,input_manifests=sources,
        precision_source='Run_HeatDriveECC_Table4_OuterSolve defaults: lift 0.1 K, SCP 0.01 W/g',
        outer_source_sha256=sha256(Path(__file__).with_name('Run_HeatDriveECC_Table4_OuterSolve.m')),
        **precision(cycles))
    output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--Tc',type=float,required=True)
    result=measure(**vars(parser.parse_args()))
    print(json.dumps({k:v for k,v in result.items() if k not in ('cycles','input_manifests')},indent=2))
