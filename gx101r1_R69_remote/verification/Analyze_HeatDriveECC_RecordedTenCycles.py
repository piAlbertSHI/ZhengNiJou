"""Read measured native packets without joining or duplicating their large MAT files."""
import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from Analyze_HeatDriveECC_CoolingBoundaryReconciliation import aligned_window_indices, integrals, reconciliation, stage_ids
from Audit_HeatDriveECC_C201Horizon import named_rows
from Audit_HeatDriveECC_ColdCoordinateSmoke import scalar_series
from Audit_HeatDriveECC_SegmentedEvidence import sha256
from Close_HeatDriveECC_SplitObservation import read, validate_gate
from HeatDriveECC_ObservationWindow import window_indices
from HeatDriveECC_RuntimeTcTrial import validate_trial
from Audit_HeatDriveECC_TLDomainInventory import density_table, resolve_domains, scalar


PUBLIC = ('SMA_Tx21_internal', 'SE_Tx21_internal', 'SHEX_hot_sink_temp_out',
          'hot_sink_temp_out', 'cold_sink_temp_out', 'ECC_constitutive21_output',
          'mass_flow_v4_hot_inlet_kgps', 'hot_hx_inlet_fluid_temp_out',
          'cold_hx_inlet_fluid_temp_out', 'cold_hx_outlet_fluid_temp_out',
          'Qdot_cold_sink_mass_to_hx_pipe_W', 'shex_source_heat_flow_W')


def join_measured(parts):
    """Remove duplicate endpoints only after verifying the actual values and clocks."""
    times, values = [], []
    for time, value in parts:
        time, value = np.asarray(time).ravel(), np.asarray(value)
        window_indices(time, float(time[0]), float(time[-1]))
        if value.ndim != 2 or value.shape[1] != time.size or not np.isfinite(value).all():
            raise ValueError('Incomplete channel/time samples')
        if times:
            if abs(time[0]-times[-1][-1]) > 1e-9 or not np.array_equal(value[:, 0], values[-1][:, -1]):
                raise ValueError('A packet boundary cannot be filled, averaged or interpolated')
            time, value = time[1:], value[:, 1:]
        times.append(time)
        values.append(value)
    return np.concatenate(times), np.concatenate(values, axis=1)


def native_statistics(time, values):
    time, values = np.asarray(time), np.asarray(values)
    if time.size != 100001 or values.shape != (1, time.size):
        raise ValueError('Require ten complete scalar measured cycles')
    # Integer samples, including the shared cycle endpoint; no resampling.
    differences = np.concatenate([values[:, c*10000:(c+1)*10000+1]-
                                 values[:, (c-1)*10000:c*10000+1] for c in range(1, 10)], axis=1)
    magnitude = np.sort(abs(differences).ravel())
    return dict(start=float(values[0, 0]), stop=float(values[0, -1]),
        net_change=float(values[0, -1]-values[0, 0]),
        maximum_cycle_endpoint_change=float(abs(np.diff(values[0, ::10000])).max()),
        same_phase_maximum=float(magnitude[-1]), same_phase_p99=float(magnitude[int(np.ceil(.99*magnitude.size))-1]),
        same_phase_rms=float(np.sqrt(np.mean(differences**2))),
        cycle_endpoints=values[0, ::10000].tolist(), tolerance_imposed=False)


def native_pipe_inventory(metadata, connectivity, block, specific_energy):
    rows = [row for row in metadata['storage_blocks'] if row['block_path'] == block]
    if len(rows) != 1:
        raise ValueError('Ambiguous native cold pipe geometry')
    pipe = rows[0]
    mode, geometry = pipe['model_modes'], pipe['mask_parameters']
    if mode['dynamic_compressibility'] != 'false' or mode['inertia'] != 'false':
        raise ValueError('This native pipe requires a different inventory equation')
    if geometry['area']['unit'] != 'm^2' or geometry['length']['unit'] != 'm':
        raise ValueError('Native pipe geometry units changed')
    domains, _ = resolve_domains(connectivity)
    settings = next(row for row in metadata['settings_tables'] if row['block_path'] == domains[block])
    density = density_table(settings['parameters'])
    temperature = scalar(mode['T_nominal'], mode['T_nominal_unit'], 'K')
    pressure = scalar(mode['p_nominal'], mode['p_nominal_unit'], 'Pa')
    mass = float(density([[temperature, pressure]])[0])*geometry['area']['value']*geometry['length']['value']
    # Native incompressible/no-inertia pipe: the same fixed nominal mass as cycle_arm/ledgers.
    return mass*np.asarray(specific_energy), mass


