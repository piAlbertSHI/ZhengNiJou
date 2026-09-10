"""Read-only output inventory; it never deletes or moves evidence."""
import json
from pathlib import Path
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def build(repo):
    root=repo/'outputs_storage_audit'
    rows=[]
    for folder in sorted(p for p in root.iterdir() if p.is_dir()):
        files=[p for p in folder.rglob('*') if p.is_file()]
        rows.append(dict(name=folder.name,bytes=sum(p.stat().st_size for p in files),
                         file_count=len(files),
                         has_compiled_record=(folder/'compiled_states_inspection.json').is_file(),
                         has_checkpoint=any(p.name.lower() in {'final_operating_point.mat','operating_point.mat','checkpoint.mat'} for p in files),
                         has_hash_manifest=any('audit' in p.name.lower() or 'manifest' in p.name.lower() for p in files)))
    return dict(schema='heatdrive_ecc_output_inventory_v1',read_only=True,delete_count=0,
                repo=str(repo),directory_count=len(rows),directories=rows)


if __name__=='__main__':
    repo=Path(__file__).resolve().parents[1]
    out=repo/'outputs_storage_audit/output_inventory_20260911.json'
    if out.exists():raise FileExistsError('Never overwrite evidence')
    out.write_text(json.dumps(build(repo),indent=2)+'\n',encoding='utf-8')
    print(out)
