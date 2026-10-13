"""Close a source-bound reboot recovery; distinguish restore identity from steady state."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CoupledEnergyInventory import ROOT, latent_decomposition, system_balance
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def require_exact_cycle(proof):
    states, signals = proof['state_comparisons'], proof['signal_comparisons']
    if (len(states) != 74 or len(signals) != 201 or
            not proof['rebuilt_complete_cycle_pass'] or not proof['strict_restore_completed'] or
            not proof['continuous_reference_pass'] or proof['checksum_policy'] != 'error/error' or
            proof['source_state_edited'] or proof['partial_state_restore_used'] or proof['error_message'] or
            proof['start_time_s'] != 20 or proof['stop_time_s'] != 30 or
            any(row['samples'] != 10001 or not row['clock_pass'] or not row['values_exact'] or
                row['max_absolute_difference'] != 0 for row in states + signals)):
        raise ValueError('Incomplete exact reconstructed-cycle identity proof')
    checks = proof['bounded_restored_cycle_mechanism_checks']
    if (proof['bounded_restored_cycle_mechanism_pass'] is not True or
            len(checks) != 73 or not all(value is True for value in checks.values())):
        raise ValueError('Full original mechanism checks are missing')


def audit(root, local_path, source_audit_path):
    arm = root / 'native'
    proof = read(arm / 'rebuilt_cycle_restore.json')
    require_exact_cycle(proof)
    local = read(local_path)
    if not all(local[key] is True for key in
               ('strict_full_cycle_state_restore_pass', 'mechanism_pass', 'local_inventory_pass')):
        raise ValueError('Actual restored physics/local inventory did not pass')
    for relative, expected in local['input_sha256'].items():
        path = (arm / relative).resolve()
        if not path.is_relative_to(arm) or sha256(path) != expected:
            raise ValueError('Changed or escaped restored-cycle evidence')
    source = read(source_audit_path)
    folder = Path(proof['source_root']).resolve()
    case = source['cases'][1]
    if (folder != Path(source['source_root']).resolve() / 'coherent' or
            proof['source_operating_point_sha256'] != case['OP_sha256'] or
            proof['source_history_sha256'] != case['history_sha256'] or
            sha256(folder / 'native/diagnostic_complete_operating_point.mat') != case['OP_sha256'] or
            sha256(folder / 'native/diagnostic_state_observation.mat') != case['history_sha256']):
        raise ValueError('C2 checkpoint changed or belongs to another chain')
    time = 20 + np.arange(10001) * .001
    with h5py.File(arm / 'restored_physical_observation.mat') as f:
        state = f['signals/ECC_constitutive21_output/values'][:]
        phase = np.vstack([state[a:b].mean(axis=0) for a, b in ((42, 63), (63, 84))])
        command = sum(f['signals/' + name + '/values'][:].sum(axis=0)
                      for name in ('ECC_Q_SMA_constitutive_W', 'ECC_Q_SE_constitutive_W'))
        cfg = f['configured']
        coefficients = np.array([float(cfg['equilibrium/' + mass][0, 0]) *
                                 float(cfg['material/' + material + '/Delta_h_J_per_kg'][0, 0])
                                 for mass, material in (('m_a_kg', 'SMA'), ('m_r_kg', 'SE'))])
        latent = latent_decomposition(time, command, phase, coefficients)
    ledger = local['inventory_ledger']
    balance = system_balance({name: data['BE_energy_J'] for name, data in ledger['source_ledger'].items()},
                             ledger['actual_endpoint_storage_plus_pdv_J'], latent)
    if not balance['model_equation_energy_closure_pass']:
        raise ValueError('Restored modeled heat/latent balance failed')
    buffers = {}
    with h5py.File(arm / 'restored_native_ledger_observation.mat') as f:
        rows = named_rows(f, f['native'])
        for name in ('ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer'):
            mass = scalar_series(rows[ROOT + name, 'stored_mass'], 'kg')
            flow = scalar_series(rows[ROOT + name, 'mdot_A'], 'kg/s')
            if mass.shape != time.shape or flow.shape != time.shape:
                raise ValueError('Missing full restored buffer window')
            delta = float(mass[-1] - mass[0])
            residual = float(np.sum(flow[1:] * np.diff(time)) - delta)
            if abs(residual) > 1e-15:
                raise ValueError('Restored buffer mass conservation failed')
            buffers[name] = dict(endpoint_mass_change_kg=delta, mass_equation_residual_kg=residual)
    execution = read(root / 'cold_chamber_execution.json')
    files = ('cold_chamber_execution.json', 'native/rebuilt_cycle_restore.json',
             'native/rebuilt_cycle_comparison.mat', 'native/restored_native_ledger_observation.mat',
             'native/restored_physical_observation.mat', 'native/configuration.mat')
    return dict(schema='heatdrive_ecc_reboot_recovery_closeout_v1', source_root=str(folder),
                restored_root=str(root), source_audit_sha256=sha256(source_audit_path),
                local_ledger_sha256=sha256(local_path), execution_commit=execution['execution_commit'],
                actual_restored_window_s=[20, 30], source_checkpoint_time_s=20,
                source_operating_point_sha256=case['OP_sha256'], source_history_sha256=case['history_sha256'],
                restored_endpoint_operating_point_saved=False,
                exact_state_groups=74, exact_signals=201, samples_per_comparison=10001,
                maximum_state_or_signal_difference=0, checksum_policy='error/error',
                full_cycle_restore_verified=True, mechanism_checks_passed=73,
                local_inventory_pass=True, modeled_energy_balance=balance, C3_buffers=buffers,
                periodic_steady_state=False, production_recovery_allowed=False,
                outer_solve_eligible=False, table4_reproduction_claim=False,
                source_state_reset=False, diagnostic_warmup_launched=False,
                input_sha256={name: sha256(root / name) for name in files},
                interpretation='C2 survived reboot and restores exactly over C3. C3 is a comparison, '
                'not a new saved endpoint. Continue structural SMA work; do not hide inventory migration '
                'with longer warmup or import C200.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--local-ledger', type=Path, required=True)
    parser.add_argument('--source-audit', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite a recovery closeout')
    result = audit(args.root.resolve(), args.local_ledger.resolve(), args.source_audit.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({key: result[key] for key in ('full_cycle_restore_verified', 'mechanism_checks_passed',
                                                  'modeled_energy_balance', 'C3_buffers', 'outer_solve_eligible')}))
