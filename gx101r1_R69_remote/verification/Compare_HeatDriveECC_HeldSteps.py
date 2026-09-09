"""Compare measured cold held-interval residuals; never extrapolate a pass."""
import argparse
import json
import math
from pathlib import Path

from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256, CHAMBERS, BUFFERS


AUDITS = (
    'hybrid_held_interval_audit_20260910_v2',
    'hybrid_held_halfstep_audit_20260910',
    'hybrid_held_quarterstep_audit_20260910',
)
RAW = (
    'specific_inventory_hybrid_held_interval_20260910_v2',
    'specific_inventory_hybrid_held_halfstep_20260910',
    'specific_inventory_hybrid_held_quarterstep_20260910',
)
STEPS = (.001, .0005, .00025)
FIELDS = ('mass_max_abs_residual_kg', 'energy_max_abs_residual_J')


def trend(values):
    if len(values) != 3 or any(not math.isfinite(x) or x < 0 for x in values):
        raise ValueError('Require three finite nonnegative measured residuals')
    ratios = [b / a if a else None for a, b in zip(values, values[1:])]
    orders = [-math.log2(r) if r is not None and r > 0 else None for r in ratios]
    return dict(measured_residuals=values, fine_over_coarse_ratios=ratios,
                empirical_residual_decay_exponents=orders,
                monotone_nonincreasing=all(b <= a for a, b in zip(values, values[1:])),
                extrapolated_pass=False)


def compare(results):
    if len(results) != 3:
        raise ValueError('Require exactly three grid results')
    names = {'heatdrive_ecc_coupled_se21/' + n for n in CHAMBERS | BUFFERS}
    maps = []
    for r, count in zip(results, (41, 81, 161)):
        if (not r['evidence_audit_pass'] or r['observed_interval_s'] != [0, .04]
                or r['exported_sample_count'] != count
                or not r['initial_coordinate_audit']['strict_initial_coordinate_gate']
                or not r['compiled_inventory_gate'] or r['compiled_algebraic_loops'] != 0
                or r['production_recovery_allowed'] or r['table4_reproduction_claim']):
            raise ValueError('Prerequisite or diagnostic boundary changed')
        rows = r['local_balances']
        if len(rows) != 6 or {x['block_path'] for x in rows} != names:
            raise ValueError('Incomplete or duplicate component coverage')
        for x in rows:
            if x['mass_limit_kg'] != 1e-15 or x['energy_limit_J'] != 1e-8:
                raise ValueError('Scientific thresholds changed')
            if (x['mass_closure_pass'] != (x[FIELDS[0]] <= 1e-15)
                    or x['energy_closure_pass'] != (x[FIELDS[1]] <= 1e-8)):
                raise ValueError('Inconsistent reported component gate')
        both = sum(x['mass_closure_pass'] and x['energy_closure_pass'] for x in rows)
        if r['passing_local_balances'] != both or r['local_balance_gate'] != (both == 6):
            raise ValueError('Inconsistent aggregate gate')
        maps.append({x['block_path']: x for x in rows})
    rows = []
    for name in sorted(names):
        items = [m[name] for m in maps]
        rows.append(dict(block_path=name,
                         **{k: trend([x[k] for x in items]) for k in FIELDS},
                         mass_pass=[x['mass_closure_pass'] for x in items],
                         energy_pass=[x['energy_closure_pass'] for x in items],
                         endpoint_changes={k: [x[k] for x in items] for k in
                             ('mass_endpoint_change_kg', 'energy_endpoint_change_J')},
                         simpson_residuals={k: [x[k] for x in items] for k in
                             ('simpson_mass_max_abs_residual_kg', 'simpson_energy_max_abs_residual_J')}))
    return dict(global_max_steps_s=list(STEPS), component_comparisons=rows,
                passing_components=[r['passing_local_balances'] for r in results],
                measured_local_balance_pass=[r['local_balance_gate'] for r in results],
                baseline_output_settings_captured=False,
                quadrature_convergence_verified=False, unique_root_cause_verified=False,
                full_system_first_law_verified=False, production_recovery_allowed=False,
                table4_reproduction_claim=False,
                interpretation='Empirical residual decay is not solver-order proof or an extrapolated scientific pass.')


def build(repo):
    base = repo / 'outputs_storage_audit'
    paths = [base / n / 'held_interval_audit.json' for n in AUDITS]
    results = [read(p) for p in paths]
    for r in results:
        for relative, expected in r['input_sha256'].items():
            if sha256(repo / relative) != expected:
                raise ValueError('Changed audit dependency: ' + relative)
    for r, folder, step in zip(results, RAW, STEPS):
        inspection = read(base / folder / 'compiled_states_inspection.json')
        if float(inspection['global_solver_configuration']['MaxStep']) != step:
            raise ValueError('Actual step differs from grid declaration')
        if r.get('global_max_step_s', step) != step:
            raise ValueError('Audit step disagrees')
    if results[1]['output_sampling_settings'] != results[2]['output_sampling_settings']:
        raise ValueError('Fine-grid sampling configuration changed')
    report = compare(results)
    report['input_audit_sha256'] = {str(p.relative_to(repo)): sha256(p) for p in paths}
    report['comparison_source_sha256'] = sha256(Path(__file__))
    files = []
    for folder in (*RAW, *AUDITS):
        root = (base / folder).resolve()
        if not root.is_relative_to(base.resolve()):
            raise ValueError('Package outside audit root')
        for p in sorted(root.rglob('*')):
            if p.is_file():
                if not p.resolve().is_relative_to(root):
                    raise ValueError('Package link escapes root')
                files.append(dict(path=str(p.relative_to(repo)), bytes=p.stat().st_size,
                                  sha256=sha256(p)))
    report['retained_packages'] = dict(file_count=len(files), bytes=sum(f['bytes'] for f in files),
                                      files=files, deleted_files=0,
                                      policy='Retain three required convergence grids, frozen benchmarks and rejection evidence; no raw duplicates created.')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result = build(Path(__file__).resolve().parents[1])
    args.output_root.mkdir(parents=True)
    (args.output_root / 'held_step_comparison.json').write_text(
        json.dumps(result, indent=2, allow_nan=False) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k not in
                     ('component_comparisons', 'retained_packages')}, indent=2))
    print(json.dumps({k: v for k, v in result['retained_packages'].items() if k != 'files'}))
