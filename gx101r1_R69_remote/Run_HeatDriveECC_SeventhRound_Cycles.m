function result = Run_HeatDriveECC_SeventhRound_Cycles(overrides)
% Run seventh-round four-stage heat-driven SMA/SE ECC cycles.
%
% MATLAB coordinates parameters, integration, audit tables, and plots. The
% physical updates come from the Eq.6/Eq.7 constitutive compatibility solver
% and finite-volume four-branch transport equations.

    if nargin < 1
        overrides = struct();
    end
    options = Build_HeatDriveECC_SeventhRound_Defaults(overrides);
    options = apply_cycle_ready_constitutive(options, overrides);
    output_dir = fullfile(options.outputs_dir, ...
        sprintf('cycles_%d', options.cycle_count));
    if ~isfolder(output_dir)
        mkdir(output_dir);
    end

    roles = Build_HeatDriveECC_SeventhRound_BranchRoles(options);
    branch_states = initialize_branches(roles, options);
    state = initialize_cycle_state(options);
    capacities = solid_capacities(options);

    total_samples = options.cycle_count * 4 * options.validation.cycle_samples_per_stage;
    log = preallocate_log(total_samples, options.node_count);
    sample_idx = 0;
    stage_summaries = repmat(empty_stage_summary(), options.cycle_count * 4, 1);
    stage_row = 0;

    for cycle_idx = 1:options.cycle_count
        for stage_id = 1:4
            stage_row = stage_row + 1;
            stage_start_idx = sample_idx + 1;
            duration_s = options.schedule.stage_durations_s(stage_id);
            samples_per_stage = options.validation.cycle_samples_per_stage;
            dt_s = duration_s / max(samples_per_stage - 1, 1);
            stage_accum = empty_stage_accum();
            for local_idx = 1:samples_per_stage
                if local_idx > 1
                    [state, branch_states, step_audit] = advance_one_step( ...
                        state, branch_states, roles, stage_id, dt_s, options, capacities);
                    stage_accum = accumulate_stage(stage_accum, step_audit, dt_s);
                else
                    step_audit = zero_step_audit(roles);
                    [state, mech_audit] = HeatDriveECC_ConstitutiveCompatibilityStep( ...
                        state, options, 0.0, stage_id);
                    step_audit.mechanical = mech_audit;
                end
                sample_idx = sample_idx + 1;
                elapsed_s = (local_idx - 1) * dt_s;
                log = write_log_sample(log, sample_idx, state, step_audit, ...
                    cycle_idx, stage_id, elapsed_s, roles);
            end
            stage_end_idx = sample_idx;
            stage_summaries(stage_row) = summarize_stage(log, stage_start_idx, ...
                stage_end_idx, stage_accum, cycle_idx, stage_id, options, capacities);
        end
    end

    log = trim_log(log, sample_idx);
    cycle_summaries = summarize_cycles(stage_summaries, options.cycle_count);
    checks = build_checks(log, stage_summaries, cycle_summaries, options);

    trace_csv = fullfile(output_dir, 'seventh_round_cycle_trace.csv');
    stage_csv = fullfile(output_dir, 'seventh_round_stage_energy.csv');
    cycle_csv = fullfile(output_dir, 'seventh_round_cycle_energy.csv');
    write_trace_csv(log, trace_csv);
    writetable(struct2table(stage_summaries), stage_csv);
    writetable(struct2table(cycle_summaries), cycle_csv);
    plot_paths = write_cycle_plots(log, stage_summaries, output_dir);

    result = struct();
    result.schema_version = 'heatdrive_ecc_seventh_round_cycles_v1';
    result.output_dir = output_dir;
    result.options = options;
    result.trace = log;
    result.stage_summaries = stage_summaries;
    result.cycle_summaries = cycle_summaries;
    result.checks = checks;
    result.passed = all(struct2array(checks));
    result.trace_csv = trace_csv;
    result.stage_csv = stage_csv;
    result.cycle_csv = cycle_csv;
    result.plot_paths = plot_paths;

    summary = rmfield(result, {'options','trace'});
    write_json(fullfile(output_dir, 'seventh_round_cycle_summary.json'), summary);
    save(fullfile(output_dir, 'seventh_round_cycle_result.mat'), 'result', '-v7.3');
