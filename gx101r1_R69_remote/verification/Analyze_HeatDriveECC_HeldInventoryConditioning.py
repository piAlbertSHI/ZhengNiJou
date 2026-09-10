"""Read-only inventory scales and reference-table coordinate conditioning."""
import argparse
import json
from pathlib import Path
import h5py
import numpy as np
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_ColdPassivePSObserver import read, sha256, CHAMBERS, BUFFERS
from Audit_HeatDriveECC_HybridHeldResult import sampled_rows
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Analyze_HeatDriveECC_HeldAlgebraicResiduals import reference_domains


def inventory_scale(values, tolerance, relative_tolerance):
    x = np.asarray(values, dtype=float)
    if x.ndim != 1 or x.size < 2 or not np.isfinite(x).all() or np.any(x <= 0):
        raise ValueError('Require positive finite full-window inventories')
    if not np.isfinite([tolerance, relative_tolerance]).all() or min(tolerance, relative_tolerance) <= 0:
        raise ValueError('Invalid diagnostic thresholds')
    change = float(np.max(abs(x-x[0]))); ulp = float(np.max(np.spacing(x)))
    return dict(initial=float(x[0]), max_change=change, relative_max_change=change/float(x[0]),
        largest_float64_spacing=ulp, closure_tolerance=tolerance, closure_tolerance_in_ulps=tolerance/ulp,
        illustrative_relative_error_term_initial=relative_tolerance*float(x[0]),
        relative_term_over_closure_tolerance=relative_tolerance*float(x[0])/tolerance,
        actual_compiled_error_weight_verified=False)


def cell_gradient(table, temperature, pressure, side):
    """Differentiate the selected bilinear cell; inspect both sides of knots."""
    if side not in ('left', 'right'): raise ValueError('Unknown knot side')
    grids = table.grid; point = (temperature, pressure); index = []
    for axis, value in zip(grids, point):
        if not np.isfinite(value) or value < axis[0] or value > axis[-1]:
            raise ValueError('No table extrapolation allowed')
        index.append(int(np.clip(np.searchsorted(axis, value, side=side)-1, 0, len(axis)-2)))
    i, j = index; t, p = grids; z = table.values
    a = (temperature-t[i])/(t[i+1]-t[i]); b = (pressure-p[j])/(p[j+1]-p[j])
    dt = ((1-b)*(z[i+1,j]-z[i,j])+b*(z[i+1,j+1]-z[i,j+1]))/(t[i+1]-t[i])
    dp = ((1-a)*(z[i,j+1]-z[i,j])+a*(z[i+1,j+1]-z[i+1,j]))/(p[j+1]-p[j])
    return np.array([dt, dp]), index


def chamber_jacobian(table, temp, pressure, volume, side):
    if not np.isfinite(volume) or volume <= 0: raise ValueError('Nonpositive chamber volume')
    point = [[temp, pressure]]
    rho = float(table['rho'](point)[0]); u = float(table['u'](point)[0])
    drho, cell = cell_gradient(table['rho'], temp, pressure, side)
    du, ucell = cell_gradient(table['u'], temp, pressure, side)
    if cell != ucell: raise ValueError('Inconsistent table grids')
    jac = np.vstack((volume*drho, volume*(u*drho+rho*du)))
    inventory = np.array([volume*rho, volume*rho*u])
    if min(temp, pressure, *inventory) <= 0 or not np.isfinite(jac).all():
        raise ValueError('Invalid positive scaling basis')
    # This is a local coordinate map, not Simscape's compiled iteration matrix.
    scaled = jac*np.array([temp, pressure])[None,:]/inventory[:,None]
    singular = np.linalg.svd(scaled, compute_uv=False)
    return dict(cell_index=cell, temperature_K=float(temp), pressure_Pa=float(pressure),
        jacobian_M_U_wrt_T_p_SI=jac.tolist(), scaled_jacobian=scaled.tolist(),
        scaling_basis='diag(1/M,1/U) * J * diag(T,p), local reference-table values',
        singular_values=singular.tolist(), condition_number_2=float(singular[0]/singular[-1]) if singular[-1] else None,
        exact_zero_singular_value=bool(singular[-1] == 0))


