"""Separate a constructor permission failure from an evaluated scientific rejection."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read, compact_evidence


def record(experiment,output):
    experiment=experiment.resolve();output=output.resolve();repo=Path(__file__).resolve().parents[1]
    if output.exists() or output.parent!=repo/'outputs_storage_audit':raise ValueError('Require a fresh local archive')
    execution=read(experiment/'cold_chamber_execution.json');case=read(experiment/'native/sensitivity_case_contract.json')
    if (execution['error_message']!='Diagnostic chamber geometry must be nominal or an explicit cold-only volume intervention.' or
            'ensure_sma_pump_manifold_volume' not in execution['error_report'] or
            (experiment/'native/sensitivity_cold_case').exists() or list(experiment.rglob('comparison_only_complete_op.mat')) or
            case['source_state_imported'] or case['production_recovery_allowed']):
        raise ValueError('This constructor-only rejection classification does not fit the actual evidence')
    raw=Path(case['fresh_native_source_path'])
    if sha256(raw)!=case['fresh_native_source_sha256']:raise ValueError('Changed native t0 diagnostic')
    marker=read(experiment/'REJECTED_DO_NOT_RESUME.json')
    if marker['original_mechanism_gates_evaluated'] or marker['recovery_allowed']:raise ValueError('Wrong rejection scope')
    output.mkdir();copies=[];retained=[]
    for p in sorted(experiment.rglob('*')):
        if not p.is_file():continue
        rel=p.relative_to(experiment);row=dict(path=str(p),bytes=p.stat().st_size,sha256=sha256(p))
        if not {'cache','codegen','component_build','buffer_component_build'}.intersection(rel.parts) and compact_evidence(p,row['bytes']):
            destination=output/'evidence'/rel;destination.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,destination)
            copies.append(dict(**row,archive_relative=str(destination.relative_to(output))))
        else:retained.append(dict(**row,classification='single execution diagnostic or regenerable build cache'))
    for suffix in ('.preflight_config.json','.stdout.log','.stderr.log','.matlab.log'):
        p=Path(str(experiment)+suffix)
        if p.exists():
            shutil.copyfile(p,output/p.name)
            copies.append(dict(path=str(p),bytes=p.stat().st_size,sha256=sha256(p),archive_relative=p.name))
    producer=execution['execution_commit'];source='gx101r1_R69_remote/Check_HeatDriveECC_DiagnosticManifoldGeometry.m'
    code=subprocess.check_output(['git','-C',str(repo.parent),'show',producer+':'+source])
    snapshot=output/'actual_producer_geometry_guard.m';snapshot.write_bytes(code)
    volume=next(r for r in case['parameters'] if r['field']=='branch.sma_pump_manifold_volume_m3')
    summary=dict(schema='heatdrive_ecc_L8_constructor_rejection_v1',case_index=case['design']['run_index'],producer=producer,
        terminal_exit_code=1,classification='construction_authorization_failure_before_coupled_cycle_execution',
        completed_coupled_cycles=0,native_probe_window_s=[0,.001],original_scientific_gates_evaluated=False,
        scientific_inadmissibility_established=False,case_still_pending_after_infrastructure_repair=True,
        volume_declaration=volume,source_native_probe_sha256=case['fresh_native_source_sha256'],
        source_guard_snapshot_sha256=sha256(snapshot),source_execution_sha256=sha256(experiment/'cold_chamber_execution.json'),
        preserve_original_factor_range=True,failed_state_propagation_allowed=False,
        full_L8_effects_evaluated=False,production_recovery_allowed=False,table4_reproduction_claim=False)
    (output/'constructor_rejection.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    receipt=dict(compact_copies=copies,retained_single_execution_files=retained,raw_copied_bytes=0,raw_deleted_bytes=0)
    (output/'storage_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    return dict(case_index=summary['case_index'],completed_coupled_cycles=0,scientific_gates_evaluated=False,
        summary_sha256=sha256(output/'constructor_rejection.json'),compact_copied_bytes=sum(r['bytes'] for r in copies),
        retained_single_execution_bytes=sum(r['bytes'] for r in retained))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--experiment',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    print(json.dumps(record(**vars(p.parse_args())),indent=2))
