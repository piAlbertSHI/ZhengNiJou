function Integrate_HeatDriveECC_Constitutive21_Interface(model_name, options, save_changes)
% Add the coupled 21-node constitutive heat-source interface to the main SLX.

    if nargin < 1 || isempty(model_name)
        model_name = 'heatdrive_ecc_coupled_se21';
    end
    if nargin < 2 || isempty(options)
        options = Build_HeatDriveECC_EighthRound_Defaults();
    end
    if nargin < 3
        save_changes = true;
    end
    if options.node_count ~= 21
        error('HeatDriveECC:ConstitutiveInterfaceNodeCount', ...
            'The constitutive Simulink interface expects 21 nodes.');
    end

    assign_exchange_workspace(options);
    assign_constitutive_workspace(options);
    load_system(model_name);
    configure_shex_boundary(model_name);
    configure_valve_command_blocks(model_name);
    configure_sma_pressure_bias_command(model_name);
    configure_se_pressure_bias_command(model_name);
    expose_component(model_name, 'SMA');
    expose_component(model_name, 'SE');
    configure_component_solid_state(model_name, 'SMA', 'sma');
    configure_component_solid_state(model_name, 'SE', 'se');
    configure_component_pipe_initial_temperature(model_name, 'SMA', ...
        'sma_hold_fluid_T_init', 'sma_cooldown_fluid_T_init');
    configure_component_pipe_initial_temperature(model_name, 'SE', ...
        'se_hold_fluid_T_init', 'se_cooldown_fluid_T_init');
    configure_sma_dynamic_thermal_gates(model_name);
    configure_se_dynamic_thermal_gates(model_name);
    add_top_level_constitutive_loop(model_name, options);
    add_top_level_eighth_round_output_loop(model_name, options);
    add_sma_stage13_observability(model_name);
    add_pressure_command_observability(model_name);
    add_sma_internal_pipe_observability(model_name);
    add_hhex_sma_branch_observability(model_name);
    apply_sma_stage13_visual_layout(model_name);
    make_to_workspace_names_unique(model_name);
    add_or_update_note(model_name);
    if save_changes
        set_param(model_name, 'SimulationCommand', 'update');
        save_system(model_name);
    end
end

function add_pressure_command_observability(model_name)
    add_pressure_command_log(model_name, 'PressurePI_Saturation', ...
        'ToWorkspace_pressure_command_se_MPa', ...
        'pressure_command_se_MPa', [-2680 710 -2315 735]);
    add_pressure_command_log(model_name, 'SMAPressurePI_Saturation', ...
        'ToWorkspace_pressure_command_sma_MPa', ...
        'pressure_command_sma_MPa', [-2680 740 -2315 765]);
end

function add_pressure_command_log(model_name, source_name, block_name, ...
        variable_name, position)
    source_path = [model_name '/' source_name];
    if ~exist_block(source_path)
        return;
    end
    sink_path = [model_name '/' block_name];
    ensure_block('simulink/Sinks/To Workspace', sink_path, ...
        'VariableName', variable_name, ...
        'SaveFormat', 'Structure With Time', ...
        'Position', position);
    safe_add_line(model_name, [source_name '/1'], [block_name '/1']);
end

function add_top_level_eighth_round_output_loop(model_name, ~)
    % The physical result is extracted from Simscape logs and the
    % ECC_ConstitutiveStateVectorStep21 heat-source chain.  The former
    % EighthRound MATLAB-core output was a second explicit thermal model
    % running in parallel; it was not an authority and could terminate the
    % physical solve after its own state diverged.  Remove it from the
    % production model instead of silently reintroducing a surrogate.
    block_names = {'ToWorkspace_EighthRound_Yout', ...
        'EighthRound_CoreStep_Output', 'EighthRound_Core_Clock'};
    for idx = 1:numel(block_names)
        block_path = [model_name '/' block_names{idx}];
        if exist_block(block_path)
            delete_block(block_path);
        end
    end
end

function assign_constitutive_workspace(options)
    sample_time_s = get_constitutive_sample_time(options);
    options.constitutive.simulink_sample_time_s = sample_time_s;
    assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
    assignin('base', 'constitutive_sample_time_s', sample_time_s);
    assignin('base', 'constitutive_state21_initial', ...
        Initialize_HeatDriveECC_ConstitutiveVector21(options));
    assignin('base', 'sma_constitutive_T21_initial', ...
        options.system.T0_K * ones(options.node_count, 1));
    assignin('base', 'se_constitutive_T21_initial', ...
        options.system.T0_K * ones(options.node_count, 1));
    assign_component_solid_workspace(options);
    assignin('base', 'constitutive_output_width', 12 * options.node_count);
end

function assign_component_solid_workspace(options)
    N = options.node_count;
    g = options.geometry;
    sma = options.material.SMA;
    se = options.material.SE;
    sma_node_mass_kg = sma.rho_kg_per_m3 * g.S_a_m2 * (g.L_a_m / N);
    se_node_mass_kg = se.rho_kg_per_m3 * g.S_r_m2 * (g.L_r_m / N);

    assignin('base', 'sma_node_mass_kg', sma_node_mass_kg);
    assignin('base', 'se_node_mass_kg', se_node_mass_kg);
    assignin('base', 'sma_node_cp', sma.cp_J_per_kgK);
    assignin('base', 'se_node_cp', se.cp_J_per_kgK);
    assignin('base', 'sma_solver_T_init_21_internal', ...
        options.system.T0_K * ones(N, 1));
    assignin('base', 'se_solver_T_init_21_internal', ...
        options.system.T0_K * ones(N, 1));
    assignin('base', 'sma_hold_fluid_T_init', options.system.Tshex_K);
    assignin('base', 'sma_cooldown_fluid_T_init', options.system.Thhex_K);
    assignin('base', 'se_hold_fluid_T_init', options.system.Tchex_K);
    assignin('base', 'se_cooldown_fluid_T_init', options.system.Thhex_K);
    assignin('base', 'sma_fluid_T_init', options.system.T0_K);
    assignin('base', 'se_fluid_T_init', options.system.Tc_K);
end

