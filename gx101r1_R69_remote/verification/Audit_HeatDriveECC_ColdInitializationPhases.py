"""Localize target mismatch using callback-visible settings and cached public phases."""
import argparse
import csv
import json
import math
from pathlib import Path

from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_ColdInitialTolerance import coordinates, check_settings
from Audit_HeatDriveECC_CompiledInventoryStates import CHAMBERS, BUFFERS, decode_tags, component_inventory_preserved
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Audit_HeatDriveECC_ColdBufferCoupled import port_contract


CASES = [('runtime_local', 'specific_inventory_initial_runtime_context_20260909', 'dbd67c3'),
         ('cached_local', 'specific_inventory_cached_initial_phases_20260909', 'abd4bc9'),
         ('global', 'specific_inventory_initial_global_tight_20260909', 'a9c8883')]
SCALING_CASES = [('buffer_nominals', 'specific_inventory_initial_buffer_nominals_20260909', 'e324f59'),
                 ('all_target_tags', 'specific_inventory_all_target_tags_20260909', '94b7920'),
                 ('normal', 'specific_inventory_initial_normal_mode_20260909', 'ec465e8')]
MOMENTUM_CASES = [('momentum', 'specific_inventory_momentum_initial_20260909', '21d9098ec5a630f6d70732e87418f5fa483bc605')]
REGULARIZATION_CASES = [('regularization_off', 'specific_inventory_regularization_off_initial_20260909', 'dada2c67fdb4d29b93c45a6662238fc6313769c3')]
RUNTIME_BASE = dict(ResolveIndetEquations='on', DoFixedCost='off', ComputeImpulses='off',
                    ImpulseIterations='2', IndexReductionMethod='DerivativeReplacement', DoDC='off')


def check_regularization(record):
    expected = dict(RUNTIME_BASE, ResolveIndetEquations='off')
    if (not record['disable_regularization_requested'] or record['runtime_solver_options_before'] != RUNTIME_BASE
            or record['runtime_solver_options_after'] != expected or any(record[k] for k in
                ('momentum_buffers_requested','normal_mode_requested','buffer_nominal_scaling_requested',
                 'global_tolerance_override','consistency_tolerance_override','residual_tolerance_override'))):
        raise ValueError('Regularization-only experiment changed another factor')
    if len(record['runtime_callbacks']) != 3 or any(c['runtime_solver_options'] != expected for c in record['runtime_callbacks']):
        raise ValueError('Runtime regularization state differs from the declared experiment')


def check_momentum_rows(contracts, rows):
    by_path = {c['block_path']: c for c in contracts}
    if len(contracts) != 4 or len(by_path) != 4 or len(rows) != 4:
        raise ValueError('Incomplete momentum buffer coverage')
    if {p.split('/', 1)[1] for p in by_path} != BUFFERS:
        raise ValueError('Wrong buffer paths')
    seen = set(); result = []
    for r in rows:
        path = r['block_path']
        if path not in by_path or path in seen: raise ValueError('Unknown or duplicate momentum observation')
        seen.add(path); c = by_path[path]; port_contract(c)
        if (c['candidate_source_file'] != 'ecc_buffer_momentum.conservative_buffer' or c['initial_source_time_s'] != 0
                or c['tank_area_m2'] != .001 or c['port_area_m2'] != .01 or c['inlet_height_m'] != 0
                or c['gravity_m_s2'] != 9.81 or c['p_environment_Pa'] != 1e6 or c['mainline_recovery_allowed']):
            raise ValueError('Changed cold buffer geometry or restore contract')
        names = ('mdot_A', 'rho_port', 'dynamic_pressure', 'p_A', 'rho_I', 'level')
        if r['source_time_s'] != 0 or not all(math.isfinite(r[k]) for k in names) or min(r['rho_port'], r['rho_I'], r['level']) <= 0:
            raise ValueError('Nonfinite or nonphysical momentum observation')
        dynamic = r['mdot_A']**2/(2*r['rho_port']*c['port_area_m2']**2) if r['mdot_A'] < 0 else 0.
        residual = r['p_A']+dynamic-c['p_environment_Pa']-r['rho_I']*c['gravity_m_s2']*r['level']
        if not math.isclose(dynamic, r['dynamic_pressure'], rel_tol=1e-10, abs_tol=1e-30) or abs(residual) > 1e-6:
            raise ValueError('Momentum equation or sign failed')
        result.append(dict(block_path=path, dynamic_pressure_Pa=dynamic, momentum_residual_Pa=residual))
    return result