end

function options = apply_cycle_ready_constitutive(options, overrides)
    if isstruct(overrides) && isfield(overrides, 'constitutive')
        return;
    end
    tuned = struct( ...
        'rate_a_to_A_1_per_s', 60.0, ...
        'rate_a_to_M_1_per_s', 220.0, ...
        'rate_r_load_1_per_s', 160.0, ...
        'rate_r_unload_1_per_s', 400.0, ...
        'se_load_hardening_Pa', 0.0, ...
        'se_unload_hysteresis_Pa', -100.0e6, ...
        'max_rate_1_per_s', 1000.0);
    options.constitutive = merge_structs(options.constitutive, tuned);
end

function state = initialize_cycle_state(options)
    N = options.node_count;
    state = struct();
    state.time_s = 0.0;
    state.stage_id = 1;
    state.Ta_51 = options.system.T0_K * ones(N, 1);
    state.Tr_51 = options.system.Tc_K * ones(N, 1);
    state.xM_a_51 = ones(N, 1);
    state.xM_r_51 = zeros(N, 1);
end

function branch_states = initialize_branches(roles, options)
    branch_states = struct();
    for idx = 1:numel(roles)
        key = matlab.lang.makeValidName(roles(idx).name);
        branch_states.(key) = Initialize_HeatDriveECC_FiniteVolumeBranchState( ...
            roles(idx), options);
    end
end

function capacities = solid_capacities(options)
    g = options.geometry;
    sma = options.material.SMA;
    se = options.material.SE;
    capacities = struct();
    capacities.Ca_J_per_K = sma.rho_kg_per_m3 * g.L_a_m * g.S_a_m2 * ...
        sma.cp_J_per_kgK;
    capacities.Cr_J_per_K = se.rho_kg_per_m3 * g.L_r_m * g.S_r_m2 * ...
        se.cp_J_per_kgK;
end

function [state, branch_states, audit] = advance_one_step( ...
        state, branch_states, roles, stage_id, dt_s, options, capacities)
    audit = zero_step_audit(roles);
    t0 = state.time_s;
    role = roles([roles.active_stage] == stage_id);
    key = matlab.lang.makeValidName(role.name);

    if strcmp(role.solid, 'SMA')
        solid_T = mean(state.Ta_51);
    else
        solid_T = mean(state.Tr_51);
    end
    [branch_states.(key), branch_audit] = HeatDriveECC_FiniteVolumeBranchStep( ...
        branch_states.(key), role, solid_T, dt_s, options, true);
    audit.branches.(key) = branch_audit;

    if strcmp(role.solid, 'SMA')
        state.Ta_51 = state.Ta_51 + ...
            branch_audit.Q_to_solid_W * dt_s / capacities.Ca_J_per_K;
        [state, mech_audit] = HeatDriveECC_ConstitutiveCompatibilityStep( ...
            state, options, dt_s, stage_id);
        state.Ta_51 = state.Ta_51 - ...
            (mech_audit.latentA_J + mech_audit.mechanicalA_J) / capacities.Ca_J_per_K;
        [state, refreshed] = HeatDriveECC_ConstitutiveCompatibilityStep( ...
            state, options, 0.0, stage_id);
        audit.mechanical = merge_structs(refreshed, struct( ...
            'latentA_J', mech_audit.latentA_J, ...
            'latentR_J', mech_audit.latentR_J, ...
            'mechanicalA_J', mech_audit.mechanicalA_J, ...
            'mechanicalR_J', mech_audit.mechanicalR_J, ...
            'se_adiabatic_energy_J', mech_audit.se_adiabatic_energy_J));
    else
        state.Tr_51 = state.Tr_51 + ...
            branch_audit.Q_to_solid_W * dt_s / capacities.Cr_J_per_K;
        [state, mech_audit] = HeatDriveECC_ConstitutiveCompatibilityStep( ...
            state, options, 0.0, stage_id);
        audit.mechanical = mech_audit;
    end

    state.time_s = t0 + dt_s;
    state.stage_id = stage_id;
