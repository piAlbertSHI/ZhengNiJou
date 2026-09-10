"""Verify L8 preflight contains design contracts only, not candidate results."""
import csv
import json
from pathlib import Path
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def build(repo, root):
    root=Path(root).resolve()
    design=root/'sensitivity_design.csv'; pre=root/'sensitivity_preflight.csv'; mat=root/'sensitivity_preflight.mat'
    for p in (design,pre,mat):
        if not p.is_file(): raise ValueError('Missing preflight artifact: '+str(p))
    with design.open(newline='',encoding='utf-8-sig') as f: designs=list(csv.DictReader(f))
    with pre.open(newline='',encoding='utf-8-sig') as f: rows=list(csv.DictReader(f))
    if len(designs)!=8 or len(rows)!=8: raise ValueError('Expected exactly eight L8 rows')
    if {int(r['run_index']) for r in designs}!={1,2,3,4,5,6,7,8}: raise ValueError('Incomplete run indices')
    if any(str(r['contract_pass']).lower() not in {'1','true'} for r in rows): raise ValueError('Contract preflight failed')
    files=[dict(path=str(p.relative_to(repo)),bytes=p.stat().st_size,sha256=sha256(p)) for p in (design,pre,mat)]
    forbidden=[str(p.relative_to(root)) for p in root.rglob('*') if p.is_file() and (
        p.name in {'sensitivity_study.mat','sensitivity_candidate_record.mat','steady_continuation_state.mat','final_operating_point.mat'} or 'interpol' in p.name.lower())]
    if forbidden: raise ValueError('Candidate or interpolation artifact found: '+str(forbidden))
    return dict(schema='heatdrive_ecc_L8_preflight_audit_v1',rows=8,contract_pass_rows=8,
                candidate_files_found=0,interpolation_files_found=0,physical_runs=0,
                interpolation_eligible=False,production_recovery_allowed=False,files=files)


if __name__=='__main__':
    repo=Path(__file__).resolve().parents[1]; root=repo/'outputs/table4_L8_sensitivity_preflight_20260911'
    out=repo/'outputs_storage_audit/L8_sensitivity_preflight_audit_20260911.json'
    if out.exists(): raise FileExistsError('Never overwrite evidence')
    result=build(repo,root);out.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='files'},indent=2))
