"""Independent cold buffer integration audit. Never grants mainline recovery."""
import argparse
from collections import Counter
import copy
import csv
import json
from pathlib import Path

import h5py
import numpy as np

from Audit_HeatDriveECC_ColdChamberCycle import checked_rows, custom_ledger, source_ledger
from Audit_HeatDriveECC_C201Inventory import ledgers, stage_totals
from Audit_HeatDriveECC_C201BoundaryCycle import integral_summary
from Audit_HeatDriveECC_C201Cycle import metrics
from Audit_HeatDriveECC_ColdChamberRejection import CHAMBERS, ROOT, edges, read
from Audit_HeatDriveECC_ColdCoordinateSmoke import compare_initial, scalar_series, ledger
from Audit_HeatDriveECC_ConservativeBufferTrial import inventory, NAMES
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_NativeWindowLedger import validate_grid
from Audit_HeatDriveECC_SegmentedEvidence import sha256, text_field
from Audit_HeatDriveECC_TLDomainInventory import resolve_domains, density_table, scalar
from Audit_HeatDriveECC_CompiledInventoryStates import decode_tags, component_inventory_preserved


PRODUCER = 'fde7153fddc9706d18f5a69b2e198bbbbb11247c'
EXPERIMENT = 'conservative_buffer_coupled_smoke_20260909_v2'
CYCLE_PRODUCER = '6148ebd49c3679821684a0e6206b8661e54fa7fa'
CYCLE_EXPERIMENT = 'conservative_buffer_coupled_cycle_20260909'
SPECIFIC_PRODUCER = '7408b1deda367f2d5324bd75e66ab593114cc459'
SPECIFIC_EXPERIMENT = 'specific_inventory_cold_onset_20260909'
FULL_SPECIFIC_085_PRODUCER = '0234f91a5bc86767abf87dd8d3040d362c6461c9'
FULL_SPECIFIC_TUNED_085_PRODUCER = '728f013ae3037f63473559567eed0fc921396312'
FULL_SPECIFIC_TUNED100_220_085_PRODUCER = '0360cf4bd445d8e49415e118ad499b53cc820b12'
FULL_SPECIFIC_TUNED110_255_085_PRODUCER = '3bbfbda56ab5d0800f147cc42c85d649e9069fed'
FULL_SPECIFIC_TUNED120_225_085_PRODUCER = '6c3d325cb45cc473a3a380d21044674bea5e6bc1'
FULL_SPECIFIC_TUNED125_225_085_PRODUCER = '800ada7f9d1a56039c271cd037fb7b14acfbcbc7'
FULL_SPECIFIC_TUNED124_225_085_PRODUCER = '56c21bb74016458b8e85861aaba15e8e77633faa'
NONLINEAR_LOCAL_BE_PRODUCER = '1c0af1a8a454d4c187062d872fa6e8b279b6742a'
# The seed contract was authored at ec9d3e1.  Later diagnostic-only runners
# may change execution mechanics while preserving the same zero-based state
# contract; keep those commits explicitly allow-listed rather than weakening
# the producer check globally.
ZERO_BASED_OFFSET_PRODUCER = 'ec9d3e1521062b7e65aebc61a996d9c233b5bfbf'
CONTROL_VOLUME_SEED_PRODUCER = 'c7e028d8a02b694f7b1e021acf6d0e880e2ece8d'
CALIBRATION_MIRROR_PRODUCERS = {
    CONTROL_VOLUME_SEED_PRODUCER,
    # These commits preserve the exact initial-flux contract and may run in
    # isolated worktrees where the hash-bound calibration is mirrored.
    '1ba3a32ae6fe9f7fe5d3d166c6fa12e740635a9c',
    '737373fe920d9a7964fcd698aa0be2de19b1698d',
}
ZERO_BASED_OFFSET_PRODUCERS = {
    ZERO_BASED_OFFSET_PRODUCER,
    '91dc097',
    # The six runner/component/initialization sources at this execution
    # commit are byte-identical to 717391a. Relative to the already accepted
    # 91dc097 source, 717391a only forces the conservative public-OP arm to
    # normal mode and records the per-arm mode; it does not change equations,
    # targets, or state initialization.
    CONTROL_VOLUME_SEED_PRODUCER,
    # Pressure-probe instrumentation is observational only and preserves the
    # same zero-based initialization and component contracts.
    '15e444ac60014a763837a67c46f17ede933d49b9',
    # Report-only commits after the pressure-probe implementation preserve
    # the exact runner and zero-based initialization contract.
    '0bd94ce91f1e6a595eb887ffa0a29c413e19045a',
    # d856090 adds only the explicitly bounded Kp-transition whitelist; the
    # zero-based state, inventory, and pressure-probe contracts are unchanged.
    'd85609098cb210962a4bd2ee8966db76d0c614da',
    # a436f2a adds the bounded two-cycle preflight horizon only; it does not
    # alter the zero-based state contract or authorize production recovery.
    'a436f2aff6440c71b21973a45a01ed5e1750d69f',
    # The detached simulation worktree ran the same source before the
    # main-branch cherry-pick; retain its exact execution identity too.
    '58049fdec3ad43222c716d508ee01c43cc77f10a',
    # a9535e2 adds only in-memory Stage-4 controller To Workspace taps and
    # persists their observations; initialization/equations/recovery authority
    # remain unchanged.
    'a9535e2582fa6c6d0841dfd3898624690cb50127',
    '393be6f000d9421c159b8c191f6f2c65ac24c185',
}
ENDPOINT_CHAMBER_PRODUCERS = {
    # Isolated endpoint-chamber route after the runner/source allowlists were
    # completed. This producer remains diagnostic-only and imports no C200 OP.
    'f5329019943455f59c15d8d9d19c873800417383',
    # v29 only accepts the native cold observation as the conservative-arm
    # initialization source; the qualified v22 package remains separate.
    '213fa7772733f725861747c04e6d62b9ac6993f3',
    '2839de0436094ae49da25336fb3b36ae6cbb6b3a',
    '384978570931127d909ddb7e9ca09545e97ffb02',
    '87668932da81d81a20611380bae2e9f14229383d',
    '7390794f4a36650d0f568931a197d0d8d7a92c2e',
    # 1e2c9b1 is byte-identical to the endpoint runner at 7390794; the
    # intervening commits changed only audit/provenance files.
    '1e2c9b1b4c9effd772af63f1546e2bacfb8df933',
    # 724376b is byte-identical to the endpoint runner at 1e2c9b1; the
    # intervening round32 commits changed only audit/provenance/report files.
    '724376b0368acaef63e3d353542c31eefc2c63c1',
    # The Stage-4 controller probes are observational and preserve the same
    # endpoint-chamber initialization contract.
    'a9535e2582fa6c6d0841dfd3898624690cb50127',
    '393be6f000d9421c159b8c191f6f2c65ac24c185',
    # 43bec65 fixes the Stage-4 logarithmic endpoint denominator wiring while
    # preserving the endpoint-chamber and zero-based cold-start contracts.
    '43bec659dde7384a5543c96886f89130c2480bd0',
    # a1e2f4a exposes only the signed Stage-4 Ki diagnostic override; plant,
    # inventory, endpoint-chamber, and recovery contracts are unchanged.
    'a1e2f4ab55880d4b4087223b9025d0c04385ce98',
    # 1ba3a32 adds only the independent 20-cycle warmup launcher contract;
    # the plant, endpoint chamber, zero-based initialization, and recovery
    # prohibitions remain unchanged.  Warmup outputs still require a separate
    # post-warmup audit and never grant production recovery.
    '1ba3a32ae6fe9f7fe5d3d166c6fa12e740635a9c',
    # 737373f adds only read-only Stage-4 boundary-transient diagnostics and
    # tests; the independent cold runner and all initialization/equation
    # contracts are unchanged.
    '737373fe920d9a7964fcd698aa0be2de19b1698d',
}
QUALIFIED_CHAMBER_HEADER = (
    '% Conservative Inventory Chamber (TL)\n'
    '% Diagnostic alternative: differentiate stored mass and energy themselves.\n'
)
ENDPOINT_CHAMBER_HEADER = (
    '% Endpoint-contract chamber diagnostic.\n'
    '% This isolated variant exposes stored mass and energy as explicit states so\n'
    '% endpoint inventories use the same state variables as the differential ledger.\n'
)
# The v8 diagnostic was run after the report-only ledger commit. Both commits
# refer to the same calibrated source implementation and remain auditable.
INITIAL_FLUX_COMPENSATION_PRODUCERS = {
    'ea8dfcb64f17ecb7221f71e805e8072d39f3d4f5',
    'ca69761aad5e86455f696d344673f66e22b7bb66',
    '8c796118900ed98e777f0d07aa1108625cbd90cd',
    # Pressure-probe instrumentation is observational only; this exact
    # committed runner preserves the same initialization and ledger contract.
    '15e444ac60014a763837a67c46f17ede933d49b9',
    '1e2c9b1b4c9effd772af63f1546e2bacfb8df933',
    'a9535e2582fa6c6d0841dfd3898624690cb50127',
    '393be6f000d9421c159b8c191f6f2c65ac24c185',
}
BUFFERS = {ROOT+n for n in ('ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer')}