end

function audit = zero_step_audit(roles)
    audit = struct();
    audit.branches = struct();
    for idx = 1:numel(roles)
        key = matlab.lang.makeValidName(roles(idx).name);
        audit.branches.(key) = struct('branch', string(roles(idx).name), ...
            'm_dot_kgps', 0.0, 'T_boundary_K', roles(idx).boundary_T_K, ...
            'T_in_K', NaN, 'T_out_K', NaN, 'T_fluid_K', NaN, ...
            'Q_boundary_W', 0.0, 'Q_to_solid_W', 0.0, ...
            'storage_delta_W', 0.0, 'energy_residual_W', 0.0);
    end
    audit.mechanical = struct('sigma_a_Pa', NaN, 'sigma_r_Pa', NaN, ...
        'epsilon_a_mean', NaN, 'epsilon_r_mean', NaN, ...
        'eq6_scaled', NaN, 'eq7_scaled', NaN, ...
        'latentA_J', 0.0, 'latentR_J', 0.0, ...
        'mechanicalA_J', 0.0, 'mechanicalR_J', 0.0, ...
        'se_adiabatic_energy_J', 0.0);
end

function accum = empty_stage_accum()
    accum = struct('Q_sma_shex_to_solid_J', 0.0, 'Q_shex_boundary_J', 0.0, ...
        'Q_sma_the_to_solid_J', 0.0, 'Q_the_sma_boundary_J', 0.0, ...
        'Q_se_the_to_solid_J', 0.0, 'Q_the_se_boundary_J', 0.0, ...
        'Q_se_rhe_to_solid_J', 0.0, 'Q_rhe_boundary_J', 0.0, ...
        'branch_storage_delta_J', 0.0, 'branch_residual_J', 0.0, ...
        'latentA_J', 0.0, 'latentR_J', 0.0, ...
        'mechanicalA_J', 0.0, 'mechanicalR_J', 0.0, ...
        'se_adiabatic_energy_J', 0.0);
end

function accum = accumulate_stage(accum, audit, dt_s)
    branch_names = fieldnames(audit.branches);
    for idx = 1:numel(branch_names)
        key = branch_names{idx};
        b = audit.branches.(key);
        accum.branch_storage_delta_J = accum.branch_storage_delta_J + ...
            b.storage_delta_W * dt_s;
        accum.branch_residual_J = accum.branch_residual_J + ...
            b.energy_residual_W * dt_s;
        switch key
            case 'SMA_SHEX'
                accum.Q_sma_shex_to_solid_J = accum.Q_sma_shex_to_solid_J + ...
                    b.Q_to_solid_W * dt_s;
                accum.Q_shex_boundary_J = accum.Q_shex_boundary_J + ...
                    b.Q_boundary_W * dt_s;
            case 'SMA_THE'
                accum.Q_sma_the_to_solid_J = accum.Q_sma_the_to_solid_J + ...
                    b.Q_to_solid_W * dt_s;
                accum.Q_the_sma_boundary_J = accum.Q_the_sma_boundary_J + ...
                    b.Q_boundary_W * dt_s;
            case 'SE_THE'
                accum.Q_se_the_to_solid_J = accum.Q_se_the_to_solid_J + ...
                    b.Q_to_solid_W * dt_s;
                accum.Q_the_se_boundary_J = accum.Q_the_se_boundary_J + ...
                    b.Q_boundary_W * dt_s;
            case 'SE_RHE'
                accum.Q_se_rhe_to_solid_J = accum.Q_se_rhe_to_solid_J + ...
                    b.Q_to_solid_W * dt_s;
                accum.Q_rhe_boundary_J = accum.Q_rhe_boundary_J + ...
                    b.Q_boundary_W * dt_s;
        end
    end
    m = audit.mechanical;
    accum.latentA_J = accum.latentA_J + get_field(m, 'latentA_J', 0.0);
    accum.latentR_J = accum.latentR_J + get_field(m, 'latentR_J', 0.0);
    accum.mechanicalA_J = accum.mechanicalA_J + get_field(m, 'mechanicalA_J', 0.0);
    accum.mechanicalR_J = accum.mechanicalR_J + get_field(m, 'mechanicalR_J', 0.0);
    accum.se_adiabatic_energy_J = accum.se_adiabatic_energy_J + ...
        get_field(m, 'se_adiabatic_energy_J', 0.0);
