function [params, schedule] = Build_HeatDriveECC_SixthRound_SimParams(options)
% Build variables for the sixth-round four-role-branch model.

    if nargin < 1 || isempty(options)
        options = Build_HeatDriveECC_SixthRound_Defaults();
    else
        options = Build_HeatDriveECC_SixthRound_Defaults(options);
    end

    N = 51;
    state = synthetic_state(N, options.system.T0_K);
    [old_schedule, ~] = Build_FourStage_Cycle_Schedule(struct('P_max', 0.59e6));
    exchange_options = struct( ...
        'model_path', options.model_path, ...
        'exchange_backend_kind', 'simulink_directional_51', ...
        'hotflush_stop_time_s', options.stage_max_duration_s(1), ...
        'coldflush_stop_time_s', options.stage_max_duration_s(3), ...
        'ambient_T_init', options.system.T0_K, ...
        'hot_sink_T_init', options.system.T0_K, ...
        'cold_sink_T_init', options.system.T0_K, ...
        'cold_load_T_init', options.system.Tc_K, ...
        'cold_load_mode', 'constant_load', ...
        'cold_load_heat_W', options.system.article_Qr_W, ...
        'flow_control_mode', 'pressure_pi_feedback_v1', ...
        'pressure_pi_kp_MPa_per_kgps', -0.0025, ...
        'pressure_pi_ki_ref_MPa_per_kgps_s', -0.0125, ...
        'pressure_pi_bias_ref_MPa', -0.003, ...
        'pressure_pi_hydraulic_scheduling_enabled', true, ...
        'pressure_pi_margin_fraction', 0.5, ...
        'pressure_pi_margin_min_MPa', 0.005, ...
        'pressure_pi_error_filter_tau_s', 0.002, ...
        'pressure_pi_normalized_error_enabled', true);
    stage_config = Resolve_Exchange_Stage_Config(old_schedule(2), exchange_options);
    params = Build_Simulink_Exchange_Params(state, stage_config, exchange_options);

    schedule = build_schedule(options, params.mdot_target_kgps);
    params.sixth_stage_id_ts = timeseries(schedule.stage_id, schedule.time_s);

    for idx = 1:numel(options.branch_roles)
        role = options.branch_roles{idx};
        key = lower(role.name);
        params.([key '_valve_command_ts']) = timeseries( ...
            schedule.branch.(key).valves, schedule.command_time_s);
        params.([key '_mdot_hold_target_ts']) = timeseries( ...
            schedule.branch.(key).hold_target, schedule.command_time_s);
        params.([key '_mdot_cool_target_ts']) = timeseries( ...
            schedule.branch.(key).cool_target, schedule.command_time_s);
        params = add_role_initial_temperatures(params, key, role, options);
    end

    params.sixth_mechanical_preflight_input_ts = build_mechanical_preflight_input(options);
end

function schedule = build_schedule(options, mdot_target)
    durations = options.stage_max_duration_s(:).';
    total_stages = options.cycle_count * 4;
    time_s = zeros(total_stages + 1, 1);
    stage_id = zeros(total_stages + 1, 1);
    row = 1;
    for cycle_idx = 1:options.cycle_count
        for sid = 1:4
            stage_id(row) = sid;
            time_s(row + 1) = time_s(row) + durations(sid);
            row = row + 1;
        end
    end
    stage_id(end) = 4;
    [command_time_s, branch] = build_ramped_branch_commands( ...
        options, time_s, mdot_target);
    schedule = struct('time_s', time_s, ...
        'stage_id', stage_id, ...
        'command_time_s', command_time_s, ...
        'branch', branch, ...
        'actual_stage_durations_s', durations, ...
        'switch_reason', 'article Eq23/Eq24 maximum duration; event guards audited after run', ...
        'total_time_s', time_s(end));
end

function [t_cmd, branch] = build_ramped_branch_commands(options, boundaries, mdot_target)
    role_names = cellfun(@(r) lower(r.name), options.branch_roles, ...
        'UniformOutput', false);
    for idx = 1:numel(role_names)
        branch.(role_names{idx}) = empty_branch_command();
    end
    t_cmd = [];
    stage_count = numel(boundaries) - 1;
    for stage_idx = 1:stage_count
        sid = mod(stage_idx - 1, 4) + 1;
        t0 = boundaries(stage_idx);
        t1 = boundaries(stage_idx + 1);
        ramp_s = min(options.command_ramp_s, 0.2 * (t1 - t0));
        epsilon_s = min(1.0e-6, 0.01 * max(ramp_s, 1.0e-6));
        local_t = [t0; t0 + ramp_s; t1 - ramp_s; t1 - epsilon_s];
        amplitude = [0; 1; 1; 0];
        t_cmd = [t_cmd; local_t]; %#ok<AGROW>
        for idx = 1:numel(options.branch_roles)
            role = options.branch_roles{idx};
            key = lower(role.name);
            [valves, hold_target, cool_target] = role_command(role, sid, mdot_target);
            branch.(key).valves = [branch.(key).valves; amplitude .* valves]; %#ok<AGROW>
            branch.(key).hold_target = [branch.(key).hold_target; amplitude .* hold_target]; %#ok<AGROW>
            branch.(key).cool_target = [branch.(key).cool_target; amplitude .* cool_target]; %#ok<AGROW>
        end
    end
    t_cmd(end + 1, 1) = boundaries(end);
    for idx = 1:numel(role_names)
        key = role_names{idx};
        branch.(key).valves(end + 1, :) = zeros(1, 6);
        branch.(key).hold_target(end + 1, 1) = 0;
        branch.(key).cool_target(end + 1, 1) = 0;
    end
