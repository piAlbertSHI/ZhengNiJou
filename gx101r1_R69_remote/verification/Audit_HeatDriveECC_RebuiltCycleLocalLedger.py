"""Audit actual restored-cycle numerical ledgers, never granting production recovery."""
import argparse
import json
from pathlib import Path

from Audit_HeatDriveECC_ColdBufferCoupled import BUFFERS, CHAMBERS, cycle_arm, port_contract
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains


def audit(root, pressure_only_density=False):
    folder = root / 'native'
    read = lambda name: json.loads((folder / name).read_text(encoding='utf-8-sig'))
    proof = read('rebuilt_cycle_restore.json')
    if (proof['rebuilt_complete_cycle_pass'] is not True or proof['error_message'] != ''
            or proof['bounded_restored_cycle_mechanism_pass'] is not True
            or not all(value is True for value in proof['bounded_restored_cycle_mechanism_checks'].values())
            or proof['native_ledger_observation_sha256'] != sha256(folder / 'restored_native_ledger_observation.mat')
            or proof['native_ledger_persistence']['all_trace_values_clock_units_metadata_exact'] is not True
            or proof['start_time_s'] != 20 or proof['stop_time_s'] != 30):
        raise ValueError('Incomplete strict restored-cycle evidence')
    assignment, domains = resolve_domains(read('tl_connectivity.json'))
    if domains != 2:
        raise ValueError('Require the actual two independent fluid domains')
    contracts = {row['block_path']: row for row in read('buffer_replacement_contract.json')['buffers']}
    if set(contracts) != BUFFERS:
        raise ValueError('Missing buffer contracts')
    for contract in contracts.values():
        port_contract(contract)
    ledger = cycle_arm(folder, assignment, contracts, mass_formulation='zero_based_offset', start=20, stop=30,
                       observation_file='restored_native_ledger_observation.mat',
                       public_observation_file='restored_physical_observation.mat',
                       pressure_only_density=pressure_only_density)
    local = []
    for row in ledger['components']:
        if row['mask_type'] == 'Conservative Buffer (TL)':
            local.append(row['component_detail']['candidate_component_pass'])
        elif row['block_path'] in CHAMBERS:
            gate = row['local_chamber_gate']
            local.append(gate['mass_closure_pass'] and gate['energy_closure_pass'])
    passed = len(local) == 6 and all(value is True for value in local)
    files = ('rebuilt_cycle_restore.json', 'restored_native_ledger_observation.mat',
             'restored_physical_observation.mat', 'configuration.mat', 'inventory_metadata.json',
             'tl_connectivity.json', 'thermal_connectivity.json', 'buffer_replacement_contract.json')
    return dict(schema='heatdrive_ecc_rebuilt_cycle_local_ledger_v1', actual_window_s=[20, 30],
                strict_full_cycle_state_restore_pass=True, mechanism_pass=True, local_inventory_pass=passed,
                inventory_ledger=ledger, production_recovery_allowed=False, outer_solve_allowed=False,
                periodic_steady_state_verified=False,
                pressure_only_density_storage_declared=pressure_only_density,
                input_sha256={name: sha256(folder / name) for name in files})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--pressure-only-density', action='store_true')
    args = parser.parse_args()
    assert not args.output.exists()
    result = audit(args.root.resolve(), pressure_only_density=args.pressure_only_density)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({key: result[key] for key in ('local_inventory_pass', 'mechanism_pass',
                                                  'strict_full_cycle_state_restore_pass')}))