end

function log = preallocate_log(rows, N)
    log = struct();
    scalar_names = {'time_s','cycle_index','stage_id','stage_elapsed_s', ...
        'Ta_mean_K','Tr_mean_K','Ta_min_K','Ta_max_K','Tr_min_K','Tr_max_K', ...
        'xM_a_mean','xM_r_mean','sigma_a_Pa','sigma_r_Pa', ...
        'epsilon_a_mean','epsilon_r_mean','eq6_scaled','eq7_scaled', ...
        'latentA_W','latentR_W','mechanicalA_W','mechanicalR_W', ...
        'SMA_SHEX_mdot','SMA_THE_mdot','SE_THE_mdot','SE_RHE_mdot', ...
        'SMA_SHEX_Tin_K','SMA_SHEX_Tout_K','SMA_THE_Tin_K','SMA_THE_Tout_K', ...
        'SE_THE_Tin_K','SE_THE_Tout_K','SE_RHE_Tin_K','SE_RHE_Tout_K', ...
        'Q_SMA_SHEX_W','Q_SMA_THE_W','Q_SE_THE_W','Q_SE_RHE_W', ...
        'Q_SHEX_boundary_W','Q_THE_SMA_boundary_W', ...
        'Q_THE_SE_boundary_W','Q_RHE_boundary_W'};
    for idx = 1:numel(scalar_names)
        log.(scalar_names{idx}) = NaN(rows, 1);
    end
    log.Ta_51 = NaN(rows, N);
    log.Tr_51 = NaN(rows, N);
    log.xM_a_51 = NaN(rows, N);
    log.xM_r_51 = NaN(rows, N);
    log.sigma_a_51 = NaN(rows, N);
    log.sigma_r_51 = NaN(rows, N);
    log.node_count = N;
end

