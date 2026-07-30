function summary = Summarize_HeatDriveECC_EighthRound_Output(physical, options)
% Summarize only the physical Simscape and coupled constitutive logs.

    required_authority = 'physical_simscape_to_workspace_logs';
    if ~isstruct(physical) || ~isfield(physical, 'authority') || ...
            ~strcmp(physical.authority, required_authority)
        error('Summarize:EighthRound:NonPhysicalAuthority', ...
            'Summary input must be the physical Simscape log structure.');
    end

    t = physical.time_s(:);
    cycle = physical.cycle_index(:);
    stage = physical.stage_id(:);
    ncycles = options.cycle_count;
    sma_mean = mean(physical.SMA_T_21_K, 2);
    se_mean = mean(physical.SE_T_21_K, 2);
    xA_mean = mean(physical.xM_SMA_21, 2);
    xR_mean = mean(physical.xM_SE_21, 2);
    sigmaA_mean = mean(physical.sigma_SMA_21_Pa, 2);
    sigmaR_mean = mean(physical.sigma_SE_21_Pa, 2);

    summary = struct();
    summary.authority = physical.authority;
    summary.legacy_surrogate_used_for_results = false;
    summary.sim_call_count = physical.sim_call_count;
    summary.walltime_s = physical.walltime_s;
    summary.samples = numel(t);
    summary.stage_sample_min = min_stage_samples(stage, cycle, ncycles);
    summary.probe_count = numel(physical.probe_names);
    summary.all_required_finite = required_fields_finite(physical);
    summary.max_SMA_node_spread_K = max(row_range(physical.SMA_T_21_K));
    summary.max_SE_node_spread_K = max(row_range(physical.SE_T_21_K));
    summary.min_temperature_K = min([physical.SMA_T_21_K(:); ...
        physical.SE_T_21_K(:); physical.SHEX_T_K(:); ...
        physical.HHEX_T_K(:); physical.CHEX_T_K(:)]);
    summary.max_temperature_K = max([physical.SMA_T_21_K(:); ...
        physical.SE_T_21_K(:); physical.SHEX_T_K(:); ...
        physical.HHEX_T_K(:); physical.CHEX_T_K(:)]);
    summary.max_abs_sigma_SMA_Pa = max(abs(physical.sigma_SMA_21_Pa(:)));
    summary.max_abs_sigma_SE_Pa = max(abs(physical.sigma_SE_21_Pa(:)));
    summary.max_abs_flow_kgps = max(abs([physical.mdot_SMA_kgps; ...
        physical.mdot_SE_stage2_in_kgps; physical.mdot_SE_stage2_out_kgps; ...
        physical.mdot_SE_stage4_in_kgps; physical.mdot_SE_stage4_out_kgps]));
    summary.max_cycle_boundary_SMA_state_jump = ...
        max_boundary_jump(t, physical.xM_SMA_21, options.schedule.tau_cycle_s, ncycles);
    summary.max_cycle_boundary_SE_state_jump = ...
        max_boundary_jump(t, physical.xM_SE_21, options.schedule.tau_cycle_s, ncycles);
    summary.max_cycle_boundary_SMA_temperature_jump_K = ...
        max_boundary_jump(t, physical.SMA_T_21_K, options.schedule.tau_cycle_s, ncycles);
    summary.max_cycle_boundary_SE_temperature_jump_K = ...
        max_boundary_jump(t, physical.SE_T_21_K, options.schedule.tau_cycle_s, ncycles);

    summary.cycle = repmat(empty_cycle(), ncycles, 1);
    for c = 1:ncycles
        idx = cycle == c;
        idx1 = idx & stage == 1;
        idx2 = idx & stage == 2;
        idx3 = idx & stage == 3;
        idx4 = idx & stage == 4;
        item = empty_cycle();
        item.cycle_index = c;
        item.SMA_start_K = first_value(sma_mean, idx);
        item.SMA_end_K = last_value(sma_mean, idx);
        item.SMA_min_K = min(sma_mean(idx));
        item.SMA_max_K = max(sma_mean(idx));
        item.SE_start_K = first_value(se_mean, idx);
        item.SE_end_K = last_value(se_mean, idx);
        item.SE_min_K = min(se_mean(idx));
        item.SE_max_K = max(se_mean(idx));
        item.SHEX_start_K = first_value(physical.SHEX_T_K, idx);
        item.SHEX_end_K = last_value(physical.SHEX_T_K, idx);
        item.HHEX_start_K = first_value(physical.HHEX_T_K, idx);
        item.HHEX_end_K = last_value(physical.HHEX_T_K, idx);
        item.CHEX_start_K = first_value(physical.CHEX_T_K, idx);
        item.CHEX_end_K = last_value(physical.CHEX_T_K, idx);
        item.delta_SHEX_K = item.SHEX_end_K - item.SHEX_start_K;
        item.delta_HHEX_K = item.HHEX_end_K - item.HHEX_start_K;
        item.delta_CHEX_K = item.CHEX_end_K - item.CHEX_start_K;
        item.SHEX_storage_J = options.system.shex_sink_C_J_per_K * item.delta_SHEX_K;
        item.HHEX_storage_J = options.system.hot_sink_C_J_per_K * item.delta_HHEX_K;
        item.CHEX_storage_J = options.system.cold_sink_C_J_per_K * item.delta_CHEX_K;
        item.xM_SMA_min = min(xA_mean(idx));
        item.xM_SMA_max = max(xA_mean(idx));
        item.xM_SE_min = min(xR_mean(idx));
        item.xM_SE_max = max(xR_mean(idx));
        item.xM_SMA_swing = item.xM_SMA_max - item.xM_SMA_min;
        item.xM_SE_swing = item.xM_SE_max - item.xM_SE_min;
        item.sigma_SMA_max_MPa = max(abs(sigmaA_mean(idx))) / 1.0e6;
        item.sigma_SE_max_MPa = max(abs(sigmaR_mean(idx))) / 1.0e6;
        item.Q_constitutive_SMA_J = integrate_signal(t, ...
            sum(physical.Q_SMA_constitutive_21_W, 2), idx);
        item.Q_constitutive_SE_J = integrate_signal(t, ...
            sum(physical.Q_SE_constitutive_21_W, 2), idx);
        item.pump_work_SMA_J = integrate_signal(t, ...
            physical.pump_power_SMA_W, idx);
        item.pump_work_SE_J = integrate_signal(t, ...
            physical.pump_power_SE_W, idx);
        item.stage1_SMA_transported_mass_kg = integrate_signal(t, ...
            abs(physical.mdot_SMA_kgps), idx1);
        item.stage2_SE_in_transported_mass_kg = integrate_signal(t, ...
            abs(physical.mdot_SE_stage2_in_kgps), idx2);
        item.stage2_SE_out_transported_mass_kg = integrate_signal(t, ...
            abs(physical.mdot_SE_stage2_out_kgps), idx2);
        item.stage3_SMA_transported_mass_kg = integrate_signal(t, ...
            abs(physical.mdot_SMA_kgps), idx3);
        item.stage4_SE_in_transported_mass_kg = integrate_signal(t, ...
            abs(physical.mdot_SE_stage4_in_kgps), idx4);
        item.stage4_SE_out_transported_mass_kg = integrate_signal(t, ...
            abs(physical.mdot_SE_stage4_out_kgps), idx4);
        item.stage1_SMA_mean_abs_flow_kgps = masked_mean_abs( ...
            physical.mdot_SMA_kgps, idx1);
        item.stage2_SE_mean_abs_flow_kgps = masked_mean_abs( ...
            physical.mdot_SE_stage2_in_kgps, idx2);
        item.stage3_SMA_mean_abs_flow_kgps = masked_mean_abs( ...
            physical.mdot_SMA_kgps, idx3);
        item.stage4_SE_mean_abs_flow_kgps = masked_mean_abs( ...
            physical.mdot_SE_stage4_in_kgps, idx4);
        item.inactive_SMA_mean_abs_flow_kgps = masked_mean_abs( ...
            physical.mdot_SMA_kgps, idx2 | idx4);
        item.inactive_SE_mean_abs_flow_kgps = mean(abs([ ...
            physical.mdot_SE_stage2_in_kgps(idx1 | idx3); ...
            physical.mdot_SE_stage4_in_kgps(idx1 | idx3)]));
        summary.cycle(c) = item;
    end

    summary.anchor = struct();
    summary.anchor.paper = [ ...
        'Qian et al., Energy 182 (2019), Table 2/Table 4/Fig. 3'];
    summary.anchor.material = options.material.SMA.name;
    summary.anchor.net_SMA_volume_m3 = options.geometry.net_sma_volume_m3;
    summary.anchor.volume_scale = options.geometry.volume_scale_vs_previous;
    summary.anchor.nominal_SMA_stress_MPa = ...
        options.material.SMA.nominal_stress_Pa / 1.0e6;
    summary.anchor.Hcur_nominal = options.material.SMA.Hcur_nominal;
    summary.anchor.Delta_s0_J_per_kgK = options.material.SMA.Delta_s0_J_per_kgK;
    summary.anchor.Delta_h_J_per_kg = options.material.SMA.Delta_h_J_per_kg;
    summary.anchor.thermal_cycle_min_K = options.material.SMA.thermal_cycle_min_K;
    summary.anchor.thermal_cycle_max_K = options.material.SMA.thermal_cycle_max_K;
    summary.quantitative_literature_reproduction_evaluated = false;
    summary.quantitative_literature_reproduction_reason = [ ...
        'A three-cycle transient checks the coupled mechanism only. Qian ', ...
        'Table 4 endpoints require periodic steady state, separate no-load ', ...
        'and zero-lift cases, and a dual water/glycol-water fluid topology.'];
