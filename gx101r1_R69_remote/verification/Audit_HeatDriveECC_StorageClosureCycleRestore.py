"""Qualify an exact C3 restore of the new C2 point, never a periodic or production claim."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_CoupledEnergyInventory import ROOT, latent_decomposition, system_balance
from Audit_HeatDriveECC_RebootRecoveryCloseout import require_exact_cycle
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from HeatDriveECC_ObservationWindow import window_indices


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def audit(root, local_path, c2_path):
    arm = root / 'native'
    proof = read(arm / 'rebuilt_cycle_restore.json')
    require_exact_cycle(proof)
    local = read(local_path)
    if (not local['pressure_only_density_storage_declared'] or
            not all(local[key] is True for key in
                    ('strict_full_cycle_state_restore_pass', 'mechanism_pass', 'local_inventory_pass'))):
        raise ValueError('New-model restored inventory/physical qualification is missing')
    for relative, expected in local['input_sha256'].items():
        path = (arm / relative).resolve()
        if not path.is_relative_to(arm) or sha256(path) != expected:
            raise ValueError('Restored-cycle evidence changed')
    source = read(c2_path)
    folder = Path(source['source_root']).resolve()
    if (source['schema'] != 'heatdrive_ecc_storage_closure_state_qualification_audit_v1' or
            not source['rebuilt_cycle_test_allowed'] or not source['full_mechanism_pass'] or
            Path(proof['source_root']).resolve() != folder or
            proof['source_operating_point_sha256'] != source['source_operating_point_sha256'] or
            proof['source_history_sha256'] != source['source_history_sha256'] or
            sha256(folder / 'native/diagnostic_complete_operating_point.mat') != source['source_operating_point_sha256'] or
            sha256(folder / 'native/diagnostic_state_observation.mat') != source['source_history_sha256']):
        raise ValueError('Wrong or changed C2 checkpoint source')
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
        raise ValueError('C3 modeled heat/latent closure failed')
    buffers = {}
    with h5py.File(arm / 'restored_native_ledger_observation.mat') as f:
        rows = named_rows(f, f['native'])
        for name in ('SHEXFluidBuffer', 'SMAHotFluidBuffer', 'ColdFluidBuffer', 'HotFluidBuffer'):
            row = rows[ROOT + name, 'stored_mass']
            indices = window_indices(row['time_s'][:], 20, 30)
            mass = scalar_series(row, 'kg')[indices]
            flow = scalar_series(rows[ROOT + name, 'mdot_A'], 'kg/s')[indices]
            delta = float(mass[-1] - mass[0])
            residual = float(np.sum(flow[1:] * np.diff(time)) - delta)
            if abs(residual) > 1e-15:
                raise ValueError('Restored buffer mass balance failed')
            buffers[name] = dict(endpoint_mass_change_kg=delta, mass_equation_residual_kg=residual)
    files = ('native/rebuilt_cycle_restore.json', 'native/rebuilt_cycle_comparison.mat',
             'native/restored_native_ledger_observation.mat', 'native/restored_physical_observation.mat',
             'native/configuration.mat', 'cold_chamber_execution.json')
    return dict(schema='heatdrive_ecc_storage_closure_complete_cycle_restore_v1', source_root=str(folder),
        restored_root=str(root), C2_audit_sha256=sha256(c2_path), local_ledger_sha256=sha256(local_path),
        source_operating_point_sha256=source['source_operating_point_sha256'],
        source_history_sha256=source['source_history_sha256'], actual_restored_window_s=[20, 30],
        state_groups_exact=74, signals_exact=201, samples_per_comparison=10001,
        checksum_policy='error/error', complete_cycle_restore_verified=True,
        full_mechanism_checks_passed=73, local_inventory_pass=True, modeled_energy_balance=balance,
        C3_buffers=buffers, source_state_edited=False, failed_state_propagated=False,
        restored_endpoint_operating_point_saved=False, diagnostic_warmup_continuation_allowed=True,
        periodic_steady_state=False, real_fluid_EOS_claim=False, production_recovery_allowed=False,
        outer_solve_eligible=False, table4_reproduction_claim=False,
        input_sha256={name: sha256(root / name) for name in files},
        interpretation='New-model C2 is intact and restores exactly over C3. Only an unchanged-model '
                       'diagnostic warmup is admitted; the residual migration and density approximation '
                       'remain scientific limitations, not a periodic/production claim.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--local-ledger', type=Path, required=True)
    parser.add_argument('--c2-audit', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Never overwrite complete-cycle evidence')
    result = audit(args.root.resolve(), args.local_ledger.resolve(), args.c2_audit.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({key: result[key] for key in ('complete_cycle_restore_verified',
        'diagnostic_warmup_continuation_allowed', 'modeled_energy_balance', 'C3_buffers')}))