def target_map(rows):
    out = {}
    for r in rows:
        if r['path'] in out: raise ValueError('Duplicate public phase target')
        out[r['path']] = (r['unit'], r['priority'], r['value'])
    return out


def check_callbacks(callbacks, targets, settings, global_tolerances, mode='accelerator'):
    if mode not in ('normal', 'accelerator'): raise ValueError('Unsupported declared execution mode')
    if [r['stage'] for r in callbacks] != ['InitFcn', 'StartFcn', 'StopFcn']:
        raise ValueError('Missing, repeated or out-of-order callbacks')
    expected = target_map(targets)
    for r in callbacks:
        status = 'terminating' if r['stage'] == 'StopFcn' else 'initializing'
        if (r['simulation_status'] != status or r['solver_settings'] != settings
                or {k: r[k] for k in ('RelTol', 'AbsTol')} != global_tolerances
                or r['SimscapeUseOperatingPoints'] != 'on' or r['LoadInitialState'] != 'off'
                or r['has_private_data'] or r['mode'] != mode or target_map(r['targets']) != expected):
            raise ValueError('Callback-visible settings or resolved public targets differ')


def check_phases(phases, targets, measured):
    if [r['phase'] for r in phases] != ['Prestart', 'Start']: raise ValueError('Missing cached phase')
    expected = target_map(targets)
    observed = {r['path']: (r['unit'], r['priority'], r['actual']) for r in measured}
    for r in phases:
        if not r['cache_requested'] or r['private_payload_exported']: raise ValueError('Noncached or private extraction')
        if target_map(r['public_targets']) != (expected if r['phase'] == 'Prestart' else observed):
            raise ValueError('Cached Prestart is not the target or Start is not logged t=0')


def check_buffer_nominals(record, targets):
    expected = {r['path']: r for r in targets if r['path'].split('/')[0] in BUFFERS and r['path'].split('/')[-1] in ('stored_mass', 'stored_energy')}
    changes = record['buffer_nominal_changes']
    if len(expected) != 8 or len(changes) != 8 or not record['buffer_nominal_scaling_requested']:
        raise ValueError('Incomplete nominal change set')
    seen = set()
    for c in changes:
        path = c['block_path'].split('/', 1)[1]+'/'+c['state_name']
        if path not in expected or path in seen: raise ValueError('Unknown or duplicated nominal change')
        seen.add(path); t = expected[path]
        if (c['source_time_s'] != 0 or c['nominal_value'] != t['value'] or c['unit'] != t['unit'] or c['nominal_value'] <= 0
                or c['before'] != dict(specify='off', value='1', unit=t['unit'])):
            raise ValueError('Nominal scale not derived from unchanged cold inventory')
    for callback in record['runtime_callbacks']:
        if callback['normalize_using_nominal_values'] != 'on' or len(callback['buffer_nominals']) != 8:
            raise ValueError('Nominal normalization not active or callback coverage incomplete')
        seen = set()
        for c in callback['buffer_nominals']:
            path = c['block_path'].split('/', 1)[1]+'/'+c['state_name']
            if path not in expected or path in seen: raise ValueError('Unknown or duplicated runtime scale')
            seen.add(path); t = expected[path]
            if c['specify'] != 'on' or c['unit'] != t['unit'] or float(c['value']) != t['value']:
                raise ValueError('Runtime nominal value differs')


