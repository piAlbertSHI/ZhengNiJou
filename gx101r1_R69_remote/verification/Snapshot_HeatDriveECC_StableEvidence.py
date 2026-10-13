"""Copy compact C102/C122/C142 evidence byte-for-byte; classify raw without deleting."""
import argparse
import json
import shutil
from pathlib import Path

from Audit_HeatDriveECC_SegmentedEvidence import sha256


RUNS = ('v31_stable_constitutive_from_C82_C102_fix6',
        'v31_stable_constitutive_from_C102_C122_fix1',
        'v31_stable_constitutive_from_C122_C142_fix1')


def snapshot(execution, destination):
    if destination.exists():
        raise FileExistsError('Never overwrite an evidence snapshot')
    sources = {}
    for name in RUNS:
        root = execution / 'outputs' / name
        audit = execution / 'outputs_storage_audit'
        paths = [root / relative for relative in (
            'cold_chamber_execution.json', 'v31_completed_warmup_physics.json',
            'native/arm_completion.json', 'native/diagnostic_state_capture.json',
            'native/postprocessing_progress.json')]
        paths += [audit / (name + suffix) for suffix in (
            '_state_drift.json', '_steadiness.json',
            '_saved_mechanism/saved_mechanism_audit.json',
            '_saved_periodicity/saved_periodicity_audit.json',
            '_ten_cycle_periodicity/ten_cycle_thermal_periodicity_audit.json',
            '_endpoint_qualification/diagnostic_resume_qualification.json')]
        paths.append(Path(str(root) + '.stable_config.json'))
        sources[name] = paths
    if any(not p.is_file() for paths in sources.values() for p in paths):
        raise ValueError('Missing required completed evidence')
    copies, retained, obsolete = [], [], []
    destination.mkdir(parents=True)
    for name, paths in sources.items():
        folder = destination / name
        folder.mkdir()
        for index, source in enumerate(paths):
            target = folder / (str(index).zfill(2) + '_' + source.name)
            before = sha256(source)
            shutil.copyfile(source, target)
            if sha256(target) != before:
                raise ValueError('Evidence copy changed bytes')
            copies.append(dict(source=str(source), snapshot=str(target),
                               sha256=before, bytes=source.stat().st_size))
        root = execution / 'outputs' / name
        retained.append(dict(source_root=str(root), role='qualified_diagnostic_chain_dependency',
                             raw_bytes=sum(p.stat().st_size for p in root.rglob('*') if p.is_file()),
                             production_recovery_allowed=False))
    for name in ('v31_stable_constitutive_from_C82_C102_fix3',
                 'v31_stable_constitutive_from_C82_C102_fix4'):
        root = execution / 'outputs' / name
        marker = root / 'INCOMPLETE_DO_NOT_RESUME.json'
        if not marker.is_file():
            raise ValueError('Interrupted package lacks its no-resume marker')
        for p in root.rglob('*.mat'):
            if p.parent.name == 'native' and p.name in (
                    'diagnostic_complete_operating_point.mat',
                    'diagnostic_state_observation.mat', 'public_observations.mat'):
                obsolete.append(dict(path=str(p), sha256=sha256(p), bytes=p.stat().st_size,
                                     classification='obsolete_incomplete_raw_candidate_not_deleted'))
        target = destination / (name + '_INCOMPLETE_DO_NOT_RESUME.json')
        shutil.copyfile(marker,target)
        copies.append(dict(source=str(marker),snapshot=str(target),
                           sha256=sha256(marker),bytes=marker.stat().st_size))
    receipt = dict(schema='heatdrive_ecc_stable_evidence_snapshot_v1', copied=copies,
                   copied_bytes=sum(r['bytes'] for r in copies), retained_chain=retained,
                   obsolete_candidates=obsolete, obsolete_candidate_bytes=sum(r['bytes'] for r in obsolete),
                   files_deleted=0, raw_copied=False, protected_slx_untouched=True, Agent6_untouched=True,
                   physical_gate_modified=False, production_recovery_allowed=False)
    (destination / 'snapshot_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    return receipt


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execution-repo',type=Path,required=True)
    parser.add_argument('--destination',type=Path,required=True)
    args=parser.parse_args()
    result=snapshot(args.execution_repo.resolve(),args.destination.resolve())
    print(json.dumps(dict(copied_files=len(result['copied']),copied_bytes=result['copied_bytes'],
                         obsolete_candidate_bytes=result['obsolete_candidate_bytes'],files_deleted=0)))