function log = write_log_sample(log, idx, state, audit, cycle_idx, stage_id, elapsed_s, roles)
    log.time_s(idx) = state.time_s;
    log.cycle_index(idx) = cycle_idx;
    log.stage_id(idx) = stage_id;
    log.stage_elapsed_s(idx) = elapsed_s;
    log.Ta_mean_K(idx) = mean(state.Ta_51);
    log.Tr_mean_K(idx) = mean(state.Tr_51);
    log.Ta_min_K(idx) = min(state.Ta_51);
    log.Ta_max_K(idx) = max(state.Ta_51);
    log.Tr_min_K(idx) = min(state.Tr_51);
    log.Tr_max_K(idx) = max(state.Tr_51);
    log.xM_a_mean(idx) = mean(state.xM_a_51);
    log.xM_r_mean(idx) = mean(state.xM_r_51);
    log.Ta_51(idx, :) = reshape(state.Ta_51, 1, []);
    log.Tr_51(idx, :) = reshape(state.Tr_51, 1, []);
    log.xM_a_51(idx, :) = reshape(state.xM_a_51, 1, []);
    log.xM_r_51(idx, :) = reshape(state.xM_r_51, 1, []);
    if isfield(state, 'sigma_a_51')
        log.sigma_a_51(idx, :) = reshape(state.sigma_a_51, 1, []);
        log.sigma_r_51(idx, :) = reshape(state.sigma_r_51, 1, []);
    end
    m = audit.mechanical;
    log.sigma_a_Pa(idx) = get_field(m, 'sigma_a_Pa', NaN);
    log.sigma_r_Pa(idx) = get_field(m, 'sigma_r_Pa', NaN);
    log.epsilon_a_mean(idx) = get_field(m, 'epsilon_a_mean', NaN);
    log.epsilon_r_mean(idx) = get_field(m, 'epsilon_r_mean', NaN);
    log.eq6_scaled(idx) = get_field(m, 'eq6_scaled', NaN);
    log.eq7_scaled(idx) = get_field(m, 'eq7_scaled', NaN);
    log.latentA_W(idx) = get_field(m, 'latentA_J', 0.0) / max_step_duration(log, idx);
    log.latentR_W(idx) = get_field(m, 'latentR_J', 0.0) / max_step_duration(log, idx);
    log.mechanicalA_W(idx) = get_field(m, 'mechanicalA_J', 0.0) / max_step_duration(log, idx);
    log.mechanicalR_W(idx) = get_field(m, 'mechanicalR_J', 0.0) / max_step_duration(log, idx);

    for role_idx = 1:numel(roles)
        key = matlab.lang.makeValidName(roles(role_idx).name);
        b = audit.branches.(key);
        switch key
            case 'SMA_SHEX'
                log.SMA_SHEX_mdot(idx) = b.m_dot_kgps;
                log.SMA_SHEX_Tin_K(idx) = b.T_in_K;
                log.SMA_SHEX_Tout_K(idx) = b.T_out_K;
                log.Q_SMA_SHEX_W(idx) = b.Q_to_solid_W;
                log.Q_SHEX_boundary_W(idx) = b.Q_boundary_W;
            case 'SMA_THE'
                log.SMA_THE_mdot(idx) = b.m_dot_kgps;
                log.SMA_THE_Tin_K(idx) = b.T_in_K;
                log.SMA_THE_Tout_K(idx) = b.T_out_K;
                log.Q_SMA_THE_W(idx) = b.Q_to_solid_W;
                log.Q_THE_SMA_boundary_W(idx) = b.Q_boundary_W;
            case 'SE_THE'
                log.SE_THE_mdot(idx) = b.m_dot_kgps;
                log.SE_THE_Tin_K(idx) = b.T_in_K;
                log.SE_THE_Tout_K(idx) = b.T_out_K;
                log.Q_SE_THE_W(idx) = b.Q_to_solid_W;
                log.Q_THE_SE_boundary_W(idx) = b.Q_boundary_W;
            case 'SE_RHE'
                log.SE_RHE_mdot(idx) = b.m_dot_kgps;
                log.SE_RHE_Tin_K(idx) = b.T_in_K;
                log.SE_RHE_Tout_K(idx) = b.T_out_K;
                log.Q_SE_RHE_W(idx) = b.Q_to_solid_W;
                log.Q_RHE_boundary_W(idx) = b.Q_boundary_W;
        end
    end
end

function dt = max_step_duration(log, idx)
    if idx <= 1 || ~isfinite(log.time_s(idx - 1))
        dt = eps;
    else
        dt = max(log.time_s(idx) - log.time_s(idx - 1), eps);
    end
end

