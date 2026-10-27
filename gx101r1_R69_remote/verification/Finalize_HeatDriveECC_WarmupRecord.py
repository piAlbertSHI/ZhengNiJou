"""Finalize a post-simulation receipt when only its final JSON write failed."""
import argparse
import json
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_TraceColumns import unpack
from scipy.io import loadmat


def finalize(root):
    root=root.resolve();pending=json.loads((root/'terminal_OP_saved_pending_observations.json').read_text(encoding='utf-8'))
    failed=json.loads((root/'FAILED_DO_NOT_RESUME.json').read_text(encoding='utf-8'))
    assert failed['error_identifier']=='MATLAB:nonExistentField'
    assert not (root/'new_process_restore.json').exists()
    source_record=dict(pending);source_record.update(failed)
    assert source_record['terminal_OP_path']==failed['terminal_OP_path']
    for name,key in (('diagnostic_complete_operating_point.mat','terminal_OP_sha256'),
                     ('warmup_context.mat','context_sha256'),
                     ('new_process_restored_observations.mat','observation_sha256')):
        path=root/name
        assert path.is_file() and sha256(path)==source_record[key], (name, path)
    parent=json.loads((Path(source_record['source_root'])/'new_process_restore.json').read_text(encoding='utf-8'))
    review=json.loads(Path('C:/Users/86182/Desktop/正逆耦合/gx101r1_R69_remote/outputs_storage_audit/shared_endpoint_OP_C40_20261027/shared_endpoint_warmup_review.json').read_text(encoding='utf-8'))
    assert review['completed_total_cycles']==40 and review['terminal_OP_sha256']==parent['terminal_OP_sha256']
    saved=loadmat(root/'new_process_restored_observations.mat',simplify_cells=True)
    packets={}
    for group in ('native','workspace','source','state'):
        packets.update(unpack(saved[group+'_packet']))
    times=[float(row['time_s'][-1]) for row in packets.values()]
    first=min(float(row['time_s'][0]) for row in packets.values());last=max(times)
    record=dict(source_record)
    record.update(execution_complete=True,actual_tout_first_s=first,actual_tout_last_s=last,
        source_root=source_record['source_root'],source_OP_sha256=parent['terminal_OP_sha256'],
        checksum_policy='error/error',complete_cycle_numerical_equivalence_evaluated=False,
        state_projection_or_reset_used=False,reader_source_sha256=sha256(Path(__file__)),
        finalization_reason='MATLAB simulation completed; only the original post-simulation receipt write referenced the C40 parent using the wrong metadata field.',
        preserved_failed_receipt_sha256=sha256(root/'FAILED_DO_NOT_RESUME.json'))
    out=root/'new_process_restore.json';assert not out.exists()
    out.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'execution_complete':True,'completed_total_cycles':60,'actual_tout_first_s':first,'actual_tout_last_s':last,
                      'terminal_OP_sha256':record['terminal_OP_sha256'],'observation_sha256':record['observation_sha256']}))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True)
    finalize(p.parse_args().root)