end

function c = empty_branch_command()
    c = struct('valves', zeros(0, 6), ...
        'hold_target', zeros(0, 1), ...
        'cool_target', zeros(0, 1));
end

function [valves, hold_target, cool_target] = role_command(role, sid, mdot_target)
    valves = zeros(1, 6);
    hold_target = 0;
    cool_target = 0;
    if sid ~= role.active_stage
        return;
    end
    if strcmpi(role.active_path, 'hold')
        valves = [1 1 1 0 0 0];
        hold_target = mdot_target;
    elseif strcmpi(role.active_path, 'cooldown')
        valves = [0 0 0 1 1 1];
        cool_target = mdot_target;
    else
        error('Build_HeatDriveECC_SixthRound_SimParams:BadActivePath', ...
            'Unknown active path: %s', role.active_path);
    end
end

function params = add_role_initial_temperatures(params, key, role, options)
    boundary_T = role.boundary_T_K;
    ambient_T = options.system.T0_K;
    cold_load_T = options.system.Tc_K;
    names = {
        'ambient_T_init', ambient_T
        'hot_sink_T_init', boundary_T
        'cold_sink_T_init', boundary_T
        'cold_load_T_init', cold_load_T
        'chip_T_init', cold_load_T
        'hot_fluid_buffer_T_init', boundary_T
        'cold_fluid_buffer_T_init', boundary_T
        'hot_side_fluid_T_init', boundary_T
        'cold_hx_pipe_T_init', boundary_T
        'cold_return_pipe_T_init', boundary_T
        'transit_pipe_T_init', boundary_T
        'cold_load_heat_W', 0.0
        'chip_heat_W', 0.0};
    for idx = 1:size(names, 1)
        params.([key '_' names{idx, 1}]) = names{idx, 2};
    end
    if strcmpi(role.solid_role, 'sma')
        solid_T = options.system.T0_K;
    else
        solid_T = options.system.Tc_K;
    end
    params.([key '_solver_T_init_101_internal']) = solid_T * ones(101, 1);
end

function ts = build_mechanical_preflight_input(options)
    t = linspace(0, sum(options.stage_max_duration_s(1:3)), 401).';
    Ta = options.system.T0_K * ones(size(t));
    Tr = options.system.Tc_K * ones(size(t));
    stage = ones(size(t));
    t_heat_end = options.stage_max_duration_s(1);
    t_hold_end = t_heat_end + options.stage_max_duration_s(2);
    t_cool_end = t_hold_end + options.stage_max_duration_s(3);
    for idx = 1:numel(t)
        if t(idx) <= t_heat_end
            f = t(idx) / max(t_heat_end, eps);
            Ta(idx) = options.system.T0_K + f * (options.system.Th_K - options.system.T0_K);
            Tr(idx) = options.system.Tc_K;
            stage(idx) = 1;
        elseif t(idx) <= t_hold_end
            Ta(idx) = options.system.Th_K;
            Tr(idx) = options.system.T0_K;
            stage(idx) = 2;
        elseif t(idx) <= t_cool_end
            f = (t(idx) - t_hold_end) / max(t_cool_end - t_hold_end, eps);
            Ta(idx) = options.system.Th_K + f * (options.system.T0_K - options.system.Th_K);
            Tr(idx) = options.system.T0_K;
            stage(idx) = 3;
        end
    end
    values = [t stage Ta Tr];
    ts = timeseries(values, t);
end

function state = synthetic_state(N, T)
    Y = zeros(4 * N, 1);
    Y(2 * N + (1:N)) = T;
    state = struct('Y', Y, 'state', struct(), ...
        'grid', struct('N', N, 'R', 0.04, 'r', linspace(0, 0.04, N).', ...
            'dr', 0.04 / (N - 1)), ...
        'params', struct('Pmax', 0.59e6, 't_delta', 0.2e-3), ...
        'pressure_MPa', 0.59, 'time_s', 0.0);
end
