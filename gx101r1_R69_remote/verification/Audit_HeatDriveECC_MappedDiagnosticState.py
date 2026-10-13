"""Map saved named states to exact public traces, keeping opaque states separate."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ObservedStateDrift import (
    comparison_grid, coordinate_metrics, matlab_text,
)
from Audit_HeatDriveECC_SegmentedEvidence import sha256


FIELDS = (
    ('xM_a_21', '1'), ('xM_r_21', '1'),
    ('sigma_a_21', 'Pa'), ('sigma_r_21', 'Pa'),
    ('epsilon_a_21', '1'), ('epsilon_r_21', '1'),
    ('pai_a_21', 'Pa'), ('pai_r_21', 'Pa'),
    ('r_xi_a_21', '1/s'), ('r_xi_r_21', '1/s'),
)
DELAYS = {
    'ECC_Constitutive21_SMA_TempDelay': 'SMA_Tx21_internal',
    'ECC_Constitutive21_SE_TempDelay': 'SE_Tx21_internal',
    'DistributedFFTemperatureDelay': 'distributed_fluid_temperature21_K',
}


def exact_indices(time, reference, delay_s):
    time = np.asarray(time, dtype=float).ravel()
    reference = np.asarray(reference, dtype=float).ravel()
    if min(time.size, reference.size) < 2 or not np.isfinite(time).all():
        raise ValueError('Invalid observation clock')
    dt = float(np.median(np.diff(reference)))
    tolerance = 16 * np.spacing(max(abs(reference).max(), abs(time).max(), 1))
    if dt <= 0 or not np.all(abs(np.diff(reference) - dt) <= tolerance):
        raise ValueError('Public clock must be uniform and strictly increasing')
    indices = np.rint((time - delay_s - reference[0]) / dt).astype(int)
    if (indices.min() < 0 or indices.max() >= reference.size
            or not np.all(np.diff(indices) == 1)
            or not np.all(abs(reference[indices] - (time - delay_s)) <= tolerance)):
        raise ValueError('Missing exact delayed public samples; interpolation is forbidden')
    return indices


def compare(values, expected):
    values = np.asarray(values)
    expected = np.asarray(expected)
    if values.shape != expected.shape or not np.isfinite(values).all():
        raise ValueError('Invalid mapped dimensions or nonfinite state')
    if not np.array_equal(values, expected):
        raise ValueError('Named state does not equal its declared public trace')


def producer_sources(repo, commit):
    paths = ('HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic.m',
             'HeatDriveECC_ConstitutiveCompatibilityStep51.m',
             'verification/Integrate_HeatDriveECC_StableConstitutiveSample.m')
    result = {}
    for relative in paths:
        git_path = 'gx101r1_R69_remote/' + relative
        historical = subprocess.run(
            ['git', '-C', str(repo), 'show', commit + ':' + git_path],
            check=True, capture_output=True).stdout
        current = (repo / relative).read_bytes()
        if historical.replace(b'\r\n', b'\n') != current.replace(b'\r\n', b'\n'):
            raise ValueError('State mapping source differs from execution producer: ' + relative)
        result[relative] = dict(producer_sha256=hashlib.sha256(historical).hexdigest().upper(),
                                working_file_sha256=sha256(repo / relative))
    return result


def audit(root, mechanism_path, repo):
    execution_file = root / 'cold_chamber_execution.json'
    read = lambda p: json.loads(p.read_text(encoding='utf-8-sig'))
    execution, mechanism = read(execution_file), read(mechanism_path)
    files = {'execution': execution_file, 'observation': root / 'native/observations.mat',
             'history': root / 'native/diagnostic_state_observation.mat',
             'configuration': root / 'native/configuration.mat', 'mechanism': mechanism_path}
    hashes = {name: sha256(p) for name, p in files.items()}
    if (not execution['requested_arm_collection_pass'] or execution['error_message']
            or not mechanism['mechanism_pass'] or len(mechanism['checks']) != 73
            or not all(mechanism['checks'].values())
            or mechanism['source_execution_sha256'] != hashes['execution']
            or mechanism['source_observation_sha256'] != hashes['observation']
            or mechanism['source_configuration_sha256'] != hashes['configuration']):
        raise ValueError('Require the same complete mechanism-passing trajectory')
    sources = producer_sources(repo, execution['execution_commit'])
    mapped, unmatched = [], []
    with h5py.File(files['configuration']) as config:
        c = config['options/constitutive']
        if matlab_text(c['diagnostic_step_function']) != 'HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic':
            raise ValueError('Unsupported constitutive interface contract')
        dt = float(c['simulink_sample_time_s'][0, 0])
        tau = float(config['options/schedule/tau_cycle_s'][0, 0])
    with h5py.File(files['observation']) as public, h5py.File(files['history']) as history:
        seen = set()
        for ref in history['observation/states'][:].flat:
            state = history[ref]
            path = matlab_text(state['block_path'])
            if path in seen:
                raise ValueError('Duplicate saved state path')
            seen.add(path)
            name = path.rsplit('/', 1)[-1]
            time = state['time_s'][:].ravel()
            count = state['values'].shape[0]
            if name == 'ECC_Constitutive21_StateDelay':
                groups = [(field, unit, slice(k*21, (k+1)*21), 42+k*21)
                          for k, (field, unit) in enumerate(FIELDS)]
                signal, delay = 'ECC_constitutive21_output', dt
                if count != 210:
                    raise ValueError('Unexpected constitutive state width')
            elif name in DELAYS:
                groups = [(name, 'K', slice(0, 21), 0)]
                signal, delay = DELAYS[name], dt
                if count != 21:
                    raise ValueError('Unexpected temperature delay width')
            elif name == 'SEStage4PressurePI_Integrator':
                groups = [(name, 'MPa', slice(0, 1), 0)]
                signal, delay = 'stage4_integrator_state', 0
                if count != 1:
                    raise ValueError('Unexpected route memory width')
            else:
                unmatched.append(dict(block_path=path, coordinates=count,
                                      reason='not_mapped_by_this_audit'))
                continue
            pair = comparison_grid(time, tau)
            if pair is None:
                raise ValueError('Require ten exact lagged state comparisons')
            row = public['signals/' + signal]
            indices = exact_indices(time, row['time_s'][:], delay)
            for field, unit, selected, column in groups:
                values = state['values'][selected, :]
                width = values.shape[0]
                expected = row['values'][column:column+width, indices[0]:indices[-1]+1]
                compare(values, expected)
                metrics = coordinate_metrics(values, *pair)
                mapped.append(dict(block_path=path, field=field, physical_unit=unit,
                                   coordinates=width, source_signal=signal,
                                   source_columns_matlab_1based=[column+1, column+width],
                                   sample_delay_s=delay, samples=time.size,
                                   exact_public_identity=True,
                                   window_s=[float(time[pair[0][0]]), float(time[-1])],
                                   metrics=metrics, physical_periodicity_gate_assigned=False))
    return dict(schema='heatdrive_ecc_mapped_diagnostic_state_v1', total_cycles=execution['cycle_count'],
                source_execution_commit=execution['execution_commit'], source_root=str(root),
                exact_mapping_pass=True, mapped_coordinate_count=sum(r['coordinates'] for r in mapped),
                unmatched_coordinate_count=sum(r['coordinates'] for r in unmatched),
                mapped=mapped, unmatched=unmatched, producer_sources=sources, input_sha256=hashes,
                joint_norm_used=False, simulation_executed=False, operating_point_loaded=False,
                complete_internal_state_periodicity_verified=False, production_recovery_allowed=False,
                outer_solve_eligible=False, table4_reproduction_claim=False,
                interpretation='210 constitutive coordinates have distinct units and exact delayed public identities. '
                'Unmapped solver/converter coordinates and undeclared physical periodic tolerances remain separate.')


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--experiment-root', type=Path, required=True)
    p.add_argument('--mechanism-audit', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite mapped evidence')
    result = audit(args.experiment_root.resolve(), args.mechanism_audit.resolve(), Path(__file__).resolve().parents[1])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({k: result[k] for k in ('total_cycles', 'exact_mapping_pass',
        'mapped_coordinate_count', 'unmatched_coordinate_count', 'outer_solve_eligible')}))