function assign_exchange_workspace(options)
    shex_T_init = get_system_temperature(options, 'Tshex_K', options.system.Th_K);
    shex_source_T_init = get_system_temperature(options, 'Tshex_source_K', ...
        get_system_temperature(options, 'T_PSC_K', shex_T_init));
    hhex_T_init = get_system_temperature(options, 'Thhex_K', options.system.T0_K);
    chex_T_init = get_system_temperature(options, 'Tchex_K', options.system.Tc_K);
    axial_heat_transfer_scale = compute_axial_heat_transfer_scale(options);
    exchange_options = struct( ...
        'model_path', options.model_path, ...
        'exchange_backend_kind', 'simulink_axial_21', ...
        'ambient_T_init', options.system.T0_K, ...
        'hot_sink_T_init', hhex_T_init, ...
        'cold_sink_T_init', chex_T_init, ...
        'cold_load_T_init', chex_T_init, ...
        'hot_sink_C_J_per_K', options.system.hot_sink_C_J_per_K, ...
        'cold_sink_C_J_per_K', options.system.cold_sink_C_J_per_K, ...
        'cold_load_C_J_per_K', options.system.cold_load_C_J_per_K, ...
        'thermal_mass_cp_ref', options.system.thermal_mass_cp_ref_J_per_kgK, ...
        'cold_load_heat_W', options.system.cold_load_heat_W, ...
        'chip_heat_W', options.system.cold_load_heat_W, ...
        'cold_load_mode', options.system.cold_load_mode, ...
        'cold_load_heat_policy', ...
            'no_external_cold_load_heat_for_three_cycle_capacity_check', ...
        'hot_sink_ambient_G_W_per_K', options.branch.hhex_to_ambient_UA_W_per_K, ...
        'hot_sink_fluid_G_W_per_K', options.branch.UA_sma_the_W_per_K, ...
        'cold_sink_ambient_G_W_per_K', options.branch.chex_environment_leak_UA_W_per_K, ...
        'cold_sink_ambient_G_cooldown_W_per_K', ...
            options.branch.chex_environment_leak_UA_W_per_K, ...
        'cold_sink_fluid_G_W_per_K', options.branch.UA_se_chex_W_per_K, ...
        'cold_load_to_cold_sink_G_W_per_K', ...
            options.branch.cold_load_to_chex_UA_W_per_K, ...
        'shex_sink_T_init', shex_T_init, ...
        'shex_source_T_init', shex_source_T_init, ...
        'shex_fluid_buffer_T_init', shex_T_init, ...
        'sma_pipe_thermal_gate_enabled', true, ...
        'sma_pipe_thermal_gate_active_G_W_per_K', ...
            options.branch.sma_pipe_thermal_gate_active_G_W_per_K, ...
        'sma_pipe_thermal_gate_inactive_G_W_per_K', ...
            options.branch.sma_pipe_thermal_gate_inactive_G_W_per_K, ...
        'pressure_differential_override_MPa', -0.00003, ...
        'pressure_pi_bias_MPa', options.branch.se_pressure_bias_MPa, ...
        'pressure_pi_bias_ref_MPa', options.branch.se_pressure_bias_MPa, ...
        'pressure_pi_min_MPa', options.branch.pressure_pi_min_MPa, ...
        'pressure_pi_max_MPa', options.branch.pressure_pi_max_MPa, ...
        'pressure_pi_kp_MPa_per_kgps', ...
            options.branch.se_pressure_pi_kp_MPa_per_kgps, ...
        'pressure_pi_ki_MPa_per_kgps_s', ...
            options.branch.se_pressure_pi_ki_MPa_per_kgps_s, ...
        'h_water_scale', axial_heat_transfer_scale, ...
        'sma_pipe_internal_volume_target_ml', ...
            options.branch.sma_pipe_internal_volume_target_ml, ...
        'total_mass', options.equilibrium.m_a_kg, ...
        'node_cp', options.material.SMA.cp_J_per_kgK, ...
        'cond_dx', options.geometry.L_a_m / max(options.node_count - 1, 1), ...
        'cond_area', options.geometry.S_a_m2, ...
        'hotflush_stop_time_s', options.schedule.stage_durations_s(2), ...
        'coldflush_stop_time_s', options.schedule.stage_durations_s(4), ...
        'probe_sample_count', options.validation.min_samples_per_stage);
    runtime = Create_Simulink_Exchange_Runtime(exchange_options);
    exchange_options.runtime = runtime;

    stage_info = struct( ...
        'stage_name', 'cooldown_exchange', ...
        't_start', options.schedule.stage_start_s(4), ...
        't_end', options.schedule.stage_end_s(4));
    stage_config = Resolve_Exchange_Stage_Config(stage_info, exchange_options);
    state_in = struct('T', options.system.T0_K * ones(21, 1));
    sim_params = Build_Simulink_Exchange_Params(state_in, stage_config, exchange_options);
    if ~isfield(sim_params, 'mdot_source_kgps')
        sim_params.mdot_source_kgps = sim_params.mdot_target_kgps;
    end
    sim_params = apply_full_cycle_valve_commands(sim_params, options);
    sim_params.thermal_mass_cp_ref = options.system.thermal_mass_cp_ref_J_per_kgK;
    sim_params.shex_sink_mass_kg = ...
        options.system.shex_sink_C_J_per_K / ...
        max(options.system.thermal_mass_cp_ref_J_per_kgK, eps);
    sim_params.shex_sink_ambient_G_W_per_K = ...
        options.branch.shex_source_to_sink_UA_W_per_K;
    sim_params.shex_sink_fluid_G_W_per_K = ...
        options.branch.UA_sma_shex_W_per_K;
    sim_params.shex_hot_side_fluid_T_init = options.system.Tshex_K;

    names = fieldnames(sim_params);
    for idx = 1:numel(names)
        assignin('base', names{idx}, sim_params.(names{idx}));
    end
end

function sim_params = apply_full_cycle_valve_commands(sim_params, options)
    [t, se_values, sma_values, sma_pressure_bias_values, ...
        se_pressure_bias_values, ...
        sma_hold_gate_values, sma_cooldown_gate_values] = ...
        build_full_cycle_valve_profiles(options);
    sim_params.L_valve_command = timeseries(se_values, t);
    sim_params.L_valve_command_time_s = t;
    sim_params.L_valve_command_values = se_values;
    sim_params.SMA_L_valve_command = timeseries(sma_values, t);
    sim_params.SMA_L_valve_command_time_s = t;
    sim_params.SMA_L_valve_command_values = sma_values;
    sim_params.SMA_pressure_bias_command = ...
        timeseries(sma_pressure_bias_values, t);
    sim_params.SMA_pressure_bias_command_time_s = t;
    sim_params.SMA_pressure_bias_command_values = sma_pressure_bias_values;
    sim_params.SE_pressure_bias_command = ...
        timeseries(se_pressure_bias_values, t);
    sim_params.SE_pressure_bias_command_time_s = t;
    sim_params.SE_pressure_bias_command_values = se_pressure_bias_values;
    sim_params.SMA_hold_pipe_to_sma_G_command = ...
        timeseries(sma_hold_gate_values, t);
    sim_params.SMA_hold_pipe_to_sma_G_command_time_s = t;
    sim_params.SMA_hold_pipe_to_sma_G_command_values = sma_hold_gate_values;
    sim_params.SMA_cooldown_pipe_to_sma_G_command = ...
        timeseries(sma_cooldown_gate_values, t);
    sim_params.SMA_cooldown_pipe_to_sma_G_command_time_s = t;
    sim_params.SMA_cooldown_pipe_to_sma_G_command_values = sma_cooldown_gate_values;
    se_active_G = options.branch.se_pipe_thermal_gate_active_G_W_per_K;
    se_inactive_G = options.branch.se_pipe_thermal_gate_inactive_G_W_per_K;
    se_hold_activity = mean(se_values(:, 1:3), 2);
    se_cooldown_activity = mean(se_values(:, 4:6), 2);
    se_hold_gate_values = se_inactive_G + ...
        (se_active_G - se_inactive_G) .* se_hold_activity;
    se_cooldown_gate_values = se_inactive_G + ...
        (se_active_G - se_inactive_G) .* se_cooldown_activity;
    sim_params.SE_hold_pipe_to_se_G_command = ...
        timeseries(se_hold_gate_values, t);
    sim_params.SE_hold_pipe_to_se_G_command_time_s = t;
    sim_params.SE_hold_pipe_to_se_G_command_values = se_hold_gate_values;
    sim_params.SE_cooldown_pipe_to_se_G_command = ...
        timeseries(se_cooldown_gate_values, t);
    sim_params.SE_cooldown_pipe_to_se_G_command_time_s = t;
    sim_params.SE_cooldown_pipe_to_se_G_command_values = se_cooldown_gate_values;
    sim_params.full_cycle_valve_command_source = ...
        'article_four_stage_continuous_simulink_valve_pressure_and_thermal_gate_profile';
end

function [t, se_values, sma_values, sma_pressure_bias_values, ...
        se_pressure_bias_values, ...
        sma_hold_gate_values, sma_cooldown_gate_values] = ...
        build_full_cycle_valve_profiles(options)
    [t, se_values, sma_values, sma_pressure_bias_values, ...
        se_pressure_bias_values, ...
        sma_hold_gate_values, sma_cooldown_gate_values] = ...
        build_full_cycle_valve_profiles_impl(options);
end