def stage_totals_window(histories, time):
    """Partition an absolute logged window into repeated 10 s cycle phases."""
    time = np.asarray(time, dtype=float).reshape(-1)
    duration = float(time[-1] - time[0])
    cycles = int(round(duration / 10.0))
    if cycles <= 0 or not np.isclose(duration, cycles * 10.0, atol=1e-9, rtol=0):
        raise ValueError('Logged window is not an integer number of 10 s cycles')
    rows = []
    for cycle in range(cycles):
        ends = [0, 3500, 5000, 8500, 10000]
        offset = cycle * 10000
        for a, b in zip(ends[:-1], ends[1:]):
            ia, ib = offset + a, offset + b
            rows.append(dict(cycle_index=cycle, start_phase_s=cycle*10 + a*.001,
                             stop_phase_s=cycle*10 + b*.001,
                             **{key: float(values[ib] - values[ia]) for key, values in histories.items()}))
    for key, values in histories.items():
        if not np.isclose(sum(row[key] for row in rows), values[-1] - values[0], atol=1e-11, rtol=1e-11):
            raise ValueError('Stage partition omitted or duplicated intervals')
    return rows


def calibration_reference_matches(execution_commit, declared, canonical):
    declared, canonical = Path(declared), Path(canonical)
    if declared.resolve() == canonical.resolve():
        return True
    # Contract-compatible isolated worktrees may mirror the hash-bound
    # prerequisite. Bind the exception to explicit producers and the exact
    # artifact tail; the caller still requires the canonical content hash and
    # verifies the mirror too when it remains present.
    return (execution_commit in CALIBRATION_MIRROR_PRODUCERS
            and declared.parts[-3:] == canonical.parts[-3:])


def evidence_path_key(path, repo, experiment_root=None):
    path, repo = Path(path).resolve(), Path(repo).resolve()
    try:
        return str(path.relative_to(repo))
    except ValueError:
        if experiment_root is None:
            raise
        root = Path(experiment_root).resolve()
        try:
            return str(Path('experiment_root') / path.relative_to(root))
        except ValueError:
            # An isolated worktree may consume the frozen C200 artifact from
            # the sibling workspace repository. Keep that provenance explicit
            # without accepting arbitrary external paths.
            for parent in repo.parents:
                sibling = parent/'gx101r1_R69_remote'
                if sibling.is_dir():
                    try:
                        return str(Path('workspace_repo') / path.relative_to(sibling))
                    except ValueError:
                        continue
            raise


def topology_check(native, candidate, chamber_source='ecc_inventory.conservative_chamber',
                   buffer_source='ecc_buffer_coupled.conservative_buffer'):
    if chamber_source not in ('ecc_inventory.conservative_chamber', 'ecc_inventory_specific.conservative_chamber',
                              'ecc_inventory_endpoint.conservative_chamber',
                              'ecc_nonlinear_chamber.conservative_chamber'):
        raise ValueError('Unknown declared chamber source')
    if buffer_source not in ('ecc_buffer_coupled.conservative_buffer',
                             'ecc_buffer_coupled_offset.conservative_buffer',
                             'ecc_nonlinear_buffer.conservative_buffer'):
        raise ValueError('Unknown declared buffer source')
    if edges(native) != edges(candidate):
        raise ValueError('Named physical edges changed')
    projected = copy.deepcopy(candidate)
    source = {b['block_path']: b['source_file'] for b in native['blocks']}
    seen = set()
    for b in projected['blocks']:
        path = b['block_path']
        if path in BUFFERS | CHAMBERS:
            expected = buffer_source if path in BUFFERS else chamber_source
            if b['source_file'] != expected:
                raise ValueError('Unexpected replacement class')
            seen.add(path)
            b['source_file'] = source[path]
        elif b['source_file'] != source.get(path):
            raise ValueError('Unexpected physical component changed')
    if seen != BUFFERS | CHAMBERS or len(projected['blocks']) != len(source):
        raise ValueError('Incomplete replacement coverage')
    a, na = resolve_domains(native); b, nb = resolve_domains(projected)
    if na != 2 or nb != 2 or a != b:
        raise ValueError('Fluid domain assignment changed')
    return a