end

function tf = required_fields_finite(p)
    names = {'time_s','SMA_T_21_K','SE_T_21_K','SHEX_T_K','HHEX_T_K', ...
        'CHEX_T_K','xM_SMA_21','xM_SE_21','sigma_SMA_21_Pa', ...
        'sigma_SE_21_Pa','Q_SMA_constitutive_21_W', ...
        'Q_SE_constitutive_21_W','mdot_SMA_kgps', ...
        'mdot_SE_stage2_in_kgps','mdot_SE_stage4_in_kgps', ...
        'pressure_command_SMA_MPa','pressure_command_SE_MPa'};
    tf = true;
    for idx = 1:numel(names)
        value = p.(names{idx});
        tf = tf && all(isfinite(value(:)));
    end
end

function value = integrate_signal(t, x, mask)
    t_local = t(mask);
    x_local = x(mask);
    if numel(t_local) < 2
        value = 0.0;
    else
        value = trapz(t_local, x_local);
    end
end

function value = masked_mean_abs(x, mask)
    if any(mask)
        value = mean(abs(x(mask)));
    else
        value = NaN;
    end
end

function value = first_value(x, mask)
    indices = find(mask, 1, 'first');
    value = x(indices);
end

function value = last_value(x, mask)
    indices = find(mask, 1, 'last');
    value = x(indices);