function [t, se_values, sma_values, sma_pressure_bias_values, ...
        se_pressure_bias_values, ...
        sma_hold_gate_values, sma_cooldown_gate_values] = ...
        build_full_cycle_valve_profiles_impl(options)
    tau = options.schedule.tau_cycle_s;
    se_stage = [
        0 0 0 0 0 0
        1 1 1 0 0 0
        0 0 0 0 0 0
        0 0 0 1 1 1];
    sma_stage = [
        1 0 1 0 1 0
        0 0 0 0 0 0
        0 1 0 1 0 1
        0 0 0 0 0 0];
    pressure_stage = [
        options.branch.sma_stage1_pressure_bias_MPa
        options.branch.sma_inactive_pressure_bias_MPa
        options.branch.sma_stage3_pressure_bias_MPa
        options.branch.sma_inactive_pressure_bias_MPa];
    se_pressure_stage = [
        get_branch_option(options, 'se_inactive_pressure_bias_MPa', ...
            options.branch.se_pressure_bias_MPa)
        get_branch_option(options, 'se_stage2_pressure_bias_MPa', ...
            options.branch.se_pressure_bias_MPa)
        get_branch_option(options, 'se_inactive_pressure_bias_MPa', ...
            options.branch.se_pressure_bias_MPa)
        get_branch_option(options, 'se_stage4_pressure_bias_MPa', ...
            options.branch.se_pressure_bias_MPa)];
    active_G = options.branch.sma_pipe_thermal_gate_active_G_W_per_K;
    inactive_G = options.branch.sma_pipe_thermal_gate_inactive_G_W_per_K;
    hold_gate_stage = [active_G; inactive_G; inactive_G; inactive_G];
    cooldown_gate_stage = [inactive_G; inactive_G; active_G; inactive_G];
    ramp_s = min(max(double(options.branch.stage_command_ramp_s), 0.0), ...
        0.10 * min(options.schedule.stage_durations_s));
    total_time_s = options.cycle_count * tau;

    t = zeros(0, 1);
    se_values = zeros(0, 6);
    sma_values = zeros(0, 6);
    sma_pressure_bias_values = zeros(0, 1);
    se_pressure_bias_values = zeros(0, 1);
    sma_hold_gate_values = zeros(0, 1);
    sma_cooldown_gate_values = zeros(0, 1);
    if ramp_s > 0.0
        t = 0.0;
        se_values = zeros(1, 6);
        sma_values = zeros(1, 6);
        sma_pressure_bias_values = 0.0;
        se_pressure_bias_values = se_pressure_stage(1);
        sma_hold_gate_values = inactive_G;
        sma_cooldown_gate_values = inactive_G;
        [t, se_values, sma_values, sma_pressure_bias_values, ...
            se_pressure_bias_values, ...
            sma_hold_gate_values, sma_cooldown_gate_values] = append_profile_row( ...
            t, se_values, sma_values, sma_pressure_bias_values, ...
            se_pressure_bias_values, ...
            sma_hold_gate_values, sma_cooldown_gate_values, ramp_s, 1, ...
            se_stage, sma_stage, pressure_stage, se_pressure_stage, ...
            hold_gate_stage, cooldown_gate_stage);
    else
        [t, se_values, sma_values, sma_pressure_bias_values, ...
            se_pressure_bias_values, ...
            sma_hold_gate_values, sma_cooldown_gate_values] = append_profile_row( ...
            t, se_values, sma_values, sma_pressure_bias_values, ...
            se_pressure_bias_values, ...
            sma_hold_gate_values, sma_cooldown_gate_values, 0.0, 1, ...
            se_stage, sma_stage, pressure_stage, se_pressure_stage, ...
            hold_gate_stage, cooldown_gate_stage);
    end

    for boundary_idx = 1:(options.cycle_count * 4)
        cycle_idx = floor((boundary_idx - 1) / 4);
        stage_idx = mod(boundary_idx - 1, 4) + 1;
        boundary_t = cycle_idx * tau + options.schedule.stage_end_s(stage_idx);
        [t, se_values, sma_values, sma_pressure_bias_values, ...
            se_pressure_bias_values, ...
            sma_hold_gate_values, sma_cooldown_gate_values] = append_profile_row( ...
            t, se_values, sma_values, sma_pressure_bias_values, ...
            se_pressure_bias_values, ...
            sma_hold_gate_values, sma_cooldown_gate_values, boundary_t, stage_idx, ...
            se_stage, sma_stage, pressure_stage, se_pressure_stage, ...
            hold_gate_stage, cooldown_gate_stage);
        if boundary_t >= total_time_s - eps(total_time_s)
            break;
        end
        next_stage_idx = mod(stage_idx, 4) + 1;
        transition_end_t = min(boundary_t + ramp_s, total_time_s);
        [t, se_values, sma_values, sma_pressure_bias_values, ...
            se_pressure_bias_values, ...
            sma_hold_gate_values, sma_cooldown_gate_values] = append_profile_row( ...
            t, se_values, sma_values, sma_pressure_bias_values, ...
            se_pressure_bias_values, ...
            sma_hold_gate_values, sma_cooldown_gate_values, transition_end_t, next_stage_idx, ...
            se_stage, sma_stage, pressure_stage, se_pressure_stage, ...
            hold_gate_stage, cooldown_gate_stage);
    end
end

function [t, se_values, sma_values, sma_pressure_bias_values, ...
        se_pressure_bias_values, ...
        sma_hold_gate_values, sma_cooldown_gate_values] = append_profile_row( ...
        t, se_values, sma_values, sma_pressure_bias_values, ...
        se_pressure_bias_values, ...
        sma_hold_gate_values, sma_cooldown_gate_values, time_s, stage_idx, ...
        se_stage, sma_stage, pressure_stage, se_pressure_stage, ...
        hold_gate_stage, cooldown_gate_stage)
    if ~isempty(t) && abs(time_s - t(end)) <= max(1.0e-12, eps(max(time_s, 1.0)))
        t(end) = time_s;
        se_values(end, :) = se_stage(stage_idx, :);
        sma_values(end, :) = sma_stage(stage_idx, :);
        sma_pressure_bias_values(end, 1) = pressure_stage(stage_idx);
        se_pressure_bias_values(end, 1) = se_pressure_stage(stage_idx);
        sma_hold_gate_values(end, 1) = hold_gate_stage(stage_idx);
        sma_cooldown_gate_values(end, 1) = cooldown_gate_stage(stage_idx);
        return;
    end
    t(end + 1, 1) = time_s;
    se_values(end + 1, :) = se_stage(stage_idx, :);
    sma_values(end + 1, :) = sma_stage(stage_idx, :);
    sma_pressure_bias_values(end + 1, 1) = pressure_stage(stage_idx);
    se_pressure_bias_values(end + 1, 1) = se_pressure_stage(stage_idx);
    sma_hold_gate_values(end + 1, 1) = hold_gate_stage(stage_idx);
    sma_cooldown_gate_values(end + 1, 1) = cooldown_gate_stage(stage_idx);
end

function value = get_branch_option(options, field_name, fallback)
    if isfield(options, 'branch') && isfield(options.branch, field_name) && ...
            ~isempty(options.branch.(field_name))
        value = options.branch.(field_name);
    else
        value = fallback;
    end
end

function scale = compute_axial_heat_transfer_scale(options)
    D_inner = 3.0e-3;
    D_outer = 5.0e-3;
    pipe_area = pi * (D_outer ^ 2 - D_inner ^ 2) / 4;
    storage_length = 1.0e-7 / max(pipe_area, eps);
    multiplier = 1.0;
    if isfield(options, 'branch') && isfield(options.branch, 'sma_pipe_heat_transfer_multiplier')
        multiplier = options.branch.sma_pipe_heat_transfer_multiplier;
    end
    if ~(isnumeric(multiplier) && isscalar(multiplier) && isfinite(multiplier) && multiplier > 0)
        multiplier = 1.0;
    end
    scale = max(options.geometry.L_a_m / max(storage_length, eps), 1.0) * multiplier;
end

function value = get_system_temperature(options, field_name, default_value)
    if isfield(options.system, field_name) && ~isempty(options.system.(field_name))
        value = options.system.(field_name);
    else
        value = default_value;
    end
end

function sample_time_s = get_constitutive_sample_time(options)
    if isfield(options.constitutive, 'simulink_sample_time_s')
        sample_time_s = options.constitutive.simulink_sample_time_s;
    else
        sample_time_s = options.simulation.fixed_step_s;
    end