def audit(repo, scaling_mode=False, momentum=False, regularization=False):
    if sum((scaling_mode,momentum,regularization)) > 1: raise ValueError('Do not mix experiment contracts')
    targets_path = repo/'outputs_storage_audit/conservative_buffer_coupled_cycle_20260909/conservative/public_inventory_targets.json'
    targets_record = read(targets_path); targets = targets_record['targets']
    if len(targets) != 204 or targets_record['has_private_data'] or targets_record['source_time_s'] != 0:
        raise ValueError('Wrong reference initial target contract')
    native = targets_path.parent.parent/'native/observations.mat'
    if sha256(native) != targets_record['source_sha256']: raise ValueError('Native source changed')
    baseline_path = repo/'outputs_storage_audit/specific_inventory_initial_default_20260909/compiled_states_inspection.json'
    baseline = read(baseline_path)
    baseline_values = {r['path']: r['actual'] for r in baseline['initial_coordinates']}
    original = repo/'verification/simscape_inventory/+ecc_inventory/conservative_chamber.ssc'
    expected_component = original.read_text(encoding='utf-8').replace('stored_mass == volume * rho_I;', 'rho_I == stored_mass / volume;')
    expected_component = expected_component.replace('stored_energy == stored_mass * u_I;', 'u_I == stored_energy / stored_mass;')
    files = [targets_path, native, baseline_path, original]; results = []; rows = []
    cases = REGULARIZATION_CASES if regularization else (MOMENTUM_CASES if momentum else (SCALING_CASES if scaling_mode else CASES))
    for name, folder, producer in cases:
        root = repo/'outputs_storage_audit'/folder; path = root/'compiled_states_inspection.json'; r = read(path)
        if (not r['inspector_commit'].startswith(producer) or not r['inspection_pass'] or not r['initialization_only']
                or not r['runtime_callback_capture_requested'] or not r['post_initialization_source_file_verified']
                or r['source_native_sha256'] != targets_record['source_sha256'] or r['source_time_s'] != 0
                or any(r[k] for k in ('c200_state_imported', 'failed_terminal_state_imported', 'checkpoint_saved', 'production_recovery_allowed'))
                or r['inventory_formulation'] != 'specific_inventory' or r['component_inventory_priority_high']):
            raise ValueError('Wrong runtime context evidence')
        global_tolerances = {'RelTol': '1e-10', 'AbsTol': '1e-12'} if name == 'global' else {'RelTol': '1e-2', 'AbsTol': '1e-3'}
        check_settings('default' if scaling_mode or momentum or regularization or name == 'global' else 'tight', r['consistency_settings_before'], r['consistency_settings_after'])
        check_callbacks(r['runtime_callbacks'], targets, r['consistency_settings_after'], global_tolerances, 'normal' if name == 'normal' else 'accelerator')
        if name == 'buffer_nominals': check_buffer_nominals(r, targets)
        if regularization: check_regularization(r)
        momentum_evidence = None
        if momentum:
            if (not r['momentum_buffers_requested'] or r['normal_mode_requested'] or r['buffer_nominal_scaling_requested']
                    or r['global_tolerance_override'] or r['consistency_tolerance_override'] or r['residual_tolerance_override']):
                raise ValueError('Momentum trial changed another experiment factor')
            contract = r['momentum_contract']
            for key in ('audit', 'component', 'library'):
                p = Path(contract[key+'_path'])
                if not p.resolve().is_relative_to(repo.resolve()) or sha256(p) != contract[key+'_sha256']:
                    raise ValueError('Changed or external momentum prerequisite')
                files.append(p)
            qualified = read(Path(contract['audit_path']))
            if (not qualified['isolated_component_conservation_pass'] or not qualified['momentum_boundary_trial']
                    or qualified['production_recovery_allowed'] or len(qualified['cases']) != 16):
                raise ValueError('Isolated momentum qualification failed')
            for relative, digest in qualified['input_sha256'].items():
                p = repo/relative
                if not p.resolve().is_relative_to(repo.resolve()) or sha256(p) != digest:
                    raise ValueError('Qualified raw evidence changed')
                files.append(p)
            momentum_evidence = check_momentum_rows(r['buffer_replacement_contracts'], r['buffer_momentum_initial'])
        library = root/'component_build/ecc_inventory_specific_lib.slx'
        component = root/'component_build/+ecc_inventory_specific/conservative_chamber.ssc'
        if (Path(r['loaded_chamber_library']).resolve() != library.resolve() or sha256(library) != r['loaded_library_sha256']
                or r['chamber_source_file'] != 'ecc_inventory_specific.conservative_chamber'
                or component.read_text(encoding='utf-8') != expected_component):
            raise ValueError('Component source changed')
        measured = coordinates(r['initial_coordinates'], targets)
        tagged = [dict(block_name=t['block_name'], variable_name=t['variable_name'], **decode_tags(t)) for t in r['node_metadata']]
        compiled = component_inventory_preserved(tagged, CHAMBERS | BUFFERS)
        target_classification = None
        if (scaling_mode and name != 'buffer_nominals') or momentum or regularization:
            classified = [dict(priority=t['priority'], **decode_tags(t)) for t in r['initial_coordinates']]
            target_classification = {p: dict(count=sum(t['priority'] == p for t in classified),
                retained_differential_count=sum(t['priority'] == p and t['isRetained'] and t['isDifferential'] for t in classified)) for p in ('High', 'Low')}
        phase_verified = False
        if name != 'runtime_local':
            if r['cached_extraction_added_callbacks']: raise ValueError('Cached extraction reinitialized model')
            check_phases(r['cached_phase_targets'], targets, measured); phase_verified = True
        results.append(dict(case=name, inspector_commit=r['inspector_commit'], callback_visible_contract_pass=True,
                            cached_phase_localization_verified=phase_verified, compiled_inventory_gate=compiled,
                            strict_initial_coordinate_match=all(t['within_strict_comparison'] for t in measured),
                            initial_matching_count=sum(t['within_strict_comparison'] for t in measured),
                            initial_matching_counts={p: sum(t['within_strict_comparison'] for t in measured if t['priority'] == p) for p in ('High', 'Low')},
                            momentum_evidence=momentum_evidence,
                            target_differential_classification=target_classification,
                            algebraic_independence_of_targets_proven=False,
                            changed_coordinate_count=sum(t['actual'] != baseline_values[t['path']] for t in measured),
                            actual_coordinates_identical_to_default={t['path']: t['actual'] for t in measured} == baseline_values))
        rows += [dict(case=name, **t) for t in measured]
        files += [path, library, component, root/'compiled_initial_state_dataset.mat', root/'matlab_diary.log']
    frozen_path = repo/'verification/c200_mainline_freeze_contract.json'; f = read(frozen_path); files.append(frozen_path)
    for key in ('result', 'checkpoint'):
        p = repo/f[key+'_relative_path']
        if sha256(p) != f[key+'_sha256']: raise ValueError('Frozen C200 changed')
        files.append(p)
    return dict(schema='heatdrive_ecc_cold_initialization_phases_v1', evidence_audit_pass=True, cases=results,
                engine_internal_tolerance_values_exported=False, initialization_repair_verified=any(
                    r['strict_initial_coordinate_match'] and r['compiled_inventory_gate'] for r in results),
                production_recovery_allowed=False, full_device_first_law_verified=False, table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files}), rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    parser.add_argument('--scaling-mode', action='store_true')
    parser.add_argument('--momentum', action='store_true')
    parser.add_argument('--regularization-off', action='store_true')
    args = parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    result, rows = audit(Path(__file__).resolve().parents[1], args.scaling_mode, args.momentum, args.regularization_off); args.output_root.mkdir(parents=True)
    (args.output_root/'initialization_phases_audit.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    with (args.output_root/'initial_coordinates.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
    print(json.dumps({k: v for k, v in result.items() if k != 'input_sha256'}, indent=2))
    raise SystemExit(0 if result['initialization_repair_verified'] else 1)