function summary = summarize_stage(log, i0, i1, accum, cycle_idx, stage_id, options, capacities)
    summary = empty_stage_summary();
    summary.cycle_index = cycle_idx;
    summary.stage_id = stage_id;
    summary.samples = i1 - i0 + 1;
    summary.time_start_s = log.time_s(i0);
    summary.time_end_s = log.time_s(i1);
    summary.Ta_start_K = log.Ta_mean_K(i0);
    summary.Ta_end_K = log.Ta_mean_K(i1);
    summary.Tr_start_K = log.Tr_mean_K(i0);
    summary.Tr_end_K = log.Tr_mean_K(i1);
    summary.xM_a_start = log.xM_a_mean(i0);
    summary.xM_a_end = log.xM_a_mean(i1);
    summary.xM_r_start = log.xM_r_mean(i0);
    summary.xM_r_end = log.xM_r_mean(i1);
    fields = fieldnames(accum);
    for idx = 1:numel(fields)
        summary.(fields{idx}) = accum.(fields{idx});
    end
    dUa = capacities.Ca_J_per_K * (summary.Ta_end_K - summary.Ta_start_K);
    dUr = capacities.Cr_J_per_K * (summary.Tr_end_K - summary.Tr_start_K);
    summary.SMA_sensible_J = dUa;
    summary.SE_sensible_J = dUr;
    if stage_id == 1
        summary.stage_energy_residual_J = summary.Q_sma_shex_to_solid_J - ...
            dUa - summary.latentA_J - summary.mechanicalA_J;
    elseif stage_id == 2
        summary.stage_energy_residual_J = summary.Q_se_the_to_solid_J - dUr;
    elseif stage_id == 3
        summary.stage_energy_residual_J = summary.Q_sma_the_to_solid_J - ...
            dUa - summary.latentA_J - summary.mechanicalA_J;
    elseif stage_id == 4
        summary.stage_energy_residual_J = summary.Q_se_rhe_to_solid_J - dUr;
    end
    denom = abs(dUa) + abs(dUr) + abs(summary.Q_sma_shex_to_solid_J) + ...
        abs(summary.Q_sma_the_to_solid_J) + abs(summary.Q_se_the_to_solid_J) + ...
        abs(summary.Q_se_rhe_to_solid_J) + abs(summary.latentA_J) + ...
        abs(summary.mechanicalA_J) + 1.0e-9;
    summary.stage_energy_residual_fraction = abs(summary.stage_energy_residual_J) / denom;
    summary.max_abs_eq6_scaled = max(abs(log.eq6_scaled(i0:i1)));
    summary.max_abs_eq7_scaled = max(abs(log.eq7_scaled(i0:i1)));
end

function s = empty_stage_summary()
    s = empty_stage_accum();
    s.cycle_index = 0;
    s.stage_id = 0;
    s.samples = 0;
    s.time_start_s = NaN;
    s.time_end_s = NaN;
    s.Ta_start_K = NaN;
    s.Ta_end_K = NaN;
    s.Tr_start_K = NaN;
    s.Tr_end_K = NaN;
    s.xM_a_start = NaN;
    s.xM_a_end = NaN;
    s.xM_r_start = NaN;
    s.xM_r_end = NaN;
    s.SMA_sensible_J = NaN;
    s.SE_sensible_J = NaN;
    s.stage_energy_residual_J = NaN;
    s.stage_energy_residual_fraction = NaN;
    s.max_abs_eq6_scaled = NaN;
    s.max_abs_eq7_scaled = NaN;
end

function cycles = summarize_cycles(stages, cycle_count)
    cycles = repmat(struct('cycle_index', 0, 'Qh_boundary_J', NaN, ...
        'Qr_boundary_J', NaN, 'THE_reject_J', NaN, ...
        'stage_energy_residual_abs_sum_J', NaN, ...
        'max_stage_energy_residual_fraction', NaN), cycle_count, 1);
    for c = 1:cycle_count
        idx = [stages.cycle_index] == c;
        ss = stages(idx);
        cycles(c).cycle_index = c;
        cycles(c).Qh_boundary_J = sum([ss.Q_shex_boundary_J]);
        cycles(c).Qr_boundary_J = sum([ss.Q_rhe_boundary_J]);
        cycles(c).THE_reject_J = -sum([ss.Q_the_sma_boundary_J] + [ss.Q_the_se_boundary_J]);
        cycles(c).stage_energy_residual_abs_sum_J = sum(abs([ss.stage_energy_residual_J]));
        cycles(c).max_stage_energy_residual_fraction = max([ss.stage_energy_residual_fraction]);
    end
end