end

function configure_shex_boundary(model_name)
    shex_mass = [model_name '/SHEX/HotSinkMass'];
    shex_source = [model_name '/SHEX/AmbientTempSource'];
    shex_ambient_link = [model_name '/SHEX/HotSinkAmbientLink'];
    shex_fluid_link = [model_name '/SHEX/HotSinkFluidLink'];
    shex_hot_pipe = [model_name '/SHEX/HotPipe'];
    if exist_block(shex_mass)
        set_param(shex_mass, ...
            'mass', 'shex_sink_mass_kg', ...
            'T', 'shex_sink_T_init');
    end
    if exist_block(shex_source)
        set_param(shex_source, 'temperature', 'shex_source_T_init');
    end
    if exist_block(shex_ambient_link)
        set_param(shex_ambient_link, 'th_cond', 'shex_sink_ambient_G_W_per_K');
    end
    if exist_block(shex_fluid_link)
        set_param(shex_fluid_link, 'th_cond', 'shex_sink_fluid_G_W_per_K');
    end
    if exist_block(shex_hot_pipe)
        set_param(shex_hot_pipe, 'T0', 'shex_hot_side_fluid_T_init');
    end
end

function configure_valve_command_blocks(model_name)
    blocks = {'ValveCommandFromWorkspace', 'SMAValveCommandFromWorkspace'};
    for idx = 1:numel(blocks)
        block_path = [model_name '/' blocks{idx}];
        if exist_block(block_path)
            set_param(block_path, ...
                'Interpolate', 'on', ...
                'OutputAfterFinalValue', 'Holding final value');
        end
    end
end

function configure_sma_pressure_bias_command(model_name)
    bias_sum = [model_name '/SMAPressurePI_BiasSum'];
    if ~exist_block(bias_sum)
        warning('HeatDriveECC:MissingSMAPressureBiasSum', ...
            'SMAPressurePI_BiasSum was not found; SMA pressure bias remains unchanged.');
        return;
    end

    command_block = [model_name '/SMAPressureBiasFromWorkspace'];
    ensure_block('simulink/Sources/From Workspace', command_block, ...
        'VariableName', 'SMA_pressure_bias_command', ...
        'Interpolate', 'on', ...
        'OutputAfterFinalValue', 'Holding final value', ...
        'Position', [-1750 480 -1570 510]);

    ports = get_param(bias_sum, 'PortHandles');
    if numel(ports.Inport) < 3
        warning('HeatDriveECC:SMAPressureBiasSumPortCount', ...
            'SMAPressurePI_BiasSum has fewer than 3 input ports; SMA pressure bias remains unchanged.');
        return;
    end
    delete_line_at_port(ports.Inport(3));
    safe_add_line_handle(model_name, get_port(command_block, 'Outport', 1), ...
        ports.Inport(3));
end

function configure_se_pressure_bias_command(model_name)
    bias_sum = [model_name '/PressurePI_BiasSum'];
    if ~exist_block(bias_sum)
        warning('HeatDriveECC:MissingSEPressureBiasSum', ...
            'PressurePI_BiasSum was not found; SE pressure bias remains unchanged.');
        return;
    end

    command_block = [model_name '/SEPressureBiasFromWorkspace'];
    ensure_block('simulink/Sources/From Workspace', command_block, ...
        'VariableName', 'SE_pressure_bias_command', ...
        'Interpolate', 'on', ...
        'OutputAfterFinalValue', 'Holding final value', ...
        'Position', [-1750 540 -1570 570]);

    ports = get_param(bias_sum, 'PortHandles');
    if numel(ports.Inport) < 3
        warning('HeatDriveECC:SEPressureBiasSumPortCount', ...
            'PressurePI_BiasSum has fewer than 3 input ports; SE pressure bias remains unchanged.');
        return;
    end
    delete_line_at_port(ports.Inport(3));
    safe_add_line_handle(model_name, get_port(command_block, 'Outport', 1), ...
        ports.Inport(3));
end

function configure_sma_dynamic_thermal_gates(model_name)
    parent = [model_name '/SMA'];
    if ~exist_block(parent)
        return;
    end
    configure_dynamic_thermal_gate_group(parent, 'Hold', ...
        'SMA_hold_pipe_to_sma_G_command', ...
        [35 860 225 890], [260 860 320 890]);
    configure_dynamic_thermal_gate_group(parent, 'Cooldown', ...
        'SMA_cooldown_pipe_to_sma_G_command', ...
        [505 860 735 890], [770 860 830 890]);
end

function configure_se_dynamic_thermal_gates(model_name)
    parent = [model_name '/SE'];
    if ~exist_block(parent)
        return;
    end
    configure_dynamic_thermal_gate_group(parent, 'Hold', ...
        'SE_hold_pipe_to_se_G_command', ...
        [35 860 225 890], [260 860 320 890]);
    configure_dynamic_thermal_gate_group(parent, 'Cooldown', ...
        'SE_cooldown_pipe_to_se_G_command', ...
        [505 860 735 890], [770 860 830 890]);
end

function configure_dynamic_thermal_gate_group(parent, gate_prefix, command_variable, ...
        source_pos, converter_pos)
    source_path = sprintf('%s/%sThermalGateCommandFromWorkspace', parent, gate_prefix);
    converter_path = sprintf('%s/%sThermalGateCommandPS', parent, gate_prefix);
    ensure_block('simulink/Sources/From Workspace', source_path, ...
        'VariableName', command_variable, ...
        'Interpolate', 'on', ...
        'OutputAfterFinalValue', 'Holding final value', ...
        'Position', source_pos);
    ensure_block('nesl_utility/Simulink-PS Converter', converter_path, ...
        'Unit', 'W/(K*m)', ...
        'Position', converter_pos);
    delete_line_at_port(get_port(converter_path, 'Inport', 1));
    safe_add_line_handle(parent, get_port(source_path, 'Outport', 1), ...
        get_port(converter_path, 'Inport', 1));

    for node_idx = 1:21
        gate_path = sprintf('%s/%sThermalGate_%03d', parent, gate_prefix, node_idx);
        if ~exist_block(gate_path)
            continue;
        end
        set_param(gate_path, 'thermal_type', ...
            'foundation.enum.ConstantVariableTabulated.Variable');
        ports = get_param(gate_path, 'PortHandles');
        if numel(ports.LConn) < 2
            warning('HeatDriveECC:MissingVariableThermalGatePort', ...
                '%s did not expose a variable thermal-conductivity port.', gate_path);
            continue;
        end
        delete_line_at_port(ports.LConn(2));
        safe_add_line_handle(parent, get_port(converter_path, 'RConn', 1), ...
            ports.LConn(2));
    end
end

function configure_component_solid_state(model_name, component_name, variable_prefix)
    inner = [model_name '/' component_name '/Subsystem2'];
    if ~exist_block(inner)
        return;
    end
    for idx = 1:21
        block_path = sprintf('%s/NodeMass_%02d', inner, idx);
        if exist_block(block_path)
            set_param(block_path, ...
                'mass', sprintf('%s_node_mass_kg', variable_prefix), ...
                'sp_heat', sprintf('%s_node_cp', variable_prefix), ...
                'T', sprintf('%s_solver_T_init_21_internal(%d)', variable_prefix, idx));
        end
    end
end

function configure_component_pipe_initial_temperature(model_name, component_name, ...
        hold_variable_name, cooldown_variable_name)
    component = [model_name '/' component_name];
    if ~exist_block(component)
        return;
    end
    for idx = 1:21
        prefixes = {'HoldPipe', 'CooldownPipe'};
        variables = {hold_variable_name, cooldown_variable_name};
        for prefix_idx = 1:numel(prefixes)
            block_path = sprintf('%s/%s_%03d', component, prefixes{prefix_idx}, idx);
            if exist_block(block_path)
                set_param(block_path, 'T0', variables{prefix_idx});
            end
        end
    end
end

