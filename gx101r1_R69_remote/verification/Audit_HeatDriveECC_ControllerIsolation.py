"""Audit isolation provenance and step counts, not coupled-device qualification."""
import argparse
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def step_metrics(t, v):
    if (t.ndim != 1 or len(t) < 2 or v.shape != (len(t), 3)
            or t[0] != 0 or t[-1] != 10 or not np.isfinite(t).all()
            or not np.isfinite(v).all() or np.any(np.diff(t) <= 0)):
        raise ValueError('Invalid isolated trajectory')
    dt = np.diff(t)
    return dict(sample_count=len(t), minimum_step_s=float(dt.min()),
                steps_below_1e_6_s=int(np.sum(dt < 1e-6)),
                sample_counts_by_second=np.histogram(t, bins=np.arange(11))[0].tolist())


def audit(repo):
    base = repo / 'outputs_storage_audit/ps_controller_equivalence_20260909_v2'
    raw = base / 'paired_observations.mat'
    model = base / 'ecc_sma_controller_equivalence.slx'
    if sha256(raw) != '8D1F23D8050CE0CF6574FF23B5BB4FC9A1E2B57EA7304C3D0FC3C1DA841662BA':
        raise ValueError('Baseline observations changed')
    if sha256(model) != 'F00F94B636225240061287F11A374B68091F38859E3AA6BF5A3257EB27981BB4':
        raise ValueError('Baseline model changed')
    files = [raw, model]
    cases = []
    for side, folder in [('reference', 'controller_reference_isolation_20260909_v2'),
                         ('candidate', 'controller_candidate_isolation_20260909')]:
        root = repo / 'outputs_storage_audit' / folder
        record_path = root / 'controller_isolation.json'
        r = read(record_path)
        public = root / 'isolated_public_traces.mat'
        if (r['execution_commit'] != 'c0c7f4081372d43d36af33a456fadb35cd5ed509'
                or r['side'] != side or not r['collection_pass'] or r['simulation_error']
                or r['coupled_model_tested'] or r['production_recovery_allowed']
                or r['baseline_observations_sha256'] != sha256(raw)
                or r['baseline_model_sha256'] != sha256(model)
                or r['observations_sha256'] != sha256(public)):
            raise ValueError('Isolation provenance failed')
        if r['solver_parameters'] != dict(Solver='ode15s', SolverType='Variable-step',
                MaxStep='.001', RelTol='1e-9', AbsTol='1e-11', StopTime='10', AlgebraicLoopMsg='error'):
            raise ValueError('Solver contract changed')
        with h5py.File(public) as f:
            result = step_metrics(f['time_s'][...].ravel(), f['values'][...].T)
        if any(r[k] != value for k, value in result.items()):
            raise ValueError('Reported counts disagree with raw arrays')
        result.update(side=side, simulation_wall_seconds=r['simulation_wall_seconds'])
        cases.append(result)
        files += [record_path, public, root / 'matlab_diary.log']
    pair_path = repo / 'outputs_storage_audit/ps_controller_pair_audit_20260909/controller_pair_audit.json'
    pair = read(pair_path)
    if not pair['isolated_equivalence_pass']:
        raise ValueError('Paired equivalence evidence failed')
    paired_count = pair['cases'][0]['sample_count']
    files.append(pair_path)
    freeze_path = repo / 'verification/c200_mainline_freeze_contract.json'
    freeze = read(freeze_path)
    files.append(freeze_path)
    for key in ('result', 'checkpoint'):
        path = repo / freeze[key + '_relative_path']
        if sha256(path) != freeze[key + '_sha256']:
            raise ValueError('Frozen C200 evidence changed')
        files.append(path)
    return dict(schema='heatdrive_ecc_controller_isolation_audit_v1', evidence_audit_pass=True,
                cases=cases, paired_sample_count=paired_count,
                paired_to_candidate_sample_ratio=paired_count / cases[1]['sample_count'],
                paired_microstep_profile_reproduced_by_candidate_alone=False,
                precise_solver_cost_cause_proven=False, coupled_model_tested=False,
                production_recovery_allowed=False, full_device_first_law_verified=False,
                c200_authority_status=freeze['authority_status'],
                c200_restore_allowed_current_model=freeze['resume_policy']['state_recovery_allowed_current_model'],
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result = audit(Path(__file__).resolve().parents[1])
    args.output_root.mkdir(parents=True)
    (args.output_root / 'controller_isolation_audit.json').write_text(
        json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