def port_contract(record):
    ports = record['original_conserving_ports']; outputs = record['removed_unconnected_outputs']
    if len(ports) != 2 or len(outputs) != 3:
        raise ValueError('Wrong original port inventory')
    expected = {'A': ('LConn', 1, 'foundation.thermal_liquid.thermal_liquid', True),
                'H': ('RConn', 1, 'foundation.thermal.thermal', False)}
    if {p['name'] for p in ports} != set(expected):
        raise ValueError('Wrong conserving ports')
    for p in ports:
        if p['interface_type'] != 'Domain' or tuple(p[k] for k in ('side', 'index', 'domain', 'connected')) != expected[p['name']]:
            raise ValueError('Wrong conserving port layout or connection')
    if {p['name'] for p in outputs} != {'L_out', 'T_out', 'V_out'} or any(
            p['interface_type'] != 'Output' or p['domain'] or p['connected'] for p in outputs):
        raise ValueError('Removed connected or unknown output')


def buffer_ledger(rows, path, table, contract, nonlinear_inventory=False, mass_formulation='direct'):
    expected_names = NAMES | ({'mass_coordinate', 'mass_delta', 'energy_delta'} if nonlinear_inventory else set())
    expected_names |= {'mass_offset'} if mass_formulation == 'zero_based_offset' else set()
    if {k[1] for k in rows if k[0] == path} != expected_names:
        raise ValueError('Incomplete buffer native leaves')
    def get(n, u):
        r = rows[path, n]
        if u == 'J/K' and text_field(r['unit']) == 'kJ/K':
            return r['values'][:].reshape(-1)*1000
        return scalar_series(r, u)
    mass, temp = get('stored_mass', 'kg'), get('T_I', 'K')
    c = contract
    r = inventory(table, temp, mass, c['p_environment_Pa'], c['tank_area_m2'], c['gravity_m_s2'],
                  c['reference_temperature_K'], c['auxiliary_depth_m'])
    errors = {k: float(abs(v-get(k, 'J')).max()) for k, v in r['parts'].items()}
    errors['stored_energy'] = float(abs(r['total']-get('stored_energy', 'J')).max())
    auxiliary = {}
    for k, name, unit, limit in [('volume', 'volume', 'm^3', 1e-12), ('level', 'level', 'm', 1e-10),
            ('rho', 'rho_I', 'kg/m^3', 1e-7), ('u', 'u_I', 'J/kg', 1e-6), ('u_port', 'u_port', 'J/kg', 1e-6),
            ('port_pressure', 'p_A', 'Pa', 1e-6), ('capacity', 'auxiliary_capacity', 'J/K', 1e-8)]:
        error = float(abs(r[k]-get(name, unit)).max())
        auxiliary[name] = dict(max_abs_error=error, limit=limit, passed=error <= limit)
    t = rows[path, 'T_I']['time_s'][:].reshape(-1)
    local = ledger(t, mass, r['total'], get('mdot_A', 'kg/s'), get('Phi_A', 'W')+get('Q_H', 'W'))
    alias_pass = max(errors.values()) <= 1e-8 and all(v['passed'] for v in auxiliary.values())
    # Unit conversion from an MPa trace can produce a sub-nanopascal roundoff;
    # the physical contract is equality within the declared measurement scale.
    if np.any(abs(get('p_I', 'Pa') - c['p_environment_Pa']) > 1e-6) or np.any(get('Q_H', 'W') != 0):
        raise ValueError('Unconnected thermal port or constant pressure contract changed')
    return dict(block_path=path, independent_ledger=local, inventory_alias_pass=alias_pass,
                energy_alias_errors_J=errors, auxiliary_alias_errors=auxiliary,
                energy_parts_change_J={k: float(v[-1]-v[0]) for k, v in r['parts'].items()},
                candidate_component_pass=bool(alias_pass and local['mass_closure_pass'] and local['energy_closure_pass']))