function expose_component(model_name, component_name)
    component = [model_name '/' component_name];
    inner = [component '/Subsystem2'];
    N = 21;

    ensure_block('simulink/Sources/In1', [inner '/ConstitutiveHeat21_W'], ...
        'Position', [1100 930 1130 950]);
    ensure_block('simulink/Signal Routing/Demux', [inner '/ConstitutiveHeatDemux21'], ...
        'Outputs', num2str(N), ...
        'Position', [1165 650 1170 1230]);
    ensure_block('simulink/Sinks/Out1', [inner '/NodeTemp21Out'], ...
        'Position', [1120 65 1150 85]);
    if exist_block([inner '/ToWorkspace_Tx21_internal'])
        set_param([inner '/ToWorkspace_Tx21_internal'], ...
            'VariableName', [component_name '_Tx21_internal'], ...
            'Position', [1120 20 1225 50]);
    end
    safe_add_line(inner, 'TempMux51/1', 'NodeTemp21Out/1');
    safe_add_line(inner, 'ConstitutiveHeat21_W/1', 'ConstitutiveHeatDemux21/1');

    for idx = 1:N
        y = 70 + (idx - 1) * 56;
        converter = sprintf('%s/ConstitutiveHeatPS_%02d', inner, idx);
        source = sprintf('%s/ConstitutiveHeatSource_%02d', inner, idx);
        ensure_block('nesl_utility/Simulink-PS Converter', converter, ...
            'Unit', 'W', ...
            'Position', [1210 y 1270 (y + 24)]);
        ensure_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source', source, ...
            'Position', [1320 (y - 6) 1370 (y + 38)]);
        safe_add_line(inner, sprintf('ConstitutiveHeatDemux21/%d', idx), ...
            sprintf('ConstitutiveHeatPS_%02d/1', idx));
        safe_add_line_handle(inner, get_port(converter, 'RConn', 1), ...
            get_port(source, 'RConn', 1));
        safe_add_line_handle(inner, get_port(source, 'LConn', 1), ...
            get_port(sprintf('%s/NodeMass_%02d', inner, idx), 'LConn', 1));
        safe_add_line_handle(inner, get_port(source, 'RConn', 2), ...
            get_port([inner '/ThermalReference51'], 'LConn', 1));
    end

    ensure_block('simulink/Sources/In1', [component '/ConstitutiveHeat21_W'], ...
        'Position', [40 1120 70 1140]);
    ensure_block('simulink/Sinks/Out1', [component '/NodeTemp21Out'], ...
        'Position', [980 1120 1010 1140]);
    sub_ports = get_param([component '/Subsystem2'], 'PortHandles');
    safe_add_line_handle(component, get_port([component '/ConstitutiveHeat21_W'], 'Outport', 1), ...
        sub_ports.Inport(end));
    safe_add_line_handle(component, sub_ports.Outport(end), ...
        get_port([component '/NodeTemp21Out'], 'Inport', 1));
end

function add_top_level_constitutive_loop(model_name, options)
    N = options.node_count;
    state_width = 10 * N;
    output_width = 2 * N + state_width;

    ensure_block('simulink/Sources/Clock', [model_name '/ECC_Constitutive21_Clock'], ...
        'Position', [700 1120 730 1140]);
    ensure_block('simulink/Discrete/Unit Delay', [model_name '/ECC_Constitutive21_SMA_TempDelay'], ...
        'InitialCondition', 'sma_constitutive_T21_initial', ...
        'SampleTime', 'constitutive_sample_time_s', ...
        'Position', [750 1135 800 1165]);
    ensure_block('simulink/Discrete/Unit Delay', [model_name '/ECC_Constitutive21_SE_TempDelay'], ...
        'InitialCondition', 'se_constitutive_T21_initial', ...
        'SampleTime', 'constitutive_sample_time_s', ...
        'Position', [750 1175 800 1205]);
    ensure_block('simulink/Signal Routing/Mux', [model_name '/ECC_Constitutive21_InputMux'], ...
        'Inputs', '4', ...
        'Position', [820 1090 825 1190]);
    ensure_block('simulink/User-Defined Functions/Interpreted MATLAB Function', ...
        [model_name '/ECC_Constitutive21_VectorStep'], ...
        'MATLABFcn', 'HeatDriveECC_ConstitutiveStateVectorStep21', ...
        'OutputDimensions', num2str(output_width), ...
        'SampleTime', 'constitutive_sample_time_s', ...
        'Position', [880 1110 1070 1170]);
    ensure_block('simulink/Signal Routing/Demux', [model_name '/ECC_Constitutive21_OutputDemux'], ...
        'Outputs', sprintf('[%d %d %d]', N, N, state_width), ...
        'Position', [1120 1085 1125 1195]);
    ensure_block('simulink/Discrete/Unit Delay', [model_name '/ECC_Constitutive21_StateDelay'], ...
        'InitialCondition', 'constitutive_state21_initial', ...
        'SampleTime', 'constitutive_sample_time_s', ...
        'Position', [690 1190 770 1230]);
    ensure_block('simulink/Sinks/To Workspace', [model_name '/ToWorkspace_ECC_Constitutive21_Output'], ...
        'VariableName', 'ECC_constitutive21_output', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [1110 1225 1345 1255]);
    ensure_block('simulink/Sinks/To Workspace', [model_name '/ToWorkspace_ECC_Q_SMA_constitutive_W'], ...
        'VariableName', 'ECC_Q_SMA_constitutive_W', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [1195 1060 1410 1090]);
    ensure_block('simulink/Sinks/To Workspace', [model_name '/ToWorkspace_ECC_Q_SE_constitutive_W'], ...
        'VariableName', 'ECC_Q_SE_constitutive_W', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [1195 1120 1410 1150]);

    safe_add_line(model_name, 'ECC_Constitutive21_Clock/1', ...
        'ECC_Constitutive21_InputMux/1');
    connect_component_temperature(model_name, 'SMA', ...
        'ECC_Constitutive21_SMA_TempDelay', 'ECC_Constitutive21_InputMux', 2);
    connect_component_temperature(model_name, 'SE', ...
        'ECC_Constitutive21_SE_TempDelay', 'ECC_Constitutive21_InputMux', 3);
    safe_add_line(model_name, 'ECC_Constitutive21_StateDelay/1', ...
        'ECC_Constitutive21_InputMux/4');
    safe_add_line(model_name, 'ECC_Constitutive21_InputMux/1', ...
        'ECC_Constitutive21_VectorStep/1');
    safe_add_line(model_name, 'ECC_Constitutive21_VectorStep/1', ...
        'ECC_Constitutive21_OutputDemux/1');
    safe_add_line(model_name, 'ECC_Constitutive21_VectorStep/1', ...
        'ToWorkspace_ECC_Constitutive21_Output/1');
    safe_add_line(model_name, 'ECC_Constitutive21_OutputDemux/1', ...
        'ToWorkspace_ECC_Q_SMA_constitutive_W/1');
    safe_add_line(model_name, 'ECC_Constitutive21_OutputDemux/2', ...
        'ToWorkspace_ECC_Q_SE_constitutive_W/1');
    safe_add_line(model_name, 'ECC_Constitutive21_OutputDemux/3', ...
        'ECC_Constitutive21_StateDelay/1');
    connect_component_heat(model_name, 'SMA', 'ECC_Constitutive21_OutputDemux', 1);
    connect_component_heat(model_name, 'SE', 'ECC_Constitutive21_OutputDemux', 2);
end

function connect_component_temperature(model_name, component_name, delay_name, mux_name, mux_port)
    component = [model_name '/' component_name];
    ports = get_param(component, 'PortHandles');
    if isempty(ports.Outport)
        error('HeatDriveECC:MissingNodeTemperatureOutport', ...
            '%s has no Simulink node-temperature output port.', component_name);
    end
    delay_path = [model_name '/' delay_name];
    delay_ports = get_param(delay_path, 'PortHandles');
    mux_port_handle = get_port([model_name '/' mux_name], 'Inport', mux_port);
    delete_line_at_port(delay_ports.Inport(1));
    delete_line_at_port(mux_port_handle);
    safe_add_line_handle(model_name, ports.Outport(end), delay_ports.Inport(1));
    safe_add_line_handle(model_name, delay_ports.Outport(1), mux_port_handle);
