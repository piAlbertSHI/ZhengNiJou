"""Audit failed cold diagnostics as rejected candidates, never as recovery inputs."""
import argparse
import json
from pathlib import Path
from Audit_HeatDriveECC_SegmentedEvidence import sha256


REQUIRED_FALSE = ('inspection_pass','checkpoint_saved','production_recovery_allowed',
                  'c200_state_imported','failed_terminal_state_imported')


def audit_package(repo, folder):
    folder=Path(folder).resolve()
    record_path=folder/'compiled_states_inspection.json'
    if not record_path.is_file(): raise ValueError('Missing compiled inspection record')
    record=json.loads(record_path.read_text(encoding='utf-8'))
    missing=[k for k in REQUIRED_FALSE if k not in record]
    if missing: raise ValueError('Missing rejection fields: '+','.join(missing))
    for key in REQUIRED_FALSE:
        if record[key] is not False: raise ValueError('Rejection field is not false: '+key)
    if not record.get('simulation_error_message') and not record.get('error_message'):
        raise ValueError('Rejected package has no solver error')
    if record.get('states'): raise ValueError('Rejected package contains promoted states')
    forbidden=[]
    for p in folder.rglob('*'):
        if p.is_file() and p.name.lower() in {'final_operating_point.mat','operating_point.mat','checkpoint.mat'}:
            forbidden.append(str(p))
    if forbidden: raise ValueError('Rejected package contains checkpoint: '+str(forbidden))
    files=[]
    for p in sorted(folder.rglob('*')):
        if p.is_file():
            files.append(dict(path=str(p.relative_to(repo)),bytes=p.stat().st_size,sha256=sha256(p)))
    return dict(schema='heatdrive_ecc_rejected_diagnostic_package_v1',
                package=str(folder.relative_to(repo)),inspection_commit=record.get('inspector_commit'),
                solver_error_present=True,required_rejection_fields_verified=True,
                checkpoint_files_found=0,states_promoted=False,c200_imported=False,
                production_recovery_allowed=False,interpolation_eligible=False,
                files=files,total_bytes=sum(x['bytes'] for x in files))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--package',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path);args=parser.parse_args()
    repo=Path(__file__).resolve().parents[1]
    if args.output.exists(): raise FileExistsError('Never overwrite evidence')
    result=audit_package(repo,args.package);args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='files'},indent=2))
