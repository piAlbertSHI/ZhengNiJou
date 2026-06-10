function [params, schedule] = Build_HeatDriveECC_FifthRound_SimParams(options)
% Build mature Simscape parameters plus independent four-stage route commands.

    if nargin < 1 || isempty(options)
        options = Build_HeatDriveECC_FifthRound_Defaults();
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
        'cold_sink_T_init', options.system.Tc_K, ...
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

    g = options.geometry;
    mat = options.material;
    params.sma_actuator_node_mass_kg = mat.rho_kg_per_m3 * g.S_a_m2 * g.L_a_m / N;
    params.sma_actuator_cp_J_per_kgK = mat.cp_J_per_kgK;
    params.sma_actuator_T_init_51 = options.system.T0_K * ones(N, 1);
    params.sma_actuator_k_W_per_mK = mat.k_W_per_mK;
    params.sma_actuator_area_m2 = g.S_a_m2;
    params.sma_actuator_dx_m = g.L_a_m / (N - 1);
    params.sma_loop_fluid_T_init_K = options.system.T0_K;

    params.se_refrigerant_node_mass_kg = mat.rho_kg_per_m3 * g.S_r_m2 * g.L_r_m / N;
    params.se_refrigerant_cp_J_per_kgK = mat.cp_J_per_kgK;
    params.se_refrigerant_T_init_51 = options.system.Tc_K * ones(N, 1);
    params.se_refrigerant_k_W_per_mK = mat.k_W_per_mK;
    params.se_refrigerant_area_m2 = g.S_r_m2;
    params.se_refrigerant_dx_m = g.L_r_m / (N - 1);
    params.se_loop_fluid_T_init_K = options.system.Tc_K;

    params.ambient_T_init = options.system.T0_K;
    params.cold_fluid_buffer_T_init = options.system.T0_K;
    params.hot_sink_T_init = options.system.T0_K;
    params.hot_fluid_buffer_T_init = options.system.Tc_K;
    params.hot_side_fluid_T_init = options.system.Tc_K;
    params.cold_sink_T_init = options.system.Tc_K;
    params.cold_load_T_init = options.system.Tc_K;
    params.chip_T_init = options.system.Tc_K;
    params.cold_hx_pipe_T_init = options.system.Tc_K;
    params.cold_return_pipe_T_init = options.system.Tc_K;
    params.transit_pipe_T_init = options.system.Tc_K;

    params.sma_ambient_T_init = options.system.T0_K;
    params.sma_cold_fluid_buffer_T_init = options.system.Th_K;
    params.sma_hot_sink_T_init = options.system.T0_K;
    params.sma_hot_fluid_buffer_T_init = options.system.T0_K;
    params.sma_hot_side_fluid_T_init = options.system.T0_K;
    params.sma_cold_sink_T_init = options.system.Th_K;
    params.sma_cold_load_T_init = options.system.Th_K;
    params.sma_chip_T_init = options.system.Th_K;
    params.sma_cold_hx_pipe_T_init = options.system.Th_K;
    params.sma_cold_return_pipe_T_init = options.system.Th_K;
    params.sma_transit_pipe_T_init = options.system.Th_K;
    params.sma_cold_load_heat_W = 0.0;
    params.sma_chip_heat_W = 0.0;

    schedule = build_schedule(options, params.mdot_target_kgps);
    params.fifth_stage_id_ts = timeseries(schedule.stage_id, schedule.time_s);
    params.L_valve_command_sma = timeseries(schedule.sma_valves, schedule.command_time_s);
    params.L_valve_command_se = timeseries(schedule.se_valves, schedule.command_time_s);
    params.sma_mdot_hold_target_ts = timeseries(schedule.sma_hold_target, schedule.command_time_s);
    params.sma_mdot_cooldown_target_ts = timeseries(schedule.sma_cool_target, schedule.command_time_s);
    params.se_mdot_hold_target_ts = timeseries(schedule.se_hold_target, schedule.command_time_s);
    params.se_mdot_cooldown_target_ts = timeseries(schedule.se_cool_target, schedule.command_time_s);
    params.sma_shex_heat_total_W_ts = timeseries(schedule.sma_shex_heat_total_W, schedule.command_time_s);
    active_G = params.sma_pipe_thermal_gate_active_G_W_per_K;
    inactive_G = params.sma_pipe_thermal_gate_inactive_G_W_per_K;
    params.sma_hold_gate_G_ts = timeseries(gate_conductance(schedule.sma_hold_gate, active_G, inactive_G), schedule.command_time_s);
    params.sma_cool_gate_G_ts = timeseries(gate_conductance(schedule.sma_cool_gate, active_G, inactive_G), schedule.command_time_s);
    params.se_hold_gate_G_ts = timeseries(gate_conductance(schedule.se_hold_gate, active_G, inactive_G), schedule.command_time_s);
    params.se_cool_gate_G_ts = timeseries(gate_conductance(schedule.se_cool_gate, active_G, inactive_G), schedule.command_time_s);
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
    [command_time_s, sma_valves, se_valves, sma_hold, sma_cool, se_hold, se_cool] = ...
        build_ramped_commands(time_s, options.command_ramp_s, mdot_target);
    sma_hold_gate = max(sma_valves(:, 1:3), [], 2);
    sma_cool_gate = max(sma_valves(:, 4:6), [], 2);
    se_hold_gate = max(se_valves(:, 1:3), [], 2);
    se_cool_gate = max(se_valves(:, 4:6), [], 2);
    tau_cycle_s = sum(durations);
    sma_shex_heat_total_W = sma_hold_gate .* options.system.article_Qh_W .* ...
        tau_cycle_s ./ max(durations(1), eps);
    schedule = struct('time_s',time_s,'stage_id',stage_id, ...
        'command_time_s',command_time_s, ...
        'sma_valves',sma_valves,'se_valves',se_valves, ...
        'sma_hold_target',sma_hold,'sma_cool_target',sma_cool, ...
        'se_hold_target',se_hold,'se_cool_target',se_cool, ...
        'sma_hold_gate',sma_hold_gate,'sma_cool_gate',sma_cool_gate, ...
        'se_hold_gate',se_hold_gate,'se_cool_gate',se_cool_gate, ...
        'sma_shex_heat_total_W',sma_shex_heat_total_W, ...
        'actual_stage_durations_s',durations, ...
        'switch_reason','maximum duration used; event guards audited after run', ...
        'total_time_s',time_s(end));