end

function connect_component_heat(model_name, component_name, demux_name, demux_port)
    component = [model_name '/' component_name];
    ports = get_param(component, 'PortHandles');
    if isempty(ports.Inport)
        error('HeatDriveECC:MissingConstitutiveHeatInport', ...
            '%s has no Simulink constitutive heat input port.', component_name);
    end
    safe_add_line_handle(model_name, ...
        get_port([model_name '/' demux_name], 'Outport', demux_port), ...
        ports.Inport(end));
end

function add_sma_stage13_observability(model_name)
    [~, shex_buffer_ps, ~] = add_tl_temperature_probe(model_name, ...
        'SHEXBufferFluidTemp', ...
        get_port([model_name '/SHEXFluidBuffer'], 'LConn', 1), ...
        'probe_root_shex_buffer_fluid_T_K', ...
        [-2250 105 -2200 145], [-2165 114 -2135 136], [-2680 105 -2315 130]);
    add_workspace_alias_from_ps(model_name, shex_buffer_ps, ...
        'ToWorkspace_shex_buffer_temp_out', 'shex_buffer_temp_out', ...
        [-2680 135 -2315 160]);

    add_tl_temperature_probe(model_name, 'SMAStage1V1SHEXSideFluidTemp', ...
        get_port([model_name '/SMA_V1_SHEX_to_pump'], 'LConn', 1), ...
        'probe_sma_stage1_v1_shex_side_T_K', ...
        [-2015 95 -1965 135], [-1930 104 -1900 126], [-2680 175 -2315 200]);
    add_tl_temperature_probe(model_name, 'SMAStage1V1PumpSideFluidTemp', ...
        get_port([model_name '/SMA_V1_SHEX_to_pump'], 'RConn', 1), ...
        'probe_sma_stage1_v1_pump_side_T_K', ...
        [-1810 220 -1760 260], [-1725 229 -1695 251], [-2680 205 -2315 230]);
    add_tl_temperature_probe(model_name, 'SMAStage13PumpOutletFluidTemp', ...
        get_port([model_name '/SMA_TJ_PumpOutlet'], 'LConn', 1), ...
        'probe_sma_stage13_pump_outlet_T_K', ...
        [-1340 340 -1290 380], [-1255 349 -1225 371], [-2680 235 -2315 260]);
    [~, stage1_in_ps, ~] = add_tl_temperature_probe(model_name, 'SMAStage1InletFluidTemp', ...
        get_port([model_name '/SMA'], 'LConn', 1), ...
        'sma_stage1_inlet_fluid_temp_out', ...
        [-985 230 -935 270], [-900 239 -870 261], [-2680 265 -2315 290]);
    add_workspace_alias_from_ps(model_name, stage1_in_ps, ...
        'ToWorkspace_probe_sma_stage1_port1_v3_side_T_K', ...
        'probe_sma_stage1_port1_v3_side_T_K', ...
        [-2680 295 -2315 320]);
    [~, stage1_out_ps, ~] = add_tl_temperature_probe(model_name, 'SMAStage1OutletFluidTemp', ...
        get_port([model_name '/SMA'], 'LConn', 2), ...
        'sma_stage1_outlet_fluid_temp_out', ...
        [-855 540 -805 580], [-770 549 -740 571], [-2680 325 -2315 350]);
    add_workspace_alias_from_ps(model_name, stage1_out_ps, ...
        'ToWorkspace_probe_sma_stage1_port2_v5_side_T_K', ...
        'probe_sma_stage1_port2_v5_side_T_K', ...
        [-2680 355 -2315 380]);
    add_tl_temperature_probe(model_name, 'SMAStage1V5SHEXSideFluidTemp', ...
        get_port([model_name '/SMA_V5_SMA_to_SHEX'], 'RConn', 1), ...
        'probe_sma_stage1_v5_shex_side_T_K', ...
        [-610 480 -560 520], [-525 489 -495 511], [-2680 385 -2315 410]);

    add_tl_temperature_probe(model_name, 'SMAStage3V2HHEXSideFluidTemp', ...
        get_port([model_name '/SMA_V2_HHEX_to_pump'], 'LConn', 1), ...
        'probe_sma_stage3_v2_hhex_side_T_K', ...
        [-2015 645 -1965 685], [-1930 654 -1900 676], [-2680 475 -2315 500]);
    add_tl_temperature_probe(model_name, 'SMAStage3V2PumpSideFluidTemp', ...
        get_port([model_name '/SMA_V2_HHEX_to_pump'], 'RConn', 1), ...
        'probe_sma_stage3_v2_pump_side_T_K', ...
        [-1810 610 -1760 650], [-1725 619 -1695 641], [-2680 505 -2315 530]);
    [~, stage3_in_ps, ~] = add_tl_temperature_probe(model_name, 'SMAStage3InletFluidTemp', ...
        get_port([model_name '/SMA'], 'LConn', 3), ...
        'sma_stage3_inlet_fluid_temp_out', ...
        [-985 555 -935 595], [-900 564 -870 586], [-2680 535 -2315 560]);
    add_workspace_alias_from_ps(model_name, stage3_in_ps, ...
        'ToWorkspace_probe_sma_stage3_port3_v4_side_T_K', ...
        'probe_sma_stage3_port3_v4_side_T_K', ...
        [-2680 565 -2315 590]);
    [~, stage3_out_ps, ~] = add_tl_temperature_probe(model_name, 'SMAStage3OutletFluidTemp', ...
        get_port([model_name '/SMA'], 'LConn', 4), ...
        'sma_stage3_outlet_fluid_temp_out', ...
        [-855 725 -805 765], [-770 734 -740 756], [-2680 595 -2315 620]);
    add_workspace_alias_from_ps(model_name, stage3_out_ps, ...
        'ToWorkspace_probe_sma_stage3_port4_v6_side_T_K', ...
        'probe_sma_stage3_port4_v6_side_T_K', ...
        [-2680 625 -2315 650]);
    add_tl_temperature_probe(model_name, 'SMAStage3V6HHEXSideFluidTemp', ...
        get_port([model_name '/SMA_V6_SMA_to_HHEX'], 'RConn', 1), ...
        'probe_sma_stage3_v6_hhex_side_T_K', ...
        [-610 725 -560 765], [-525 734 -495 756], [-2680 655 -2315 680]);
end