def cycle_arm(folder, assignment, contracts, nonlinear_inventory=False, mass_formulation='direct', start=0, stop=10):
    meta = read(folder/'inventory_metadata.json')
    tables = {r['block_path']: energy_tables(r['parameters']) for r in meta['settings_tables']}
    densities = {r['block_path']: density_table(r['parameters']) for r in meta['settings_tables']}
    sources = {b['block_path']: b['source_file'] for b in read(folder/'tl_connectivity.json')['blocks']}
    time = None; components = []; consumed = set()
    source_files = {b['block_path']: b['source_file'] for b in read(folder/'tl_connectivity.json')['blocks']}
    endpoint_chamber = 'ecc_inventory_endpoint.conservative_chamber' in set(source_files.values())
    expected_count = (1262 if endpoint_chamber else 1240) if folder.name == 'native' else (
        1276 if nonlinear_inventory else 1262 if mass_formulation == 'zero_based_offset' else 1258)
    with h5py.File(folder/'observations.mat') as f:
        rows = checked_rows(f, 'native', expected_count, stop, start,
                            allow_leading_warmup=start > 0)
        time = next(iter(rows.values()))['time_s'][:].reshape(-1)
        for original in meta['storage_blocks']:
            block = copy.deepcopy(original); path = block['block_path']; kind = block['mask_type']
            block['reference_block'] = sources.get(path, 'foundation.thermal.elements.mass')
            block['leaf_variables'] = []
            for key, r in rows.items():
                if key[0] == path:
                    consumed.add(key)
                    block['leaf_variables'].append(dict(name=key[1], unit=text_field(r['unit']),
                        time_s=r['time_s'][:].reshape(-1), values=r['values'][:].reshape(-1)))
            table = tables.get(assignment.get(path)); nominal = None
            if kind == 'Pipe (TL)':
                mode = block['model_modes']; p = block['mask_parameters']
                temp = scalar(mode['T_nominal'], mode['T_nominal_unit'], 'K')
                pressure = scalar(mode['p_nominal'], mode['p_nominal_unit'], 'Pa')
                if p['area']['unit'] != 'm^2' or p['length']['unit'] != 'm': raise ValueError('Unexpected native pipe geometry units')
                nominal = float(densities[assignment[path]]([[temp, pressure]])[0])*p['area']['value']*p['length']['value']
            if kind == 'Conservative Buffer (TL)':
                detail = buffer_ledger(rows, path, table, contracts[path], nonlinear_inventory, mass_formulation); c = contracts[path]
                get = lambda n, u: scalar_series(rows[path, n], u)
                mass = get('stored_mass', 'kg')
                reconstructed = inventory(table, get('T_I', 'K'), mass, c['p_environment_Pa'], c['tank_area_m2'],
                    c['gravity_m_s2'], c['reference_temperature_K'], c['auxiliary_depth_m'])
                energy = reconstructed['total']
                energy_input = np.r_[0, np.cumsum((get('Phi_A', 'W')+get('Q_H', 'W'))[1:]*np.diff(time))]
                mass_input = np.r_[0, np.cumsum(get('mdot_A', 'kg/s')[1:]*np.diff(time))]
                h = dict(endpoint_energy_residual_J=energy_input-(energy-energy[0]),
                         endpoint_mass_residual_kg=mass_input-(mass-mass[0]))
                row = dict(block_path=path, mask_type=kind, energy_endpoint_change_J=float(energy[-1]-energy[0]),
                           pressure_volume_work_J=0., endpoint_energy_residual_J_end=float(h['endpoint_energy_residual_J'][-1]),
                           endpoint_mass_residual_kg_end=float(h['endpoint_mass_residual_kg'][-1]),
                           energy_basis='M*u + p_environment*V + M*g*level/2 + C_aux*(T-T_ref); do not add p*dV again',
                           component_detail=detail)
            elif block['conservative_diagnostic']:
                if path not in CHAMBERS: raise ValueError('Unknown custom storage')
                row, h = custom_ledger(block, table)
            else:
                row, h = ledgers(block, table, nominal)
            row['stages'] = stage_totals_window(h, time); components.append(row)
        if consumed != set(rows) or len(components) != 119 or len({r['block_path'] for r in components}) != 119:
            raise ValueError('Unaccounted storage leaves')
        rates, source_rows, pumps = source_ledger(f, read(folder/'thermal_connectivity.json'), time,
                                                  allow_leading_warmup=start > 0)
        signals = {}
        for key, r in f['signals'].items():
            signal_time = np.asarray(r['time_s'][:], dtype=float).reshape(-1)
            values = np.asarray(r['values'][:])
            expected = len(time)
            if (signal_time.size == round(stop/.001)+1 and abs(signal_time[0]) <= 1e-9
                    and abs(signal_time[-1]-stop) <= 1e-9 and start > 0):
                first = round(start/.001)
                last = first + expected
                signal_time = signal_time[first:last]
                values = values[..., first:last]
            elif (start > 0 and signal_time.size == expected+1
                    and abs(signal_time[0]-(start-.001)) <= 1e-9
                    and abs(signal_time[-1]-stop) <= 1e-9):
                signal_time = signal_time[1:]
                values = values[..., 1:]
            validate_grid(signal_time, start, stop, .001)
            if values.ndim != 2 or values.shape[1] != len(time) or not np.isfinite(values).all(): raise ValueError('Incomplete public signals')
            signals[key] = values
        with h5py.File(folder/'configuration.mat') as config:
            origin = max(start, stop - 10.0)
            window = time >= origin - 1.0e-12
            window_signals = {key: value[:, window] for key, value in signals.items()}
            performance, solids, flows = metrics(window_signals, config['options'],
                                                 time[window], origin=origin)
        storage = sum(scalar_series(r, 'W') for (_, n), r in rows.items() if n.startswith('Phi_') or n in ('Q_H', 'Q'))
        kcl = sum(rates.values())-storage
    endpoint = sum(r['energy_endpoint_change_J']+r.get('pressure_volume_work_J', 0) for r in components)
    source_input = integral_summary(sum(rates.values()), time)['BE_energy_J']
    residual = source_input-endpoint
    if abs(residual-sum(r['endpoint_energy_residual_J_end'] for r in components)-integral_summary(kcl, time)['BE_energy_J']) > 1e-7:
        raise ValueError('Full source/storage ledger identity failed')
    groups = {kind: dict(count=sum(r['mask_type'] == kind for r in components),
                        endpoint_energy_residual_J=sum(r['endpoint_energy_residual_J_end'] for r in components if r['mask_type'] == kind))
              for kind in sorted({r['mask_type'] for r in components})}
    return dict(arm=folder.name, storage_count=119, source_count=49, samples=len(time), omitted_intervals=0,
                components=components, component_groups=groups, source_rows=source_rows, pumps=pumps,
                source_ledger={k: integral_summary(v, time) for k, v in rates.items()},
                 source_stages=stage_totals_window({k: np.r_[0, np.cumsum(v[1:]*np.diff(time))] for k, v in rates.items()}, time),
                BE_source_net_energy_J=source_input, actual_endpoint_storage_plus_pdv_J=endpoint,
                source_minus_actual_endpoint_storage_J=residual, selected_flow_gates=flows,
                performance=performance, selected_solid_balances=solids, own_actual_initial_inventory_used=True,
                full_device_first_law_verified=False, production_recovery_allowed=False,
                interpretation='One cold cycle, declared lumped storage and native ideal source boundaries only; not full device validation')


