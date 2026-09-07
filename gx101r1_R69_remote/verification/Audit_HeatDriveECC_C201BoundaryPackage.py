"""Freeze tank attribution and one-step boundary coverage, not cycle closure."""
import argparse
import csv
from datetime import datetime
from pathlib import Path
import subprocess
import sys
import json

from Audit_HeatDriveECC_C201CyclePackage import cache,read,write
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--create',action='store_true')
    args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]
    workspace=repo.parent
    audit=repo/'outputs_storage_audit'
    root=audit/'c201_boundary_source_release_20260907'
    tank_root=audit/'c201_tank_basis_20260907'
    probe_root=audit/'c201_boundary_source_probe_20260907'
    tank=read(tank_root/'c201_tank_basis.json')
    probe=read(probe_root/'independent_boundary_audit_v2.json')
    if (not tank['all_tank_intervals_match_prior_equation'] or tank['hypothesis_fitted_to_C201']
            or not probe['instantaneous_port_sum_match'] or probe['exact_comparison_groups']!=1474
            or probe['trace_count']!=162 or probe['full_cycle_boundary_observation_verified']):
        raise ValueError('Scientific diagnosis changed')
    for data in (tank,probe):
        if any(data[k] for k in ('full_device_first_law_verified','production_recovery_allowed','table4_reproduction_claim')):
            raise ValueError('Diagnostic evidence overclaims qualification')
        for path,digest in data['input_sha256'].items():
            if sha256(Path(path))!=digest:
                raise ValueError('Diagnostic input changed: '+path)
    subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_C201InventoryPackage.py')],
                   check=True,stdout=subprocess.DEVNULL)
    if args.create:
        if root.exists() or subprocess.check_output(['git','status','--porcelain'],cwd=workspace,text=True).strip():
            raise ValueError('Require clean source and a fresh package')
        root.mkdir()
        target=root/'recomputed_probe.json'
        subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_BoundaryProbe.py'),
                        '--repo',str(repo),'--output',str(target)],check=True,stdout=subprocess.DEVNULL)
        if read(target)!=probe:
            raise ValueError('Boundary probe recomputation changed')
        replay=root/'tank_recompute'
        subprocess.run([sys.executable,'-X','utf8',str(repo/'verification/Audit_HeatDriveECC_C201TankBasis.py'),
                        '--repo',str(repo),'--output-root',str(replay)],check=True,stdout=subprocess.DEVNULL)
        recomputed=read(replay/'c201_tank_basis.json')
        for data in (recomputed,tank):
            data['input_sha256']={Path(k).name:v for k,v in data['input_sha256'].items()}
        if recomputed!=tank:
            raise ValueError('Tank reconstruction changed')
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
        directories=[tank_root,probe_root,audit/'c201_tank_geometry_20260907']
        files=[p for p in workspace.rglob('*') if p.is_file()]
        write(root/'storage_snapshot.json',dict(measured_at=datetime.now().astimezone().isoformat(),
              workspace_bytes=sum(p.stat().st_size for p in files),file_count=len(files),
              new_scientific_evidence_bytes=sum(p.stat().st_size for d in directories for p in d.rglob('*') if p.is_file() and not cache(p)),
              copied_production_raw_bytes=0,deleted_bytes=0,
              git_objects=subprocess.check_output(['git','count-objects','-vH'],cwd=workspace,text=True)))
        paths={p for d in [root,*directories] for p in d.rglob('*') if p.is_file() and not cache(p)}
        paths.add(source_zip)
        paths.update(audit/'c201_inventory_release_20260907'/n for n in ('release.json','result_manifest.csv'))
        paths.update(audit/n for n in ('c201_tank_geometry_stdout_20260907.log','c201_boundary_source_probe_stdout_20260907.log'))
        paths.add(workspace/'项目文档/研究笔记/2026-09-07_C201_Tank归因与原生边界观测.md')
        rows=[dict(relative_path=str(p.relative_to(workspace)),bytes=p.stat().st_size,sha256=sha256(p)) for p in sorted(paths)]
        with (root/'result_manifest.csv').open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=['relative_path','bytes','sha256'])
            writer.writeheader();writer.writerows(rows)
        write(root/'release.json',dict(schema='heatdrive_ecc_c201_boundary_source_release_v1',source_commit=commit,
              source_base_commit=base['source_commit'],required_file_count=len(rows),tests_exit_code=0,
              independent_recomputation_pass=True,probe_execution_commit='b980cce',probe_exit_code=0,
              full_cycle_boundary_observation_verified=False,full_device_first_law_verified=False,
              production_recovery_allowed=False,table4_reproduction_claim=False))
    release=read(root/'release.json')
    if (release['tests_exit_code']!=0 or not release['independent_recomputation_pass']
            or any(release[k] for k in ('full_cycle_boundary_observation_verified','full_device_first_law_verified',
                                       'production_recovery_allowed','table4_reproduction_claim'))):
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
                          full_cycle_boundary_observation_verified=False,full_device_first_law_verified=False,
                          production_recovery_allowed=False,table4_reproduction_claim=False),indent=2))


if __name__=='__main__':
    main()