function add_sma_internal_pipe_observability(model_name)
    parent = [model_name '/SMA'];
    if ~exist_block(parent)
        return;
    end

    add_tl_temperature_probe(parent, 'SMAHoldPipeNode01FluidTemp', ...
        get_port([parent '/HoldPipe_001'], 'LConn', 1), ...
        'sma_hold_pipe_node01_fluid_temp_out', ...
        [30 925 80 965], [115 934 145 956], [170 925 455 950]);
    add_tl_temperature_probe(parent, 'SMAHoldPipeNode11FluidTemp', ...
        get_port([parent '/HoldPipe_011'], 'LConn', 1), ...
        'sma_hold_pipe_node11_fluid_temp_out', ...
        [30 970 80 1010], [115 979 145 1001], [170 970 455 995]);
    add_tl_temperature_probe(parent, 'SMAHoldPipeNode21FluidTemp', ...
        get_port([parent '/HoldPipe_021'], 'RConn', 1), ...
        'sma_hold_pipe_node21_fluid_temp_out', ...
        [30 1015 80 1055], [115 1024 145 1046], [170 1015 455 1040]);

    add_tl_temperature_probe(parent, 'SMACooldownPipeNode01FluidTemp', ...
        get_port([parent '/CooldownPipe_001'], 'RConn', 1), ...
        'sma_cooldown_pipe_node01_fluid_temp_out', ...
        [500 925 550 965], [585 934 615 956], [640 925 955 950]);
    add_tl_temperature_probe(parent, 'SMACooldownPipeNode11FluidTemp', ...
        get_port([parent '/CooldownPipe_011'], 'LConn', 1), ...
        'sma_cooldown_pipe_node11_fluid_temp_out', ...
        [500 970 550 1010], [585 979 615 1001], [640 970 955 995]);
    add_tl_temperature_probe(parent, 'SMACooldownPipeNode21FluidTemp', ...
        get_port([parent '/CooldownPipe_021'], 'LConn', 1), ...
        'sma_cooldown_pipe_node21_fluid_temp_out', ...
        [500 1015 550 1055], [585 1024 615 1046], [640 1015 955 1040]);

    add_sma_pipe_heat_flow_probe(parent, 'HoldThermalGate_001', ...
        'SMAHoldNode01HeatFlow', 'sma_hold_node01_heatflow_W', ...
        [960 925 1010 965], [1045 934 1075 956], [1100 925 1410 950]);
    add_sma_pipe_heat_flow_probe(parent, 'HoldThermalGate_011', ...
        'SMAHoldNode11HeatFlow', 'sma_hold_node11_heatflow_W', ...
        [960 970 1010 1010], [1045 979 1075 1001], [1100 970 1410 995]);
    add_sma_pipe_heat_flow_probe(parent, 'HoldThermalGate_021', ...
        'SMAHoldNode21HeatFlow', 'sma_hold_node21_heatflow_W', ...
        [960 1015 1010 1055], [1045 1024 1075 1046], [1100 1015 1410 1040]);
    add_sma_pipe_heat_flow_probe(parent, 'CooldownThermalGate_001', ...
        'SMACooldownNode01HeatFlow', 'sma_cooldown_node01_heatflow_W', ...
        [1450 925 1500 965], [1535 934 1565 956], [1590 925 1940 950]);
    add_sma_pipe_heat_flow_probe(parent, 'CooldownThermalGate_011', ...
        'SMACooldownNode11HeatFlow', 'sma_cooldown_node11_heatflow_W', ...
        [1450 970 1500 1010], [1535 979 1565 1001], [1590 970 1940 995]);
    add_sma_pipe_heat_flow_probe(parent, 'CooldownThermalGate_021', ...
        'SMACooldownNode21HeatFlow', 'sma_cooldown_node21_heatflow_W', ...
        [1450 1015 1500 1055], [1535 1024 1565 1046], [1590 1015 1940 1040]);
end

function add_sma_pipe_heat_flow_probe(parent, gate_name, probe_base_name, ...
        variable_name, sensor_pos, ps_pos, workspace_pos)
    gate_path = [parent '/' gate_name];
    sensor_path = [parent '/' probe_base_name 'Sensor'];
    ps_path = [parent '/' probe_base_name 'PS'];
    toworkspace_path = [parent '/ToWorkspace_' variable_name];
    if ~exist_block(gate_path)
        return;
    end

    gate_port = get_port(gate_path, 'RConn', 1);
    downstream_port = find_existing_heat_flow_downstream(sensor_path, gate_port);
    delete_block_if_present_with_lines(toworkspace_path);
    delete_block_if_present_with_lines(ps_path);
    delete_block_if_present_with_lines(sensor_path);
    if downstream_port == -1
        return;
    end
    delete_line_at_port(gate_port);
    delete_line_at_port(downstream_port);

    add_block(sprintf('fl_lib/Thermal/Thermal Sensors/Heat Flow Rate\nSensor'), ...
        sensor_path, 'Position', sensor_pos);
    add_block('nesl_utility/PS-Simulink Converter', ps_path, ...
        'Position', ps_pos, ...
        'VectorFormat', '1-D array', ...
        'Unit', 'W');
    add_block('simulink/Sinks/To Workspace', toworkspace_path, ...
        'VariableName', variable_name, ...
        'SaveFormat', 'Structure With Time', ...
        'Position', workspace_pos);

    safe_add_line_handle(parent, gate_port, get_port(sensor_path, 'LConn', 1));
    safe_add_line_handle(parent, get_port(sensor_path, 'RConn', 2), downstream_port);
    safe_add_line_handle(parent, get_port(sensor_path, 'RConn', 1), get_port(ps_path, 'LConn', 1));
    safe_add_line_handle(parent, get_port(ps_path, 'Outport', 1), get_port(toworkspace_path, 'Inport', 1));
end

function downstream_port = find_existing_heat_flow_downstream(sensor_path, gate_port)
    downstream_port = -1;
    if exist_block(sensor_path)
        try
            sensor_ports = get_param(sensor_path, 'PortHandles');
            downstream_port = downstream_port_from_sensor_port(sensor_ports.RConn(2));
            if downstream_port ~= -1
                return;
            end
            downstream_port = downstream_port_from_sensor_port(sensor_ports.RConn(1));
            if downstream_port ~= -1
                return;
            end
        catch
            downstream_port = -1;
        end
    end

    try
        original_line = get_param(gate_port, 'Line');
        if isnumeric(original_line) && original_line ~= -1
            downstream_port = get_param(original_line, 'DstPortHandle');
        end
    catch
        downstream_port = -1;
    end
end

function downstream_port = downstream_port_from_sensor_port(sensor_port)
    downstream_port = -1;
    try
        downstream_line = get_param(sensor_port, 'Line');
        if ~(isnumeric(downstream_line) && downstream_line ~= -1)
            return;
        end
        dst_block = get_param(downstream_line, 'DstBlockHandle');
        if isnumeric(dst_block) && dst_block ~= -1
            dst_name = getfullname(dst_block);
            if contains(dst_name, 'HeatFlowPS') || endsWith(dst_name, 'PS')
                return;
            end
        end
        candidate = get_param(downstream_line, 'DstPortHandle');
        if isnumeric(candidate) && candidate ~= -1
            downstream_port = candidate;
        end
    catch
        downstream_port = -1;
    end
end

function add_hhex_sma_branch_observability(model_name)
    hhex_path = find_hhex_with_sma_branch(model_name);
    if isempty(hhex_path)
        return;
    end
    add_tl_temperature_probe(hhex_path, 'HHEXSMAInletFluidTemp', ...
        get_port([hhex_path '/SMAHotPipe'], 'RConn', 1), ...
        'hhex_sma_branch_inlet_fluid_temp_out', ...
        [310 450 360 490], [395 459 425 481], [500 450 830 475]);
    add_tl_temperature_probe(hhex_path, 'HHEXSMAOutletFluidTemp', ...
        get_port([hhex_path '/SMAHotPipe'], 'LConn', 1), ...
        'hhex_sma_branch_outlet_fluid_temp_out', ...
        [310 535 360 575], [395 544 425 566], [500 535 830 560]);
end

function hhex_path = find_hhex_with_sma_branch(model_name)
    matches = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'Name', 'SMAHotPipe');
    if isempty(matches)
        hhex_path = '';
    else
        hhex_path = get_param(matches{1}, 'Parent');
    end
end

function apply_sma_stage13_visual_layout(model_name)
    layout = {
        'SHEXFluidBuffer', [-2100 130 -2060 170]
        'SMA_V1_SHEX_to_pump', [-1900 150 -1860 190]
        'SMA_V2_HHEX_to_pump', [-1900 660 -1860 700]
        'SMA_TJ_SourceSelect', [-1710 390 -1670 430]
        'SMA Pressure Source (TL)', [-1550 390 -1500 440]
        'FlowSensor_SMA_stage13_loop', [-1400 395 -1345 450]
        'SMA_TJ_PumpOutlet', [-1230 390 -1190 430]
        'SMA_V3_pump_to_heat_path', [-1060 250 -1020 290]
        'SMA_V4_pump_to_cool_path', [-1060 550 -1020 590]
        'SMA', [-900 370 -760 520]
        'SMA_V5_SMA_to_SHEX', [-700 515 -660 555]
        'SMA_V6_SMA_to_HHEX', [-700 710 -660 750]
        'SHEX', [-530 500 -445 560]
        'ToWorkspace_mass_flow_sma_stage13_kgps', [-1310 470 -1010 495]
    };
    for idx = 1:size(layout, 1)
        block_path = [model_name '/' layout{idx, 1}];
        if exist_block(block_path)
            set_param(block_path, 'Position', layout{idx, 2});
        end
    end
