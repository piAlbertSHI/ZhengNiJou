"""Reconstruct a local initial pump/chamber residual with observed outer fluxes.

This is an independent four-equation diagnostic, not a replacement simulator.
"""
import argparse
import json
from pathlib import Path
import h5py
import numpy as np
from scipy.optimize import least_squares
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_ColdChamberRejection import read
from Audit_HeatDriveECC_NativeAccumulation import energy_tables
from Audit_HeatDriveECC_TLDomainInventory import literal_vector, scalar
from Audit_HeatDriveECC_SegmentedEvidence import sha256


def port_flux(table, mdot, node_temperature, pressure, outflow_u, conductance):
    if conductance <= 0 or not np.isfinite([mdot, node_temperature, pressure, outflow_u, conductance]).all():
        raise ValueError('Invalid port inputs')
    u_in = float(table['u']([[node_temperature, pressure]])[0])
    mdot_abs = np.hypot(mdot, 2*conductance)
    positive, negative = (1+mdot/mdot_abs)/2, (1-mdot/mdot_abs)/2
    upwind_u = positive*u_in+negative*outflow_u
    tgrid = table['u'].grid[0]
    ugrid = table['u'](np.column_stack((tgrid, np.full_like(tgrid, pressure))))
    if np.any(np.diff(ugrid) <= 0) or not ugrid[0] <= upwind_u <= ugrid[-1]:
        raise ValueError('Upwind property inversion outside monotone table')
    upwind_temperature = float(np.interp(upwind_u, ugrid, tgrid))
    rho = float(table['rho']([[upwind_temperature, pressure]])[0])
    # Algebraically equivalent to the normalized foundation port equation.
    phi = mdot_abs*(positive*u_in-negative*outflow_u)+mdot*pressure/rho
    return float(phi)


def central_jacobian(function, x, step):
    x = np.asarray(x, dtype=float)
    columns = []
    for k in range(len(x)):
        d = np.zeros_like(x); d[k] = step
        columns.append((function(x+d)-function(x-d))/(2*step))
    return np.column_stack(columns)