def audit(repo, full_cycle=False, specific_onset=False, experiment_root=None, nonlinear_inventory=False,
          initial_flux_compensation=False, zero_based_offset=False, specific_inventory=False,
          duration_s=None, cycle_count=None):
    if nonlinear_inventory and initial_flux_compensation:
        raise ValueError('Coordinate and initial-flux diagnostics must remain separate')
    if experiment_root is not None:
        root = Path(experiment_root).resolve()
        producer = {FULL_SPECIFIC_085_PRODUCER, FULL_SPECIFIC_TUNED_085_PRODUCER,
                    FULL_SPECIFIC_TUNED100_220_085_PRODUCER,
                    FULL_SPECIFIC_TUNED110_255_085_PRODUCER,
                    FULL_SPECIFIC_TUNED120_225_085_PRODUCER,
                    FULL_SPECIFIC_TUNED125_225_085_PRODUCER,
                    FULL_SPECIFIC_TUNED124_225_085_PRODUCER}
        if nonlinear_inventory:
            producer = {NONLINEAR_LOCAL_BE_PRODUCER}
        elif initial_flux_compensation:
            producer = INITIAL_FLUX_COMPENSATION_PRODUCERS
        if zero_based_offset:
            producer = ZERO_BASED_OFFSET_PRODUCERS
    else:
        if full_cycle and specific_onset: raise ValueError('Onset probe is not a full cycle')
        root = repo/'outputs_storage_audit'/(SPECIFIC_EXPERIMENT if specific_onset else CYCLE_EXPERIMENT if full_cycle else EXPERIMENT)
        producer = SPECIFIC_PRODUCER if specific_onset else CYCLE_PRODUCER if full_cycle else PRODUCER
    execution = read(root/'cold_chamber_execution.json')
    endpoint_chamber_diagnostic = bool(execution.get('endpoint_chamber_diagnostic', False))
    if endpoint_chamber_diagnostic:
        producer = ENDPOINT_CHAMBER_PRODUCERS
    default_stop = 10 if full_cycle else .2 if specific_onset else .01
    stop = float(default_stop if duration_s is None else duration_s)
    if stop <= 0 or abs(stop/.001 - round(stop/.001)) > 1.0e-9:
        raise ValueError('Diagnostic duration must be an integer number of 1 ms samples')
    declared_cycles = int(execution.get('cycle_count', round(stop/10)))
    if cycle_count is not None and declared_cycles != int(cycle_count):
        raise ValueError('Declared cycle count differs from execution contract')
    if full_cycle and abs(stop - declared_cycles*10.0) > 1.0e-9:
        raise ValueError('Full-cycle diagnostic duration does not match its cycle count')
    trace_start = float(execution.get('simscape_log_window_start_s', 0.0))
    trace_stop = stop
    if trace_start < 0 or trace_start >= trace_stop or abs(trace_start/.001-round(trace_start/.001)) > 1.0e-9:
        raise ValueError('Invalid Simscape log window in execution contract')
    specific_inventory = specific_inventory or execution.get('inventory_formulation') == 'specific_inventory'
    if (execution['execution_commit'] not in producer or not execution['collection_pass'] or not execution['conservative_buffers']
            or execution['start_time_s'] != 0 or execution['stop_time_s'] != stop
            or bool(execution.get('nonlinear_inventory_coordinates', False)) != nonlinear_inventory
            or bool(execution.get('initial_flux_compensation', False)) != initial_flux_compensation
            or bool(execution.get('buffer_mass_formulation') == 'zero_based_offset') != zero_based_offset
            or any(execution[k] for k in ('c200_state_imported', 'checkpoint_saved', 'production_recovery_allowed'))
            or [c['arm'] for c in execution['cases']] != ['native', 'conservative']):
        raise ValueError('Wrong independent cold experiment')
    for c in execution['cases']:
        if sha256(root/c['arm']/'observations.mat') != c['observation_sha256']:
            raise ValueError('Observation hash mismatch')
    compiled_gate = None
    chamber_source = 'ecc_inventory.conservative_chamber'
    buffer_source = 'ecc_buffer_coupled.conservative_buffer'
    if zero_based_offset:
        buffer_source = 'ecc_buffer_coupled_offset.conservative_buffer'
    if endpoint_chamber_diagnostic:
        if execution.get('inventory_formulation') != 'specific_inventory':
            raise ValueError('Endpoint chamber diagnostic requires specific inventory formulation')
        prereq = repo/'outputs_storage_audit/compiled_specific_inventory_audit_20260909/compiled_inventory_state_audit.json'
        pre = read(prereq)
        component = root/'component_build/+ecc_inventory_endpoint/conservative_chamber.ssc'
        reference = (repo/'verification/simscape_inventory_specific/+ecc_inventory_specific/conservative_chamber.ssc').read_text(encoding='utf-8')
        reference = reference.replace(QUALIFIED_CHAMBER_HEADER, ENDPOINT_CHAMBER_HEADER)
        if (not component.is_file() or component.read_text(encoding='utf-8') != reference
                or execution.get('chamber_source_file') != 'ecc_inventory_endpoint.conservative_chamber'
                or execution.get('endpoint_chamber_source_sha256') != sha256(component)
                or execution.get('endpoint_chamber_library_sha256') != sha256(root/'component_build/ecc_inventory_endpoint_lib.slx')
                or execution.get('compiled_inventory_gate_sha256') != sha256(prereq)
                or not pre['specific_inventory_compiled_gate_pass'] or not pre['evidence_audit_pass']
                or pre['production_recovery_allowed']):
            raise ValueError('Endpoint chamber source or compiled prerequisite changed')
        chamber_source = 'ecc_inventory_endpoint.conservative_chamber'
        specific_inventory = True
        tags = read(root/'conservative/compiled_inventory_tags.json')
        if tags['chamber_source_file'] != execution['chamber_source_file'] or not tags['post_simulation_source_verified']:
            raise ValueError('Wrong endpoint trajectory source identity')
        tag_rows = [dict(block_name=r['block_name'], variable_name=r['variable_name'], **decode_tags(r))
                    for r in tags['node_metadata']]
        chamber_names = {p.removeprefix(ROOT) for p in CHAMBERS}
        buffer_names = {p.removeprefix(ROOT) for p in BUFFERS}
        compiled_gate = (component_inventory_preserved(
                            [r for r in tag_rows if r['block_name'] in chamber_names], chamber_names) and
                         component_inventory_preserved(
                            [r for r in tag_rows if r['block_name'] in buffer_names], buffer_names,
                            variables={'mass_offset', 'stored_energy', 'T_I', 'p_I'},
                            differential_variables=('mass_offset', 'stored_energy')))
    if specific_inventory and not endpoint_chamber_diagnostic:
        prereq = repo/'outputs_storage_audit/compiled_specific_inventory_audit_20260909/compiled_inventory_state_audit.json'
        pre = read(prereq)
        component = root/'component_build/+ecc_inventory_specific/conservative_chamber.ssc'
        original = (repo/'verification/simscape_inventory/+ecc_inventory/conservative_chamber.ssc').read_text(encoding='utf-8')
        expected = original.replace('stored_mass == volume * rho_I;', 'rho_I == stored_mass / volume;')
        expected = expected.replace('stored_energy == stored_mass * u_I;', 'u_I == stored_energy / stored_mass;')
        expected_chamber_source = ('ecc_nonlinear_chamber.conservative_chamber' if nonlinear_inventory
                                   else 'ecc_inventory_specific.conservative_chamber')
        if (execution['inventory_formulation'] != 'specific_inventory' or execution['chamber_source_file'] != expected_chamber_source
                or execution['compiled_inventory_gate_sha256'] != sha256(prereq) or not pre['specific_inventory_compiled_gate_pass']
                or not pre['evidence_audit_pass'] or pre['production_recovery_allowed']
                or component.read_text(encoding='utf-8') != expected
                or execution['chamber_library_sha256'] != sha256(root/'component_build/ecc_inventory_specific_lib.slx')):
            raise ValueError('Specific inventory onset source or compiled prerequisite changed')
        chamber_source = expected_chamber_source
        if nonlinear_inventory:
            buffer_source = 'ecc_nonlinear_buffer.conservative_buffer'
            contract = execution['nonlinear_inventory_contract']
            qualification = repo/'outputs_storage_audit/nonlinear_mass_qualification_package_20260910/nonlinear_mass_probe_audit.json'
            if (execution.get('nonlinear_buffer_source_file') != buffer_source
                    or contract['qualification_sha256'] != sha256(qualification)
                    or contract['translated_count'] != 12 or contract['unchanged_count'] != 192
                    or not contract['typed_nets_preserved'] or contract['private_state_imported']
                    or contract['production_recovery_allowed']):
                raise ValueError('Nonlinear coordinate contract changed')
            for variant in contract['variants']:
                for field, hash_field in (('source', 'source_sha256'), ('generated_source', 'generated_sha256'),
                                          ('library_path', 'library_sha256')):
                    if sha256(Path(variant[field])) != variant[hash_field]:
                        raise ValueError('Nonlinear component artifact hash changed')
        tags = read(root/'conservative/compiled_inventory_tags.json')
        if tags['chamber_source_file'] != execution['chamber_source_file'] or not tags['post_simulation_source_verified']:
            raise ValueError('Wrong trajectory source identity')
        tag_rows = [dict(block_name=r['block_name'], variable_name=r['variable_name'], **decode_tags(r)) for r in tags['node_metadata']]
        if nonlinear_inventory:
            blocks = {p.removeprefix(ROOT) for p in BUFFERS | CHAMBERS}
            expected = {(b, v) for b in blocks for v in ('mass_coordinate', 'energy_delta', 'T_I', 'p_I')}
            compiled_gate = ({(r['block_name'], r['variable_name']) for r in tag_rows} == expected
                             and all(r['isDifferential'] and r['isRetained'] for r in tag_rows
                                     if r['variable_name'] in ('mass_coordinate', 'energy_delta')))
        elif zero_based_offset:
            chamber_names = {p.removeprefix(ROOT) for p in CHAMBERS}
            buffer_names = {p.removeprefix(ROOT) for p in BUFFERS}
            compiled_gate = (component_inventory_preserved(
                                [r for r in tag_rows if r['block_name'] in chamber_names], chamber_names) and
                             component_inventory_preserved(
                                [r for r in tag_rows if r['block_name'] in buffer_names], buffer_names,
                                variables={'mass_offset', 'stored_energy', 'T_I', 'p_I'},
                                differential_variables=('mass_offset', 'stored_energy')))
        else:
            compiled_gate = component_inventory_preserved(tag_rows, {p.removeprefix(ROOT) for p in BUFFERS | CHAMBERS})
    native_topology = read(root/'native/tl_connectivity.json')
    conservative_topology = read(root/'conservative/tl_connectivity.json')
    if endpoint_chamber_diagnostic:
        native_has_endpoint = any(b['source_file'] == chamber_source
                                  for b in native_topology['blocks'])
        if native_has_endpoint:
            # Retain the v29 both-replacement path for already audited evidence.
            qualified_root_text = (execution.get('endpoint_chamber_qualified_source_root') or
                                   (execution.get('initialization_source_root')
                                    if execution.get('endpoint_all_arms') else ''))
            if execution.get('endpoint_all_arms') and not execution.get('endpoint_chamber_qualified_source_root'):
                seed_root = Path(execution.get('initialization_source_root', ''))
                seed_execution = seed_root / 'cold_chamber_execution.json'
                if seed_execution.is_file():
                    seed_record = read(seed_execution)
                    qualified_root_text = seed_record.get('endpoint_chamber_qualified_source_root', '')
            qualified_root = Path(qualified_root_text)
            if not qualified_root_text or not (qualified_root / 'native/tl_connectivity.json').is_file():
                raise ValueError('Missing qualified endpoint topology source')
            reference_topology = read(qualified_root/'native/tl_connectivity.json')
            native_assignment = topology_check(reference_topology, native_topology,
                                               chamber_source, buffer_source)
            conservative_assignment = topology_check(reference_topology, conservative_topology,
                                                     chamber_source, buffer_source)
        else:
            # Corrected route: native is the physical baseline; only the
            # conservative arm receives endpoint chamber and offset buffers.
            native_assignment, native_domains = resolve_domains(native_topology)
            conservative_assignment = topology_check(native_topology, conservative_topology,
                                                     chamber_source, buffer_source)
            if native_domains != 2:
                raise ValueError('Native endpoint baseline has wrong domain count')
        if native_assignment != conservative_assignment:
            raise ValueError('Endpoint arm domain assignment differs')
        assignment = native_assignment
    else:
        assignment = topology_check(native_topology, conservative_topology,
                                    chamber_source, buffer_source)
    if edges(read(root/'native/thermal_connectivity.json')) != edges(read(root/'conservative/thermal_connectivity.json')):
        raise ValueError('Thermal physical edges changed')
    metas = {a: read(root/a/'inventory_metadata.json') for a in ('native', 'conservative')}
    if metas['native']['settings_tables'] != metas['conservative']['settings_tables']:
        raise ValueError('Fluid tables changed')
    native_has_endpoint = endpoint_chamber_diagnostic and any(
        b['source_file'] == chamber_source for b in native_topology['blocks'])
    for a, meta in metas.items():
        buffer_mask = ('Conservative Buffer (TL)' if endpoint_chamber_diagnostic and
                       (a == 'conservative' or native_has_endpoint) else
                       ('Tank (TL)' if a == 'native' else 'Conservative Buffer (TL)'))
        expected = {'Pipe (TL)': 67, 'Constant Volume Chamber (TL)': 2, 'Thermal Mass': 46,
                    buffer_mask: 4}
        if dict(Counter(b['mask_type'] for b in meta['storage_blocks'])) != expected:
            raise ValueError('Incomplete storage coverage')
    tables = {r['block_path']: energy_tables(r['parameters']) for r in metas['native']['settings_tables']}
    replacement = read(root/'conservative/buffer_replacement_contract.json')
    targets = read(root/'conservative/public_inventory_targets.json')
    initialization_sha256 = execution.get('initialization_source_observation_sha256',
                                          execution['cases'][0]['observation_sha256'])
    for record in (targets, replacement):
        if record['source_sha256'] != initialization_sha256 or record['source_time_s'] != 0:
            raise ValueError('Non-native or nonzero-time initialization source')
    if targets['has_private_data'] or len(targets['targets']) != 204 or Counter(t['priority'] for t in targets['targets']) != {'High': 125, 'Low': 79}:
        raise ValueError('Unexpected public initialization target coverage')
    if initial_flux_compensation:
        compensation = execution['initial_flux_compensation_contract']
        runtime = read(root/'conservative/runtime_inventory_targets.json')
        prerequisite = repo/'outputs_storage_audit/cold_initial_flux_signature_20260909_v2/initial_flux_signature.json'
        calibration = repo/'outputs_storage_audit/cold_flux_compensated_onset_0p85_20260913_v6/cold_buffer_coupled_audit.json'
        declared_calibration = Path(compensation['calibration_reference'])
        declared_calibration_hash_pass = (not declared_calibration.exists()
            or sha256(declared_calibration) == compensation['calibration_reference_sha256'])
        if (compensation['schema'] != 'heatdrive_ecc_cold_initial_flux_compensation_v1'
                or compensation['diagnostic_prerequisite_sha256'] != sha256(prerequisite)
                or compensation['calibration_reference_sha256'] != sha256(calibration)
                or not calibration_reference_matches(execution['execution_commit'], declared_calibration, calibration)
                or not declared_calibration_hash_pass
                or compensation['pipe_startup_correction_s'] != 3.481406701427476e-9
                or compensation['hypothesis_step_s'] != 2e-5
                or compensation['physical_target_count'] != 204
                or compensation['corrected_high_target_count'] != 125
                or compensation['unchanged_low_target_count'] != 79
                or compensation['private_state_imported'] or compensation['solver_internal_step_claimed']
                or compensation['production_recovery_allowed']
                or runtime['physical_target_count'] != 204 or runtime['translated_target_count'] != 0
                or runtime['compensated_high_target_count'] != 125
                or len(runtime['targets']) != 204):
            raise ValueError('Initial-flux compensation contract changed')
        physical = {r['path']: r for r in targets['targets']}
        runtime_by_path = {r['path']: r for r in runtime['targets']}
        corrections = {r['path']: r for r in compensation['corrections']}
        if len(physical) != 204 or len(runtime_by_path) != 204 or len(corrections) != 125:
            raise ValueError('Incomplete compensated target identities')
        for path, original in physical.items():
            candidate = runtime_by_path[path]
            if original['priority'] == 'High':
                row = corrections[path]
                startup = 3.481406701427476e-9 if '/SE/HoldPipe_' in row['block_path'] else 0.0
                if (row['hypothesis_step_s'] != 2e-5 or row['startup_correction_s'] != startup
                        or row['effective_step_s'] != 2e-5-startup):
                    raise ValueError('Unapproved flux compensation step')
                expected = original['value'] - row['subtracted_delta']
                if (row['physical_value'] != original['value'] or row['runtime_value'] != candidate['value']
                        or not np.isclose(candidate['value'], expected, rtol=1e-14, atol=1e-300)):
                    raise ValueError('Compensated High target changed')
            elif candidate != original:
                raise ValueError('Low target changed by flux compensation')
    contracts = {r['block_path']: r for r in replacement['buffers']}
    if set(contracts) != BUFFERS or len(replacement['buffers']) != 4:
        raise ValueError('Incomplete buffer replacement contract')
    expected_environment = (execution['diagnostic_network_absolute_pressure_MPa'] * 1e6
                            if experiment_root is not None else 1e6)
    for c in contracts.values():
        port_contract(c)
        if (c['inlet_height_m'] != 0 or c['initial_source_time_s'] != 0 or c['mainline_recovery_allowed']
            or c['tank_area_m2'] != .001 or c['port_area_m2'] != .01 or c['auxiliary_depth_m'] != .001
            or c['gravity_m_s2'] != 9.81 or c['p_environment_Pa'] != expected_environment):
            raise ValueError('Actual buffer geometry differs from declared experiment')
    comparisons = []; local = []; kcls = []
    initialization_path = Path(execution.get('initialization_source_root', ''))/'native'/'observations.mat'
    if endpoint_chamber_diagnostic:
        if not initialization_path.is_file():
            raise ValueError('Missing hash-bound endpoint cold initialization source')
        if sha256(initialization_path) != execution.get('initialization_source_observation_sha256'):
            raise ValueError('Endpoint cold initialization source hash mismatch')
        seed_file = h5py.File(initialization_path, 'r')
        seed_rows = checked_rows(seed_file, 'native',
                                 int(next(c['native_trace_count'] for c in execution['cases']
                                         if c['arm'] == 'native')), 10, 0)
    elif trace_start > 0:
        if not initialization_path.is_file():
            raise ValueError('Missing hash-bound cold initialization source')
        if sha256(initialization_path) != execution.get('initialization_source_observation_sha256'):
            raise ValueError('Cold initialization source hash mismatch')
        seed_file = h5py.File(initialization_path, 'r')
        seed_rows = checked_rows(seed_file, 'native', 1240, 10, 0)
    else:
        seed_file = None
        seed_rows = None
    with h5py.File(root/'native/observations.mat') as a, h5py.File(root/'conservative/observations.mat') as b:
        native_trace_count = int(next(c['native_trace_count'] for c in execution['cases']
                                     if c['arm'] == 'native'))
        conservative_trace_count = int(next(c['native_trace_count'] for c in execution['cases']
                                            if c['arm'] == 'conservative'))
        aa = checked_rows(a, 'native', native_trace_count, trace_stop, trace_start,
                          allow_leading_warmup=trace_start > 0)
        bb = checked_rows(b, 'native', conservative_trace_count,
                          trace_stop, trace_start, allow_leading_warmup=trace_start > 0)
        volumes = {r['block_path']: r['mask_parameters']['volume']['value'] for r in metas['native']['storage_blocks'] if r['block_path'] in CHAMBERS}
        for path, c in contracts.items():
            initial = seed_rows if seed_rows is not None else aa
            def get(n, u):
                key = n
                if n == 'mass' and (path, key) not in initial:
                    key = 'stored_mass'
                return scalar_series(initial[path, key], u)[0]
            mass, temp, rho, u = get('mass', 'kg'), get('T_I', 'K'), get('rho_I', 'kg/m^3'), get('u_I', 'J/kg')
            v = mass/rho; e = mass*u+c['p_environment_Pa']*v+mass*c['gravity_m_s2']*v/c['tank_area_m2']/2
            for key, expected in [('initial_mass_kg', mass), ('initial_volume_m3', v), ('initial_extended_energy_J', e), ('reference_temperature_K', temp)]:
                if not compare_initial(c[key], expected)['within_strict_comparison']:
                    raise ValueError('Buffer mapping is not measured same-run native t=0')
            actual = next(r for r in metas['conservative']['storage_blocks'] if r['block_path'] == path)['mask_parameters']
            for field, key in [('tank_area', 'tank_area_m2'), ('port_area', 'port_area_m2'), ('gravity', 'gravity_m_s2'),
                               ('p_environment', 'p_environment_Pa'), ('reference_temperature', 'reference_temperature_K'), ('auxiliary_depth', 'auxiliary_depth_m')]:
                if not np.isclose(actual[field]['value'], c[key], rtol=1e-14, atol=0):
                    raise ValueError('Actual model geometry does not match contract')
            local.append(buffer_ledger(bb, path, tables[assignment[path]], c, nonlinear_inventory,
                                       'zero_based_offset' if zero_based_offset else 'direct'))
        seen = set()
        for target in targets['targets']:
            key = target['block_path'], target['state_name']; unit = target['unit']
            if key in seen or target['source_time_s'] != 0:
                raise ValueError('Duplicate or nonzero-time target')
            seen.add(key)
            if key[1] in ('stored_mass', 'stored_energy'):
                if key[0] in BUFFERS:
                    expected = contracts[key[0]]['initial_mass_kg' if key[1] == 'stored_mass' else 'initial_extended_energy_J']
                elif key[0] in CHAMBERS:
                    expected = volumes[key[0]]*scalar_series(initial[key[0], 'rho_I'], 'kg/m^3')[0]
                    if key[1] == 'stored_energy': expected *= scalar_series(initial[key[0], 'u_I'], 'J/kg')[0]
                else: raise ValueError('Unknown stored inventory target')
            else: expected = scalar_series(initial[key], unit)[0]
            if abs(target['value']-expected) > 1e-12*max(1, abs(expected)):
                raise ValueError('Target differs from measured native initialization')
            actual = expected if trace_start > 0 else scalar_series(bb[key], unit)[0]
            comparisons.append(dict(path=target['path'], priority=target['priority'], unit=unit,
                                    **compare_initial(actual, expected)))
        chambers = []
        for block in metas['conservative']['storage_blocks']:
            if block['block_path'] not in CHAMBERS: continue
            block = copy.deepcopy(block); path = block['block_path']
            block['leaf_variables'] = [dict(name=k[1], unit=text_field(r['unit']), time_s=r['time_s'][:].reshape(-1),
                                           values=r['values'][:].reshape(-1)) for k, r in bb.items() if k[0] == path]
            row, _ = custom_ledger(block, tables[assignment[path]]); chambers.append(row)
        time = next(iter(aa.values()))['time_s'][:].reshape(-1)
        for arm, f, rows in [('native', a, aa), ('conservative', b, bb)]:
            rates, _, _ = source_ledger(f, read(root/arm/'thermal_connectivity.json'), time,
                                        allow_leading_warmup=trace_start > 0)
            storage = sum(scalar_series(r, 'W') for (_, n), r in rows.items() if n.startswith('Phi_') or n in ('Q_H', 'Q'))
            error = float(abs(sum(rates.values())-storage).max())
            kcls.append(dict(arm=arm, max_abs_W=error, limit_W=1e-8, passed=error <= 1e-8))
    if seed_file is not None:
        seed_file.close()
    with h5py.File(root/'native/configuration.mat') as a, h5py.File(root/'conservative/configuration.mat') as b:
        if set(a['commands']) != set(b['commands']) or len(a['commands']) != 5: raise ValueError('Changed command set')
        for f in (a, b):
            s = f['options/simscape']
            if (not s['local_solver_enabled'][0, 0] or s['local_solver_sample_time_s'][0, 0] != .001 or
                    text_field(s['local_solver_choice']) != 'NE_BACKWARD_EULER_ADVANCER'): raise ValueError('Wrong solver')
        for n in a['commands']:
            for field in ('time_s', 'values'):
                if not np.array_equal(a['commands'][n][field][:], b['commands'][n][field][:]): raise ValueError('Changed command trajectory')
    contract_path = repo/'verification/c200_mainline_freeze_contract.json'; frozen = read(contract_path)
    files = [contract_path]
    if specific_onset:
        files += [prereq, component, root/'component_build/ecc_inventory_specific_lib.slx']
    for key in ('result', 'checkpoint'):
        p = repo/frozen[key+'_relative_path']
        if sha256(p) != frozen[key+'_sha256']: raise ValueError('Frozen C200 changed')
        files.append(p)
    files += [p for p in root.rglob('*') if p.is_file() and p.suffix in ('.json', '.mat', '.log', '.ssc') and not any(x in p.parts for x in ('cache', 'codegen'))]
    strict = all(r['within_strict_comparison'] for r in comparisons)
    local_pass = all(r['candidate_component_pass'] for r in local) and all(
        r['local_chamber_gate']['mass_closure_pass'] and r['local_chamber_gate']['energy_closure_pass'] for r in chambers)
    numerical_pass = bool(local_pass and strict and all(r['passed'] for r in kcls) and (not specific_inventory or compiled_gate))
    result = dict(schema='heatdrive_ecc_cold_buffer_coupled_audit_v2', evidence_audit_pass=True,
        execution_commit=execution['execution_commit'], stop_time_s=stop,
        logged_window_start_s=trace_start, logged_window_stop_s=trace_stop,
        samples=round((trace_stop-trace_start)/.001)+1, buffers=local, chambers=chambers,
        topology_edges_and_domain_assignment_identical=True, property_tables_identical=True,
        source_storage_port_checks=kcls, local_inventory_conservation_pass=local_pass,
        strict_initial_coordinate_match=strict, initial_matching_counts={p: sum(r['within_strict_comparison'] for r in comparisons if r['priority'] == p) for p in ('High', 'Low')},
        declared_window_numerical_gates_pass=numerical_pass,
        nonlinear_inventory_coordinates=nonlinear_inventory,
        initial_flux_compensation=initial_flux_compensation,
        zero_based_offset=zero_based_offset,
        specific_inventory_onset_probe=specific_onset, trajectory_compiled_inventory_gate=compiled_gate,
        experiment_root=str(root) if experiment_root is not None else None,
        cold_smoke_numerical_gates_pass=numerical_pass if not full_cycle else None,
        full_cycle_completed=full_cycle, all_mechanism_gates_evaluated=False, full_device_first_law_verified=False,
        production_recovery_allowed=False, table4_reproduction_claim=False,
        input_sha256={evidence_path_key(p, repo, root if experiment_root is not None else None): sha256(p)
                      for p in sorted(set(files))})
    if full_cycle:
        result['arms'] = [cycle_arm(root/a, assignment, contracts, nonlinear_inventory,
                                    'zero_based_offset' if zero_based_offset else 'direct', trace_start, trace_stop)
                          for a in ('native', 'conservative')]
        result['cycle_count'] = declared_cycles
        result['leading_warmup_sample_trimmed'] = bool(trace_start > 0)
        result['periodic_steady_state'] = False
    return result, comparisons


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    parser.add_argument('--experiment-root', type=Path)
    parser.add_argument('--full-cycle', action='store_true')
    parser.add_argument('--specific-onset', action='store_true')
    parser.add_argument('--nonlinear-inventory', action='store_true')
    parser.add_argument('--initial-flux-compensation', action='store_true')
    parser.add_argument('--zero-based-offset', action='store_true')
    parser.add_argument('--specific-inventory', action='store_true')
    parser.add_argument('--duration-s', type=float)
    parser.add_argument('--cycle-count', type=int)
    args = parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    result, comparisons = audit(Path(__file__).resolve().parents[1], args.full_cycle, args.specific_onset,
                                args.experiment_root, args.nonlinear_inventory, args.initial_flux_compensation, args.zero_based_offset,
                                args.specific_inventory, args.duration_s, args.cycle_count)
    args.output_root.mkdir(parents=True)
    (args.output_root/'cold_buffer_coupled_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(comparisons[0])); writer.writeheader(); writer.writerows(comparisons)
    print(json.dumps({k: result[k] for k in ('evidence_audit_pass', 'local_inventory_conservation_pass',
        'strict_initial_coordinate_match', 'initial_matching_counts', 'source_storage_port_checks', 'declared_window_numerical_gates_pass', 'production_recovery_allowed')}, indent=2))
    if args.full_cycle:
        print(json.dumps([{k: a[k] for k in ('arm', 'source_minus_actual_endpoint_storage_J', 'component_groups', 'selected_flow_gates', 'performance')}
                          for a in result['arms']], indent=2))
    raise SystemExit(0 if result['declared_window_numerical_gates_pass'] else 1)