end

function [sensor_path, ps_path, toworkspace_path] = add_tl_temperature_probe(parent_path, probe_base_name, node_port_handle, variable_name, sensor_pos, ps_pos, workspace_pos)
    sensor_path = [parent_path '/' probe_base_name 'Sensor'];
    ps_path = [parent_path '/' probe_base_name 'PS'];
    toworkspace_path = [parent_path '/ToWorkspace_' variable_name];

    delete_block_if_present_with_lines(toworkspace_path);
    delete_block_if_present_with_lines(ps_path);
    delete_block_if_present_with_lines(sensor_path);

    add_block('fl_lib/Thermal Liquid/Sensors/Pressure & Temperature Sensor (TL)', sensor_path, ...
        'Position', sensor_pos, ...
        'pressure', 'false', ...
        'temperature', 'true');
    add_block('nesl_utility/PS-Simulink Converter', ps_path, ...
        'Position', ps_pos, ...
        'VectorFormat', '1-D array', ...
        'Unit', 'K');
    add_block('simulink/Sinks/To Workspace', toworkspace_path, ...
        'VariableName', variable_name, ...
        'SaveFormat', 'Structure With Time', ...
        'Position', workspace_pos);

    safe_add_line_handle(parent_path, node_port_handle, get_port(sensor_path, 'LConn', 1));
    safe_add_line_handle(parent_path, get_port(sensor_path, 'RConn', 1), get_port(ps_path, 'LConn', 1));
    safe_add_line_handle(parent_path, get_port(ps_path, 'Outport', 1), get_port(toworkspace_path, 'Inport', 1));
end

function add_workspace_alias_from_ps(parent_path, ps_path, alias_block_name, variable_name, workspace_pos)
    alias_path = [parent_path '/' alias_block_name];
    delete_block_if_present_with_lines(alias_path);
    add_block('simulink/Sinks/To Workspace', alias_path, ...
        'VariableName', variable_name, ...
        'SaveFormat', 'Structure With Time', ...
        'Position', workspace_pos);
    safe_add_line_handle(parent_path, get_port(ps_path, 'Outport', 1), get_port(alias_path, 'Inport', 1));
end

function delete_block_if_present_with_lines(block_path)
    if ~exist_block(block_path)
        return;
    end
    ports = get_param(block_path, 'PortHandles');
    port_groups = fieldnames(ports);
    for group_idx = 1:numel(port_groups)
        handles = ports.(port_groups{group_idx});
        for handle_idx = 1:numel(handles)
            delete_line_at_port(handles(handle_idx));
        end
    end
    try
        delete_block(block_path);
    catch
    end
end

function make_to_workspace_names_unique(model_name)
    blocks = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'BlockType', 'ToWorkspace');
    if isempty(blocks)
        return;
    end
    variable_names = cell(size(blocks));
    for idx = 1:numel(blocks)
        variable_names{idx} = get_param(blocks{idx}, 'VariableName');
    end
    used = variable_names(:);
    unique_names = unique(variable_names);
    for idx = 1:numel(unique_names)
        name = unique_names{idx};
        duplicate_idx = find(strcmp(variable_names, name));
        if numel(duplicate_idx) < 2
            continue;
        end
        keep = select_duplicate_to_workspace_keeper(blocks(duplicate_idx));
        for item = duplicate_idx(:).'
            if item == duplicate_idx(keep)
                continue;
            end
            prefix = workspace_prefix_for_block(blocks{item}, model_name);
            new_name = matlab.lang.makeValidName([prefix '_' name]);
            new_name = make_unique_name(new_name, used);
            set_param(blocks{item}, 'VariableName', new_name);
            used{end + 1, 1} = new_name; %#ok<AGROW>
        end
    end
end

function keep = select_duplicate_to_workspace_keeper(blocks)
    keep = find(~contains(blocks, '/SHEX/'), 1, 'first');
    if isempty(keep)
        keep = 1;
    end
end

function prefix = workspace_prefix_for_block(block_path, model_name)
    rel = erase(block_path, [model_name '/']);
    parts = strsplit(rel, '/');
    if any(strcmp(parts, 'SHEX'))
        prefix = 'SHEX';
    elseif any(strcmp(parts, 'SMA'))
        prefix = 'SMA';
    elseif any(strcmp(parts, 'SE'))
        prefix = 'SE';
    else
        prefix = matlab.lang.makeValidName(parts{1});
        if isempty(prefix)
            prefix = 'probe';
        end
    end
end

function name = make_unique_name(base_name, used)
    name = base_name;
    suffix = 2;
    while any(strcmp(used, name))
        name = sprintf('%s_%d', base_name, suffix);
        suffix = suffix + 1;
    end
end

function ensure_block(library_path, block_path, varargin)
    if ~exist_block(block_path)
        add_block(library_path, block_path, varargin{:});
    else
        for idx = 1:2:numel(varargin)
            set_param(block_path, varargin{idx}, varargin{idx + 1});
        end
    end
end

function safe_add_line(system_path, source, destination)
    destination_handle = signal_destination_handle(system_path, destination);
    if destination_handle ~= -1 && has_line(destination_handle)
        return;
    end
    try
        add_line(system_path, source, destination, 'autorouting', 'on');
    catch ME
        if ~is_existing_line_error(ME)
            rethrow(ME);
        end
    end
end

function safe_add_line_handle(system_path, source_handle, destination_handle)
    try
        add_line(system_path, source_handle, destination_handle, 'autorouting', 'on');
    catch
        % Reruns can encounter existing Simscape conserving-connection
        % branches. Compilation checks below catch real missing topology.
    end
end

function delete_line_at_port(port_handle)
    try
        line_handle = get_param(port_handle, 'Line');
        if isnumeric(line_handle) && line_handle ~= -1
            delete_line(line_handle);
        end
    catch
    end
end

function tf = is_existing_line_error(ME)
    msg = ME.message;
    tf = contains(msg, 'already has a line') || ...
        contains(msg, 'There is already a line') || ...
        contains(msg, 'already connected');
end

function tf = has_line(port_handle)
    try
        line_handle = get_param(port_handle, 'Line');
        tf = isnumeric(line_handle) && line_handle ~= -1;
    catch
        tf = false;
    end
end

function handle = signal_destination_handle(system_path, destination)
    handle = -1;
    parts = regexp(destination, '^(.*)/(\d+)$', 'tokens', 'once');
    if isempty(parts)
        return;
    end
    block_path = [system_path '/' parts{1}];
    port_idx = str2double(parts{2});
    if ~exist_block(block_path) || ~isfinite(port_idx)
        return;
    end
    ports = get_param(block_path, 'PortHandles');
    if numel(ports.Inport) >= port_idx
        handle = ports.Inport(port_idx);
    end
end

function handle = get_port(block_path, kind, idx)
    ports = get_param(block_path, 'PortHandles');
    handle = ports.(kind)(idx);
end

function tf = exist_block(block_path)
    try
        get_param(block_path, 'Handle');
        tf = true;
    catch
        tf = false;
    end
end

function add_or_update_note(model_name)
    tag = 'ECC_Constitutive21_Interface_Note';
    existing = find_system(model_name, 'FindAll', 'on', ...
        'Type', 'annotation', 'Tag', tag);
    for idx = 1:numel(existing)
        try
            delete(existing(idx));
        catch
        end
    end
    text = ['21-node coupled constitutive interface installed.', newline, ...
        'SMA and SE remain independent thermal/flow modules.', newline, ...
        'Global vector step solves coupled stress/strain/phase state and injects latent/mechanical heat sources into both 21-node solids.'];
    ann = Simulink.Annotation(model_name, text);
    ann.Tag = tag;
    ann.Position = [690 1030 1420 1080];
end