def analyze(repo, onset_side=None):
    if onset_side not in (None, 'left', 'right'):
        raise ValueError('Unknown event side')
    root = repo/'outputs_storage_audit'
    contract_path = root/'pump_subnetwork_contract_20260909_v2/pump_subnetwork_contract.json'
    c = read(contract_path)
    if (c['execution_commit'] != 'fa5d8f297a7bac7bfe9486362bbd27c4c0b6b72f' or
            not c['collection_pass'] or c['simulation_run'] or c['state_imported'] or c['production_recovery_allowed']):
        raise ValueError('Invalid local contract')
    blocks = {r['path'].split('/')[-1]: r for r in c['blocks']}
    pump = blocks['SMA Pressure Source (TL)']
    if pump['parameters']['power_spec'] != 'foundation.enum.power_spec.none':
        raise ValueError('Only the actually observed zero-added-power mode is implemented')
    if pump['parameters']['source_type'] != 'foundation.enum.constant_controlled.controlled':
        raise ValueError('Unexpected pressure source mode')
    settings = blocks['SMA_ThermalLiquidSettings']['parameters']
    table = energy_tables(settings)
    if settings['k_TLU_2_unit'] != 'mW/m/K':
        raise ValueError('Unexpected conductivity unit')
    conductivity = literal_vector(settings['k_TLU_2'])*1e-3
    tgrid, pgrid = table['u'].grid
    patm = scalar(settings['p_atm'], settings['p_atm_unit'], 'Pa')
    tatm = float(np.clip(293.15, tgrid[0], tgrid[-1])); patm = float(np.clip(patm, pgrid[0], pgrid[-1]))
    k_cv = float(np.interp(tatm, tgrid, conductivity)/table['cp']([[tatm, patm]])[0])
    equations = []
    for row in c['equation_sources']:
        path = Path(row['path'])
        if sha256(path) != row['sha256']:
            raise ValueError('Local equation source changed')
        equations.append(path)
    pressure_path = root/'chamber_pressure_coordinates_20260909_v2/pressure_coordinates.json'
    coordinates = read(pressure_path)
    if not coordinates['coordinate_derivative_audit_pass']:
        raise ValueError('Pressure-coordinate prerequisite failed')
    rows = coordinates['records']
    if len(rows) != 2 or not rows[0]['block_path'].endswith('SMA_PumpInletConnectingPipeVolume'):
        raise ValueError('Wrong chamber order')
    p = np.array([r['prescribed_pressure_Pa'] for r in rows])
    commands_path = root/'sma_derivative_contract_20260909_v3/sma_derivative_contract.json'
    if sha256(commands_path) != 'EE5C16D580693FCA925D24D0DB2A8E021BAC65E36F0A77A8E12AE795070ACEE2':
        raise ValueError('Original pressure command changed')
    commands = read(commands_path)['commands']
    if (commands[0]['values'][0] != commands[0]['values'][1]
            or commands[2]['values'][:2] != [0, 0] or commands[3]['values'][:2] != [1, 1]
            or abs((p[1]-p[0])-commands[0]['values'][0]*1e6) > 1e-8):
        raise ValueError('Initial zero pressure-rate reduction is not justified')
    temp = np.array([r['prescribed_temperature_K'] for r in rows])
    u = np.array([r['internal_energy_J_kg'] for r in rows])
    derivative = np.array([[r['pressure_derivative_Pa_per_kg'], r['pressure_derivative_Pa_per_J']] for r in rows])
    for row in rows:
        name = row['block_path'].split('/')[-1]
        if blocks[name]['resolved_geometry']['volume']['value'] != row['volume_m3']:
            raise ValueError('Inventory volume changed')
        if abs(float(table['u']([[row['prescribed_temperature_K'], row['prescribed_pressure_Pa']]])[0])
               -row['internal_energy_J_kg']) > 1e-6:
            raise ValueError('Actual full settings differ from coordinate tables')
    def conductance(block):
        geometry = block['resolved_geometry']['area']
        if geometry['unit'] != 'm^2' or geometry['value'] <= 0:
            raise ValueError('Invalid resolved port area')
        area = geometry['value']
        return k_cv*area/np.sqrt(4*area/np.pi)
    gp = conductance(pump)
    gc = [conductance(blocks[r['block_path'].split('/')[-1]]) for r in rows]
    source_root = root/'conservative_buffer_coupled_cycle_20260909'
    raw = source_root/'native/observations.mat'
    execution = read(source_root/'cold_chamber_execution.json')
    if sha256(raw) != execution['cases'][0]['observation_sha256']:
        raise ValueError('Native outer-flux reference changed')
    fluxes = []
    with h5py.File(raw) as f:
        native = named_rows(f, f['native'])
        for row, outer in zip(rows, ('A', 'B')):
            path = row['block_path']
            def initial(name, unit):
                if float(np.asarray(native[path, name]['time_s']).ravel()[0]) != 0:
                    raise ValueError('Noninitial outer flux')
                return float(scalar_series(native[path, name], unit)[0])
            fluxes.append(dict(block_path=path, outer_port=outer,
                               mdot_kg_s=initial('mdot_'+outer, 'kg/s'),
                               Phi_W=initial('Phi_'+outer, 'W'), Q_H_W=initial('Q_H', 'W')))
    prescribed_rate = 0.
    if onset_side is not None:
        from Audit_HeatDriveECC_ColdChamberStateCoordinates import bilinear_gradient
        from Analyze_HeatDriveECC_ChamberPressureCoordinates import inventory_jacobian
        raw = root/'nonlinear_pre_feedback_ramp_20260910/failed_public_observations.mat'
        if sha256(raw) != '4342D0B6ABC0DC06804886D83DDE8FA0C75D84B5DE37D98C5ACCC2512ABE24BE':
            raise ValueError('Onset evidence changed')
        fluxes = []
        with h5py.File(raw) as f:
            native = named_rows(f, f['native'])
            for i, (row, outer) in enumerate(zip(rows, ('A', 'B'))):
                path = row['block_path']
                def final(name, unit):
                    if float(np.asarray(native[path, name]['time_s']).ravel()[-1]) != .1:
                        raise ValueError('Require last observed left sample at 0.1s')
                    return float(scalar_series(native[path, name], unit)[-1])
                p[i], temp[i], u[i] = final('p_I', 'Pa'), final('T_I', 'K'), final('u_I', 'J/kg')
                rho = float(table['rho']([[temp[i], p[i]]])[0])
                rho_t, rho_p = (float(v[0]) for v in bilinear_gradient(table['rho'], [temp[i]], [p[i]]))
                u_t, u_p = (float(v[0]) for v in bilinear_gradient(table['u'], [temp[i]], [p[i]]))
                derivative[i] = np.linalg.inv(inventory_jacobian(rho, u[i], rho_t, rho_p, u_t, u_p, row['volume_m3']))[1]
                fluxes.append(dict(block_path=path, outer_port=outer, mdot_kg_s=final('mdot_'+outer, 'kg/s'),
                                   Phi_W=final('Phi_'+outer, 'W'), Q_H_W=final('Q_H', 'W')))
        if onset_side == 'right':
            ts, vs = np.asarray(commands[0]['time_s']), np.asarray(commands[0]['values'])
            first = np.flatnonzero(np.diff(vs) != 0)[0]
            if abs(ts[first]-.1)>1e-15:
                raise ValueError('Unexpected ramp onset')
            prescribed_rate = float((vs[first+1]-vs[first])/(ts[first+1]-ts[first])*1e6)
    mass_outer = np.array([r['mdot_kg_s'] for r in fluxes])
    energy_outer = np.array([r['Phi_W']+r['Q_H_W'] for r in fluxes])
    qscale, uscale, p_rate_scale = .001, 1000., 1e6
    ubase = float(u.mean())
    def evaluate(x, details=False):
        q = x[0]*qscale; node_t = temp+x[1:3]; pump_u = ubase+x[3]*uscale
        chamber_phi = np.array([port_flux(table, -q, node_t[0], p[0], u[0], gc[0]),
                                port_flux(table, q, node_t[1], p[1], u[1], gc[1])])
        pump_phi = np.array([port_flux(table, q, node_t[0], p[0], pump_u, gp),
                             port_flux(table, -q, node_t[1], p[1], pump_u, gp)])
        mdot = mass_outer+[-q, q]; udot = energy_outer+chamber_phi
        pdot = derivative[:, 0]*mdot+derivative[:, 1]*udot
        residual = np.r_[chamber_phi+pump_phi, pump_phi.sum(), (pdot[1]-pdot[0]-prescribed_rate)/p_rate_scale]
        if details:
            return dict(mdot_A_pump_kg_s=float(q), node_temperature_K=node_t.tolist(), pump_common_u_J_kg=pump_u,
                        chamber_Mdot_kg_s=mdot.tolist(), chamber_Udot_W=udot.tolist(), chamber_pdot_Pa_s=pdot.tolist(),
                        node_energy_residual_W=residual[:2].tolist(), pump_energy_residual_W=float(residual[2]),
                        pressure_rate_difference_Pa_s=float(pdot[1]-pdot[0]))
        return residual
    lower = [-1e3, *(tgrid[0]-temp), (max(table['u']([[tgrid[0], pressure]])[0] for pressure in p)-ubase)/uscale]
    upper = [1e3, *(tgrid[-1]-temp), (min(table['u']([[tgrid[-1], pressure]])[0] for pressure in p)-ubase)/uscale]
    result = least_squares(evaluate, np.zeros(4), bounds=(lower, upper), xtol=1e-12, ftol=1e-12, gtol=1e-12, max_nfev=1000)
    starts = []
    for seed in ([-.01, .01, -.01, .01], [.01, -.01, .01, -.01]):
        other = least_squares(evaluate, seed, bounds=(lower, upper), xtol=1e-12, ftol=1e-12, gtol=1e-12, max_nfev=1000)
        starts.append(dict(initial_scaled_coordinates=seed, maximum_scaled_residual=float(np.max(abs(other.fun))),
                           max_scaled_solution_difference=float(np.max(abs(other.x-result.x))), evaluations=other.nfev,
                           root_solver_success=bool(other.success)))
    spectra = []
    for step in (1e-5, 1e-6, 1e-7):
        j = central_jacobian(evaluate, result.x, step); singular = np.linalg.svd(j, compute_uv=False)
        row_scales = np.max(abs(j), axis=1); equilibrated = j/row_scales[:, None]
        spectra.append(dict(scaled_coordinate_step=step, scaled_jacobian=j.tolist(), singular_values=singular.tolist(),
                            numerical_rank=int(np.linalg.matrix_rank(j)), condition_number=float(singular[0]/singular[-1]),
                            row_equilibration_scales=row_scales.tolist(),
                            row_equilibrated_condition_number=float(np.linalg.cond(equilibrated))))
    files = [contract_path, pressure_path, commands_path, raw, source_root/'cold_chamber_execution.json', Path(__file__).resolve()]
    return dict(schema='heatdrive_ecc_pump_local_initialization_v2',
                local_residual_limit_scaled=1e-8,
                local_residual_pass=bool(np.max(abs(result.fun)) <= 1e-8 and all(r['maximum_scaled_residual'] <= 1e-8 for r in starts)),
                root_solver_success=bool(result.success), root_solver_message=result.message, evaluations=result.nfev,
                scaled_residual=result.fun.tolist(), prescribed_outer_fluxes=fluxes,
                variable_scales=dict(flow_kg_s=qscale, temperature_K=1., internal_energy_J_kg=uscale),
                pressure_rate_scale_Pa_s=p_rate_scale, thermal_energy_scale_W=1.,
                k_cv_kg_m_s=k_cv, pump_port_conductance_kg_s=gp, chamber_port_conductance_kg_s=gc,
                actual_power_spec='none', actual_pressure_derivative_Pa_s=prescribed_rate, result=evaluate(result.x, True),
                jacobian_refinements=spectra, additional_initial_guesses=starts,
                diagnostic_row_equilibration_applied_to_simscape=False,
                scope=('local four-equation reconstruction with fixed native t=0 external port fluxes' if onset_side is None
                       else 'conditional onset residual with fixed observed left-side outer fluxes'),
                onset_side=onset_side,
                whole_network_boundary_coupling_tested=False, actual_compiled_DAE_matrix_extracted=False,
                failed_model_initialization_repaired=False, trajectory_conservation_verified=False,
                production_recovery_allowed=False, table4_reproduction_claim=False,
                input_sha256={str(p.relative_to(repo)): sha256(p) for p in files},
                equation_source_sha256={str(p): sha256(p) for p in equations})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output-root', type=Path, required=True)
    parser.add_argument('--onset-side', choices=('left', 'right'))
    args = parser.parse_args()
    if args.output_root.exists():
        raise FileExistsError('Never overwrite evidence')
    result = analyze(Path(__file__).resolve().parents[1], args.onset_side); args.output_root.mkdir(parents=True)
    (args.output_root/'pump_local_initialization.json').write_text(json.dumps(result, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k not in ('input_sha256', 'equation_source_sha256')}, indent=2))
    raise SystemExit(0 if result['local_residual_pass'] else 1)
