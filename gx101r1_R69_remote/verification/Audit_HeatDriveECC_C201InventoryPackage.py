"""Recompute and package C201 storage diagnostics without granting production use."""
import argparse
import csv
from datetime import datetime
import json
from pathlib import Path
import subprocess
import sys

from Audit_HeatDriveECC_C201Inventory import compute
from Audit_HeatDriveECC_C201CyclePackage import cache,read,write
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def scope(result):
    if (result['schema']!='heatdrive_ecc_c201_native_inventory_v2' or not result['computation_complete']
            or result['component_count']!=119 or result['native_trace_count']!=1240
            or result['sample_count']!=10001 or result['intervals_omitted']!=0
            or result['external_boundaries_fully_observed'] or result['full_device_first_law_verified']
            or result['production_recovery_allowed'] or result['table4_reproduction_claim']):
        raise ValueError('Scientific scope changed')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]
    workspace=repo.parent
    audit=repo/'outputs_storage_audit'
    evidence=audit/'c201_inventory_20260907_v2'
    root=audit/'c201_inventory_release_20260907'
    result=read(evidence/'native_inventory_v2.json')
    scope(result)
    with (evidence/'native_inventory_v2.csv').open(encoding='utf-8-sig',newline='') as f:
        table=list(csv.DictReader(f))
    if len(table)!=119:
        raise ValueError('Incomplete human-readable component table')
    for csv_row,json_row in zip(table,result['components']):
        for key,value in csv_row.items():
            if (float(value)!=json_row[key] if isinstance(json_row[key],(int,float)) else value!=json_row[key]):
                raise ValueError('CSV differs from the scientific JSON')
    subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_C201CyclePackage.py')],
                   check=True,stdout=subprocess.DEVNULL)
    for relative,digest in result['input_sha256'].items():
        path=(repo/relative).resolve()
        if not path.is_relative_to(repo) or sha256(path)!=digest:
            raise ValueError('Inventory input changed: '+relative)
    if args.create:
        if root.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
            raise ValueError('Require clean source and fresh package')
        recomputed,_=compute(repo)
        if recomputed!=result:
            raise ValueError('Independent reread changed ledger')
        root.mkdir()
        commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=workspace,text=True).strip()
        base=read(audit/'tl_inventory_release_20260906/release.json')
        source_zip=audit/'tl_inventory_release_20260906/source_snapshot.zip'
        if sha256(source_zip)!=base['source_archive_sha256']:
            raise ValueError('Base source changed')
        patch=root/'source_delta.patch'
        subprocess.run(['git','diff','--binary',f'--output={patch}',base['source_commit'],commit],cwd=workspace,check=True)
        subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=workspace,check=True)
        with (root/'python_tests.log').open('w',encoding='utf-8') as log:
            subprocess.run([sys.executable,'-m','unittest','discover','-s',str(repo/'verification'),'-p','test_*.py','-v'],
                           check=True,stdout=log,stderr=subprocess.STDOUT)
        write(root/'recomputation.json',dict(recomputed_equal=True,components=119,samples=10001,
              production_recovery_allowed=False,full_device_first_law_verified=False))
        files=[p for p in workspace.rglob('*') if p.is_file()]
        folders={}
        for p in files:
            key=str(Path(*p.relative_to(workspace).parts[:2]))
            folders[key]=folders.get(key,0)+p.stat().st_size
        write(root/'workspace_storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
              workspace_bytes=sum(p.stat().st_size for p in files),file_count=len(files),
              top_folders_bytes=dict(sorted(folders.items(),key=lambda item:-item[1])[:15]),
              new_inventory_evidence_bytes=sum(p.stat().st_size for p in evidence.rglob('*') if p.is_file() and not cache(p)),
              copied_production_raw_bytes=0,deleted_bytes_this_stage=0,
              previous_stage_retired_bytes=182430077,
              git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        paths={p for p in evidence.rglob('*') if p.is_file() and not cache(p)}
        paths.update(root.iterdir())
        paths.add(source_zip)
        paths.update(audit/'c201_cycle_release_20260907'/n for n in ('release.json','result_manifest.csv'))
        paths.update(audit/n for n in ('c201_inventory_export_stdout_20260907.log','c201_inventory_export_v2_stdout_20260907.log'))
        paths.update(audit/n for n in ('cleanup_candidates_20260907_132155.csv','cleanup_summary_20260907_132155.txt'))
        paths.add(workspace/'项目文档/报告/SMA-SE正逆耦合_第三十五阶段C201全库存收支审核报告.md')
        rows=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['relative_path','bytes','sha256'])
            writer.writeheader();writer.writerows(rows)
        write(root/'release.json',dict(schema='heatdrive_ecc_c201_inventory_release_v1',source_commit=commit,
              source_base_commit=base['source_commit'],required_file_count=len(rows),tests_exit_code=0,
              parent_package_reaudit_pass=True,recomputed_equal=True,
              simulation_run_this_stage=False,metadata_export_exit_codes=[1,0],
              external_boundaries_fully_observed=False,full_device_first_law_verified=False,
              production_recovery_allowed=False,table4_reproduction_claim=False))
    release=read(root/'release.json')
    if (release['tests_exit_code']!=0 or not release['recomputed_equal'] or release['simulation_run_this_stage']
            or release['external_boundaries_fully_observed'] or release['full_device_first_law_verified']
            or release['production_recovery_allowed'] or release['table4_reproduction_claim']):
        raise ValueError('Invalid release scope')
    with (root/'result_manifest.csv').open(encoding='utf-8',newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows)!=release['required_file_count'] or len({r['relative_path'] for r in rows})!=len(rows):
        raise ValueError('Incomplete manifest')
    for row in rows:
        p=(workspace/row['relative_path']).resolve()
        if not p.is_relative_to(workspace) or p.stat().st_size!=int(row['bytes']) or sha256(p)!=row['sha256']:
            raise ValueError('Changed evidence: '+str(p))
    print(json.dumps(dict(package_integrity_pass=True,required_files=len(rows),source_commit=release['source_commit'],
                          full_device_first_law_verified=False,production_recovery_allowed=False,
                          table4_reproduction_claim=False),indent=2))


if __name__=='__main__':
    main()