function checks = build_checks(log, stages, cycles, options)
    checks = struct();
    checks.all_finite = all(isfinite([log.time_s(:); log.Ta_51(:); log.Tr_51(:); ...
        log.xM_a_51(:); log.xM_r_51(:); log.sigma_a_Pa(:); log.sigma_r_Pa(:)]));
    checks.samples_per_stage = all([stages.samples] >= options.validation.cycle_samples_per_stage);
    checks.eq6 = max(abs(log.eq6_scaled), [], 'omitnan') < options.validation.max_eq6_scaled;
    checks.eq7 = max(abs(log.eq7_scaled), [], 'omitnan') < options.validation.max_eq7_scaled;
    checks.stage1_trend = all(arrayfun(@(s) s.Ta_end_K > s.Ta_start_K && ...
        s.xM_a_end < s.xM_a_start && s.xM_r_end > s.xM_r_start && ...
        s.Q_sma_shex_to_solid_J > 0, stages([stages.stage_id] == 1)));
    checks.stage2_trend = all(arrayfun(@(s) s.Tr_end_K < s.Tr_start_K && ...
        s.Q_se_the_to_solid_J < 0, stages([stages.stage_id] == 2)));
    checks.stage3_trend = all(arrayfun(@(s) s.Ta_end_K < s.Ta_start_K && ...
        s.xM_a_end > s.xM_a_start && s.xM_r_end < s.xM_r_start && ...
        s.Q_sma_the_to_solid_J < 0, stages([stages.stage_id] == 3)));
    checks.stage4_trend = all(arrayfun(@(s) s.Tr_end_K > s.Tr_start_K && ...
        s.Q_se_rhe_to_solid_J > 0, stages([stages.stage_id] == 4)));
    checks.branch_heat_nonzero = all([cycles.Qh_boundary_J] > 0) && ...
        all([cycles.Qr_boundary_J] > 0);
end

function log = trim_log(log, rows)
    names = fieldnames(log);
    for idx = 1:numel(names)
        key = names{idx};
        value = log.(key);
        if isnumeric(value) && size(value, 1) >= rows
            log.(key) = value(1:rows, :);
        end
    end
end

function write_trace_csv(log, path_value)
    scalar_names = fieldnames(log);
    scalar_names = scalar_names(~ismember(scalar_names, ...
        {'Ta_51','Tr_51','xM_a_51','xM_r_51','sigma_a_51','sigma_r_51','node_count'}));
    T = table();
    for idx = 1:numel(scalar_names)
        key = scalar_names{idx};
        T.(key) = log.(key)(:);
    end
    arrays = [log.Ta_51, log.Tr_51, log.xM_a_51, log.xM_r_51, ...
        log.sigma_a_51, log.sigma_r_51];
    names = numbered_names({'Ta','Tr','xM_a','xM_r','sigma_a','sigma_r'}, log.node_count);
    writetable([T array2table(arrays, 'VariableNames', names)], path_value);
end

function names = numbered_names(prefixes, N)
    names = cell(1, numel(prefixes) * N);
    col = 1;
    for p = 1:numel(prefixes)
        for n = 1:N
            names{col} = sprintf('%s_%02d', prefixes{p}, n);
            col = col + 1;
        end
    end
end