end

function G = gate_conductance(open_fraction, active_G, inactive_G)
    G = inactive_G + open_fraction .* (active_G - inactive_G);
end

function [t_cmd, sma_valves, se_valves, sma_hold, sma_cool, se_hold, se_cool] = ...
        build_ramped_commands(boundaries, requested_ramp_s, mdot_target)
    stage_count = numel(boundaries) - 1;
    t_cmd = [];
    sma_valves = zeros(0, 6);
    se_valves = zeros(0, 6);
    sma_hold = zeros(0, 1);
    sma_cool = zeros(0, 1);
    se_hold = zeros(0, 1);
    se_cool = zeros(0, 1);
    for stage_idx = 1:stage_count
        sid = mod(stage_idx - 1, 4) + 1;
        t0 = boundaries(stage_idx);
        t1 = boundaries(stage_idx + 1);
        ramp_s = min(requested_ramp_s, 0.2 * (t1 - t0));
        epsilon_s = min(1.0e-6, 0.01 * ramp_s);
        local_t = [t0; t0 + ramp_s; t1 - ramp_s; t1 - epsilon_s];
        amplitude = [0; 1; 1; 0];
        [sv, rv, sh, sc, rh, rc] = active_route(sid, mdot_target);
        t_cmd = [t_cmd; local_t]; %#ok<AGROW>
        sma_valves = [sma_valves; amplitude .* sv]; %#ok<AGROW>
        se_valves = [se_valves; amplitude .* rv]; %#ok<AGROW>
        sma_hold = [sma_hold; amplitude .* sh]; %#ok<AGROW>
        sma_cool = [sma_cool; amplitude .* sc]; %#ok<AGROW>
        se_hold = [se_hold; amplitude .* rh]; %#ok<AGROW>
        se_cool = [se_cool; amplitude .* rc]; %#ok<AGROW>
    end
    t_cmd(end + 1, 1) = boundaries(end);
    sma_valves(end + 1, :) = zeros(1, 6);
    se_valves(end + 1, :) = zeros(1, 6);
    sma_hold(end + 1, 1) = 0;
    sma_cool(end + 1, 1) = 0;
    se_hold(end + 1, 1) = 0;
    se_cool(end + 1, 1) = 0;
end

function [sma_valves, se_valves, sma_hold, sma_cool, se_hold, se_cool] = ...
        active_route(sid, mdot_target)
    sma_valves = zeros(1, 6);
    se_valves = zeros(1, 6);
    sma_hold = 0;
    sma_cool = 0;
    se_hold = 0;
    se_cool = 0;
    if sid == 1
        sma_valves = [1 1 1 0 0 0];
        sma_hold = mdot_target;
    elseif sid == 2
        se_valves = [1 1 1 0 0 0];
        se_hold = mdot_target;
    elseif sid == 3
        sma_valves = [0 0 0 1 1 1];
        sma_cool = mdot_target;
    else
        se_valves = [0 0 0 1 1 1];
        se_cool = mdot_target;
    end
end

function state = synthetic_state(N, T)
    Y = zeros(4 * N, 1);
    Y(2 * N + (1:N)) = T;
    state = struct('Y',Y,'state',struct(), ...
        'grid',struct('N',N,'R',0.04,'r',linspace(0,0.04,N).','dr',0.04/(N-1)), ...
        'params',struct('Pmax',0.59e6,'t_delta',0.2e-3), ...
        'pressure_MPa',0.59,'time_s',0.0);
end