def analyze(repo):
    root = repo/'outputs_storage_audit'
    audit_path = root/'hybrid_held_ode23t_audit_20260910/held_interval_audit.json'; audit = read(audit_path)
    if sha256(audit_path) != 'BB1136088658C84AD15F6A369FF087C617D2F5349F1EE00B0FAEECCFED0F1C21':
        raise ValueError('Qualified held evidence changed')
    for relative, expected in audit['input_sha256'].items():
        if sha256(repo/relative) != expected: raise ValueError('Recorded trajectory dependency changed')
    source = root/'conservative_buffer_coupled_cycle_20260909/conservative'
    mp = source/'inventory_metadata.json'; tp = source/'tl_connectivity.json'
    if sha256(mp) != '0920512F1D0C6A0075FED55045A7AD4D6E47818D7EB7EC806A679E97D25CC5FF' or sha256(tp) != '64C339631FD5F85A6F5F3103A40B52B7626FE34CC39828A873A1821359CE4E4F':
        raise ValueError('Reference metadata changed')
    metadata = read(mp); assignment, aliases = reference_domains(read(tp))
    tables = {b['block_path']:energy_tables(b['parameters']) for b in metadata['settings_tables']}
    params = {b['block_path']:b['mask_parameters'] for b in metadata['storage_blocks']}
    data_root = root/'specific_inventory_hybrid_held_ode23t_after_restart_20260910'
    record_path = data_root/'compiled_states_inspection.json'; record = read(record_path)
    raw = data_root/'observations.mat'; components = []; mappings = []
    with h5py.File(raw) as f:
        rows, t = sampled_rows(f, 'native', 1258)
        for name in sorted(CHAMBERS | BUFFERS):
            path = 'heatdrive_ecc_coupled_se21/'+name
            get = lambda n, u: scalar_series(rows[path,n], u)
            entries = record['runtime_callbacks'][0]['chamber_nominals' if name in CHAMBERS else 'buffer_nominals']
            nominal = [e for e in entries if e['block_path'] == path]
            if len(nominal) != 2: raise ValueError('Missing runtime nominal settings')
            components.append(dict(block_path=path, recorded_nominal_overrides=nominal,
                mass_kg=inventory_scale(get('stored_mass','kg'), 1e-15, 1e-6),
                energy_J=inventory_scale(get('stored_energy','J'), 1e-8, 1e-6)))
            if name not in CHAMBERS: continue
            volume = params[path]['volume']
            if volume['unit'] != 'm^3': raise ValueError('Unexpected chamber geometry units')
            temp = get('T_I','K'); pressure = get('p_I','Pa'); table = tables[assignment[path]]
            evaluations = [chamber_jacobian(table, a, b, volume['value'], side)
                           for a, b in zip(temp, pressure) for side in ('left','right')]
            conditions = [e['condition_number_2'] for e in evaluations if e['condition_number_2'] is not None]
            mappings.append(dict(block_path=path, sample_count=len(t), evaluations=len(evaluations),
                initial_left=evaluations[0], initial_right=evaluations[1], final_left=evaluations[-2], final_right=evaluations[-1],
                condition_number_range=[min(conditions),max(conditions)] if conditions else None,
                any_exact_zero_singular_value=any(e['exact_zero_singular_value'] for e in evaluations)))
    files = [audit_path, mp, tp, record_path, raw]
    return dict(inventory_scales=components, chamber_reference_coordinate_maps=mappings,
        model_normalization=record['normalize_using_nominal_values'],
        model_nominal_value_table=json.loads(record['model_nominal_value_table']),
        compiled_dataset_elements=record['dataset_elements'],
        compiled_dataset_is_solver_error_weight_vector=False,
        auto_scale_absolute_tolerance_recorded=all('AutoScaleAbsTol' in c for c in record['runtime_callbacks']),
        actual_compiled_error_weights_verified=False, full_compiled_iteration_matrix_verified=False,
        reference_table_derivatives_not_fresh_runtime_export=True,
        illustrative_relative_tolerance=1e-6, relative_error_term_is_not_balance_error_bound=True,
        unique_root_cause_verified=False, production_recovery_allowed=False,
        full_system_first_law_verified=False, table4_reproduction_claim=False,
        input_sha256={str(p.relative_to(repo)):sha256(p) for p in files})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root',type=Path,required=True); args = parser.parse_args()
    if args.output_root.exists(): raise FileExistsError('Never overwrite evidence')
    result = analyze(Path(__file__).resolve().parents[1]); args.output_root.mkdir(parents=True)
    (args.output_root/'inventory_conditioning.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('inventory_scales','chamber_reference_coordinate_maps','model_nominal_value_table','input_sha256')},indent=2))