function plot_paths = write_cycle_plots(log, stages, output_dir)
    plot_paths = struct();
    plot_paths.temperature = fullfile(output_dir, 'cycle_temperature_trends.png');
    plot_paths.phase_stress = fullfile(output_dir, 'cycle_xM_sigma_residual.png');
    plot_paths.branch_temps = fullfile(output_dir, 'cycle_branch_inlet_outlet_temperatures.png');
    plot_paths.branch_heat = fullfile(output_dir, 'cycle_branch_heat_flows.png');
    plot_paths.energy_residual = fullfile(output_dir, 'cycle_stage_energy_residuals.png');
    plot_paths.Ta_heatmap = fullfile(output_dir, 'cycle_Ta_51_heatmap.png');
    plot_paths.Tr_heatmap = fullfile(output_dir, 'cycle_Tr_51_heatmap.png');

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1100 650]);
    plot(log.time_s, log.Ta_mean_K, 'LineWidth', 1.5); hold on;
    plot(log.time_s, log.Tr_mean_K, 'LineWidth', 1.5);
    grid on; xlabel('time s'); ylabel('mean T K');
    legend({'SMA','SE'}, 'Location', 'best');
    exportgraphics(fig, plot_paths.temperature, 'Resolution', 180); close(fig);

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1100 760]);
    tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    nexttile; plot(log.time_s, log.xM_a_mean, 'LineWidth', 1.4); hold on;
    plot(log.time_s, log.xM_r_mean, 'LineWidth', 1.4); grid on; ylabel('x_M');
    legend({'SMA','SE'}, 'Location', 'best');
    nexttile; plot(log.time_s, log.sigma_a_Pa/1e6, 'LineWidth', 1.4); hold on;
    plot(log.time_s, log.sigma_r_Pa/1e6, 'LineWidth', 1.4); grid on; ylabel('MPa');
    legend({'SMA','SE'}, 'Location', 'best');
    nexttile; semilogy(log.time_s, abs(log.eq6_scaled)+eps, 'LineWidth', 1.3); hold on;
    semilogy(log.time_s, abs(log.eq7_scaled)+eps, 'LineWidth', 1.3); grid on;
    ylabel('residual'); xlabel('time s'); legend({'Eq6','Eq7'}, 'Location', 'best');
    exportgraphics(fig, plot_paths.phase_stress, 'Resolution', 180); close(fig);

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1100 650]);
    plot(log.time_s, log.SMA_SHEX_Tin_K, '-', log.time_s, log.SMA_SHEX_Tout_K, '--', ...
        log.time_s, log.SMA_THE_Tin_K, '-', log.time_s, log.SMA_THE_Tout_K, '--', ...
        log.time_s, log.SE_THE_Tin_K, '-', log.time_s, log.SE_THE_Tout_K, '--', ...
        log.time_s, log.SE_RHE_Tin_K, '-', log.time_s, log.SE_RHE_Tout_K, '--', ...
        'LineWidth', 1.0);
    grid on; xlabel('time s'); ylabel('branch T K');
    exportgraphics(fig, plot_paths.branch_temps, 'Resolution', 180); close(fig);

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1100 650]);
    plot(log.time_s, log.Q_SMA_SHEX_W, 'LineWidth', 1.3); hold on;
    plot(log.time_s, -log.Q_SMA_THE_W, 'LineWidth', 1.3);
    plot(log.time_s, -log.Q_SE_THE_W, 'LineWidth', 1.3);
    plot(log.time_s, log.Q_SE_RHE_W, 'LineWidth', 1.3);
    grid on; xlabel('time s'); ylabel('positive role heat W');
    legend({'SMA SHEX in','SMA THE out','SE THE out','SE RHE in'}, 'Location', 'best');
    exportgraphics(fig, plot_paths.branch_heat, 'Resolution', 180); close(fig);

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1100 600]);
    bar([stages.stage_energy_residual_fraction]);
    grid on; xlabel('stage row'); ylabel('energy residual fraction');
    exportgraphics(fig, plot_paths.energy_residual, 'Resolution', 180); close(fig);

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1100 600]);
    imagesc(log.Ta_51'); colorbar; xlabel('sample'); ylabel('SMA node');
    exportgraphics(fig, plot_paths.Ta_heatmap, 'Resolution', 180); close(fig);

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1100 600]);
    imagesc(log.Tr_51'); colorbar; xlabel('sample'); ylabel('SE node');
    exportgraphics(fig, plot_paths.Tr_heatmap, 'Resolution', 180); close(fig);
end

function write_json(path_value, s)
    try
        text = jsonencode(s, 'PrettyPrint', true);
    catch
        text = jsonencode(s);
    end
    fid = fopen(path_value, 'w');
    cleanup = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end

function value = get_field(s, key, default_value)
    if isstruct(s) && isfield(s, key)
        value = s.(key);
    else
        value = default_value;
    end
end

function out = merge_structs(out, overrides)
    names = fieldnames(overrides);
    for idx = 1:numel(names)
        key = names{idx};
        if isfield(out, key) && isstruct(out.(key)) && isstruct(overrides.(key))
            out.(key) = merge_structs(out.(key), overrides.(key));
        else
            out.(key) = overrides.(key);
        end
    end
end