end

function spread = row_range(values)
    spread = max(values, [], 2) - min(values, [], 2);
end

function count = min_stage_samples(stage, cycle, ncycles)
    counts = zeros(ncycles, 4);
    for c = 1:ncycles
        for s = 1:4
            counts(c, s) = nnz(cycle == c & stage == s);
        end
    end
    count = min(counts(:));
end

function jump = max_boundary_jump(t, values, tau, ncycles)
    jump = 0.0;
    for c = 1:(ncycles - 1)
        boundary = c * tau;
        before = find(t < boundary, 1, 'last');
        after = find(t >= boundary, 1, 'first');
        if ~isempty(before) && ~isempty(after)
            jump = max(jump, max(abs(values(after, :) - values(before, :))));
        end
    end
end

function item = empty_cycle()
    item = struct( ...
        'cycle_index', 0, ...
        'SMA_start_K', NaN, 'SMA_end_K', NaN, ...
        'SMA_min_K', NaN, 'SMA_max_K', NaN, ...
        'SE_start_K', NaN, 'SE_end_K', NaN, ...
        'SE_min_K', NaN, 'SE_max_K', NaN, ...
        'SHEX_start_K', NaN, 'SHEX_end_K', NaN, ...
        'HHEX_start_K', NaN, 'HHEX_end_K', NaN, ...
        'CHEX_start_K', NaN, 'CHEX_end_K', NaN, ...
        'delta_SHEX_K', NaN, 'delta_HHEX_K', NaN, 'delta_CHEX_K', NaN, ...
        'SHEX_storage_J', NaN, 'HHEX_storage_J', NaN, 'CHEX_storage_J', NaN, ...
        'xM_SMA_min', NaN, 'xM_SMA_max', NaN, 'xM_SMA_swing', NaN, ...
        'xM_SE_min', NaN, 'xM_SE_max', NaN, 'xM_SE_swing', NaN, ...
        'sigma_SMA_max_MPa', NaN, 'sigma_SE_max_MPa', NaN, ...
        'Q_constitutive_SMA_J', NaN, 'Q_constitutive_SE_J', NaN, ...
        'pump_work_SMA_J', NaN, 'pump_work_SE_J', NaN, ...
        'stage1_SMA_transported_mass_kg', NaN, ...
        'stage2_SE_in_transported_mass_kg', NaN, ...
        'stage2_SE_out_transported_mass_kg', NaN, ...
        'stage3_SMA_transported_mass_kg', NaN, ...
        'stage4_SE_in_transported_mass_kg', NaN, ...
        'stage4_SE_out_transported_mass_kg', NaN, ...
        'stage1_SMA_mean_abs_flow_kgps', NaN, ...
        'stage2_SE_mean_abs_flow_kgps', NaN, ...
        'stage3_SMA_mean_abs_flow_kgps', NaN, ...
        'stage4_SE_mean_abs_flow_kgps', NaN, ...
        'inactive_SMA_mean_abs_flow_kgps', NaN, ...
        'inactive_SE_mean_abs_flow_kgps', NaN);
end