def runtime_window(result):
    start,stop=result['collection_window_s']
    rows=result['completed_packets']
    if result['schema']=='heatdrive_ecc_runtime_Tc_continuation_collection_v1':
        c=result['continuation'];check=result['latest_periodicity'];target=result['latest_target_stability']
        source=Path(result['origin_measured_window_path'])
        if (not result['pass'] or result['error_message'] or result['source_state_edited'] or result['partial_state_restore_used'] or
                not 1<=len(rows)<=10 or stop-start!=20*len(rows) or start!=c['source_snapshot_s'] or
                c['budget_stop_s']!=start+200 or stop>c['budget_stop_s'] or stop>2000 or
                result['planned_collection_window_s']!=[start,start+200] or stop!=10*result['total_cycles'] or
                check['window_s']!=[stop-100,stop] or target['window_s']!=[stop-100,stop] or
                stop<result.get('minimum_stop_time_s',start+20) or
                (stop<start+200 and not (check['periodic_steady_state'] and target['precision_pass'])) or
                sha256(source)!=result['origin_measured_window_sha256'] or not c['temperature_unchanged'] or
                any(row['start_time_s']!=start+20*k or row['stop_time_s']!=start+20*(k+1) for k,row in enumerate(rows))):
            raise ValueError('Incomplete or changed same-Tc target-precision continuation')
        origin=read(source)
        if (origin['window_s']!=[start-100,start] or len(origin['packets'])!=5 or
                not origin['fixed_Tc_candidate'] or origin['candidate_Tc_K']!=result['candidate_Tc_K']):
            raise ValueError('Cannot borrow a different-temperature or incomplete source window')
        prior=[]
        for k,p in enumerate(origin['packets']):
            if p['window_s']!=[start-100+20*k,start-80+20*k]:raise ValueError('Origin gap')
            prior.append(dict(packet_root=p['packet_root'],start_time_s=p['window_s'][0],stop_time_s=p['window_s'][1]))
        all_rows=prior+rows
        return stop-100,stop,all_rows[-5:],Path(all_rows[-6]['packet_root'])
    candidate=result['schema']=='heatdrive_ecc_runtime_Tc_candidate_collection_v1'
    if candidate:
        t=result['boundary_trial'];check=result['latest_periodicity']
        validate_trial(t)
        if (not result['pass'] or result['error_message'] or result['source_state_edited'] or result['partial_state_restore_used'] or
                not 6<=len(rows)<=10 or stop-start!=20*len(rows) or stop>2000 or
                start!=t['transition_time_s'] or result['planned_collection_window_s']!=[start,start+200] or
                t['minimum_transition_cycles']!=12 or result['candidate_Tc_K']!=t['candidate_Tc_K'] or
                stop!=10*result['total_cycles'] or check['window_s']!=[stop-100,stop] or
                check['physical_tolerances_changed'] or (stop<start+200 and not check['periodic_steady_state']) or
                not result['transition_excluded_from_current_window'] or
                any(row['start_time_s']!=start+20*k or row['stop_time_s']!=start+20*(k+1) for k,row in enumerate(rows))):
            raise ValueError('A fixed-Tc window needs at least twelve complete post-transition cycles at that Tc')
        if t['schema']=='heatdrive_ecc_runtime_Tc_intervention_v2':
            precision=result['latest_target_stability']
            if (result.get('target_precision_required') is not True or precision['window_s']!=[stop-100,stop] or
                    (stop<start+200 and not precision['precision_pass'])):
                raise ValueError('Bounded search must satisfy the declared target precision before early exit')
        return stop-100,stop,rows[-5:],Path(rows[-6]['packet_root'])
    adaptive=result.get('stop_on_public_periodicity',False)
    if (result['schema']!='heatdrive_ecc_runtime_boundary_transient_collection_v1' or
            not result['pass'] or result['error_message'] or result['source_state_edited'] or result['partial_state_restore_used'] or
            start<20 or stop>2000 or stop!=10*result['total_cycles'] or
            not 1<=len(rows)<=10 or stop-start!=20*len(rows) or
            any(row['start_time_s']!=start+20*k or row['stop_time_s']!=start+20*(k+1) for k,row in enumerate(rows))):
        raise ValueError('Require ten naturally completed same-family two-cycle packets')
    if adaptive:
        planned=result['planned_collection_window_s']
        check=result['latest_periodicity']
        source=Path(result['origin_measured_window_path'])
        if (planned!=[start,start+200] or stop>planned[1] or
                check['window_s']!=[stop-100,stop] or check['physical_tolerances_changed'] or
                (stop<planned[1] and not check['periodic_steady_state']) or
                sha256(source)!=result['origin_measured_window_sha256']):
            raise ValueError('Changed rolling-window origin or unjustified early stop')
        origin=read(source)
        if origin['window_s']!=[start-100,start] or not origin['runtime_family'] or len(origin['packets'])!=5:
            raise ValueError('Require the sealed same-runtime-family origin window')
        prior=[]
        for k,p in enumerate(origin['packets']):
            if p['window_s']!=[start-100+20*k,start-80+20*k]:
                raise ValueError('Origin packets cannot have gaps or overlap')
            prior.append(dict(packet_root=p['packet_root'],start_time_s=p['window_s'][0],stop_time_s=p['window_s'][1]))
        rows=prior+rows
    elif stop-start!=200 or len(rows)!=10:
        raise ValueError('The fixed warmup still requires all twenty cycles')
    return stop-100,stop,rows[-5:],Path(rows[-6]['packet_root'])


