"""Audit physical-state preservation separately from failed full initialization."""
import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys

import numpy as np

from Audit_HeatDriveECC_C201CyclePackage import cache,read,write
from Audit_HeatDriveECC_DigitalConverterHistory import compute as digital_compute
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TargetInitialization import compute,rows as observations


def evidence(repo):
    audit=repo/'outputs_storage_audit'
    names=('joint_converter_history_seeded_op_20260908','joint_differential_seeded_op_20260908')
    verified=[]
    for name in names:
        actual=compute(repo,audit/name);saved=read(audit/name/'independent_initialization_audit_v2.json')
        if actual!=saved or actual['all_observations_roundtrip_pass'] or actual['production_recovery_allowed']:
            raise ValueError('Rejected full comparison changed')
        if actual['failed_initial_groups']!=7 or actual['failed_one_step_groups']!=197:
            raise ValueError('Full comparison counts changed')
        verified.append(actual)
    if verified[-1]['exact_initial_dynamic_state_count']!=125 or verified[-1]['failed_one_step_dynamic_state_count']!=1:
        raise ValueError('Dynamic-state outcome changed')
    digital=read(audit/'c200_converter_digital_history_20260908/independent_digital_history_audit.json')
    if digital_compute(repo,audit/'c200_converter_digital_history_20260908')!=digital:
        raise ValueError('Digital observation changed')
    rejected=read(audit/'joint_converter_flux_seeded_op_20260908/initialization_probe_audit.json')
    failed=[r for r in rejected['seed_target_matches'] if not r['pass']]
    if (rejected['computation_complete'] or rejected['seed_target_preservation_pass']
            or len(failed)!=2 or any(not r['path'].endswith('/p_I') for r in failed)
            or rejected['seed_generated_model_op_used']):
        raise ValueError('Rejected flux seed was propagated or its failure changed')
    old=observations(audit/'joint_target_controller_seeded_op_20260908/joint_initialization_observations.mat')
    history=observations(audit/names[0]/'joint_initialization_observations.mat')
    dynamic=observations(audit/names[1]/'joint_initialization_observations.mat')
    if not set(old)==set(history)==set(dynamic) or len(old)!=1474:
        raise ValueError('Incomplete probe-to-probe comparison')
    changed=[k for k in old if not np.array_equal(old[k][2],history[k][2])]
    unchanged_step=sum(np.array_equal(old[k][2][...,-1],history[k][2][...,-1]) for k in old)
    if len(changed)!=42 or any('/ConstitutiveHeatPS_' not in k for k in changed) or unchanged_step!=1474:
        raise ValueError('Converter-only causal result changed')
    reference=observations(audit/'c200_source_compatibility_20260907/archived_source_probe_v4/restored_step_signals.mat')
    reference.update(observations(audit/'c200_source_compatibility_20260907/archived_source_probe_v4/registered_states.mat',True))
    csv_rows=[]
    for r in verified[-1]['comparisons']:
        unit,_,values=reference[r['key']];_,_,actual=dynamic[r['key']]
        for i,phase in enumerate(('initial','one_step')):
            csv_rows.append(dict(group=r['key'],native_unit=unit,phase=phase,time_s=(2000,2000.001)[i],
                channel_count=r[phase]['channel_count'],pass_existing_tolerance=r[phase]['pass_endpoint_match'],
                bitwise_exact=r['exact_'+phase],max_abs_error=r[phase]['max_abs_error'],
                max_scaled_error=r[phase]['max_scaled_error'],
                reference_values=json.dumps(values[...,i].reshape(-1).tolist()),
                actual_values=json.dumps(actual[...,i].reshape(-1).tolist())))
    summary=dict(schema='heatdrive_ecc_dynamic_initialization_comparison_v1',
        converter_only_changed_groups=changed,converter_only_unchanged_one_step_count=unchanged_step,
        original_declared_target_count=125,actual_differential_coordinate_count=125,
        newly_observed_coordinates=dict(pipe_specific_internal_energy=67,buffer_mass=4),
        exact_initial_dynamic_coordinate_count=125,failed_one_step_dynamic_coordinate_count=1,
        initial_failed_groups=7,one_step_failed_groups=197,failed_flux_seed_targets=failed,
        whole_model_migration_verified=False,production_recovery_allowed=False)
    return summary,csv_rows


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--create',action='store_true');args=p.parse_args()
    repo=Path(__file__).resolve().parents[1];workspace=repo.parent;audit=repo/'outputs_storage_audit'
    root=audit/'dynamic_initialization_release_20260908'
    summary,csv_rows=evidence(repo)
    subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_ConverterPackage.py')],
                   check=True,stdout=subprocess.DEVNULL)
    folders=[audit/n for n in ('c200_converter_digital_history_20260908','joint_converter_history_seeded_op_20260908',
                              'joint_converter_flux_seeded_op_20260908','joint_differential_seeded_op_20260908')]
    if args.create:
        if root.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
            raise ValueError('Require clean source and a fresh package')
        root.mkdir();commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        base=read(audit/'tl_inventory_release_20260906/release.json');source_zip=audit/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(source_zip)!=base['source_archive_sha256']:raise ValueError('Source base changed')
        patch=root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',base['source_commit'],commit],cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as f:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),'-p','test_*.py','-v'],
                           check=True,stdout=f,stderr=subprocess.STDOUT)
        write(root/'comparison_summary.json',summary)
        with (root/'full_1474_group_comparison.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=list(csv_rows[0]));writer.writeheader();writer.writerows(csv_rows)
        files=[p for p in workspace.rglob('*') if p.is_file()];size=sum(p.stat().st_size for p in files)
        write(root/'storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
            workspace_bytes=size,workspace_GiB=size/2**30,file_count=len(files),
            new_evidence_bytes=sum(p.stat().st_size for folder in folders for p in folder.rglob('*') if p.is_file()),
            production_raw_copied_bytes=0,deleted_bytes=0,
            git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        paths={p for folder in folders+[root] for p in folder.rglob('*') if p.is_file() and not cache(p)}
        paths.add(source_zip);paths.add(audit/'c200_differential_target_metadata_20260908.json')
        paths.update(audit/'converter_phase_release_20260908'/n for n in ('release.json','result_manifest.csv'))
        paths.update(audit/n for n in ('cleanup_candidates_20260908_074535.csv','cleanup_summary_20260908_074535.txt'))
        paths.add(workspace/'项目文档/报告/SMA-SE正逆耦合_第四十阶段动态状态初始化审核报告.md')
        manifest=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['relative_path','bytes','sha256']);writer.writeheader();writer.writerows(manifest)
        write(root/'release.json',dict(schema='heatdrive_ecc_dynamic_initialization_release_v1',source_commit=commit,
            source_base_commit=base['source_commit'],required_file_count=len(manifest),tests_exit_code=0,
            probe_program_exit_codes=[0,1,0],full_scientific_gate_pass=False,
            exact_initial_dynamic_coordinate_count=125,production_recovery_allowed=False,
            full_device_first_law_verified=False))
    if read(root/'comparison_summary.json')!=summary:raise ValueError('Comparison summary changed')
    with (root/'full_1474_group_comparison.csv').open(encoding='utf-8',newline='') as f:actual=list(csv.DictReader(f))
    if actual!=[{k:str(v) for k,v in r.items()} for r in csv_rows]:raise ValueError('Full comparison CSV changed')
    release=read(root/'release.json')
    if release['full_scientific_gate_pass'] or release['production_recovery_allowed'] or release['tests_exit_code']!=0:
        raise ValueError('Scientific scope changed')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as f:manifest=list(csv.DictReader(f))
    if len(manifest)!=release['required_file_count'] or len({r['relative_path'] for r in manifest})!=len(manifest):
        raise ValueError('Incomplete manifest')
    for r in manifest:
        path=(workspace/r['relative_path']).resolve()
        if not path.is_relative_to(workspace) or path.stat().st_size!=int(r['bytes']) or sha256(path)!=r['sha256']:
            raise ValueError('Evidence changed: '+str(path))
    print(json.dumps(dict(package_integrity_pass=True,required_files=len(manifest),source_commit=release['source_commit'],
                         exact_initial_dynamic_coordinates=125,full_scientific_gate_pass=False,production_recovery_allowed=False),indent=2))


if __name__=='__main__':main()