def analyze(collection, reference, review, output):
    if output.exists():
        raise FileExistsError('Never replace a measured-window analysis')
    result = read(collection/'collection_result.json')
    continuing=result['schema']=='heatdrive_ecc_runtime_Tc_continuation_collection_v1'
    candidate=continuing or result['schema']=='heatdrive_ecc_runtime_Tc_candidate_collection_v1'
    runtime=candidate or result['schema']=='heatdrive_ecc_runtime_boundary_transient_collection_v1'
    lineage=[]
    pointer = read(collection/'initial_recording_contract.json')
    if runtime:
        start,stop,selected,previous=runtime_window(result)
        expected_role=('runtime_boundary_Tc_continuation' if continuing else
                       'runtime_boundary_Tc_candidate' if candidate else 'runtime_boundary_transient')
        expected_Tc=result['candidate_Tc_K'] if candidate else 276.95
        if (sha256(collection/'initial_recording_contract.json')!=result['origin_snapshot_sha256'] or
                sha256(collection/'initial_prepared_recipe.json')!=result['origin_recipe_sha256']):
            raise ValueError('Changed runtime source or construction recipe')
        parent=pointer['operating_point_sha256']
        if sha256(Path(pointer['operating_point_path']))!=parent:raise ValueError('Changed runtime origin OP')
        for row in result['completed_packets']:
            root=Path(row['packet_root']);m=read(root/'packet_manifest.json');g=read(root/'packet_gate.json')
            validate_gate(g);boundary=read(root/'boundary_comparison.json')
            if (m['packet_role']!=expected_role or m['prescribed_Tc_K']!=expected_Tc or
                    m['temperature_configurability']!='runtime' or m['parent_complete_OP_sha256']!=parent or
                    m['window_s']!=[row['start_time_s'],row['stop_time_s']] or
                    g['input_sha256']['manifest']!=sha256(root/'packet_manifest.json') or
                    sha256(root/'comparison_only_complete_op.mat')!=m['complete_OP_sha256'] or
                    row['operating_point_sha256']!=m['complete_OP_sha256'] or
                    not boundary['pass'] or not boundary['retained_memories_bitwise_equal']):
                raise ValueError('Runtime recording lineage changed')
            if candidate and m['boundary_trial']!=result['boundary_trial']:
                raise ValueError('The candidate parameter intervention changed mid-collection')
            if continuing and m['continuation']!=result['continuation']:
                raise ValueError('The same-Tc continuation source changed')
            parent=m['complete_OP_sha256']
            lineage.append(dict(packet_root=str(root),manifest_sha256=sha256(root/'packet_manifest.json'),
                gate_sha256=sha256(root/'packet_gate.json'),boundary_sha256=sha256(root/'boundary_comparison.json'),
                complete_OP_sha256=parent))
        packets=[Path(row['packet_root']) for row in selected]
        reference=packets[0];proof=None
        parent=read(previous/'packet_manifest.json')['complete_OP_sha256']
        if sha256(previous/'comparison_only_complete_op.mat')!=parent:raise ValueError('Window predecessor changed')
    else:
        start,stop=620,720
        if (not result['pass'] or result['total_cycles'] != 72 or result['error_message'] or
            result['source_state_edited'] or result['partial_state_restore_used'] or
            len(result['completed_packets']) != 4):
            raise ValueError('Require the naturally completed C64-C72 collection')
        if reference is None or review is None:raise ValueError('The legacy reference requires its immutable review')
        proof = read(review)
        if (Path(proof['source_packet_root']).resolve() != reference.resolve() or
            not proof['mechanism_pass'] or not proof['reference_comparison_only'] or
            sha256(Path(proof['packet_gate_path'])) != proof['packet_gate_sha256']):
            raise ValueError('Require the sealed numerical reference review')
        packets = [reference]+[Path(row['packet_root']) for row in result['completed_packets']]
        parent = pointer['operating_point_sha256']
    index, balances, boundaries = [], [], []
    public_parts = {name: [] for name in PUBLIC}
    native_parts = {}
    for number, root in enumerate(packets):
        manifest_path = root/'packet_manifest.json'
        manifest = read(manifest_path)
        begin, end = start+20*number, start+20*(number+1)
        if manifest['window_s'] != [begin, end] or manifest['source_state_edited']:
            raise ValueError('Missing, overlapping or changed measured window')
        for entry in manifest['input_files']:
            path = (root/entry['path']).resolve()
            if not path.is_relative_to(root.resolve()) or sha256(path) != entry['sha256']:
                raise ValueError('Changed packet evidence: '+str(path))
        if sha256(root/'comparison_only_complete_op.mat') != manifest['complete_OP_sha256']:
            raise ValueError('Complete endpoint changed')
        gate_path = Path(proof['packet_gate_path']) if number == 0 and not runtime else root/'packet_gate.json'
        gate = read(gate_path)
        validate_gate(gate)
        if gate['input_sha256']['manifest'] != sha256(manifest_path):
            raise ValueError('Gate does not bind the actual manifest')
        if number or runtime:
            boundary = read(root/'boundary_comparison.json')
            if (manifest['parent_complete_OP_sha256'] != parent or not boundary['pass'] or
                    not boundary['retained_memories_bitwise_equal'] or boundary['retained_memory_count'] != 4 or
                    boundary['candidate_observation_sha256'] != sha256(root/'native/observations.mat') or
                    boundary['candidate_state_sha256'] != sha256(root/'observed_states.mat')):
                raise ValueError('Broken complete-state or measured boundary chain')
            boundaries.append(dict(window_s=[begin, end], retained_memories_bitwise_equal=True,
                                   comparison_sha256=sha256(root/'boundary_comparison.json')))
            parent = manifest['complete_OP_sha256']
        balances.append(dict(window_s=[begin, end], **gate['modeled_energy_balance']))
        raw, configuration = root/'native/observations.mat', root/'native/configuration.mat'
        index.append(dict(packet_root=str(root), observation_path=str(raw), observation_sha256=sha256(raw),
            configuration_path=str(configuration), configuration_sha256=sha256(configuration), window_s=[begin, end]))
        with h5py.File(raw) as f:
            for name in PUBLIC:
                row = f['signals/'+name]
                ix = window_indices(row['time_s'][:], begin, end)
                public_parts[name].append((row['time_s'][:].ravel()[ix], row['values'][:, ix]))
            rows = named_rows(f, f['native'])
            selected = {key: row for key, row in rows.items() if key[1] in ('T', 'T_I', 'stored_mass', 'stored_energy') or
                        (key[0].endswith('/ColdSinkPipe') and key[1] in ('Phi_A', 'Phi_B', 'Q_H', 'rho_I', 'u_I'))}
            if number and set(selected) != set(native_parts):
                raise ValueError('Native identities changed')
            for key, row in selected.items():
                ix = window_indices(row['time_s'][:], begin, end)
                unit = ('K' if key[1] in ('T', 'T_I') else 'kg' if key[1] == 'stored_mass' else
                        'J' if key[1] == 'stored_energy' else 'kg/m^3' if key[1] == 'rho_I' else
                        'J/kg' if key[1] == 'u_I' else 'W')
                values = scalar_series(row, unit)[ix][None, :]
                native_parts.setdefault(key, []).append((row['time_s'][:].ravel()[ix], values))
    public = {key: join_measured(parts) for key, parts in public_parts.items()}
    native = {key: join_measured(parts) for key, parts in native_parts.items()}
    time = public[PUBLIC[0]][0]
    if time.size != 100001 or abs(time[0]-start) > 1e-9 or abs(time[-1]-stop) > 1e-9:
        raise ValueError('The actual ten-cycle window is incomplete')
    clock_difference_max_s = 0.
    for clock, _ in list(public.values())+list(native.values()):
        aligned_window_indices(clock, time)
        clock_difference_max_s = max(clock_difference_max_s, float(abs(time-clock).max()))
    with h5py.File(index[0]['configuration_path']) as cfg:
        o = cfg['options']
        cp = float(o['system/cp_fluid_J_per_kgK'][0, 0])
        mass = float(o['equilibrium/m_r_kg'][0, 0])
        stage = stage_ids(time, float(o['cycle_count'][0, 0]), o['schedule/stage_start_s'][:].ravel(),
                          o['schedule/stage_end_s'][:].ravel())
    signal = lambda key: public[key][1].sum(axis=0)
    eq10 = abs(signal('mass_flow_v4_hot_inlet_kgps'))*(stage == 4)*cp*(
        signal('cold_hx_inlet_fluid_temp_out')-signal('cold_hx_outlet_fluid_temp_out'))
    lift = signal('hot_hx_inlet_fluid_temp_out')-signal('cold_hx_inlet_fluid_temp_out')
    sensor = signal('Qdot_cold_sink_mass_to_hx_pipe_W')
    source = np.maximum(signal('shex_source_heat_flow_W'), 0)
    def performance(mask):
        clock = time[mask]
        mean = lambda values: integrals(clock, values[mask])['trapz_J']/(clock[-1]-clock[0])
        q, hot = mean(eq10), mean(source)
        return dict(window_s=[float(clock[0]), float(clock[-1])], temperature_lift_eq9_K=mean(lift),
            cooling_power_eq10_W=q, SCP_W_per_g=q/(1000*mass), CHEX_sensor_mean_W=mean(sensor),
            positive_SHEX_heat_mean_W=hot, heat_driven_COP=q/hot if hot > 0 else None)
    temperatures, inventories = [], []
    for (block, variable), (_, values) in native.items():
        if variable in ('T', 'T_I', 'stored_mass', 'stored_energy'):
            record = dict(block_path=block, variable=variable,
                unit='K' if variable in ('T', 'T_I') else 'kg' if variable == 'stored_mass' else 'J',
                **native_statistics(time, values))
            (temperatures if variable in ('T', 'T_I') else inventories).append(record)
    if len(temperatures) != 119 or len(inventories) != 12:
        raise ValueError('Missing modeled temperature or explicit inventory states')
    pipe = next(block for block, variable in native if block.endswith('/ColdSinkPipe'))
    n = lambda key: native[pipe, key][1][0]
    # Obtain the actual pipe geometry from the same inventory metadata, not an assumed volume.
    metadata = read(reference/'native/inventory_metadata.json')
    storage, pipe_nominal_mass = native_pipe_inventory(metadata, read(reference/'native/tl_connectivity.json'), pipe, n('u_I'))
    decomposition = reconciliation(time, stage == 4, eq10, n('Phi_A')+n('Phi_B'), n('Q_H'), sensor,
                                   storage[-1]-storage[0])
    output.mkdir(parents=True)
    record = dict(schema='heatdrive_ecc_measured_ten_cycle_collection_v1', window_s=[start, stop],
        sample_count=time.size, total_cycles=result['total_cycles'], packets=index, boundaries=boundaries, packet_balances=balances,
        runtime_family=runtime,collection_lineage=lineage,
        fixed_Tc_candidate=candidate,candidate_Tc_K=result['candidate_Tc_K'] if candidate else None,
        maximum_actual_clock_difference_s=clock_difference_max_s, clock_alignment='Existing 16-ULP ordinal grid check; no interpolation',
        collection_result_path=str(collection/'collection_result.json'), collection_result_sha256=sha256(collection/'collection_result.json'),
        reference_review_path=str(review) if review else '', reference_review_sha256=sha256(review) if review else '',
        performance=performance(np.ones(time.size, dtype=bool)),
        cycles=[dict(cycle=c+int(start/10)+1, **performance((time >= start+10*c-1e-9)&(time <= start+10*(c+1)+1e-9))) for c in range(10)],
        active_SE_mass_kg=mass, fluid_cp_J_per_kgK=cp, native_temperatures=temperatures, native_explicit_inventories=inventories,
        cooling_boundary_reconciliation=decomposition,
        cold_pipe_storage_basis='Native fixed nominal mass times u_I; transport density is not storage mass',
        cold_pipe_nominal_mass_kg=pipe_nominal_mass,
        native_inventory_tolerance_invented=False, solver_energy_quadrature='BE_J', performance_quadrature='trapz_J',
        simulation_executed=False, operating_point_loaded=False, source_state_edited=False,
        production_recovery_allowed=False, outer_solve_eligible=False, table4_reproduction_claim=False)
    path = output/'measured_window.json'
    path.write_text(json.dumps(record, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    return dict(output=str(path), performance=record['performance'], native_temperature_count=len(temperatures),
                explicit_inventory_count=len(inventories))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('collection', 'output'):
        parser.add_argument('--'+name, required=True, type=Path)
    for name in ('reference','review'):parser.add_argument('--'+name,type=Path)
    args = parser.parse_args()
    print(json.dumps(analyze(**vars(args)), indent=2))
