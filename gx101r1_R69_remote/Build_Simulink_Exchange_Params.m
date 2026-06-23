function sim_params = Build_Simulink_Exchange_Params(state_in, stage_config, exchange_options)
% Assemble the MATLAB variables expected by the 21-node axial SE Simulink model.

    if nargin < 3 || isempty(exchange_options)
        exchange_options = struct();
    end

    state_std = standardize_globalxi_exchange_state(state_in);
    runtime = get_option_field(exchange_options, 'runtime', struct());
    T_init = extract_temperature_vector(state_std);
    state_node_count = numel(T_init);
    exchange_backend_kind = normalize_exchange_backend_kind(get_option_field( ...
        exchange_options, 'exchange_backend_kind', 'simulink_axial_21'));
    thermal_model_node_count = get_option_field(exchange_options, ...
        'simulink_internal_node_count', 21);
    if state_node_count ~= thermal_model_node_count
        error('Build_Simulink_Exchange_Params:UnexpectedNodeCount', ...
            ['The SE Simulink exchange interface is 21-node axial. ', ...
            'Expected %d temperature values, got %d.'], ...
            thermal_model_node_count, state_node_count);
    end

    radius_m = get_option_field(exchange_options, 'radius_m', 40e-3);
    thickness_m = get_option_field(exchange_options, 'thickness_m', 0.20e-3);
    sma_density_kg_per_m3 = get_option_field(exchange_options, 'rho_sma', ...
        get_option_field(exchange_options, 'rho', 6500.0));
    sma_physical_mass_kg = sma_density_kg_per_m3 * pi * radius_m ^ 2 * thickness_m;
    if isfield(exchange_options, 'total_mass') && ~isempty(exchange_options.total_mass)
        total_mass = exchange_options.total_mass;
        sma_mass_source = 'exchange_options.total_mass';
    else
        total_mass = sma_physical_mass_kg;
        sma_mass_source = 'rho_sma*pi*R^2*t_delta';
    end
    sma_mass_consistency_ratio = total_mass / max(sma_physical_mass_kg, eps);
    sma_mass_contract_ok = isfinite(sma_mass_consistency_ratio) && ...
        sma_mass_consistency_ratio >= 0.95 && sma_mass_consistency_ratio <= 1.05;
    node_cp = get_option_field(exchange_options, 'node_cp', 450);
    cond_k = get_option_field(exchange_options, 'cond_k', 18);
    cond_dx = get_option_field(exchange_options, 'cond_dx', radius_m / max(thermal_model_node_count - 1, 1));
    cond_area_default = max(2 * pi * radius_m * thickness_m / thermal_model_node_count, 1.0e-7);
    cond_area = get_option_field(exchange_options, 'cond_area', cond_area_default);

    D_inner = get_option_field(exchange_options, 'D_inner', 3e-3);
    D_outer = get_option_field(exchange_options, 'D_outer', 5e-3);
    tube_l = get_option_field(exchange_options, 'tube_l', 0.1481);
    rho_water = get_option_field(exchange_options, 'rho_water', 998.0);
    mu_water = get_option_field(exchange_options, 'mu_water', 1.0e-3);
    k_water = get_option_field(exchange_options, 'k_water', 0.6);
    cp_water = get_option_field(exchange_options, 'cp_water', 4180.0);
    Pr = get_option_field(exchange_options, 'Pr', cp_water * mu_water / max(k_water, eps));
    viscosity_ratio = get_option_field(exchange_options, 'viscosity_ratio', 1.0);

    ambient_T_init = get_stage_field(stage_config, 'ambient_T_init', get_option_field(exchange_options, 'ambient_T_init', 293.0));
    hot_sink_T_init = get_stage_field(stage_config, 'hot_sink_T_in', get_option_field(exchange_options, 'hot_sink_T_init', 293.0));
    cold_sink_T_init = get_stage_field(stage_config, 'cold_sink_T_in', get_option_field(exchange_options, 'cold_sink_T_init', 293.0));
    shex_sink_T_init = get_option_field(exchange_options, 'shex_sink_T_init', hot_sink_T_init);
    shex_source_T_init = get_option_field(exchange_options, 'shex_source_T_init', shex_sink_T_init);
    cold_load_mode = char(string(get_option_field(exchange_options, 'cold_load_mode', 'constant_load')));
    cold_load_T_init = get_stage_field(stage_config, 'cold_load_T_in', get_stage_field(stage_config, ...
        'chip_T_in', get_option_field(exchange_options, 'cold_load_T_init', get_option_field(exchange_options, 'chip_T_init', 293.0))));
    chip_T_init = cold_load_T_init;
    % R50: root TL buffers are solver-side fluid containers. They do not
    % represent independent paper-level thermal accumulators.
    buffer_follow_sink_enabled = logical(get_option_field(exchange_options, ...
        'buffer_follow_sink_enabled', true));
    if buffer_follow_sink_enabled
        hot_buffer_temp_current = hot_sink_T_init;
        cold_buffer_temp_current = cold_sink_T_init;
        buffer_follow_sink_policy_source = ...
            'r50_each_stage_init_equals_corresponding_side_sink_T';
    else
        hot_buffer_temp_current = get_stage_field(stage_config, 'hot_buffer_T_in', ...
            get_option_field(exchange_options, 'hot_buffer_temp_current', hot_sink_T_init));
        cold_buffer_temp_current = get_stage_field(stage_config, 'cold_buffer_T_in', ...
            get_option_field(exchange_options, 'cold_buffer_temp_current', cold_sink_T_init));
        buffer_follow_sink_policy_source = 'legacy_raw_carry_from_previous_stage_runtime';
    end
    hot_sink_C = get_option_field(exchange_options, 'hot_sink_C_J_per_K', 41.8);
    cold_sink_C = get_option_field(exchange_options, 'cold_sink_C_J_per_K', 4.18);
    cold_load_C = get_option_field(exchange_options, 'cold_load_C_J_per_K', ...
        get_option_field(exchange_options, 'chip_C_J_per_K', 5.0));
    chip_C = cold_load_C;
    hot_sink_ambient_G = get_option_field(exchange_options, 'hot_sink_ambient_G_W_per_K', 30.0);
    cold_sink_ambient_G_configured = get_option_field(exchange_options, 'cold_sink_ambient_G_W_per_K', 1.0e-12);
    cold_sink_ambient_G_hold = get_option_field(exchange_options, ...
        'cold_sink_ambient_G_hold_W_per_K', 1.0e-12);
    cold_sink_ambient_G_cooldown = get_option_field(exchange_options, ...
        'cold_sink_ambient_G_cooldown_W_per_K', cold_sink_ambient_G_configured);
    cold_load_ambient_G = get_option_field(exchange_options, 'cold_load_ambient_G_W_per_K', ...
        get_option_field(exchange_options, 'chip_ambient_G_W_per_K', 1.0e-12));
    chip_ambient_G = cold_load_ambient_G;
    cold_load_heat_default_W = get_option_field(exchange_options, 'chip_heat_W', 0.0);
    cold_load_heat_W = get_option_field(exchange_options, 'cold_load_heat_W', cold_load_heat_default_W);
    cold_load_to_cold_sink_G_hold = get_option_field(exchange_options, ...
        'cold_load_to_cold_sink_G_hold_W_per_K', 1.0e-12);
    cold_load_to_cold_sink_G_cooldown = get_option_field(exchange_options, ...
        'cold_load_to_cold_sink_G_cooldown_W_per_K', get_option_field(exchange_options, ...
        'cold_load_to_cold_sink_G_W_per_K', get_option_field(exchange_options, ...
        'chip_fluid_G_cooldown_W_per_K', get_option_field(exchange_options, 'chip_fluid_G_W_per_K', 0.4))));
    stage_name = char(string(get_stage_field(stage_config, 'stage_name', '')));
    cold_sink_fluid_G_hold = get_option_field(exchange_options, ...
        'cold_sink_fluid_G_hold_W_per_K', 1.0e-12);
    cold_sink_fluid_G_cooldown = get_option_field(exchange_options, ...
        'cold_sink_fluid_G_cooldown_W_per_K', get_option_field(exchange_options, ...
        'cold_sink_fluid_G_W_per_K', 20.0));
    if strcmpi(stage_name, 'hold_exchange')
        cold_load_to_cold_sink_G = cold_load_to_cold_sink_G_hold;
        cold_load_coupling_stage_policy = 'isolated_during_hold_exchange';
        cold_sink_fluid_G = cold_sink_fluid_G_hold;
        cold_sink_ambient_G = cold_sink_ambient_G_hold;
        cold_sink_stage_coupling_policy = 'cold_sink_mass_frozen_during_hold_exchange';
    elseif strcmpi(stage_name, 'cooldown_exchange')
        cold_load_to_cold_sink_G = cold_load_to_cold_sink_G_cooldown;
        cold_load_coupling_stage_policy = 'coupled_to_CHEX_during_cooldown_exchange';
        cold_sink_fluid_G = cold_sink_fluid_G_cooldown;
        cold_sink_ambient_G = cold_sink_ambient_G_cooldown;
        cold_sink_stage_coupling_policy = 'cold_sink_mass_coupled_to_CHEX_during_cooldown_exchange';
    else
        cold_load_to_cold_sink_G = 1.0e-12;
        cold_load_coupling_stage_policy = 'isolated_during_non_exchange_stage';
        cold_sink_fluid_G = cold_sink_fluid_G_hold;
        cold_sink_ambient_G = cold_sink_ambient_G_hold;
        cold_sink_stage_coupling_policy = 'cold_sink_mass_frozen_during_non_exchange_stage';
    end
    switch lower(strtrim(cold_load_mode))
        case 'no_load'
            cold_load_heat_W = 0.0;
            cold_load_to_cold_sink_G = 1.0e-12;
            cold_load_ambient_G = 1.0e-12;
            cold_load_coupling_stage_policy = ['no_load_', cold_load_coupling_stage_policy];
        case 'constant_load'
            % keep configured values
        otherwise
            error('Build_Simulink_Exchange_Params:UnsupportedColdLoadMode', ...
                'Unsupported cold_load_mode: %s', cold_load_mode);
    end
    chip_heat_dry_equilibrium_W = cold_load_ambient_G * max(cold_load_T_init - ambient_T_init, 0.0);
    chip_heat_default_W = cold_load_heat_default_W;
    chip_heat_W = cold_load_heat_W;
    probe_sample_count = max(2, round(get_option_field(exchange_options, 'probe_sample_count', 50)));
    hot_sink_fluid_G = get_option_field(exchange_options, 'hot_sink_fluid_G_W_per_K', 20.0);
    chip_fluid_G_cooldown_configured = cold_load_to_cold_sink_G;
    chip_fluid_G_hold = get_option_field(exchange_options, 'chip_fluid_G_hold_W_per_K', 1.0e-9);
    thermal_mass_cp_ref = get_option_field(exchange_options, 'thermal_mass_cp_ref', 500.0);
    fluid_buffer_cp_ref = get_option_field(exchange_options, 'fluid_buffer_cp_ref', cp_water);

    stage_duration_s = get_stage_field(stage_config, 'stop_time_s', NaN);
    if ~isfinite(stage_duration_s) || stage_duration_s <= 0
        error('Build_Simulink_Exchange_Params:InvalidStopTime', ...
            'stage_config.stop_time_s must be finite and positive.');
    end

    plate_volume_m3 = pi * radius_m ^ 2 * thickness_m;
    flush_volume_target_ratio = get_option_field(exchange_options, 'flush_volume_target_ratio', 1.0);
    use_closed_valve_flow = isfield(stage_config, 'all_valves_closed') && logical(stage_config.all_valves_closed);
    target_flush_volume_ratio = flush_volume_target_ratio;
    target_flush_volume_m3 = target_flush_volume_ratio * plate_volume_m3;
    sma_stage13_nominal_mdot_target_kgps = rho_water * target_flush_volume_m3 / max(stage_duration_s, eps);
    if use_closed_valve_flow
        target_flush_volume_ratio = 0.0;
        target_flush_volume_m3 = 0.0;
    end
    Q_target_m3ps = target_flush_volume_m3 / max(stage_duration_s, eps);
    mdot_target_kgps = rho_water * Q_target_m3ps;

    legacy_D_inner = D_inner;
    legacy_D_outer = D_outer;
    legacy_tube_A_m2 = pi * (legacy_D_outer ^ 2 - legacy_D_inner ^ 2) / 4;
    legacy_active_sma_pipe_internal_volume_m3 = legacy_tube_A_m2 * tube_l;
    legacy_pipe_internal_fluid_C_J_per_K = rho_water * cp_water * legacy_active_sma_pipe_internal_volume_m3;
    sma_pipe_internal_volume_target_ml = get_option_field(exchange_options, ...
        'sma_pipe_internal_volume_target_ml', 0.1);
    sma_pipe_internal_volume_target_m3 = get_option_field(exchange_options, ...
        'sma_pipe_internal_volume_target_m3', sma_pipe_internal_volume_target_ml * 1.0e-6);
    sma_pipe_volume_calibration_mode = char(string(get_option_field(exchange_options, ...
        'sma_pipe_volume_calibration_mode', 'hydraulic_resistance_preserving_volume_v1')));
    if ~isfinite(sma_pipe_internal_volume_target_m3) || sma_pipe_internal_volume_target_m3 <= 0
        sma_pipe_volume_calibration_mode = 'legacy';
    end
    normalized_pipe_volume_mode = lower(strtrim(sma_pipe_volume_calibration_mode));
    sma_pipe_storage_l = tube_l;
    sma_pipe_hydraulic_length_add_l = 0.0;
    sma_pipe_hydraulic_resistance_strategy = 'legacy_full_length_storage';
    if strcmpi(normalized_pipe_volume_mode, 'legacy')
        tube_A_m2 = legacy_tube_A_m2;
        pipe_fa = tube_A_m2;
        sma_pipe_internal_volume_target_m3 = legacy_active_sma_pipe_internal_volume_m3;
        sma_pipe_internal_volume_target_ml = sma_pipe_internal_volume_target_m3 * 1.0e6;
        sma_pipe_volume_calibration_mode = 'legacy';
    elseif ismember(normalized_pipe_volume_mode, ...
            {'target_internal_volume', 'area_shrinkage_target_volume', 'target_internal_volume_area_shrinkage'})
        % Deprecated comparison mode: it hits the liquid storage target by
        % shrinking flow area, but also changes hydraulic resistance strongly.
        pipe_fa = sma_pipe_internal_volume_target_m3 / max(tube_l, eps);
        tube_A_m2 = pipe_fa;
        D_outer = sqrt(max(D_inner ^ 2 + 4 * tube_A_m2 / pi, D_inner ^ 2 + eps));
        sma_pipe_storage_l = tube_l;
        sma_pipe_hydraulic_length_add_l = 0.0;
        sma_pipe_volume_calibration_mode = 'target_internal_volume_area_shrinkage';
        sma_pipe_hydraulic_resistance_strategy = 'area_shrinkage_deprecated_changes_hydraulic_resistance';
    else
        % Mainline mode: keep the legacy flow area / hydraulic diameter and
        % shorten only the thermally-stored liquid length. The remaining
        % length is restored through Pipe(TL) length_add, so the pressure
        % loss scale stays close to the legacy hydraulic path.
        pipe_fa = legacy_tube_A_m2;
        tube_A_m2 = legacy_tube_A_m2;
        D_inner = legacy_D_inner;
        D_outer = legacy_D_outer;
        sma_pipe_storage_l = sma_pipe_internal_volume_target_m3 / max(pipe_fa, eps);
        if sma_pipe_storage_l > tube_l
            sma_pipe_storage_l = tube_l;
            sma_pipe_internal_volume_target_m3 = pipe_fa * sma_pipe_storage_l;
            sma_pipe_internal_volume_target_ml = sma_pipe_internal_volume_target_m3 * 1.0e6;
            sma_pipe_volume_calibration_mode = 'hydraulic_resistance_preserving_volume_v1_capped_at_legacy_volume';
        else
            sma_pipe_volume_calibration_mode = 'hydraulic_resistance_preserving_volume_v1';
        end
        sma_pipe_hydraulic_length_add_l = max(tube_l - sma_pipe_storage_l, 0.0);
        sma_pipe_hydraulic_resistance_strategy = 'keep_area_and_Dh_restore_length_with_length_add';
    end
    tube_A = tube_A_m2 * 1e6;
    D_e = D_outer - D_inner;
    sma_pipe_hydraulic_total_l = sma_pipe_storage_l + sma_pipe_hydraulic_length_add_l;
    sma_pipe_storage_length_fraction = sma_pipe_storage_l / max(tube_l, eps);
    L = max(sma_pipe_hydraulic_total_l, sma_pipe_storage_l);
    active_sma_pipe_internal_volume_m3 = pipe_fa * sma_pipe_storage_l;
    pipe_internal_fluid_C_J_per_K = rho_water * cp_water * active_sma_pipe_internal_volume_m3;
    pipe_internal_volume_to_plate_volume_ratio = active_sma_pipe_internal_volume_m3 / max(plate_volume_m3, eps);
    pipe_internal_volume_to_flush_volume_ratio = active_sma_pipe_internal_volume_m3 / max(target_flush_volume_m3, eps);
    V_star_vs_SMA = target_flush_volume_m3 / max(plate_volume_m3, eps);
    V_star_vs_pipe = target_flush_volume_m3 / max(active_sma_pipe_internal_volume_m3, eps);

    if isfield(exchange_options, 'v_water') && ~isempty(exchange_options.v_water)
        v_water = exchange_options.v_water;
    elseif use_closed_valve_flow
        v_water = 0.0;
    else
        v_water = Q_target_m3ps / max(tube_A_m2, eps);
    end

    Re = (rho_water * v_water * D_e) / max(mu_water, eps);
    [Nu_uncapped, correlation_name, flow_regime] = compute_nusselt_number( ...
        Re, Pr, D_inner, D_outer, D_e, L, viscosity_ratio);
    h_conv = (Nu_uncapped * k_water) / max(D_e, eps);
    h_water_uncapped = h_conv;
    h_water_scale = get_option_field(exchange_options, 'h_water_scale', 1.0);
    h_water_scaled_uncapped = h_conv * h_water_scale;
    contact_resistance = get_option_field(exchange_options, 'contact_resistance_m2K_per_W', 0.0);
    wall_resistance = get_option_field(exchange_options, 'wall_resistance_m2K_per_W', 0.0);
    spreading_resistance = get_option_field(exchange_options, 'spreading_resistance_m2K_per_W', 0.0);
    wetting_efficiency = get_option_field(exchange_options, 'wetting_efficiency', 1.0);
    wetting_efficiency = min(max(wetting_efficiency, 0.0), 1.0);
    resistance_area = 1.0 / max(h_water_scaled_uncapped, eps) + ...
        max(contact_resistance, 0.0) + max(wall_resistance, 0.0) + max(spreading_resistance, 0.0);
    U_eff = 1.0 / max(resistance_area, eps);
    h_water_effective_uncapped = U_eff * wetting_efficiency;
    enable_h_water_cap = logical(get_option_field(exchange_options, 'enable_h_water_cap', false));
    h_water_cap = get_option_field(exchange_options, 'h_water_cap_W_per_m2K', Inf);
    if enable_h_water_cap
        h_water = min(h_water_effective_uncapped, h_water_cap);
    else
        h_water = h_water_effective_uncapped;
        h_water_cap = Inf;
    end
    h_water_cap_active = enable_h_water_cap && ...
        h_water < h_water_effective_uncapped - 10 * eps(max(abs(h_water_effective_uncapped), 1.0));
    Nu = h_water * max(D_e, eps) / max(k_water, eps);
    Q = tube_A_m2 * v_water;
    flush_volume_m3 = Q * stage_duration_s;
    flush_volume_ratio = flush_volume_m3 / max(plate_volume_m3, eps);
    chip_model = compute_chip_fluid_conductance(exchange_options, stage_name, ...
        Q_target_m3ps, rho_water, mu_water, k_water, cp_water, Pr);
    chip_fluid_G = cold_load_to_cold_sink_G;
    chip_fluid_coupling_mode = ['cold_load_', lower(strtrim(cold_load_mode))];
    chip_model.chip_fluid_G_effective_W_per_K = chip_fluid_G;
    water_contact_area_m2 = get_option_field(exchange_options, 'water_contact_area_m2', pi * radius_m ^ 2);
    UA_sma = h_water * water_contact_area_m2;
    requested_flow_control_mode = char(string(get_option_field(exchange_options, ...
        'flow_control_mode', 'target_duty_pressure_v1')));
    pressure_control_reference_pressure_MPa = get_option_field(exchange_options, ...
        'pressure_control_reference_pressure_MPa', 0.1);
    pressure_control_direction_sign = get_option_field(exchange_options, ...
        'pressure_control_direction_sign', -1.0);
    pressure_control_reference_duration_s = get_option_field(exchange_options, ...
        'pressure_control_reference_duration_s', 0.4);
    if ~(isfinite(pressure_control_reference_duration_s) && pressure_control_reference_duration_s > 0)
        error('Build_Simulink_Exchange_Params:InvalidPressureReferenceDuration', ...
            'pressure_control_reference_duration_s must be finite and positive.');
    end
    if strcmpi(get_stage_field(stage_config, 'stage_name', ''), 'hold_exchange')
        pressure_control_reference_actual_flush_ratio = get_option_field(exchange_options, ...
            'pressure_control_reference_actual_flush_ratio_hold', 0.6132);
        pressure_control_duration_exponent = get_option_field(exchange_options, ...
            'pressure_control_duration_exponent_hold', 0.95);
    elseif strcmpi(get_stage_field(stage_config, 'stage_name', ''), 'cooldown_exchange')
        pressure_control_reference_actual_flush_ratio = get_option_field(exchange_options, ...
            'pressure_control_reference_actual_flush_ratio_cooldown', 0.5909);
        pressure_control_duration_exponent = get_option_field(exchange_options, ...
            'pressure_control_duration_exponent_cooldown', 1.00);
    else
        pressure_control_reference_actual_flush_ratio = max(target_flush_volume_ratio, 1.0);
        pressure_control_duration_exponent = get_option_field(exchange_options, ...
            'pressure_control_duration_exponent', 1.00);
    end
    pressure_control_exponent = get_option_field(exchange_options, 'pressure_control_exponent', 1.0);
    pressure_control_target_ratio_scale = target_flush_volume_ratio / max(pressure_control_reference_actual_flush_ratio, eps);
    pressure_control_duration_scale = pressure_control_reference_duration_s / max(stage_duration_s, eps);
    pressure_control_duration_scale_adjusted = max(pressure_control_duration_scale, 0.0) ^ pressure_control_duration_exponent;
    pressure_control_flow_scale = pressure_control_target_ratio_scale * pressure_control_duration_scale_adjusted;
    duty_audit_ignore_initial_s = compute_audit_ignore_initial_s(stage_name, exchange_options, stage_duration_s);
    duty_reference_window_s = max(pressure_control_reference_duration_s - ...
        min(duty_audit_ignore_initial_s, pressure_control_reference_duration_s), eps);
    duty_stage_window_s = max(stage_duration_s - ...
        min(duty_audit_ignore_initial_s, stage_duration_s), eps);
    pressure_control_duty_capacity_ratio = target_flush_volume_ratio * ...
        duty_reference_window_s / duty_stage_window_s;
    pressure_control_duty_pressure_capacity_ratio = max(pressure_control_duty_capacity_ratio, 1.0);
    if strcmpi(get_stage_field(stage_config, 'stage_name', ''), 'cooldown_exchange')
        if stage_duration_s < pressure_control_reference_duration_s && target_flush_volume_ratio <= 1.0
            cooldown_duty_exponent_default = 3.20;
        else
            cooldown_duty_exponent_default = 0.75;
        end
        pressure_control_duty_capacity_exponent = get_option_field(exchange_options, ...
            'pressure_control_duty_capacity_exponent_cooldown', get_option_field(exchange_options, ...
            'pressure_control_duty_capacity_exponent', cooldown_duty_exponent_default));
    else
        pressure_control_duty_capacity_exponent = get_option_field(exchange_options, ...
            'pressure_control_duty_capacity_exponent_hold', get_option_field(exchange_options, ...
            'pressure_control_duty_capacity_exponent', 0.25));
    end
    pressure_control_duty_flow_scale = ...
        max(pressure_control_duty_pressure_capacity_ratio, 0.0) ^ pressure_control_duty_capacity_exponent / ...
        max(pressure_control_reference_actual_flush_ratio, eps);
    mdot_root_source_kgps = 0.0;
    mdot_hold_source_kgps = 0.0;
    mdot_cooldown_source_kgps = 0.0;
    mdot_source_kgps = 0.0;
    Q_source_m3ps = Q_target_m3ps;
    root_bypass_restriction_area_m2 = max(pipe_fa * 1.0e-6, 1.0e-12);
    pressure_pi_normalized_error_enabled = logical(get_option_field( ...
        exchange_options, 'pressure_pi_normalized_error_enabled', false));
    if pressure_pi_normalized_error_enabled
        pressure_pi_kp_default = -0.0025;
        pressure_pi_ki_default = -0.0125;
    else
        pressure_pi_kp_default = -1.0;
        pressure_pi_ki_default = -2.0;
    end
    pressure_pi_kp_MPa_per_kgps = get_option_field(exchange_options, ...
        'pressure_pi_kp_MPa_per_kgps', pressure_pi_kp_default);
    pressure_pi_ki_MPa_per_kgps_s = get_option_field(exchange_options, ...
        'pressure_pi_ki_MPa_per_kgps_s', pressure_pi_ki_default);
    pressure_pi_bias_MPa = get_option_field(exchange_options, 'pressure_pi_bias_MPa', -0.003);
    pressure_pi_min_MPa = get_option_field(exchange_options, 'pressure_pi_min_MPa', -0.02);
    pressure_pi_max_MPa = get_option_field(exchange_options, 'pressure_pi_max_MPa', 0.02);
    pressure_pi_hydraulic_scheduling_enabled = logical(get_option_field(exchange_options, ...
        'pressure_pi_hydraulic_scheduling_enabled', strcmpi(requested_flow_control_mode, 'pressure_pi_feedback_v1')));
    root_manifold_split_mode = lower(strtrim(char(string(get_option_field( ...
        exchange_options, 'root_manifold_split_mode', 'none')))));
    if isempty(root_manifold_split_mode)
        root_manifold_split_mode = 'none';
    end
    cold_end_topology_mode = lower(strtrim(char(string(get_option_field( ...
        exchange_options, 'cold_end_topology_mode', 'r69_symmetric')))));
    if any(strcmp(cold_end_topology_mode, {'', 'current'}))
        cold_end_topology_mode = 'r69_symmetric';
    elseif any(strcmp(cold_end_topology_mode, {'r68', 'split', 'r68_split'}))
        cold_end_topology_mode = 'r68_split';
    elseif any(strcmp(cold_end_topology_mode, {'r69', 'symmetric', 'single_pipe', 'no_transit'}))
        cold_end_topology_mode = 'r69_symmetric';
    elseif ~strcmp(cold_end_topology_mode, 'r69_symmetric')
        cold_end_topology_mode = 'r69_symmetric';
    end
    pressure_pi_bias_ref_MPa_unsplit = get_option_field(exchange_options, 'pressure_pi_bias_ref_MPa', ...
        get_option_field(exchange_options, 'pressure_pi_bias_MPa', -0.003));
    if ~(isnumeric(pressure_pi_bias_ref_MPa_unsplit) && isscalar(pressure_pi_bias_ref_MPa_unsplit) && ...
            isfinite(pressure_pi_bias_ref_MPa_unsplit))
        pressure_pi_bias_ref_MPa_unsplit = -0.003;
    end
    pressure_pi_bias_ref_MPa_split_mode = get_option_field(exchange_options, ...
        'pressure_pi_bias_ref_MPa_split_mode', -0.002);
    if ~(isnumeric(pressure_pi_bias_ref_MPa_split_mode) && isscalar(pressure_pi_bias_ref_MPa_split_mode) && ...
            isfinite(pressure_pi_bias_ref_MPa_split_mode))
        pressure_pi_bias_ref_MPa_split_mode = -0.002;
    end
    pressure_pi_bias_ref_MPa_split_hold = get_option_field(exchange_options, ...
        'pressure_pi_bias_ref_MPa_split_hold_MPa', pressure_pi_bias_ref_MPa_split_mode);
    if ~(isnumeric(pressure_pi_bias_ref_MPa_split_hold) && isscalar(pressure_pi_bias_ref_MPa_split_hold) && ...
            isfinite(pressure_pi_bias_ref_MPa_split_hold))
        pressure_pi_bias_ref_MPa_split_hold = pressure_pi_bias_ref_MPa_split_mode;
    end
    pressure_pi_bias_ref_MPa_split_cooldown = get_option_field(exchange_options, ...
        'pressure_pi_bias_ref_MPa_split_cooldown_MPa', pressure_pi_bias_ref_MPa_split_mode);
    if ~(isnumeric(pressure_pi_bias_ref_MPa_split_cooldown) && isscalar(pressure_pi_bias_ref_MPa_split_cooldown) && ...
            isfinite(pressure_pi_bias_ref_MPa_split_cooldown))
        pressure_pi_bias_ref_MPa_split_cooldown = pressure_pi_bias_ref_MPa_split_mode;
    end
    if strcmpi(root_manifold_split_mode, 'r63_full_split')
        if strcmpi(stage_name, 'hold_exchange')
            pressure_pi_bias_ref_MPa = pressure_pi_bias_ref_MPa_split_hold;
        elseif strcmpi(stage_name, 'cooldown_exchange')
            pressure_pi_bias_ref_MPa = pressure_pi_bias_ref_MPa_split_cooldown;
        else
            pressure_pi_bias_ref_MPa = pressure_pi_bias_ref_MPa_split_mode;
        end
    else
        pressure_pi_bias_ref_MPa = pressure_pi_bias_ref_MPa_unsplit;
        if strcmpi(stage_name, 'hold_exchange')
            pressure_pi_bias_ref_MPa = get_option_field(exchange_options, ...
                'pressure_pi_bias_ref_hold_MPa', pressure_pi_bias_ref_MPa);
        elseif strcmpi(stage_name, 'cooldown_exchange')
            pressure_pi_bias_ref_MPa = get_option_field(exchange_options, ...
                'pressure_pi_bias_ref_cooldown_MPa', pressure_pi_bias_ref_MPa);
        end
    end
    pressure_pi_mdot_scale_exponent = get_option_field(exchange_options, ...
        'pressure_pi_mdot_scale_exponent', 2.0);
    if strcmpi(root_manifold_split_mode, 'r63_full_split')
        split_exponent = get_option_field(exchange_options, ...
            'pressure_pi_mdot_scale_exponent_split_mode', pressure_pi_mdot_scale_exponent);
        if strcmpi(stage_name, 'hold_exchange')
            pressure_pi_mdot_scale_exponent = get_option_field(exchange_options, ...
                'pressure_pi_mdot_scale_exponent_split_hold', split_exponent);
        elseif strcmpi(stage_name, 'cooldown_exchange')
            pressure_pi_mdot_scale_exponent = get_option_field(exchange_options, ...
                'pressure_pi_mdot_scale_exponent_split_cooldown', split_exponent);
        else
            pressure_pi_mdot_scale_exponent = split_exponent;
        end
    end
    if ~(isnumeric(pressure_pi_mdot_scale_exponent) && isscalar(pressure_pi_mdot_scale_exponent) && ...
            isfinite(pressure_pi_mdot_scale_exponent) && pressure_pi_mdot_scale_exponent > 0)
        pressure_pi_mdot_scale_exponent = 2.0;
    end
    pressure_pi_mdot_scale_piecewise_enabled = logical(get_option_field(exchange_options, ...
        'pressure_pi_mdot_scale_piecewise_enabled', strcmpi(requested_flow_control_mode, 'pressure_pi_feedback_v1')));
    pressure_pi_mdot_scale_exponent_low = get_option_field(exchange_options, ...
        'pressure_pi_mdot_scale_exponent_low', 0.10);
    pressure_pi_mdot_scale_exponent_high = get_option_field(exchange_options, ...
        'pressure_pi_mdot_scale_exponent_high', 0.50);
    pressure_pi_mdot_scale_piecewise_threshold = get_option_field(exchange_options, ...
        'pressure_pi_mdot_scale_piecewise_threshold', 1.0);
    if ~(isnumeric(pressure_pi_mdot_scale_exponent_low) && isscalar(pressure_pi_mdot_scale_exponent_low) && ...
            isfinite(pressure_pi_mdot_scale_exponent_low) && pressure_pi_mdot_scale_exponent_low > 0)
        pressure_pi_mdot_scale_exponent_low = 0.10;
    end
    if ~(isnumeric(pressure_pi_mdot_scale_exponent_high) && isscalar(pressure_pi_mdot_scale_exponent_high) && ...
            isfinite(pressure_pi_mdot_scale_exponent_high) && pressure_pi_mdot_scale_exponent_high > 0)
        pressure_pi_mdot_scale_exponent_high = 0.50;
    end
    if ~(isnumeric(pressure_pi_mdot_scale_piecewise_threshold) && isscalar(pressure_pi_mdot_scale_piecewise_threshold) && ...
            isfinite(pressure_pi_mdot_scale_piecewise_threshold) && pressure_pi_mdot_scale_piecewise_threshold > 0)
        pressure_pi_mdot_scale_piecewise_threshold = 1.0;
    end
    if ~strcmpi(root_manifold_split_mode, 'r63_full_split') && strcmpi(requested_flow_control_mode, 'pressure_pi_feedback_v1')
        if strcmpi(stage_name, 'hold_exchange')
            pressure_pi_mdot_scale_exponent_low = get_option_field(exchange_options, ...
                'pressure_pi_mdot_scale_exponent_low_hold', 0.05);
            pressure_pi_mdot_scale_exponent_high = get_option_field(exchange_options, ...
                'pressure_pi_mdot_scale_exponent_high_hold', 0.33);
        elseif strcmpi(stage_name, 'cooldown_exchange')
            pressure_pi_mdot_scale_exponent_low = get_option_field(exchange_options, ...
                'pressure_pi_mdot_scale_exponent_low_cooldown', 0.10);
            pressure_pi_mdot_scale_exponent_high = get_option_field(exchange_options, ...
                'pressure_pi_mdot_scale_exponent_high_cooldown', 0.10);
        end
        if ~(isnumeric(pressure_pi_mdot_scale_exponent_low) && isscalar(pressure_pi_mdot_scale_exponent_low) && ...
                isfinite(pressure_pi_mdot_scale_exponent_low) && pressure_pi_mdot_scale_exponent_low > 0)
            pressure_pi_mdot_scale_exponent_low = 0.10;
        end
        if ~(isnumeric(pressure_pi_mdot_scale_exponent_high) && isscalar(pressure_pi_mdot_scale_exponent_high) && ...
                isfinite(pressure_pi_mdot_scale_exponent_high) && pressure_pi_mdot_scale_exponent_high > 0)
            pressure_pi_mdot_scale_exponent_high = 0.50;
        end
    end
    pressure_pi_reference_stage_time_s = get_option_field(exchange_options, ...
        'pressure_pi_reference_stage_time_s', 0.40);
    if ~(isnumeric(pressure_pi_reference_stage_time_s) && isscalar(pressure_pi_reference_stage_time_s) && ...
            isfinite(pressure_pi_reference_stage_time_s) && pressure_pi_reference_stage_time_s > 0)
        pressure_pi_reference_stage_time_s = 0.40;
    end
    pressure_pi_mdot_ref_kgps = get_option_field(exchange_options, 'pressure_pi_reference_mdot_kgps', ...
        rho_water * plate_volume_m3 / max(pressure_pi_reference_stage_time_s, eps));
    if ~(isnumeric(pressure_pi_mdot_ref_kgps) && isscalar(pressure_pi_mdot_ref_kgps) && ...
            isfinite(pressure_pi_mdot_ref_kgps) && pressure_pi_mdot_ref_kgps > 0)
        pressure_pi_mdot_ref_kgps = rho_water * plate_volume_m3 / max(pressure_pi_reference_stage_time_s, eps);
    end
    pressure_pi_mdot_scale = mdot_target_kgps / max(pressure_pi_mdot_ref_kgps, eps);
    if pressure_pi_mdot_scale_piecewise_enabled && strcmpi(requested_flow_control_mode, 'pressure_pi_feedback_v1')
        if pressure_pi_mdot_scale <= pressure_pi_mdot_scale_piecewise_threshold
            pressure_pi_mdot_scale_exponent = pressure_pi_mdot_scale_exponent_low;
        else
            pressure_pi_mdot_scale_exponent = pressure_pi_mdot_scale_exponent_high;
        end
    end
    pressure_pi_duration_attenuation_enabled = logical(get_option_field(exchange_options, ...
        'pressure_pi_duration_attenuation_enabled', ...
        ~strcmpi(root_manifold_split_mode, 'r63_full_split') && strcmpi(requested_flow_control_mode, 'pressure_pi_feedback_v1')));
    pressure_pi_duration_attenuation_factor = 1.0;
    pressure_pi_duration_attenuation_gain = get_option_field(exchange_options, ...
        'pressure_pi_duration_attenuation_gain', 1.00);
    if ~(isnumeric(pressure_pi_duration_attenuation_gain) && isscalar(pressure_pi_duration_attenuation_gain) && ...
            isfinite(pressure_pi_duration_attenuation_gain) && pressure_pi_duration_attenuation_gain >= 0)
        pressure_pi_duration_attenuation_gain = 1.00;
    end
    pressure_pi_duration_attenuation_min = get_option_field(exchange_options, ...
        'pressure_pi_duration_attenuation_min', 0.53);
    if ~(isnumeric(pressure_pi_duration_attenuation_min) && isscalar(pressure_pi_duration_attenuation_min) && ...
            isfinite(pressure_pi_duration_attenuation_min) && pressure_pi_duration_attenuation_min > 0 && ...
            pressure_pi_duration_attenuation_min <= 1)
        pressure_pi_duration_attenuation_min = 0.53;
    end
    if pressure_pi_duration_attenuation_enabled && strcmpi(stage_name, 'cooldown_exchange')
        duration_ratio = stage_duration_s / max(pressure_pi_reference_stage_time_s, eps);
        if isfinite(duration_ratio) && duration_ratio > 0
            pressure_pi_duration_attenuation_factor = max(pressure_pi_duration_attenuation_min, ...
                1.0 - pressure_pi_duration_attenuation_gain * abs(log(duration_ratio)));
        end
    end
    pressure_pi_dp_guess_MPa = pressure_pi_bias_MPa;
    pressure_pi_margin_MPa = NaN;
    pressure_pi_margin_min_MPa = get_option_field(exchange_options, 'pressure_pi_margin_min_MPa', 0.005);
    if ~(isnumeric(pressure_pi_margin_min_MPa) && isscalar(pressure_pi_margin_min_MPa) && ...
            isfinite(pressure_pi_margin_min_MPa) && pressure_pi_margin_min_MPa >= 0)
        pressure_pi_margin_min_MPa = 0.005;
    end
    pressure_pi_margin_fraction = get_option_field(exchange_options, 'pressure_pi_margin_fraction', 0.5);
    if ~(isnumeric(pressure_pi_margin_fraction) && isscalar(pressure_pi_margin_fraction) && ...
            isfinite(pressure_pi_margin_fraction) && pressure_pi_margin_fraction >= 0)
        pressure_pi_margin_fraction = 0.5;
    end
    pressure_pi_ki_ref_MPa_per_kgps_s = get_option_field(exchange_options, ...
        'pressure_pi_ki_ref_MPa_per_kgps_s', pressure_pi_ki_MPa_per_kgps_s);
    if ~(isnumeric(pressure_pi_ki_ref_MPa_per_kgps_s) && isscalar(pressure_pi_ki_ref_MPa_per_kgps_s) && ...
            isfinite(pressure_pi_ki_ref_MPa_per_kgps_s))
        pressure_pi_ki_ref_MPa_per_kgps_s = pressure_pi_ki_default;
    end
    pressure_pi_long_duration_ki_boost_enabled = logical(get_option_field(exchange_options, ...
        'pressure_pi_long_duration_ki_boost_enabled', ...
        ~strcmpi(root_manifold_split_mode, 'r63_full_split') && strcmpi(requested_flow_control_mode, 'pressure_pi_feedback_v1')));
    pressure_pi_long_duration_ki_boost_threshold = get_option_field(exchange_options, ...
        'pressure_pi_long_duration_ki_boost_threshold', 1.0);
    if ~(isnumeric(pressure_pi_long_duration_ki_boost_threshold) && ...
            isscalar(pressure_pi_long_duration_ki_boost_threshold) && ...
            isfinite(pressure_pi_long_duration_ki_boost_threshold) && ...
            pressure_pi_long_duration_ki_boost_threshold > 0)
        pressure_pi_long_duration_ki_boost_threshold = 1.0;
    end
    pressure_pi_long_duration_ki_boost_factor = get_option_field(exchange_options, ...
        'pressure_pi_long_duration_ki_boost_factor', 2.0);
    if ~(isnumeric(pressure_pi_long_duration_ki_boost_factor) && ...
            isscalar(pressure_pi_long_duration_ki_boost_factor) && ...
            isfinite(pressure_pi_long_duration_ki_boost_factor) && ...
            pressure_pi_long_duration_ki_boost_factor >= 1.0)
        pressure_pi_long_duration_ki_boost_factor = 2.0;
    end
    pressure_pi_ki_ref_effective_MPa_per_kgps_s = pressure_pi_ki_ref_MPa_per_kgps_s;
    if pressure_pi_long_duration_ki_boost_enabled && strcmpi(stage_name, 'cooldown_exchange')
        duration_ratio = stage_duration_s / max(pressure_pi_reference_stage_time_s, eps);
        if isfinite(duration_ratio) && duration_ratio > pressure_pi_long_duration_ki_boost_threshold
            pressure_pi_ki_ref_effective_MPa_per_kgps_s = ...
                pressure_pi_ki_ref_MPa_per_kgps_s * pressure_pi_long_duration_ki_boost_factor;
        end
    end
    pressure_pi_ki_time_scale = 1.0;
    if pressure_pi_hydraulic_scheduling_enabled && strcmpi(requested_flow_control_mode, 'pressure_pi_feedback_v1')
        pressure_pi_dp_guess_MPa = pressure_pi_bias_ref_MPa * ...
            pressure_pi_duration_attenuation_factor * ...
            pressure_pi_mdot_scale ^ pressure_pi_mdot_scale_exponent;
        pressure_pi_margin_MPa = max(pressure_pi_margin_min_MPa, ...
            pressure_pi_margin_fraction * abs(pressure_pi_dp_guess_MPa));
        pressure_pi_bias_MPa = pressure_pi_dp_guess_MPa;
        pressure_pi_min_MPa = pressure_pi_dp_guess_MPa - pressure_pi_margin_MPa;
        pressure_pi_max_MPa = pressure_pi_dp_guess_MPa + pressure_pi_margin_MPa;
        pressure_pi_ki_time_scale = 0.40 / max(stage_duration_s, eps);
        pressure_pi_ki_MPa_per_kgps_s = pressure_pi_ki_ref_effective_MPa_per_kgps_s * pressure_pi_ki_time_scale;
    end
    pressure_pi_error_filter_tau_s = max(get_option_field(exchange_options, 'pressure_pi_error_filter_tau_s', 0.002), 1.0e-5);
    if pressure_pi_normalized_error_enabled
        pressure_pi_error_normalization_gain_kgps_inv = 1.0 / max(abs(mdot_target_kgps), 1.0e-12);
    else
        pressure_pi_error_normalization_gain_kgps_inv = 1.0;
    end
    mass_flow_source_direction_sign = 0.0;
    explicit_mass_flow_mode = any(strcmpi(requested_flow_control_mode, { ...
        'mass_flow_source_v3', 'mass_flow_v3', 'root_mass_flow_source', ...
        'root_mass_flow_source_v3', 'mass_flow_source_v4_valve_front', ...
        'mass_flow_v4_valve_front', 'pressure_pi_feedback_v1'}));
    if explicit_mass_flow_mode
        if use_closed_valve_flow
            Q_source_m3ps = 0.0;
            if any(strcmpi(requested_flow_control_mode, {'mass_flow_source_v4_valve_front', 'mass_flow_v4_valve_front'}))
                flow_control_mode = 'mass_flow_source_v4_valve_front_closed';
            else
                flow_control_mode = 'mass_flow_source_v3_closed';
            end
        elseif any(strcmpi(requested_flow_control_mode, {'mass_flow_source_v4_valve_front', 'mass_flow_v4_valve_front', ...
                'pressure_pi_feedback_v1'}))
            if strcmpi(stage_name, 'hold_exchange')
                mass_flow_source_direction_sign = 1.0;
                mdot_hold_source_kgps = mdot_target_kgps;
            elseif strcmpi(stage_name, 'cooldown_exchange')
                mass_flow_source_direction_sign = 1.0;
                mdot_cooldown_source_kgps = mdot_target_kgps;
            else
                mass_flow_source_direction_sign = 0.0;
            end
            mdot_source_kgps = mdot_hold_source_kgps + mdot_cooldown_source_kgps;
            Q_source_m3ps = mdot_source_kgps / max(rho_water, eps);
            if strcmpi(requested_flow_control_mode, 'pressure_pi_feedback_v1')
                flow_control_mode = 'pressure_pi_feedback_v1';
            else
                flow_control_mode = 'mass_flow_source_v4_valve_front';
            end
        else
            if strcmpi(stage_name, 'hold_exchange')
                mass_flow_source_direction_sign = 1.0;
            elseif strcmpi(stage_name, 'cooldown_exchange')
                mass_flow_source_direction_sign = -1.0;
            else
                mass_flow_source_direction_sign = 0.0;
            end
            mdot_root_source_kgps = mass_flow_source_direction_sign * mdot_target_kgps;
            mdot_source_kgps = mdot_root_source_kgps;
            Q_source_m3ps = mass_flow_source_direction_sign * Q_target_m3ps;
            flow_control_mode = 'mass_flow_source_v3';
        end

        sma_pipe_pressure_hydraulic_reference_volume_ml = NaN;
        sma_pipe_pressure_storage_length_fraction = NaN;
        default_pressure_exponent = NaN;
        pressure_trim_default = NaN;
        sma_pipe_pressure_calibration_method = 'explicit_experimental_mass_flow_no_pressure_trim';
        if strcmpi(stage_name, 'hold_exchange')
            factor_field_name = 'deprecated_sma_pipe_pressure_calibration_factor_hold';
        elseif strcmpi(stage_name, 'cooldown_exchange')
            factor_field_name = 'deprecated_sma_pipe_pressure_calibration_factor_cooldown';
        else
            factor_field_name = 'deprecated_sma_pipe_pressure_calibration_factor';
        end
        sma_pipe_pressure_calibration_factor = NaN;
        pressure_differential_MPa_initial_guess_source = 'explicit_experimental_mass_flow_no_pressure_control';
        pressure_differential_MPa_uncached = NaN;
        pressure_differential_MPa_analytic_guess = NaN;
        pressure_differential_MPa_cached_guess = NaN;
        if use_closed_valve_flow
            pressure_differential_MPa = 0.0;
        else
            pressure_differential_MPa = NaN;
        end
    else
        flow_control_mode = requested_flow_control_mode;
        sma_pipe_pressure_hydraulic_reference_volume_ml = get_option_field(exchange_options, ...
            'sma_pipe_pressure_hydraulic_reference_volume_ml', sma_pipe_internal_volume_target_ml);
        sma_pipe_pressure_hydraulic_reference_volume_m3 = max(sma_pipe_pressure_hydraulic_reference_volume_ml, eps) * 1.0e-6;
        sma_pipe_pressure_storage_length_fraction = min(max( ...
            sma_pipe_pressure_hydraulic_reference_volume_m3 / max(pipe_fa * tube_l, eps), eps), 1.0);
        if strcmpi(sma_pipe_volume_calibration_mode, 'hydraulic_resistance_preserving_volume_v1') || ...
                strcmpi(sma_pipe_volume_calibration_mode, 'hydraulic_resistance_preserving_volume_v1_capped_at_legacy_volume')
            if strcmpi(stage_name, 'hold_exchange')
                default_pressure_exponent = get_option_field(exchange_options, ...
                    'sma_pipe_pressure_storage_fraction_exponent_hold', 2.91);
            elseif strcmpi(stage_name, 'cooldown_exchange')
                default_pressure_exponent = get_option_field(exchange_options, ...
                    'sma_pipe_pressure_storage_fraction_exponent_cooldown', 3.7);
            else
                default_pressure_exponent = get_option_field(exchange_options, ...
                    'sma_pipe_pressure_storage_fraction_exponent', 3.7);
            end
            default_pipe_pressure_scale = max(sma_pipe_pressure_storage_length_fraction, eps) ^ ...
                default_pressure_exponent;
            if strcmpi(stage_name, 'hold_exchange')
                pressure_trim_default = get_option_field(exchange_options, ...
                    'sma_pipe_pressure_actual_flush_trim_factor_hold', 0.95);
            elseif strcmpi(stage_name, 'cooldown_exchange')
                pressure_trim_default = get_option_field(exchange_options, ...
                    'sma_pipe_pressure_actual_flush_trim_factor_cooldown', 0.00605);
            else
                pressure_trim_default = get_option_field(exchange_options, ...
                    'sma_pipe_pressure_actual_flush_trim_factor', 1.0);
            end
            if ~(isnumeric(pressure_trim_default) && isscalar(pressure_trim_default) && ...
                    isfinite(pressure_trim_default) && pressure_trim_default > 0)
                pressure_trim_default = 1.0;
            end
            default_pipe_pressure_scale = default_pipe_pressure_scale * pressure_trim_default;
            sma_pipe_pressure_calibration_method = 'storage_length_fraction_power_law_v1';
        else
            default_pressure_exponent = NaN;
            pressure_trim_default = 1.0;
            default_pipe_pressure_scale = 1.0;
            sma_pipe_pressure_calibration_method = 'legacy_or_area_shrinkage_no_extra_scale';
        end
        if strcmpi(stage_name, 'hold_exchange')
            factor_field_name = 'sma_pipe_pressure_calibration_factor_hold';
        elseif strcmpi(stage_name, 'cooldown_exchange')
            factor_field_name = 'sma_pipe_pressure_calibration_factor_cooldown';
        else
            factor_field_name = 'sma_pipe_pressure_calibration_factor';
        end
        sma_pipe_pressure_calibration_factor = get_option_field(exchange_options, factor_field_name, ...
            get_option_field(exchange_options, 'sma_pipe_pressure_calibration_factor', default_pipe_pressure_scale));
        if ~(isnumeric(sma_pipe_pressure_calibration_factor) && isscalar(sma_pipe_pressure_calibration_factor) && ...
                isfinite(sma_pipe_pressure_calibration_factor) && sma_pipe_pressure_calibration_factor > 0)
            sma_pipe_pressure_calibration_factor = default_pipe_pressure_scale;
        end
        pressure_differential_MPa_initial_guess_source = 'closed_valve_zero_pressure';
        pressure_differential_MPa_uncached = NaN;
        pressure_differential_MPa_analytic_guess = NaN;
        pressure_differential_MPa_cached_guess = NaN;
        if use_closed_valve_flow
            pressure_differential_MPa = 0.0;
        else
            switch lower(strtrim(flow_control_mode))
                case {'target_flow_pressure_scaled_v1', 'target_flow_pressure_scaled', ...
                        'calibrated_pressure_source'}
                    pressure_differential_MPa = pressure_control_direction_sign * ...
                        abs(pressure_control_reference_pressure_MPa) * ...
                        max(pressure_control_flow_scale, 0.0) ^ pressure_control_exponent * ...
                        sma_pipe_pressure_calibration_factor;
                    flow_control_mode = 'target_flow_pressure_scaled_v1';
                case {'actual_flush_closed_loop_v1', 'actual_flush_pressure_closed_loop_v1'}
                    pressure_differential_MPa = pressure_control_direction_sign * ...
                        abs(pressure_control_reference_pressure_MPa) * ...
                        max(pressure_control_flow_scale, 0.0) ^ pressure_control_exponent * ...
                        sma_pipe_pressure_calibration_factor;
                    flow_control_mode = 'actual_flush_closed_loop_v1';
                case {'target_duty_pressure_v1', 'target_duty_pressure'}
                    pressure_differential_MPa = pressure_control_direction_sign * ...
                        abs(pressure_control_reference_pressure_MPa) * ...
                        max(pressure_control_duty_flow_scale, 0.0) ^ pressure_control_exponent * ...
                        sma_pipe_pressure_calibration_factor;
                    flow_control_mode = 'target_duty_pressure_v1';
                case {'legacy_calibrated_pressure_source', 'calibrated_pressure_source_legacy'}
                    pressure_differential_MPa = pressure_control_direction_sign * ...
                        abs(pressure_control_reference_pressure_MPa) * ...
                        max(pressure_control_target_ratio_scale, 0.0) ^ pressure_control_exponent * ...
                        sma_pipe_pressure_calibration_factor;
                    flow_control_mode = 'legacy_calibrated_pressure_source';
                otherwise
                    error('Build_Simulink_Exchange_Params:UnknownFlowControlMode', ...
                        'Unknown flow_control_mode: %s', flow_control_mode);
            end
            pressure_differential_MPa_uncached = pressure_differential_MPa;
            pressure_differential_MPa_analytic_guess = compute_analytic_pressure_guess( ...
                pressure_differential_MPa_uncached, mdot_target_kgps, stage_duration_s, ...
                rho_water, plate_volume_m3, pressure_control_reference_duration_s, Re, exchange_options);
            pressure_differential_MPa = pressure_differential_MPa_analytic_guess;
            pressure_differential_MPa_initial_guess_source = 'analytic_mdot_scaled_pressure_guess';
            [cached_pressure, cached_source] = select_cached_pressure_guess(runtime, stage_name);
            if isfinite(cached_pressure)
                pressure_differential_MPa = cached_pressure;
                pressure_differential_MPa_cached_guess = cached_pressure;
                pressure_differential_MPa_initial_guess_source = cached_source;
            end
            if isfield(exchange_options, 'pressure_differential_override_MPa') && ...
                    ~isempty(exchange_options.pressure_differential_override_MPa)
                pressure_differential_MPa = double(exchange_options.pressure_differential_override_MPa);
                pressure_differential_MPa_initial_guess_source = 'pressure_differential_override_MPa';
            end
        end
    end
    tank_pressure_MPa = get_option_field(exchange_options, 'tank_pressure_MPa', 0.5);

    allow_flush_volume_ratio_out_of_gate = logical(get_option_field(exchange_options, ...
        'allow_flush_volume_ratio_out_of_gate', false));
    if ~use_closed_valve_flow && ~allow_flush_volume_ratio_out_of_gate
        if flush_volume_ratio < 0.23 || flush_volume_ratio > 1.52
            error('Build_Simulink_Exchange_Params:FlushVolumeOutOfGate', ...
                'flush_volume_ratio = %.6g is outside the hard gate [0.23, 1.52].', ...
                flush_volume_ratio);
        end
    end

    fluid_buffer_reference_ratio = get_option_field(exchange_options, 'fluid_buffer_reference_ratio', 100.0);
    if ~(isnumeric(fluid_buffer_reference_ratio) && isscalar(fluid_buffer_reference_ratio) && ...
            isfinite(fluid_buffer_reference_ratio) && fluid_buffer_reference_ratio > 0)
        error('Build_Simulink_Exchange_Params:InvalidFluidBufferReferenceRatio', ...
            'fluid_buffer_reference_ratio must be finite and positive.');
    end
    fluid_buffer_reference_volume_m3 = fluid_buffer_reference_ratio * plate_volume_m3;
    fluid_buffer_volume_m3 = get_option_field(exchange_options, ...
        'fluid_buffer_volume_m3', fluid_buffer_reference_volume_m3);
    fluid_buffer_tank_area_m2 = get_option_field(exchange_options, 'fluid_buffer_tank_area_m2', 1.0e-3);
    fluid_buffer_tank_level_m = get_option_field(exchange_options, 'fluid_buffer_tank_level_m', ...
        max(fluid_buffer_volume_m3 / max(fluid_buffer_tank_area_m2, eps), 0.05));
    fluid_buffer_max_capacity_m3 = get_option_field(exchange_options, 'fluid_buffer_max_capacity_m3', ...
        max([10 * fluid_buffer_volume_m3, fluid_buffer_tank_area_m2 * max(2 * fluid_buffer_tank_level_m, 0.1), 1.0e-5]));
    default_buffer_C = rho_water * fluid_buffer_volume_m3 * cp_water;
    hot_fluid_buffer_C = get_option_field(exchange_options, 'hot_fluid_buffer_C_J_per_K', default_buffer_C);
    cold_fluid_buffer_C = get_option_field(exchange_options, 'cold_fluid_buffer_C_J_per_K', default_buffer_C);
    buffer_effective_energy_accounting_enabled = logical(get_option_field(exchange_options, ...
        'buffer_effective_energy_accounting_enabled', true));
    buffer_effective_energy_accounting_source = 'actual_active_flush_volume_over_numerical_buffer_volume';
    sma_pipe_thermal_gate_enabled = logical(get_option_field(exchange_options, ...
        'sma_pipe_thermal_gate_enabled', true));
    sma_pipe_thermal_gate_active_G_W_per_K = get_option_field(exchange_options, ...
        'sma_pipe_thermal_gate_active_G_W_per_K', 1.0e6);
    sma_pipe_thermal_gate_inactive_G_W_per_K = get_option_field(exchange_options, ...
        'sma_pipe_thermal_gate_inactive_G_W_per_K', 1.0e-9);
    if ~(isnumeric(sma_pipe_thermal_gate_active_G_W_per_K) && isscalar(sma_pipe_thermal_gate_active_G_W_per_K) && ...
            isfinite(sma_pipe_thermal_gate_active_G_W_per_K) && sma_pipe_thermal_gate_active_G_W_per_K > 0)
        sma_pipe_thermal_gate_active_G_W_per_K = 1.0e6;
    end
    if ~(isnumeric(sma_pipe_thermal_gate_inactive_G_W_per_K) && isscalar(sma_pipe_thermal_gate_inactive_G_W_per_K) && ...
            isfinite(sma_pipe_thermal_gate_inactive_G_W_per_K) && sma_pipe_thermal_gate_inactive_G_W_per_K >= 0)
        sma_pipe_thermal_gate_inactive_G_W_per_K = 1.0e-9;
    end
    if ~sma_pipe_thermal_gate_enabled
        sma_hold_pipe_to_sma_G_W_per_K = sma_pipe_thermal_gate_active_G_W_per_K;
        sma_cooldown_pipe_to_sma_G_W_per_K = sma_pipe_thermal_gate_active_G_W_per_K;
        sma_pipe_thermal_gate_active_path = 'disabled_both_paths_active';
    elseif strcmpi(stage_name, 'hold_exchange')
        sma_hold_pipe_to_sma_G_W_per_K = sma_pipe_thermal_gate_active_G_W_per_K;
        sma_cooldown_pipe_to_sma_G_W_per_K = sma_pipe_thermal_gate_inactive_G_W_per_K;
        sma_pipe_thermal_gate_active_path = 'hold';
    elseif strcmpi(stage_name, 'cooldown_exchange')
        sma_hold_pipe_to_sma_G_W_per_K = sma_pipe_thermal_gate_inactive_G_W_per_K;
        sma_cooldown_pipe_to_sma_G_W_per_K = sma_pipe_thermal_gate_active_G_W_per_K;
        sma_pipe_thermal_gate_active_path = 'cooldown';
    else
        sma_hold_pipe_to_sma_G_W_per_K = sma_pipe_thermal_gate_inactive_G_W_per_K;
        sma_cooldown_pipe_to_sma_G_W_per_K = sma_pipe_thermal_gate_inactive_G_W_per_K;
        sma_pipe_thermal_gate_active_path = 'none';
    end
    startup_config = build_exchange_startup_config(stage_config, exchange_options, stage_duration_s, use_closed_valve_flow);
    sma_stage13_config = build_sma_stage13_startup_config(stage_config, exchange_options, ...
        stage_duration_s, sma_stage13_nominal_mdot_target_kgps);

    sim_params = struct();
    sim_params.solver_T_init_21 = T_init(:);
    sim_params.solver_T_init_51 = T_init(:);
    if isstruct(state_std) && isfield(state_std, 'xi') && ~isempty(state_std.xi)
        sim_params.sma_xi_in_51 = state_std.xi(:);
    else
        sim_params.sma_xi_in_51 = NaN(size(T_init(:)));
    end
    sim_params.L_valve = reshape(stage_config.L_valve, 1, []);
    sim_params.L_valve_target = startup_config.L_valve_target;
    sim_params.L_valve_command_target = startup_config.L_valve_command_target;
    sim_params.L_valve_initial = startup_config.L_valve_initial;
    sim_params.L_valve_command = startup_config.L_valve_command;
    sim_params.L_valve_command_time_s = startup_config.L_valve_command_time_s;
    sim_params.L_valve_command_values = startup_config.L_valve_command_values;
    sim_params.SMA_L_valve_command_target = sma_stage13_config.L_valve_command_target;
    sim_params.SMA_L_valve_command_initial = sma_stage13_config.L_valve_initial;
    sim_params.SMA_L_valve_command = sma_stage13_config.L_valve_command;
    sim_params.SMA_L_valve_command_time_s = sma_stage13_config.L_valve_command_time_s;
    sim_params.SMA_L_valve_command_values = sma_stage13_config.L_valve_command_values;
    sim_params.SMA_stage13_valve_order = sma_stage13_config.valve_order;
    sim_params.SMA_stage13_route_name = sma_stage13_config.route_name;
    sim_params.SMA_stage13_route_description = sma_stage13_config.route_description;
    sim_params.SMA_stage13_active = sma_stage13_config.active;
    sim_params.SMA_stage13_startup_profile = sma_stage13_config.startup_profile;
    sim_params.SMA_stage13_startup_ramp_s = sma_stage13_config.startup_ramp_s;
    sim_params.exchange_startup_smoothing_enabled = startup_config.exchange_startup_smoothing_enabled;
    sim_params.exchange_startup_ramp_s = startup_config.exchange_startup_ramp_s;
    sim_params.exchange_startup_profile = startup_config.exchange_startup_profile;
    sim_params.startup_smoothing_used = startup_config.startup_smoothing_used;
    sim_params.startup_smoothing_reason = startup_config.startup_smoothing_reason;
    sim_params.exchange_startup_closed_valve_opening = startup_config.exchange_startup_closed_valve_opening;
    sim_params.active_valve_opening_scale = startup_config.active_valve_opening_scale;
    sim_params.active_valve_duty_cycle_enabled = startup_config.active_valve_duty_cycle_enabled;
    sim_params.active_valve_duty_fraction = startup_config.active_valve_duty_fraction;
    sim_params.active_valve_duty_raw_fraction = startup_config.active_valve_duty_raw_fraction;
    sim_params.active_valve_duty_dead_fraction = startup_config.active_valve_duty_dead_fraction;
    sim_params.active_valve_duty_effective_dead_fraction = startup_config.active_valve_duty_effective_dead_fraction;
    sim_params.active_valve_duty_capacity_ratio = startup_config.active_valve_duty_capacity_ratio;
    sim_params.pressure_startup_smoothing_enabled = false;
    sim_params.pressure_startup_smoothing_reason = 'pressure_source_compiletime_constant; active flow is ramped by valve opening command';
    sim_params.pressure_startup_compensation_factor = 1.0;
    sim_params.hot_source = hot_sink_T_init;
    sim_params.radius_m = radius_m;
    sim_params.thickness_m = thickness_m;
    sim_params.solver51_node_mass = total_mass / thermal_model_node_count;
    sim_params.solver51_node_cp = node_cp;
    sim_params.sma_density_kg_per_m3 = sma_density_kg_per_m3;
    sim_params.sma_physical_mass_kg = sma_physical_mass_kg;
    sim_params.sma_proxy_mass_kg = total_mass;
    sim_params.sma_mass_source = sma_mass_source;
    sim_params.sma_mass_consistency_ratio = sma_mass_consistency_ratio;
    sim_params.sma_mass_contract_ok = sma_mass_contract_ok;
    sim_params.sma_heat_capacity_total_J_per_K = total_mass * node_cp;
    sim_params.solver51_cond_k = cond_k;
    sim_params.solver51_cond_area = cond_area;
    sim_params.solver51_cond_dx = cond_dx;
    sim_params.solver_internal_thermal_node_count = thermal_model_node_count;
    sim_params.D_inner = D_inner;
    sim_params.D_outer = D_outer;
    sim_params.tube_l = tube_l;
    sim_params.sma_pipe_storage_l = sma_pipe_storage_l;
    sim_params.sma_pipe_hydraulic_length_add_l = sma_pipe_hydraulic_length_add_l;
    sim_params.sma_pipe_hydraulic_total_l = sma_pipe_hydraulic_total_l;
    sim_params.sma_pipe_storage_length_fraction = sma_pipe_storage_length_fraction;
    sim_params.sma_pipe_segment_l = sma_pipe_storage_l / max(thermal_model_node_count, 1);
    sim_params.sma_pipe_segment_length_add_l = sma_pipe_hydraulic_length_add_l / max(thermal_model_node_count, 1);
    sim_params.tube_A_m2 = tube_A_m2;
    sim_params.tube_A = tube_A;
    sim_params.pipe_fa = pipe_fa;
    sim_params.D_e = D_e;
    sim_params.L = L;
    sim_params.sma_pipe_volume_calibration_mode = sma_pipe_volume_calibration_mode;
    sim_params.sma_pipe_internal_volume_target_ml = sma_pipe_internal_volume_target_ml;
    sim_params.sma_pipe_internal_volume_target_m3 = sma_pipe_internal_volume_target_m3;
    sim_params.sma_pipe_hydraulic_resistance_strategy = sma_pipe_hydraulic_resistance_strategy;
    sim_params.active_sma_pipe_internal_volume_m3 = active_sma_pipe_internal_volume_m3;
    sim_params.active_sma_pipe_internal_volume_ml = active_sma_pipe_internal_volume_m3 * 1.0e6;
    sim_params.pipe_internal_fluid_C_J_per_K = pipe_internal_fluid_C_J_per_K;
    % Stage4 transit pipe (Simulink-observable: V6 valve + connection-line fluid
    % volume between SMA cooldown outlet and the CHEX inlet). The pipe is a
    % real TL Pipe block in cold_subsystem so its internal energy state evolves
    % under Simscape solver, not by residual closure. Its volume must be set
    % from physical geometry, NOT fitted from energy gap.
    transit_pipe_length_m = get_option_field(exchange_options, ...
        'transit_pipe_length_m', 0.04);
    if strcmp(cold_end_topology_mode, 'r69_symmetric')
        transit_pipe_length_m = 0.0;
    end
    if ~(isnumeric(transit_pipe_length_m) && isscalar(transit_pipe_length_m) && ...
            isfinite(transit_pipe_length_m) && transit_pipe_length_m >= 0)
        transit_pipe_length_m = 0.04;
    end
    transit_pipe_volume_m3 = pipe_fa * transit_pipe_length_m;
    transit_pipe_internal_fluid_C_J_per_K = rho_water * cp_water * max(transit_pipe_volume_m3, 0.0);
    % Single TransitPipe inside cold_subsystem (TransitPipe_V6_to_CHEX,
    % between Conn2 and ColdSinkPipe.RConn). The previous attempt to add a
    % second pipe at root level (between V6.RConn and cold_subsystem.Conn2)
    % made cycle 1 transport_ratio collapse to 0.49 (vs 0.84 baseline)
    % because the extra pipe absorbed cold from flow without re-releasing it,
    % so the cold never reached CHEX. That experiment was reverted in r19d.
    sim_params.transit_pipe_length_m = transit_pipe_length_m;
    sim_params.transit_pipe_area_m2 = pipe_fa;
    sim_params.transit_pipe_volume_m3 = transit_pipe_volume_m3;
    sim_params.transit_pipe_volume_ml = transit_pipe_volume_m3 * 1.0e6;
    sim_params.transit_pipe_internal_fluid_C_J_per_K = transit_pipe_internal_fluid_C_J_per_K;
    sim_params.transit_pipe_count_in_series = 1;
    if strcmp(cold_end_topology_mode, 'r69_symmetric')
        sim_params.transit_pipe_geometry_source = 'R69_removed_no_independent_transit_pipe_direct_SMA_to_CHEX_boundary';
    else
        sim_params.transit_pipe_geometry_source = 'pipe_fa_times_transit_pipe_length_m_independent_of_energy_residual_single_inner_subsystem_pipe';
    end
    % Backward-compat aliases for legacy stage4_sma_to_CHEX_transit_* names.
    sim_params.stage4_sma_to_CHEX_transit_volume_m3 = transit_pipe_volume_m3;
    sim_params.stage4_sma_to_CHEX_transit_volume_ml = transit_pipe_volume_m3 * 1.0e6;
    sim_params.stage4_sma_to_CHEX_transit_C_J_per_K = transit_pipe_internal_fluid_C_J_per_K;
    if strcmp(cold_end_topology_mode, 'r69_symmetric')
        default_transit_model = 'removed_in_R69_symmetric_direct_CHEX_boundary';
    else
        default_transit_model = 'simulink_TL_pipe_internal_observation_v2_independent_of_residual';
    end
    sim_params.stage4_sma_to_CHEX_transit_model = char(string(get_option_field(exchange_options, ...
        'stage4_sma_to_CHEX_transit_model', default_transit_model)));
    sim_params.pipe_storage_scheme = 'two_path_thermal_state_with_hydraulic_resistance_preserved_v1';
    sim_params.pipe_storage_physical_note = ['The thermal dead volume is represented by a shortened Pipe(TL) ', ...
        'storage length while legacy area and total hydraulic length are retained for Re, h, pressure and pump-work estimates.'];
    sim_params.pipe_internal_volume_to_plate_volume_ratio = pipe_internal_volume_to_plate_volume_ratio;
    sim_params.pipe_internal_volume_to_flush_volume_ratio = pipe_internal_volume_to_flush_volume_ratio;
    sim_params.V_star_vs_SMA = V_star_vs_SMA;
    sim_params.V_star_vs_pipe = V_star_vs_pipe;
    sim_params.legacy_D_inner = legacy_D_inner;
    sim_params.legacy_D_outer = legacy_D_outer;
    sim_params.legacy_tube_A_m2 = legacy_tube_A_m2;
    sim_params.legacy_active_sma_pipe_internal_volume_m3 = legacy_active_sma_pipe_internal_volume_m3;
    sim_params.legacy_pipe_internal_fluid_C_J_per_K = legacy_pipe_internal_fluid_C_J_per_K;
    sim_params.legacy_pipe_internal_volume_to_plate_volume_ratio = ...
        legacy_active_sma_pipe_internal_volume_m3 / max(plate_volume_m3, eps);
    sim_params.rho_water = rho_water;
    sim_params.mu_water = mu_water;
    sim_params.k_water = k_water;
    sim_params.Pr = Pr;
    sim_params.viscosity_ratio = viscosity_ratio;
    sim_params.cp_water = cp_water;
    sim_params.v_water = v_water;
    sim_params.Re = Re;
    sim_params.Nu_uncapped = Nu_uncapped;
    sim_params.Nu = Nu;
    sim_params.h_water = h_water;
    sim_params.h_water_uncapped = h_water_uncapped;
    sim_params.h_water_scaled_uncapped = h_water_scaled_uncapped;
    sim_params.h_conv_W_per_m2K = h_conv;
    sim_params.U_eff_W_per_m2K = U_eff;
    sim_params.UA_sma_W_per_K = UA_sma;
    sim_params.correlation_name = correlation_name;
    sim_params.flow_regime = flow_regime;
    sim_params.contact_resistance_m2K_per_W = contact_resistance;
    sim_params.wall_resistance_m2K_per_W = wall_resistance;
    sim_params.spreading_resistance_m2K_per_W = spreading_resistance;
    sim_params.wetting_efficiency = wetting_efficiency;
    sim_params.enable_h_water_cap = enable_h_water_cap;
    sim_params.h_water_scale = h_water_scale;
    sim_params.h_water_cap_W_per_m2K = h_water_cap;
    sim_params.h_water_cap_active = h_water_cap_active;
    sim_params.Q = Q;
    sim_params.Q_target_m3ps = Q_target_m3ps;
    sim_params.Q_source_m3ps = Q_source_m3ps;
    if strcmpi(flow_control_mode, 'pressure_pi_feedback_v1')
        sim_params.Q_source_semantics = 'target_mass_flow_drives_root_pressure_feedback_PI';
    elseif strcmpi(flow_control_mode, 'mass_flow_source_v4_valve_front')
        sim_params.Q_source_semantics = 'target_mass_flow_imposed_by_valve_front_Flow_Rate_Source_TL';
    elseif startsWith(lower(strtrim(flow_control_mode)), 'mass_flow_source_v3')
        sim_params.Q_source_semantics = 'signed_target_mass_flow_imposed_by_root_Flow_Rate_Source_TL';
    else
        sim_params.Q_source_semantics = 'target_pressure_differential_imposed_by_root_Pressure_Source_TL';
    end
    sim_params.mdot_target_kgps = mdot_target_kgps;
    sim_params.mdot_source_kgps = mdot_source_kgps;
    sim_params.mdot_root_source_kgps = mdot_root_source_kgps;
    sim_params.mdot_hold_source_kgps = mdot_hold_source_kgps;
    sim_params.mdot_cooldown_source_kgps = mdot_cooldown_source_kgps;
    sim_params.sma_mdot_stage1_source_kgps = sma_stage13_config.stage1_mdot_kgps;
    sim_params.sma_mdot_stage3_source_kgps = sma_stage13_config.stage3_mdot_kgps;
    sim_params.sma_stage13_nominal_mdot_target_kgps = sma_stage13_nominal_mdot_target_kgps;
    sim_params.root_bypass_restriction_area_m2 = root_bypass_restriction_area_m2;
    sim_params.pressure_pi_kp_MPa_per_kgps = pressure_pi_kp_MPa_per_kgps;
    sim_params.pressure_pi_ki_MPa_per_kgps_s = pressure_pi_ki_MPa_per_kgps_s;
    sim_params.pressure_pi_bias_MPa = pressure_pi_bias_MPa;
    sim_params.pressure_pi_min_MPa = pressure_pi_min_MPa;
    sim_params.pressure_pi_max_MPa = pressure_pi_max_MPa;
    sim_params.pressure_pi_hydraulic_scheduling_enabled = pressure_pi_hydraulic_scheduling_enabled;
    sim_params.root_manifold_split_mode = root_manifold_split_mode;
    sim_params.cold_end_topology_mode = cold_end_topology_mode;
    sim_params.pressure_pi_bias_ref_MPa = pressure_pi_bias_ref_MPa;
    sim_params.pressure_pi_bias_ref_MPa_unsplit = pressure_pi_bias_ref_MPa_unsplit;
    sim_params.pressure_pi_bias_ref_MPa_split_mode = pressure_pi_bias_ref_MPa_split_mode;
    sim_params.pressure_pi_bias_ref_MPa_split_hold = pressure_pi_bias_ref_MPa_split_hold;
    sim_params.pressure_pi_bias_ref_MPa_split_cooldown = pressure_pi_bias_ref_MPa_split_cooldown;
    sim_params.pressure_pi_reference_stage_time_s = pressure_pi_reference_stage_time_s;
    sim_params.pressure_pi_mdot_ref_kgps = pressure_pi_mdot_ref_kgps;
    sim_params.pressure_pi_mdot_scale = pressure_pi_mdot_scale;
    sim_params.pressure_pi_mdot_scale_exponent = pressure_pi_mdot_scale_exponent;
    sim_params.pressure_pi_mdot_scale_piecewise_enabled = pressure_pi_mdot_scale_piecewise_enabled;
    sim_params.pressure_pi_mdot_scale_exponent_low = pressure_pi_mdot_scale_exponent_low;
    sim_params.pressure_pi_mdot_scale_exponent_high = pressure_pi_mdot_scale_exponent_high;
    sim_params.pressure_pi_mdot_scale_piecewise_threshold = pressure_pi_mdot_scale_piecewise_threshold;
    sim_params.pressure_pi_duration_attenuation_enabled = pressure_pi_duration_attenuation_enabled;
    sim_params.pressure_pi_duration_attenuation_factor = pressure_pi_duration_attenuation_factor;
    sim_params.pressure_pi_duration_attenuation_gain = pressure_pi_duration_attenuation_gain;
    sim_params.pressure_pi_duration_attenuation_min = pressure_pi_duration_attenuation_min;
    sim_params.pressure_pi_dp_guess_MPa = pressure_pi_dp_guess_MPa;
    sim_params.pressure_pi_margin_MPa = pressure_pi_margin_MPa;
    sim_params.pressure_pi_margin_min_MPa = pressure_pi_margin_min_MPa;
    sim_params.pressure_pi_margin_fraction = pressure_pi_margin_fraction;
    sim_params.pressure_pi_ki_ref_MPa_per_kgps_s = pressure_pi_ki_ref_MPa_per_kgps_s;
    sim_params.pressure_pi_ki_ref_effective_MPa_per_kgps_s = pressure_pi_ki_ref_effective_MPa_per_kgps_s;
    sim_params.pressure_pi_ki_time_scale = pressure_pi_ki_time_scale;
    sim_params.pressure_pi_long_duration_ki_boost_enabled = pressure_pi_long_duration_ki_boost_enabled;
    sim_params.pressure_pi_long_duration_ki_boost_factor = pressure_pi_long_duration_ki_boost_factor;
    sim_params.pressure_pi_long_duration_ki_boost_threshold = pressure_pi_long_duration_ki_boost_threshold;
    sim_params.pressure_pi_error_filter_tau_s = pressure_pi_error_filter_tau_s;
    sim_params.pressure_pi_normalized_error_enabled = pressure_pi_normalized_error_enabled;
    sim_params.pressure_pi_error_normalization_gain_kgps_inv = pressure_pi_error_normalization_gain_kgps_inv;
    sim_params.mass_flow_source_direction_sign = mass_flow_source_direction_sign;
    sim_params.flow_control_mode = flow_control_mode;
    sim_params.requested_flow_control_mode = requested_flow_control_mode;
    sim_params.pressure_differential_MPa = pressure_differential_MPa;
    sim_params.pressure_differential_override_used = isfield(exchange_options, 'pressure_differential_override_MPa') && ...
        ~isempty(exchange_options.pressure_differential_override_MPa);
    sim_params.pressure_differential_MPa_uncached = pressure_differential_MPa_uncached;
    sim_params.pressure_differential_MPa_analytic_guess = pressure_differential_MPa_analytic_guess;
    sim_params.pressure_differential_MPa_cached_guess = pressure_differential_MPa_cached_guess;
    sim_params.pressure_differential_MPa_initial_guess_source = pressure_differential_MPa_initial_guess_source;
    sim_params.pressure_control_reference_pressure_MPa = pressure_control_reference_pressure_MPa;
    sim_params.pressure_control_direction_sign = pressure_control_direction_sign;
    sim_params.pressure_control_reference_actual_flush_ratio = pressure_control_reference_actual_flush_ratio;
    sim_params.pressure_control_reference_duration_s = pressure_control_reference_duration_s;
    sim_params.pressure_control_target_ratio_scale = pressure_control_target_ratio_scale;
    sim_params.pressure_control_duration_scale = pressure_control_duration_scale;
    sim_params.pressure_control_duration_exponent = pressure_control_duration_exponent;
    sim_params.pressure_control_duration_scale_adjusted = pressure_control_duration_scale_adjusted;
    sim_params.pressure_control_flow_scale = pressure_control_flow_scale;
    sim_params.pressure_control_duty_capacity_ratio = pressure_control_duty_capacity_ratio;
    sim_params.pressure_control_duty_pressure_capacity_ratio = pressure_control_duty_pressure_capacity_ratio;
    sim_params.pressure_control_duty_flow_scale = pressure_control_duty_flow_scale;
    sim_params.pressure_control_duty_capacity_exponent = pressure_control_duty_capacity_exponent;
    sim_params.pressure_control_duty_audit_ignore_initial_s = duty_audit_ignore_initial_s;
    sim_params.pressure_control_duty_reference_window_s = duty_reference_window_s;
    sim_params.pressure_control_duty_stage_window_s = duty_stage_window_s;
    sim_params.pressure_control_exponent = pressure_control_exponent;
    sim_params.sma_pipe_pressure_calibration_factor = sma_pipe_pressure_calibration_factor;
    sim_params.sma_pipe_pressure_calibration_method = sma_pipe_pressure_calibration_method;
    sim_params.sma_pipe_pressure_storage_fraction_exponent = default_pressure_exponent;
    sim_params.sma_pipe_pressure_actual_flush_trim_factor = pressure_trim_default;
    sim_params.sma_pipe_pressure_hydraulic_reference_volume_ml = sma_pipe_pressure_hydraulic_reference_volume_ml;
    sim_params.sma_pipe_pressure_storage_length_fraction = sma_pipe_pressure_storage_length_fraction;
    sim_params.sma_pipe_pressure_calibration_factor_field = factor_field_name;
    if strcmpi(stage_name, 'cooldown_exchange')
        pipe_blend_default = min(max(0.30 + 0.62 * (stage_duration_s - 0.4), 0.02), 0.50);
    else
        pipe_blend_default = min(max(0.13 + 0.62 * (stage_duration_s - 0.4), 0.02), 0.50);
    end
    sim_params.sma_pipe_internal_fluid_profile_blend_factor = get_option_field( ...
        exchange_options, 'sma_pipe_internal_fluid_profile_blend_factor', pipe_blend_default);
    sim_params.tank_pressure_MPa = tank_pressure_MPa;
    sim_params.Nuh = Nu;
    sim_params.nu = Nu;
    sim_params.nuh = Nu;
    sim_params.mh = cold_sink_C / thermal_mass_cp_ref;
    sim_params.Th = hot_sink_T_init;
    sim_params.T_fluid = ambient_T_init;
    sim_params.ambient_T_init = ambient_T_init;
    sim_params.hot_sink_T_init = hot_sink_T_init;
    sim_params.cold_sink_T_init = cold_sink_T_init;
    sim_params.chip_T_init = chip_T_init;
    sim_params.cold_load_model_version = 'cold_load_external_to_chex_v1';
    sim_params.cold_load_mode = cold_load_mode;
    sim_params.cold_load_T_init = cold_load_T_init;
    sim_params.hot_buffer_temp_current = hot_buffer_temp_current;
    sim_params.cold_buffer_temp_current = cold_buffer_temp_current;
    cold_pipe_or_CHEX_T_state = get_option_field(runtime, 'cold_pipe_or_CHEX_T_state_K', cold_buffer_temp_current);
    if ~(isnumeric(cold_pipe_or_CHEX_T_state) && isscalar(cold_pipe_or_CHEX_T_state) && isfinite(cold_pipe_or_CHEX_T_state))
        cold_pipe_or_CHEX_T_state = cold_buffer_temp_current;
    end
    cold_hx_pipe_T_state = get_option_field(runtime, 'cold_hx_pipe_T_state_K', cold_pipe_or_CHEX_T_state);
    if ~(isnumeric(cold_hx_pipe_T_state) && isscalar(cold_hx_pipe_T_state) && isfinite(cold_hx_pipe_T_state))
        cold_hx_pipe_T_state = cold_pipe_or_CHEX_T_state;
    end
    cold_return_pipe_T_state = get_option_field(runtime, 'cold_return_pipe_T_state_K', cold_pipe_or_CHEX_T_state);
    if ~(isnumeric(cold_return_pipe_T_state) && isscalar(cold_return_pipe_T_state) && isfinite(cold_return_pipe_T_state))
        cold_return_pipe_T_state = cold_pipe_or_CHEX_T_state;
    end
    % Transit pipe T_init: prefer the new runtime key transit_pipe_T_state_K
    % (post-stage4 end temperature of the Simulink TransitPipe). Accept legacy
    % stage4_sma_to_CHEX_transit_T_state_K as an alias for resume-from-old runs.
    % First-cycle fallback uses hot_buffer_temp_current, since the fluid sitting
    % between V6 and CHEX before any cooldown has flushed comes from hot side.
    transit_pipe_T_state = get_option_field(runtime, 'transit_pipe_T_state_K', NaN);
    if ~(isnumeric(transit_pipe_T_state) && isscalar(transit_pipe_T_state) && ...
            isfinite(transit_pipe_T_state))
        transit_pipe_T_state = get_option_field(runtime, ...
            'stage4_sma_to_CHEX_transit_T_state_K', hot_buffer_temp_current);
    end
    if ~(isnumeric(transit_pipe_T_state) && isscalar(transit_pipe_T_state) && ...
            isfinite(transit_pipe_T_state))
        transit_pipe_T_state = hot_buffer_temp_current;
    end
    sim_params.hot_side_fluid_T_init = hot_buffer_temp_current;
    sim_params.cold_side_fluid_T_init = cold_pipe_or_CHEX_T_state;
    sim_params.cold_pipe_or_CHEX_T_state_in_K = cold_pipe_or_CHEX_T_state;
    sim_params.cold_pipe_or_CHEX_T_state_source = 'runtime_cold_pipe_or_CHEX_T_state_or_cold_buffer_first_cycle';
    sim_params.cold_hx_pipe_T_init = cold_hx_pipe_T_state;
    sim_params.cold_hx_pipe_T_state_in_K = cold_hx_pipe_T_state;
    sim_params.cold_hx_pipe_T_state_source = 'runtime_cold_hx_pipe_T_state_or_legacy_cold_pipe_state';
    sim_params.cold_return_pipe_T_init = cold_return_pipe_T_state;
    sim_params.cold_return_pipe_T_state_in_K = cold_return_pipe_T_state;
    sim_params.cold_return_pipe_T_state_source = 'runtime_cold_return_pipe_T_state_or_legacy_cold_pipe_state';
    sim_params.transit_pipe_T_init = transit_pipe_T_state;
    sim_params.transit_pipe_T_state_in_K = transit_pipe_T_state;
    sim_params.transit_pipe_T_state_source = 'runtime_transit_pipe_T_state_K_or_hot_buffer_first_cycle';
    % Backward-compat aliases.
    sim_params.stage4_sma_to_CHEX_transit_T_state_in_K = transit_pipe_T_state;
    sim_params.stage4_sma_to_CHEX_transit_T_state_source = sim_params.transit_pipe_T_state_source;
    sma_fluid_T_init_policy = char(string(get_option_field(exchange_options, ...
        'sma_fluid_T_init_policy', 'same_path_carryover')));
    sma_fluid_T_init_policy = lower(strtrim(sma_fluid_T_init_policy));
    if isempty(sma_fluid_T_init_policy)
        sma_fluid_T_init_policy = 'same_path_carryover';
    end
    valid_sma_fluid_T_init_policies = {'same_path_carryover', ...
        'previous_active_stage_pipe', 'shared_pipe_previous_stage', ...
        'opposite_path_carryover', 'previous_exchange_sma_avg', ...
        'stage_buffer_temperature'};
    if ~any(strcmp(sma_fluid_T_init_policy, valid_sma_fluid_T_init_policies))
        sma_fluid_T_init_policy = 'same_path_carryover';
    end
    sim_params.sma_fluid_T_init_policy = sma_fluid_T_init_policy;
    use_previous_exchange_sma_avg = strcmp(sma_fluid_T_init_policy, ...
        'previous_exchange_sma_avg');
    use_stage_buffer_temperature = strcmp(sma_fluid_T_init_policy, ...
        'stage_buffer_temperature');
    use_previous_active_stage_pipe = any(strcmp(sma_fluid_T_init_policy, ...
        {'previous_active_stage_pipe', 'shared_pipe_previous_stage', ...
        'opposite_path_carryover'}));
    if strcmpi(get_stage_field(stage_config, 'stage_kind', ''), 'hotflush')
        if use_stage_buffer_temperature
            hold_pipe_T = cold_buffer_temp_current;
            sma_fluid_T_init_source = 'stage2_cold_buffer_temperature';
        elseif use_previous_exchange_sma_avg
            hold_pipe_T = get_option_field(runtime, 'last_exchange_sma_avg_T_K', ...
                cold_buffer_temp_current);
            sma_fluid_T_init_source = 'previous_exchange_sma_avg_T_or_cold_buffer_first_cycle';
        elseif use_previous_active_stage_pipe
            hold_pipe_T = get_option_field(runtime, 'stage4_path_pipe_T_state_K', ...
                cold_buffer_temp_current);
            sma_fluid_T_init_source = 'previous_active_stage4_pipe_state_or_cold_buffer_first_cycle';
        else
            hold_pipe_T = get_option_field(runtime, 'stage2_path_pipe_T_state_K', ...
                get_option_field(runtime, 'hold_pipe_fluid_mean_T_current_K', cold_buffer_temp_current));
            sma_fluid_T_init_source = 'stage2_path_pipe_state_or_cold_buffer_first_cycle';
        end
        if ~(isnumeric(hold_pipe_T) && isscalar(hold_pipe_T) && isfinite(hold_pipe_T))
            hold_pipe_T = cold_buffer_temp_current;
        end
        sim_params.sma_fluid_T_init = hold_pipe_T;
        sim_params.sma_fluid_T_init_source = sma_fluid_T_init_source;
        sim_params.sma_fluid_T_carryover_diagnostic_K = hold_pipe_T;
        sim_params.stage2_path_pipe_T_state_in_K = hold_pipe_T;
        sim_params.stage2_path_pipe_reference_T_K = hold_pipe_T;
        if use_previous_exchange_sma_avg || use_stage_buffer_temperature
            sim_params.stage2_path_pipe_unreleased_cumulative_in_J = 0.0;
        else
            sim_params.stage2_path_pipe_unreleased_cumulative_in_J = get_option_field(runtime, ...
                'stage2_path_pipe_unreleased_cumulative_J', 0.0);
        end
        sim_params.stage4_path_pipe_T_state_in_K = get_option_field(runtime, ...
            'stage4_path_pipe_T_state_K', hot_buffer_temp_current);
        sim_params.stage4_path_pipe_unreleased_cumulative_in_J = get_option_field(runtime, ...
            'stage4_path_pipe_unreleased_cumulative_J', 0.0);
    elseif strcmpi(get_stage_field(stage_config, 'stage_kind', ''), 'coldflush')
        if use_stage_buffer_temperature
            cooldown_pipe_T = hot_buffer_temp_current;
            sma_fluid_T_init_source = 'stage4_hot_buffer_temperature';
        elseif use_previous_exchange_sma_avg
            cooldown_pipe_T = get_option_field(runtime, 'last_exchange_sma_avg_T_K', ...
                hot_buffer_temp_current);
            sma_fluid_T_init_source = 'previous_exchange_sma_avg_T_or_hot_buffer_first_cycle';
        elseif use_previous_active_stage_pipe
            cooldown_pipe_T = get_option_field(runtime, 'stage2_path_pipe_T_state_K', ...
                hot_buffer_temp_current);
            sma_fluid_T_init_source = 'previous_active_stage2_pipe_state_or_hot_buffer_first_cycle';
        else
            cooldown_pipe_T = get_option_field(runtime, 'stage4_path_pipe_T_state_K', ...
                get_option_field(runtime, 'cooldown_pipe_fluid_mean_T_current_K', hot_buffer_temp_current));
            sma_fluid_T_init_source = 'stage4_path_pipe_state_or_hot_buffer_first_cycle';
        end
        if ~(isnumeric(cooldown_pipe_T) && isscalar(cooldown_pipe_T) && isfinite(cooldown_pipe_T))
            cooldown_pipe_T = hot_buffer_temp_current;
        end
        sim_params.sma_fluid_T_init = cooldown_pipe_T;
        sim_params.sma_fluid_T_init_source = sma_fluid_T_init_source;
        sim_params.sma_fluid_T_carryover_diagnostic_K = cooldown_pipe_T;
        sim_params.stage4_path_pipe_T_state_in_K = cooldown_pipe_T;
        sim_params.stage4_path_pipe_reference_T_K = cooldown_pipe_T;
        if use_previous_exchange_sma_avg || use_stage_buffer_temperature
            sim_params.stage4_path_pipe_unreleased_cumulative_in_J = 0.0;
        else
            sim_params.stage4_path_pipe_unreleased_cumulative_in_J = get_option_field(runtime, ...
                'stage4_path_pipe_unreleased_cumulative_J', 0.0);
        end
        sim_params.stage2_path_pipe_T_state_in_K = get_option_field(runtime, ...
            'stage2_path_pipe_T_state_K', cold_buffer_temp_current);
        sim_params.stage2_path_pipe_unreleased_cumulative_in_J = get_option_field(runtime, ...
            'stage2_path_pipe_unreleased_cumulative_J', 0.0);
    else
        sim_params.sma_fluid_T_init = 0.5 * (hot_buffer_temp_current + cold_buffer_temp_current);
        sim_params.sma_fluid_T_init_source = 'non_exchange_mean_buffer_temperature';
        sim_params.sma_fluid_T_carryover_diagnostic_K = sim_params.sma_fluid_T_init;
        sim_params.stage2_path_pipe_T_state_in_K = cold_buffer_temp_current;
        sim_params.stage4_path_pipe_T_state_in_K = hot_buffer_temp_current;
        sim_params.stage2_path_pipe_unreleased_cumulative_in_J = 0.0;
        sim_params.stage4_path_pipe_unreleased_cumulative_in_J = 0.0;
    end
    sim_params.root_hot_loop_T_init = hot_buffer_temp_current;
    sim_params.root_cold_loop_T_init = cold_buffer_temp_current;
    sim_params.chip_heat_W = chip_heat_W;
    sim_params.cold_load_heat_W = cold_load_heat_W;
    sim_params.hot_sink_C_J_per_K = hot_sink_C;
    sim_params.cold_sink_C_J_per_K = cold_sink_C;
    sim_params.hot_sink_effective_C_J_per_K = hot_sink_C;
    sim_params.cold_sink_effective_C_J_per_K = cold_sink_C;
    sim_params.hot_sink_effective_water_volume_ml = hot_sink_C / max(rho_water * cp_water, eps) * 1.0e6;
    sim_params.cold_sink_effective_water_volume_ml = cold_sink_C / max(rho_water * cp_water, eps) * 1.0e6;
    sim_params.hot_sink_C_semantics = 'effective_heat_exchanger_mixed_thermal_capacity_not_full_reservoir';
    sim_params.cold_sink_C_semantics = 'effective_heat_exchanger_mixed_thermal_capacity_not_full_reservoir';
    sim_params.chip_C_J_per_K = chip_C;
    sim_params.cold_load_C_J_per_K = cold_load_C;
    sim_params.hot_sink_mass_kg = hot_sink_C / thermal_mass_cp_ref;
    sim_params.cold_sink_mass_kg = cold_sink_C / thermal_mass_cp_ref;
    sim_params.chip_mass_kg = chip_C / thermal_mass_cp_ref;
    sim_params.cold_load_mass_kg = cold_load_C / thermal_mass_cp_ref;
    sim_params.thermal_mass_cp_ref = thermal_mass_cp_ref;
    sim_params.hot_sink_ambient_G_W_per_K = hot_sink_ambient_G;
    sim_params.cold_sink_ambient_G_W_per_K = cold_sink_ambient_G;
    sim_params.cold_sink_ambient_G_configured_W_per_K = cold_sink_ambient_G_configured;
    sim_params.cold_sink_ambient_G_hold_W_per_K = cold_sink_ambient_G_hold;
    sim_params.cold_sink_ambient_G_cooldown_W_per_K = cold_sink_ambient_G_cooldown;
    sim_params.chip_ambient_G_W_per_K = chip_ambient_G;
    sim_params.cold_load_ambient_G_W_per_K = cold_load_ambient_G;
    sim_params.hot_sink_fluid_G_W_per_K = hot_sink_fluid_G;
    sim_params.cold_sink_fluid_G_W_per_K = cold_sink_fluid_G;
    sim_params.cold_sink_fluid_G_hold_W_per_K = cold_sink_fluid_G_hold;
    sim_params.cold_sink_fluid_G_cooldown_W_per_K = cold_sink_fluid_G_cooldown;
    sim_params.cold_sink_stage_coupling_policy = cold_sink_stage_coupling_policy;
    sim_params.chip_fluid_G_W_per_K = chip_fluid_G;
    sim_params.cold_load_to_cold_sink_G_W_per_K = cold_load_to_cold_sink_G;
    sim_params.cold_load_to_cold_sink_G_hold_W_per_K = cold_load_to_cold_sink_G_hold;
    sim_params.cold_load_to_cold_sink_G_cooldown_W_per_K = cold_load_to_cold_sink_G_cooldown;
    sim_params.cold_load_coupling_stage_policy = cold_load_coupling_stage_policy;
    sim_params.cold_load_heat_policy = char(string(get_option_field(exchange_options, ...
        'cold_load_heat_policy', 'continuous_load_isolated_except_cooldown')));
    sim_params.chip_fluid_G_configured_W_per_K = chip_fluid_G_cooldown_configured;
    sim_params.chip_fluid_G_cooldown_W_per_K = chip_fluid_G;
    sim_params.chip_fluid_G_hold_W_per_K = chip_fluid_G_hold;
    sim_params.chip_fluid_G_effective_W_per_K = chip_fluid_G;
    sim_params.chip_fluid_G_model = chip_model.chip_fluid_G_model;
    sim_params.chip_fluid_G_reference_W_per_K = chip_model.chip_fluid_G_reference_W_per_K;
    sim_params.chip_fluid_G_uncapped_W_per_K = chip_model.chip_fluid_G_uncapped_W_per_K;
    sim_params.chip_fluid_G_cap_W_per_K = chip_model.chip_fluid_G_cap_W_per_K;
    sim_params.chip_fluid_G_cap_active = chip_model.chip_fluid_G_cap_active;
    sim_params.chip_fluid_G_scale = chip_model.chip_fluid_G_scale;
    sim_params.chip_contact_area_m2 = chip_model.chip_contact_area_m2;
    sim_params.chip_D_h_m = chip_model.chip_D_h_m;
    sim_params.chip_channel_hydraulic_diameter_m = chip_model.chip_D_h_m;
    sim_params.chip_channel_flow_area_m2 = chip_model.chip_channel_flow_area_m2;
    sim_params.chip_channel_length_m = chip_model.chip_channel_length_m;
    sim_params.chip_v_fluid_m_per_s = chip_model.chip_v_fluid_m_per_s;
    sim_params.chip_Re = chip_model.chip_Re;
    sim_params.chip_Nu = chip_model.chip_Nu;
    sim_params.chip_h_conv_W_per_m2K = chip_model.chip_h_conv_W_per_m2K;
    sim_params.chip_flow_regime = chip_model.chip_flow_regime;
    sim_params.chip_R_conv_K_per_W = chip_model.chip_R_conv_K_per_W;
    sim_params.chip_R_package_K_per_W = chip_model.chip_R_package_K_per_W;
    sim_params.chip_R_contact_K_per_W = chip_model.chip_R_contact_K_per_W;
    sim_params.chip_R_wall_K_per_W = chip_model.chip_R_wall_K_per_W;
    sim_params.chip_R_total_K_per_W = chip_model.chip_R_total_K_per_W;
    sim_params.chip_fluid_coupling_mode = chip_fluid_coupling_mode;
    sim_params.chip_heat_dry_equilibrium_W = chip_heat_dry_equilibrium_W;
    sim_params.chip_heat_default_W = chip_heat_default_W;
    sim_params.chip_heat_default_source = sim_params.cold_load_heat_policy;
    % R68 splits the previous ColdSinkPipe into a physical HX segment plus an
    % adiabatic return segment. Only the HX segment is thermally coupled to the
    % 1 ml ColdSinkMass; the return segment keeps hydraulic/storage carryover
    % without being allowed to inject heat directly into the cold sink.
    cold_hx_pipe_length_fraction = get_option_field(exchange_options, ...
        'cold_hx_pipe_length_fraction', 0.50);
    if strcmp(cold_end_topology_mode, 'r69_symmetric')
        cold_hx_pipe_length_fraction = 1.0;
    end
    if ~(isnumeric(cold_hx_pipe_length_fraction) && isscalar(cold_hx_pipe_length_fraction) && ...
            isfinite(cold_hx_pipe_length_fraction))
        cold_hx_pipe_length_fraction = 0.50;
    end
    cold_hx_pipe_length_fraction = min(max(cold_hx_pipe_length_fraction, 0.05), 0.95);
    if strcmp(cold_end_topology_mode, 'r69_symmetric')
        cold_hx_pipe_length_fraction = 1.0;
    end
    cold_hx_pipe_length_m = tube_l * cold_hx_pipe_length_fraction;
    cold_return_pipe_length_m = tube_l - cold_hx_pipe_length_m;
    cold_hx_pipe_volume_m3 = pipe_fa * cold_hx_pipe_length_m;
    cold_return_pipe_volume_m3 = pipe_fa * cold_return_pipe_length_m;
    cold_hx_pipe_C_J_per_K = rho_water * cp_water * max(cold_hx_pipe_volume_m3, 0.0);
    cold_return_pipe_C_J_per_K = rho_water * cp_water * max(cold_return_pipe_volume_m3, 0.0);
    cold_sink_pipe_total_volume_m3 = cold_hx_pipe_volume_m3 + cold_return_pipe_volume_m3;
    if strcmp(cold_end_topology_mode, 'r69_symmetric')
        default_cold_pipe_or_CHEX_volume_m3 = pipe_fa * tube_l;
    else
        default_cold_pipe_or_CHEX_volume_m3 = cold_hx_pipe_volume_m3;
    end
    cold_pipe_or_CHEX_volume_m3 = get_option_field(exchange_options, ...
        'cold_pipe_or_CHEX_volume_m3', default_cold_pipe_or_CHEX_volume_m3);
    cold_pipe_or_CHEX_C_J_per_K = get_option_field(exchange_options, ...
        'cold_pipe_or_CHEX_C_J_per_K', rho_water * cp_water * max(cold_pipe_or_CHEX_volume_m3, 0.0));
    cold_pipe_or_CHEX_effective_storage_fraction = get_option_field(exchange_options, ...
        'cold_pipe_or_CHEX_effective_storage_fraction', ...
        min(max(target_flush_volume_m3 / max(cold_pipe_or_CHEX_volume_m3, eps), 0.0), 1.0));
    cold_pipe_or_CHEX_effective_storage_fraction = min(max(cold_pipe_or_CHEX_effective_storage_fraction, 0.0), 1.0);
    cold_end_C_total = cold_sink_C + cold_fluid_buffer_C + cold_hx_pipe_C_J_per_K;
    cold_end_external_mixer_enabled = logical(get_option_field(exchange_options, ...
        'cold_end_external_mixer_enabled', true));
    if cold_end_external_mixer_enabled
        default_cold_end_definition = 'external_cold_end_mixer_CHEX_boundary_enthalpy_state_v1';
        default_cold_end_sync_policy = ['cooldown_end_external_mixer_written_to_cold_official_state; ', ...
            'inactive_stages_freeze_previous_cooldown_state'];
    else
        default_cold_end_definition = 'entity_cold_end_storage_sum_v1';
        default_cold_end_sync_policy = ['cooldown_end_entity_energy_weighted_temperature_written_to_cold_sink_and_cold_buffer; ', ...
            'hold_end_cold_buffer_probe_not_written_back'];
    end
    sim_params.cold_end_external_mixer_enabled = cold_end_external_mixer_enabled;
    sim_params.cold_sink_pipe_split_enabled = ~strcmp(cold_end_topology_mode, 'r69_symmetric');
    sim_params.cold_pipe_or_CHEX_length_m = tube_l;
    sim_params.cold_hx_pipe_length_fraction = cold_hx_pipe_length_fraction;
    sim_params.cold_hx_pipe_length_m = cold_hx_pipe_length_m;
    sim_params.cold_return_pipe_length_m = cold_return_pipe_length_m;
    sim_params.cold_hx_pipe_volume_m3 = cold_hx_pipe_volume_m3;
    sim_params.cold_hx_pipe_volume_ml = cold_hx_pipe_volume_m3 * 1.0e6;
    sim_params.cold_return_pipe_volume_m3 = cold_return_pipe_volume_m3;
    sim_params.cold_return_pipe_volume_ml = cold_return_pipe_volume_m3 * 1.0e6;
    sim_params.cold_hx_pipe_C_J_per_K = cold_hx_pipe_C_J_per_K;
    sim_params.cold_return_pipe_C_J_per_K = cold_return_pipe_C_J_per_K;
    sim_params.cold_sink_pipe_total_volume_m3 = cold_sink_pipe_total_volume_m3;
    sim_params.cold_sink_pipe_total_volume_ml = cold_sink_pipe_total_volume_m3 * 1.0e6;
    sim_params.cold_sink_pipe_total_C_J_per_K = cold_hx_pipe_C_J_per_K + cold_return_pipe_C_J_per_K;
    if strcmp(cold_end_topology_mode, 'r69_symmetric')
        sim_params.cold_sink_pipe_split_contract = ...
            'R69 symmetric cold end: single ColdSinkPipe mirrors HotPipe; no TransitPipe, no return pipe, no cold ambient branch.';
    else
        sim_params.cold_sink_pipe_split_contract = ...
            'ColdSinkMass couples only to ColdSinkHXPipe; ColdSinkReturnPipe is adiabatic hydraulic/storage carryover.';
    end
    sim_params.official_cold_end_definition = char(string(get_option_field(exchange_options, ...
        'official_cold_end_definition', default_cold_end_definition)));
    sim_params.official_cold_end_control_mode = char(string(get_option_field(exchange_options, ...
        'official_cold_end_control_mode', default_cold_end_definition)));
    sim_params.cold_pipe_or_CHEX_volume_m3 = cold_pipe_or_CHEX_volume_m3;
    sim_params.cold_pipe_or_CHEX_C_J_per_K = cold_pipe_or_CHEX_C_J_per_K;
    if strcmp(cold_end_topology_mode, 'r69_symmetric')
        sim_params.cold_pipe_or_CHEX_volume_source = 'R69_single_ColdSinkPipe_mirrors_HotPipe_no_transit_or_return';
    else
        sim_params.cold_pipe_or_CHEX_volume_source = 'R68_official_CHEX_volume_ColdSinkHXPipe_only_return_pipe_excluded';
    end
    sim_params.cold_pipe_or_CHEX_storage_model = char(string(get_option_field(exchange_options, ...
        'cold_pipe_or_CHEX_storage_model', 'chex_50point_refreshed_fraction_blend_observed_no_residual_writeback_v1')));
    sim_params.cold_pipe_or_CHEX_default_volume_m3 = default_cold_pipe_or_CHEX_volume_m3;
    sim_params.cold_pipe_or_CHEX_effective_storage_fraction = cold_pipe_or_CHEX_effective_storage_fraction;
    sim_params.cold_pipe_or_CHEX_effective_C_J_per_K = ...
        cold_pipe_or_CHEX_C_J_per_K * cold_pipe_or_CHEX_effective_storage_fraction;
    sim_params.cold_end_C_total_J_per_K = cold_end_C_total;
    sim_params.cold_end_effective_water_volume_ml = cold_end_C_total / max(rho_water * cp_water, eps) * 1.0e6;
    sim_params.cold_end_includes_cold_sink_mass = true;
    sim_params.cold_end_includes_cold_fluid_buffer = true;
    sim_params.cold_end_includes_cold_pipe_or_CHEX = true;
    sim_params.cold_end_includes_cold_hx_pipe = true;
    sim_params.cold_end_includes_cold_return_pipe = false;
    sim_params.cold_fluid_buffer_stage2_role = 'source_boundary_supply_only_not_official_cold_end_receiver';
    sim_params.cold_buffer_hold_writeback_allowed = false;
    sim_params.cold_end_state_sync_policy = char(string(get_option_field(exchange_options, ...
        'cold_end_state_sync_policy', default_cold_end_sync_policy)));
    hot_pipe_or_HHEX_volume_m3 = get_option_field(exchange_options, ...
        'hot_pipe_or_HHEX_volume_m3', cold_pipe_or_CHEX_volume_m3);
    hot_pipe_or_HHEX_C_J_per_K = get_option_field(exchange_options, ...
        'hot_pipe_or_HHEX_C_J_per_K', rho_water * cp_water * max(hot_pipe_or_HHEX_volume_m3, 0.0));
    hot_end_C_total = hot_sink_C + hot_fluid_buffer_C + hot_pipe_or_HHEX_C_J_per_K;
    sim_params.official_hot_end_definition = char(string(get_option_field(exchange_options, ...
        'official_hot_end_definition', 'external_hot_end_mixer_boundary_enthalpy_state_v1')));
    sim_params.official_hot_end_control_mode = char(string(get_option_field(exchange_options, ...
        'official_hot_end_control_mode', 'external_hot_end_mixer_boundary_enthalpy_state_v1')));
    sim_params.hot_pipe_or_HHEX_volume_m3 = hot_pipe_or_HHEX_volume_m3;
    sim_params.hot_pipe_or_HHEX_C_J_per_K = hot_pipe_or_HHEX_C_J_per_K;
    sim_params.hot_end_C_total_J_per_K = hot_end_C_total;
    sim_params.hot_end_effective_water_volume_ml = hot_end_C_total / max(rho_water * cp_water, eps) * 1.0e6;
    sim_params.hot_end_includes_hot_sink_mass = true;
    sim_params.hot_end_includes_hot_fluid_buffer = true;
    sim_params.hot_end_includes_hot_pipe_or_HHEX = true;
    sim_params.hot_fluid_buffer_stage4_role = 'source_boundary_supply_only_not_official_hot_end_receiver';
    sim_params.hot_buffer_cooldown_writeback_allowed = false;
    sim_params.hot_end_state_sync_policy = 'hold_end_external_mixer_written_to_hot_sink_and_hot_buffer; cooldown_hot_buffer_probe_not_written_back';
    sim_params.probe_sample_count = probe_sample_count;
    sim_params.flush_volume_target_ratio = flush_volume_target_ratio;
    sim_params.target_flush_volume_ratio = target_flush_volume_ratio;
    sim_params.target_flush_volume_m3 = target_flush_volume_m3;
    sim_params.flush_volume_m3 = flush_volume_m3;
    sim_params.flush_volume_ratio = flush_volume_ratio;
    sim_params.flush_volume_control_abs_tolerance = get_option_field(exchange_options, ...
        'flush_volume_control_abs_tolerance', 0.05);
    sim_params.flush_volume_control_rel_tolerance = get_option_field(exchange_options, ...
        'flush_volume_control_rel_tolerance', 0.05);
    if strcmpi(stage_name, 'cooldown_exchange')
        cooldown_audit_ignore_default = default_cooldown_audit_ignore_initial_s(stage_duration_s);
        audit_ignore_default = get_option_field(exchange_options, ...
            'actual_flush_audit_ignore_initial_s_cooldown', cooldown_audit_ignore_default);
        if audit_ignore_default > 0
            audit_mode_default = 'post_initial_hydraulic_settling_window_v1';
        else
            audit_mode_default = 'full_stage_integral';
        end
    elseif strcmpi(stage_name, 'hold_exchange')
        audit_ignore_default = get_option_field(exchange_options, ...
            'actual_flush_audit_ignore_initial_s_hold', 0.0);
        audit_mode_default = 'full_stage_integral';
    else
        audit_ignore_default = 0.0;
        audit_mode_default = 'not_exchange_stage';
    end
    sim_params.actual_flush_audit_ignore_initial_s = max(0.0, get_option_field( ...
        exchange_options, 'actual_flush_audit_ignore_initial_s', audit_ignore_default));
    sim_params.actual_flush_audit_mode = char(string(get_option_field( ...
        exchange_options, 'actual_flush_audit_mode', audit_mode_default)));
    sim_params.allow_flush_volume_ratio_out_of_gate = allow_flush_volume_ratio_out_of_gate;
    sim_params.plate_volume_m3 = plate_volume_m3;
    sim_params.water_contact_area_m2 = water_contact_area_m2;
    sim_params.water_contact_area_mode = 'single_side_plate_area';
    sim_params.hot_fluid_buffer_T_init = hot_buffer_temp_current;
    sim_params.cold_fluid_buffer_T_init = cold_buffer_temp_current;
    sim_params.shex_sink_T_init = shex_sink_T_init;
    sim_params.shex_source_T_init = shex_source_T_init;
    sim_params.shex_fluid_buffer_T_init = get_option_field(exchange_options, ...
        'shex_fluid_buffer_T_init', shex_sink_T_init);
    sim_params.buffer_follow_sink_enabled = buffer_follow_sink_enabled;
    sim_params.buffer_follow_sink_policy_source = buffer_follow_sink_policy_source;
    sim_params.buffer_effective_energy_accounting_enabled = buffer_effective_energy_accounting_enabled;
    sim_params.buffer_effective_energy_accounting_source = buffer_effective_energy_accounting_source;
    sim_params.hot_fluid_buffer_C_J_per_K = hot_fluid_buffer_C;
    sim_params.cold_fluid_buffer_C_J_per_K = cold_fluid_buffer_C;
    sim_params.fluid_buffer_cp_ref = fluid_buffer_cp_ref;
    sim_params.fluid_buffer_reference_ratio = fluid_buffer_reference_ratio;
    sim_params.fluid_buffer_reference_volume_m3 = fluid_buffer_reference_volume_m3;
    sim_params.fluid_buffer_volume_m3 = fluid_buffer_volume_m3;
    sim_params.fluid_buffer_tank_area_m2 = fluid_buffer_tank_area_m2;
    sim_params.fluid_buffer_tank_level_m = fluid_buffer_tank_level_m;
    sim_params.fluid_buffer_max_capacity_m3 = fluid_buffer_max_capacity_m3;
    sim_params.sma_pipe_thermal_gate_enabled = sma_pipe_thermal_gate_enabled;
    sim_params.sma_pipe_thermal_gate_active_G_W_per_K = sma_pipe_thermal_gate_active_G_W_per_K;
    sim_params.sma_pipe_thermal_gate_inactive_G_W_per_K = sma_pipe_thermal_gate_inactive_G_W_per_K;
    sim_params.sma_hold_pipe_to_sma_G_W_per_K = sma_hold_pipe_to_sma_G_W_per_K;
    sim_params.sma_cooldown_pipe_to_sma_G_W_per_K = sma_cooldown_pipe_to_sma_G_W_per_K;
    sim_params.sma_pipe_thermal_gate_active_path = sma_pipe_thermal_gate_active_path;
    sim_params.flush_ratio_warning = (~use_closed_valve_flow) && ...
        (flush_volume_ratio < 0.5 || flush_volume_ratio > 1.0);
    sim_params.exchange_backend_kind = exchange_backend_kind;

    if strcmp(exchange_backend_kind, 'simulink_axial_21')
        target_count = thermal_model_node_count;
        [T_internal_init, initialization_report] = resize_temperature_vector(T_init(:), target_count);
        [carryover_T_x, carryover_source] = get_path_Tx21_carryover( ...
            get_stage_field(stage_config, 'stage_name', ''), runtime, target_count);
        if ~isempty(carryover_T_x)
            T_internal_init = carryover_T_x(:);
            initialization_report = struct( ...
                'initial_state_kind', 'path_axial_21_carryover', ...
                'final_exchange_state_must_be_directional', true, ...
                'source_node_count', numel(T_init), ...
                'target_strip_count', numel(T_internal_init), ...
                'source_min_T', min(T_init), ...
                'source_max_T', max(T_init), ...
                'target_min_T', min(T_internal_init), ...
                'target_max_T', max(T_internal_init), ...
                'carryover_source', carryover_source);
        end
        sim_params.solver_T_init_21_internal = T_internal_init(:);
        sim_params.solver_internal_21_strip_count = numel(T_internal_init);
        sim_params.solver_internal_21_initialization_report = initialization_report;
        sim_params.solver_internal_temperature_workspace_var = 'Tx21_internal';
    end
end

function [T_out, report] = resize_temperature_vector(T_in, target_count)
    T_in = T_in(:);
    if target_count <= 0 || target_count ~= round(target_count)
        error('Build_Simulink_Exchange_Params:InvalidInternalNodeCount', ...
            'Internal Simulink node count must be a positive integer.');
    end
    if numel(T_in) == target_count
        T_out = T_in;
        mode = 'direct_node_count_match';
    elseif numel(T_in) == 1
        T_out = repmat(T_in, target_count, 1);
        mode = 'scalar_replicated_to_internal_nodes';
    else
        x_in = linspace(0.0, 1.0, numel(T_in)).';
        x_out = linspace(0.0, 1.0, target_count).';
        T_out = interp1(x_in, T_in, x_out, 'linear');
        mode = 'linear_resample_to_internal_nodes';
    end
    report = struct( ...
        'initial_state_kind', mode, ...
        'final_exchange_state_must_be_directional', true, ...
        'source_node_count', numel(T_in), ...
        'target_strip_count', numel(T_out), ...
        'source_min_T', min(T_in), ...
        'source_max_T', max(T_in), ...
        'target_min_T', min(T_out), ...
        'target_max_T', max(T_out));
end

function [T_x, source] = get_path_Tx21_carryover(stage_name, runtime, expected_count)
    T_x = [];
    source = '';
    if ~isstruct(runtime)
        return;
    end
    if ~strcmpi(char(string(get_option_field(runtime, 'last_stage_name', ''))), char(string(stage_name)))
        return;
    end
    if strcmpi(char(string(stage_name)), 'hold_exchange')
        field_candidates = {'stage2_T_x_21_state'};
    elseif strcmpi(char(string(stage_name)), 'cooldown_exchange')
        field_candidates = {'stage4_T_x_21_state'};
    else
        return;
    end
    for idx = 1:numel(field_candidates)
        field_name = field_candidates{idx};
        if ~isfield(runtime, field_name) || isempty(runtime.(field_name))
            continue;
        end
        candidate = runtime.(field_name)(:);
        if numel(candidate) == expected_count && all(isfinite(candidate))
            T_x = candidate;
            source = field_name;
            return;
        end
    end
end

function exchange_backend_kind = normalize_exchange_backend_kind(value)
    exchange_backend_kind = char(string(value));
    if isempty(strtrim(exchange_backend_kind)) || strcmpi(exchange_backend_kind, 'simulink_directional_101')
        exchange_backend_kind = 'simulink_axial_21';
    end
    if ~strcmp(exchange_backend_kind, 'simulink_axial_21')
        error('Build_Simulink_Exchange_Params:UnsupportedBackend', ...
            'Only the 21-node axial Simulink SE backend is supported, got %s.', exchange_backend_kind);
    end
end

function audit_ignore_initial_s = compute_audit_ignore_initial_s(stage_name, exchange_options, stage_duration_s)
    if nargin < 3 || isempty(stage_duration_s)
        stage_duration_s = NaN;
    end
    if strcmpi(stage_name, 'cooldown_exchange')
        cooldown_default = default_cooldown_audit_ignore_initial_s(stage_duration_s);
        default_value = get_option_field(exchange_options, ...
            'actual_flush_audit_ignore_initial_s_cooldown', cooldown_default);
    elseif strcmpi(stage_name, 'hold_exchange')
        default_value = get_option_field(exchange_options, ...
            'actual_flush_audit_ignore_initial_s_hold', 0.0);
    else
        default_value = 0.0;
    end
    audit_ignore_initial_s = max(0.0, get_option_field(exchange_options, ...
        'actual_flush_audit_ignore_initial_s', default_value));
end

function value = default_cooldown_audit_ignore_initial_s(stage_duration_s)
    if isfinite(stage_duration_s) && stage_duration_s <= 0.25 + 1.0e-12
        value = 0.0;
    else
        value = 0.10;
    end
end

function config = build_sma_stage13_startup_config(stage_config, exchange_options, ...
        stage_duration_s, nominal_mdot_kgps)
    stage_name = lower(strtrim(char(string(get_stage_field(stage_config, 'stage_name', '')))));
    stage_id = get_stage_field(stage_config, 'stage_id', NaN);
    valve_order = { ...
        'SMA_V1_SHEX_to_pump', ...
        'SMA_V2_HHEX_to_pump', ...
        'SMA_V3_pump_to_heat_path', ...
        'SMA_V4_pump_to_cool_path', ...
        'SMA_V5_SMA_to_SHEX', ...
        'SMA_V6_SMA_to_HHEX'};

    stage1_names = {'load_adiabatic', 'sma_heat_load', 'stage1', 'stage_1', ...
        'sma_stage1_heat_load', 'heat_load'};
    stage3_names = {'unload_adiabatic', 'sma_cool_unload', 'stage3', 'stage_3', ...
        'sma_stage3_cool_unload', 'cool_unload'};
    is_stage1 = any(strcmpi(stage_name, stage1_names)) || ...
        (isnumeric(stage_id) && isscalar(stage_id) && isfinite(stage_id) && round(stage_id) == 1);
    is_stage3 = any(strcmpi(stage_name, stage3_names)) || ...
        (isnumeric(stage_id) && isscalar(stage_id) && isfinite(stage_id) && round(stage_id) == 3);

    if is_stage1
        command_target = [1 0 1 0 1 0];
        route_name = 'shex_buffer_to_sma_to_shex';
        route_description = ['Stage 1 active SMA route: SHEXFluidBuffer -> ', ...
            'SMA_V1 -> SMA pump -> SMA_V3 -> SMA hold path Conn1/Conn2 -> ', ...
            'SMA_V5 -> SHEX -> SHEXFluidBuffer.'];
    elseif is_stage3
        command_target = [0 1 0 1 0 1];
        route_name = 'hhex_buffer_to_sma_to_hhex';
        route_description = ['Stage 3 active SMA route: HotFluidBuffer/HHEX -> ', ...
            'SMA_V2 -> SMA pump -> SMA_V4 -> SMA cooldown path Conn3/Conn4 -> ', ...
            'SMA_V6 -> HHEX SMA branch -> HotFluidBuffer.'];
    else
        command_target = zeros(1, 6);
        route_name = 'sma_stage13_inactive';
        route_description = 'SMA stage-1/3 valves closed; SE-side stage uses the mature V1-V6 network.';
    end

    active_scale = get_option_field(exchange_options, 'sma_stage13_active_valve_opening_scale', ...
        get_option_field(exchange_options, 'active_valve_opening_scale', 1.0));
    if ~(isnumeric(active_scale) && isscalar(active_scale) && isfinite(active_scale))
        active_scale = 1.0;
    end
    active_scale = min(max(double(active_scale), 0.0), 1.0);
    command_target = command_target * active_scale;

    closed_opening = get_option_field(exchange_options, 'sma_stage13_closed_valve_opening', ...
        get_option_field(exchange_options, 'exchange_startup_closed_valve_opening', 0.0));
    if ~(isnumeric(closed_opening) && isscalar(closed_opening) && isfinite(closed_opening))
        closed_opening = 0.0;
    end
    closed_opening = min(max(double(closed_opening), 0.0), 1.0);

    startup_enabled = logical(get_option_field(exchange_options, ...
        'sma_stage13_startup_smoothing_enabled', get_option_field(exchange_options, ...
        'exchange_startup_smoothing_enabled', true)));
    if is_stage1
        requested_ramp_s = get_option_field(exchange_options, ...
            'sma_stage13_startup_ramp_s_stage1', get_option_field(exchange_options, ...
            'sma_stage13_startup_ramp_s', get_option_field(exchange_options, ...
            'exchange_startup_ramp_s', 0.002)));
    elseif is_stage3
        requested_ramp_s = get_option_field(exchange_options, ...
            'sma_stage13_startup_ramp_s_stage3', get_option_field(exchange_options, ...
            'sma_stage13_startup_ramp_s', get_option_field(exchange_options, ...
            'exchange_startup_ramp_s', 0.002)));
    else
        requested_ramp_s = 0.0;
    end
    if ~(isnumeric(requested_ramp_s) && isscalar(requested_ramp_s) && isfinite(requested_ramp_s))
        requested_ramp_s = 0.0;
    end
    ramp_s = min(max(double(requested_ramp_s), 0.0), 0.25 * max(stage_duration_s, eps));

    active_mask = command_target ~= 0;
    if startup_enabled && any(active_mask) && ramp_s > 0
        command_initial = command_target;
        command_initial(active_mask) = closed_opening;
        time_s = [0.0; ramp_s; max(stage_duration_s, eps)];
        values = [command_initial; command_target; command_target];
        startup_profile = 'linear_valve_ramp_for_sma_stage13';
    else
        command_initial = command_target;
        time_s = [0.0; max(stage_duration_s, eps)];
        values = [command_target; command_target];
        startup_profile = 'constant_sma_stage13_valve_command';
        ramp_s = 0.0;
    end

    if is_stage1
        stage1_mdot = get_option_field(exchange_options, ...
            'sma_mdot_stage1_source_kgps', nominal_mdot_kgps);
        stage3_mdot = 0.0;
    elseif is_stage3
        stage1_mdot = 0.0;
        stage3_mdot = get_option_field(exchange_options, ...
            'sma_mdot_stage3_source_kgps', nominal_mdot_kgps);
    else
        stage1_mdot = 0.0;
        stage3_mdot = 0.0;
    end

    config = struct( ...
        'active', is_stage1 || is_stage3, ...
        'route_name', route_name, ...
        'route_description', route_description, ...
        'valve_order', {valve_order}, ...
        'L_valve_command_target', command_target, ...
        'L_valve_initial', command_initial, ...
        'L_valve_command', timeseries(values, time_s), ...
        'L_valve_command_time_s', time_s, ...
        'L_valve_command_values', values, ...
        'startup_profile', startup_profile, ...
        'startup_ramp_s', ramp_s, ...
        'stage1_mdot_kgps', stage1_mdot, ...
        'stage3_mdot_kgps', stage3_mdot);
end

function startup_config = build_exchange_startup_config(stage_config, exchange_options, stage_duration_s, use_closed_valve_flow)
    L_target = reshape(get_stage_field(stage_config, 'L_valve', zeros(1, 6)), 1, []);
    if numel(L_target) ~= 6
        error('Build_Simulink_Exchange_Params:InvalidValveVector', ...
            'stage_config.L_valve must be a 1x6 vector.');
    end
    stage_name = char(string(get_stage_field(stage_config, 'stage_name', '')));
    if strcmpi(stage_name, 'hold_exchange')
        active_valve_scale = get_option_field(exchange_options, ...
            'active_valve_opening_scale_hold', get_option_field(exchange_options, 'active_valve_opening_scale', 1.0));
    elseif strcmpi(stage_name, 'cooldown_exchange')
        active_valve_scale = get_option_field(exchange_options, ...
            'active_valve_opening_scale_cooldown', get_option_field(exchange_options, 'active_valve_opening_scale', 1.0));
    else
        active_valve_scale = get_option_field(exchange_options, 'active_valve_opening_scale', 1.0);
    end
    if ~(isnumeric(active_valve_scale) && isscalar(active_valve_scale) && isfinite(active_valve_scale))
        active_valve_scale = 1.0;
    end
    active_valve_scale = min(max(double(active_valve_scale), 0.0), 1.0);
    active_mask = abs(L_target) > 0;
    L_command_target = L_target;
    L_command_target(active_mask) = active_valve_scale * L_target(active_mask);
    flow_control_mode = char(string(get_option_field(exchange_options, 'flow_control_mode', 'target_duty_pressure_v1')));
    reference_duration_s = get_option_field(exchange_options, 'pressure_control_reference_duration_s', 0.4);
    target_ratio = get_option_field(exchange_options, 'flush_volume_target_ratio', 1.0);
    duty_audit_ignore_initial_s = compute_audit_ignore_initial_s(stage_name, exchange_options, stage_duration_s);
    duty_reference_window_s = max(reference_duration_s - ...
        min(duty_audit_ignore_initial_s, reference_duration_s), eps);
    duty_stage_window_s = max(stage_duration_s - ...
        min(duty_audit_ignore_initial_s, stage_duration_s), eps);
    duty_capacity_ratio = target_ratio * duty_reference_window_s / duty_stage_window_s;
    if strcmpi(stage_name, 'cooldown_exchange') && ...
            ~isfield(exchange_options, 'active_valve_opening_scale_cooldown') && ...
            ~isfield(exchange_options, 'active_valve_opening_scale')
        cooldown_capacity_exponent = get_option_field(exchange_options, ...
            'active_valve_opening_scale_cooldown_capacity_exponent', 2.20);
        active_valve_scale = min(1.0, active_valve_scale * max(1.0, duty_capacity_ratio) ^ cooldown_capacity_exponent);
        L_command_target = L_target;
        L_command_target(active_mask) = active_valve_scale * L_target(active_mask);
    end
    duty_enabled = any(strcmpi(flow_control_mode, {'target_duty_pressure_v1', 'target_duty_pressure'})) && ...
        any(active_mask) && ~use_closed_valve_flow;
    if strcmpi(stage_name, 'hold_exchange')
        duty_dead_fraction = get_option_field(exchange_options, ...
            'active_valve_duty_dead_fraction_hold', get_option_field(exchange_options, ...
            'active_valve_duty_dead_fraction', 0.40));
    elseif strcmpi(stage_name, 'cooldown_exchange')
        duty_dead_fraction = get_option_field(exchange_options, ...
            'active_valve_duty_dead_fraction_cooldown', get_option_field(exchange_options, ...
            'active_valve_duty_dead_fraction', 0.70));
    else
        duty_dead_fraction = get_option_field(exchange_options, 'active_valve_duty_dead_fraction', 0.40);
    end
    if ~(isnumeric(duty_dead_fraction) && isscalar(duty_dead_fraction) && isfinite(duty_dead_fraction))
        duty_dead_fraction = 0.0;
    end
    duty_dead_fraction = min(max(double(duty_dead_fraction), 0.0), 0.95);
    duty_fraction = 1.0;
    duty_raw_fraction = 1.0;
    if duty_enabled
        duty_raw_fraction = min(max(duty_capacity_ratio, 0.0), 1.0);
        duty_effective_dead_fraction = duty_dead_fraction;
        if duty_raw_fraction < 1.0 && target_ratio >= 1.0
            if strcmpi(stage_name, 'hold_exchange')
                duty_effective_dead_fraction = get_option_field(exchange_options, ...
                    'active_valve_duty_dead_fraction_hold_frequency', 0.25);
            elseif strcmpi(stage_name, 'cooldown_exchange')
                duty_effective_dead_fraction = get_option_field(exchange_options, ...
                    'active_valve_duty_dead_fraction_cooldown_frequency', 0.70);
            end
        end
        duty_effective_dead_fraction = min(max(double(duty_effective_dead_fraction), 0.0), 0.95);
        if duty_raw_fraction < 1.0
            duty_fraction = duty_effective_dead_fraction + duty_raw_fraction * (1.0 - duty_effective_dead_fraction);
        else
            duty_fraction = duty_raw_fraction;
        end
        duty_fraction = min(max(duty_fraction, 0.0), 1.0);
    else
        duty_effective_dead_fraction = duty_dead_fraction;
    end
    if strcmpi(stage_name, 'cooldown_exchange')
        duty_fraction_override = get_option_field(exchange_options, ...
            'active_valve_duty_fraction_cooldown', NaN);
    elseif strcmpi(stage_name, 'hold_exchange')
        duty_fraction_override = get_option_field(exchange_options, ...
            'active_valve_duty_fraction_hold', NaN);
    else
        duty_fraction_override = NaN;
    end
    if duty_enabled && isnumeric(duty_fraction_override) && isscalar(duty_fraction_override) && ...
            isfinite(duty_fraction_override)
        duty_fraction = min(max(double(duty_fraction_override), 0.0), 1.0);
        duty_raw_fraction = duty_fraction;
    end
    startup_enabled = logical(get_option_field(exchange_options, ...
        'exchange_startup_smoothing_enabled', true));
    if strcmpi(stage_name, 'hold_exchange')
        requested_ramp_s = get_option_field(exchange_options, ...
            'exchange_startup_ramp_s_hold', get_option_field(exchange_options, 'exchange_startup_ramp_s', 0.002));
    elseif strcmpi(stage_name, 'cooldown_exchange')
        requested_ramp_s = get_option_field(exchange_options, ...
            'exchange_startup_ramp_s_cooldown', get_option_field(exchange_options, 'exchange_startup_ramp_s', 0.002));
    else
        requested_ramp_s = get_option_field(exchange_options, 'exchange_startup_ramp_s', 0.002);
    end
    if ~(isnumeric(requested_ramp_s) && isscalar(requested_ramp_s) && isfinite(requested_ramp_s))
        error('Build_Simulink_Exchange_Params:InvalidStartupRamp', ...
            'exchange_startup_ramp_s must be a finite scalar.');
    end
    requested_ramp_s = max(double(requested_ramp_s), 0.0);
    closed_opening = get_option_field(exchange_options, 'exchange_startup_closed_valve_opening', 0.0);
    closed_opening = min(max(double(closed_opening), 0.0), 1.0);
    has_open_valves = any(abs(L_command_target) > 0);
    ramp_s = min(requested_ramp_s, 0.25 * stage_duration_s);
    startup_used = startup_enabled && has_open_valves && ~use_closed_valve_flow && ramp_s > 0;
    if startup_used
        L_initial = L_command_target;
        L_initial(active_mask) = closed_opening * sign_nonzero(L_command_target(active_mask));
        if duty_enabled && duty_fraction < 1.0
            open_end_s = max(ramp_s, min(stage_duration_s, ...
                duty_audit_ignore_initial_s + duty_fraction * duty_stage_window_s));
            close_time_s = min(stage_duration_s, open_end_s + max(eps, min(1.0e-6, 1.0e-3 * stage_duration_s)));
            L_closed = L_command_target;
            L_closed(active_mask) = closed_opening * sign_nonzero(L_command_target(active_mask));
            time_s = unique([0.0; ramp_s; open_end_s; close_time_s; stage_duration_s], 'stable');
            values = zeros(numel(time_s), numel(L_command_target));
            for idx = 1:numel(time_s)
                if time_s(idx) <= ramp_s
                    values(idx, :) = L_initial;
                elseif time_s(idx) <= open_end_s
                    values(idx, :) = L_command_target;
                else
                    values(idx, :) = L_closed;
                end
            end
            reason = 'duty-cycle valve command preserves processed volume while pressure sets active-flow capacity';
            profile = 'duty_cycle_valve_with_pressure_capacity';
        else
            time_s = [0.0; ramp_s; stage_duration_s];
            values = [L_initial; L_command_target; L_command_target];
            reason = 'linear valve-opening ramp from closed leakage command to target; pressure source remains compile-time constant';
            profile = 'linear_valve_ramp_pressure_constant';
        end
    else
        L_initial = L_command_target;
        time_s = [0.0; max(stage_duration_s, eps)];
        values = [L_command_target; L_command_target];
        if ~startup_enabled
            reason = 'startup smoothing disabled by exchange_options';
        elseif use_closed_valve_flow || ~has_open_valves
            reason = 'all valves closed or no active exchange path';
        else
            reason = 'startup ramp duration is zero';
        end
        profile = 'constant_valve_command';
        ramp_s = 0.0;
    end
    startup_config = struct( ...
        'L_valve_target', L_target, ...
        'L_valve_command_target', L_command_target, ...
        'L_valve_initial', L_initial, ...
        'L_valve_command', timeseries(values, time_s), ...
        'L_valve_command_time_s', time_s, ...
        'L_valve_command_values', values, ...
        'exchange_startup_smoothing_enabled', startup_enabled, ...
        'exchange_startup_ramp_s', ramp_s, ...
        'exchange_startup_profile', profile, ...
        'startup_smoothing_used', startup_used, ...
        'startup_smoothing_reason', reason, ...
        'exchange_startup_closed_valve_opening', closed_opening, ...
        'active_valve_opening_scale', active_valve_scale, ...
        'active_valve_duty_cycle_enabled', duty_enabled, ...
        'active_valve_duty_fraction', duty_fraction, ...
        'active_valve_duty_raw_fraction', duty_raw_fraction, ...
        'active_valve_duty_dead_fraction', duty_dead_fraction, ...
        'active_valve_duty_effective_dead_fraction', duty_effective_dead_fraction, ...
        'active_valve_duty_capacity_ratio', duty_capacity_ratio);
end

function values = sign_nonzero(values)
    signs = sign(values);
    signs(signs == 0) = 1;
    values = signs;
end

function T_init = extract_temperature_vector(state_std)
    if isstruct(state_std) && isfield(state_std, 'T') && ~isempty(state_std.T)
        T_init = state_std.T(:);
        return;
    end

    if isstruct(state_std) && isfield(state_std, 'Y') && isfield(state_std, 'T_idx')
        T_init = state_std.Y(state_std.T_idx);
        return;
    end

    X = state_std.X(:);
    node_count = numel(X) / 3;
    if floor(node_count) ~= node_count
        error('Build_Simulink_Exchange_Params:InvalidStateVector', ...
            'State vector length must be divisible by 3.');
    end
    T_init = X(2 * node_count + 1 : 3 * node_count);
end

function state_std = standardize_globalxi_exchange_state(state_in)
    try
        state_std = GlobalXi_Checkpoint_To_Simulink_State(state_in);
    catch adapter_error
        if isstruct(state_in) && isfield(state_in, 'T') && ~isempty(state_in.T)
            state_std = state_in;
            return;
        end
        rethrow(adapter_error);
    end
end

function [Nu, correlation_name, flow_regime] = compute_nusselt_number(Re, Pr, D_inner, D_outer, D_e, L, viscosity_ratio)
    if Re <= 0
        Nu = 3.66;
        correlation_name = 'static_laminar_limit';
        flow_regime = 'no_flow';
        return;
    end

    laminar_Nu = compute_laminar_annulus_nusselt(Re, Pr, D_inner, D_outer, D_e, L);
    if Re < 2100
        Nu = laminar_Nu;
        correlation_name = 'laminar_annulus_entry_hausen_like';
        flow_regime = 'laminar';
    elseif Re < 10000
        turbulent_Nu = compute_gnielinski_nusselt(max(Re, 3000), Pr, D_e, L, viscosity_ratio);
        blend = min(max((Re - 2100) / (10000 - 2100), 0.0), 1.0);
        Nu = (1.0 - blend) * laminar_Nu + blend * turbulent_Nu;
        correlation_name = 'transitional_laminar_gnielinski_blend';
        flow_regime = 'transitional';
    else
        Nu = compute_gnielinski_nusselt(Re, Pr, D_e, L, viscosity_ratio);
        correlation_name = 'turbulent_gnielinski';
        flow_regime = 'turbulent';
    end
end

function Nu = compute_laminar_annulus_nusselt(Re, Pr, D_inner, D_outer, D_e, L)
    ratio = D_outer / D_inner;
    term1 = 3.66 + 1.2 * ratio ^ 0.8;
    term2 = 0.19 * (1 + 0.14 * ratio ^ 0.5);
    red_pr = max(Re, 0.0) * Pr * D_e / max(L, eps);
    term3 = red_pr ^ 0.8;
    term4 = 1 + 0.117 * red_pr ^ 0.467;
    Nu = term1 + (term2 * term3) / max(term4, eps);
end

function Nu = compute_gnielinski_nusselt(Re, Pr, D_e, L, viscosity_ratio)
    friction_factor = (0.79 * log(max(Re, 1.0)) - 1.64) ^ -2;
    numerator = (friction_factor / 8.0) * (Re - 1000.0) * Pr;
    denominator = 1.0 + 12.7 * sqrt(friction_factor / 8.0) * (Pr ^ (2 / 3) - 1.0);
    entry_factor = 1.0 + (D_e / max(L, eps)) ^ (2 / 3);
    Nu = max(numerator / max(denominator, eps) * entry_factor * (viscosity_ratio ^ 0.14), 3.66);
end

function chip = compute_chip_fluid_conductance(exchange_options, stage_name, Q_target_m3ps, ...
        rho_water, mu_water, k_water, cp_water, Pr)
    chip_contact_area_m2 = get_option_field(exchange_options, 'chip_contact_area_m2', 1.0e-4);
    chip_D_h_m = get_option_field(exchange_options, 'chip_D_h_m', ...
        get_option_field(exchange_options, 'chip_channel_hydraulic_diameter_m', 1.0e-3));
    chip_channel_flow_area_m2 = get_option_field(exchange_options, 'chip_channel_flow_area_m2', 2.0e-6);
    chip_channel_length_m = get_option_field(exchange_options, 'chip_channel_length_m', 0.02);
    chip_package_R = get_option_field(exchange_options, 'chip_package_resistance_K_per_W', 1.0);
    chip_contact_R = get_option_field(exchange_options, 'chip_contact_resistance_K_per_W', 0.5);
    chip_wall_R = get_option_field(exchange_options, 'chip_wall_resistance_K_per_W', 0.2);
    chip_fluid_G_scale = get_option_field(exchange_options, 'chip_fluid_G_scale', 1.0);
    chip_fluid_G_cap = get_option_field(exchange_options, 'chip_fluid_G_cap_W_per_K', Inf);

    assert_positive_scalar(chip_contact_area_m2, 'chip_contact_area_m2');
    assert_positive_scalar(chip_D_h_m, 'chip_D_h_m');
    assert_positive_scalar(chip_channel_flow_area_m2, 'chip_channel_flow_area_m2');
    assert_positive_scalar(chip_channel_length_m, 'chip_channel_length_m');

    if strcmp(stage_name, 'cooldown_exchange')
        Q_chip_m3ps = max(double(Q_target_m3ps), 0.0);
    else
        Q_chip_m3ps = 0.0;
    end
    v_chip = Q_chip_m3ps / max(chip_channel_flow_area_m2, eps);
    Re_chip = rho_water * v_chip * chip_D_h_m / max(mu_water, eps);
    [Nu_chip, chip_flow_regime] = compute_chip_nusselt_number(Re_chip, Pr, chip_D_h_m, ...
        chip_channel_length_m, cp_water, mu_water, k_water);
    h_chip_conv = Nu_chip * k_water / max(chip_D_h_m, eps);
    R_conv = 1.0 / max(h_chip_conv * chip_contact_area_m2, eps);
    R_total = R_conv + max(chip_package_R, 0.0) + max(chip_contact_R, 0.0) + max(chip_wall_R, 0.0);
    G_uncapped = chip_fluid_G_scale / max(R_total, eps);
    G_effective = min(G_uncapped, chip_fluid_G_cap);

    chip = struct( ...
        'chip_fluid_G_model', 'flow_dependent_thermal_resistance_v1', ...
        'chip_contact_area_m2', chip_contact_area_m2, ...
        'chip_D_h_m', chip_D_h_m, ...
        'chip_channel_flow_area_m2', chip_channel_flow_area_m2, ...
        'chip_channel_length_m', chip_channel_length_m, ...
        'chip_v_fluid_m_per_s', v_chip, ...
        'chip_Re', Re_chip, ...
        'chip_Nu', Nu_chip, ...
        'chip_h_conv_W_per_m2K', h_chip_conv, ...
        'chip_flow_regime', chip_flow_regime, ...
        'chip_R_conv_K_per_W', R_conv, ...
        'chip_R_package_K_per_W', max(chip_package_R, 0.0), ...
        'chip_R_contact_K_per_W', max(chip_contact_R, 0.0), ...
        'chip_R_wall_K_per_W', max(chip_wall_R, 0.0), ...
        'chip_R_total_K_per_W', R_total, ...
        'chip_fluid_G_uncapped_W_per_K', G_uncapped, ...
        'chip_fluid_G_effective_W_per_K', G_effective, ...
        'chip_fluid_G_cap_W_per_K', chip_fluid_G_cap, ...
        'chip_fluid_G_cap_active', isfinite(chip_fluid_G_cap) && G_effective < G_uncapped, ...
        'chip_fluid_G_scale', chip_fluid_G_scale, ...
        'chip_fluid_G_reference_W_per_K', NaN);
end

function [Nu, regime] = compute_chip_nusselt_number(Re, Pr, D_h, L, cp_water, mu_water, k_water)
    if Re <= 0
        Nu = 3.66;
        regime = 'no_flow';
        return;
    end
    graetz = max(Re, 0.0) * Pr * D_h / max(L, eps);
    laminar_Nu = max(3.66, 1.86 * max(graetz, 0.0) ^ (1 / 3));
    if Re < 2100
        Nu = laminar_Nu;
        regime = 'laminar';
    elseif Re < 10000
        turbulent_Nu = compute_gnielinski_nusselt(max(Re, 3000), Pr, D_h, L, 1.0);
        blend = min(max((Re - 2100) / (10000 - 2100), 0.0), 1.0);
        Nu = (1.0 - blend) * laminar_Nu + blend * turbulent_Nu;
        regime = 'transitional';
    else
        viscosity_ratio = max(cp_water * mu_water / max(k_water, eps), eps) / max(Pr, eps);
        Nu = compute_gnielinski_nusselt(Re, Pr, D_h, L, viscosity_ratio);
        regime = 'turbulent';
    end
end

function assert_positive_scalar(value, name)
    if ~(isnumeric(value) && isscalar(value) && isfinite(value) && value > 0)
        error('Build_Simulink_Exchange_Params:InvalidChipGeometry', ...
            '%s must be a finite positive scalar.', name);
    end
end

function pressure_guess = compute_analytic_pressure_guess(base_pressure_MPa, mdot_target_kgps, ...
        stage_duration_s, rho_water, plate_volume_m3, reference_duration_s, Re, exchange_options)
    pressure_guess = base_pressure_MPa;
    if ~(isnumeric(base_pressure_MPa) && isscalar(base_pressure_MPa) && isfinite(base_pressure_MPa))
        return;
    end
    if ~(isnumeric(mdot_target_kgps) && isscalar(mdot_target_kgps) && isfinite(mdot_target_kgps) && mdot_target_kgps > 0)
        return;
    end
    baseline_mdot = get_option_field(exchange_options, 'pressure_control_reference_mdot_kgps', ...
        rho_water * plate_volume_m3 / max(reference_duration_s, eps));
    if ~(isnumeric(baseline_mdot) && isscalar(baseline_mdot) && isfinite(baseline_mdot) && baseline_mdot > 0)
        return;
    end
    mdot_scale = max(mdot_target_kgps / baseline_mdot, eps);
    if Re < 2100
        exponent = get_option_field(exchange_options, 'pressure_control_laminar_mdot_exponent', 1.0);
    else
        exponent = get_option_field(exchange_options, 'pressure_control_turbulent_mdot_exponent', 1.75);
    end
    existing_flow_scale = max(get_option_field(exchange_options, ...
        'pressure_control_existing_flow_scale_exponent', 1.0), 0.0);
    corrective_exponent = max(exponent - existing_flow_scale, 0.0);
    pressure_guess = base_pressure_MPa * mdot_scale ^ corrective_exponent;
    max_abs_pressure = get_option_field(exchange_options, 'actual_flush_pressure_max_abs_MPa', 5.0);
    min_abs_pressure = get_option_field(exchange_options, 'actual_flush_pressure_min_abs_MPa', 1.0e-8);
    if isfinite(max_abs_pressure) && abs(pressure_guess) > max_abs_pressure
        pressure_guess = sign(pressure_guess) * max_abs_pressure;
    elseif isfinite(min_abs_pressure) && abs(pressure_guess) < min_abs_pressure
        pressure_guess = sign(base_pressure_MPa) * min_abs_pressure;
    end
    if ~(isfinite(stage_duration_s) && stage_duration_s > 0)
        pressure_guess = base_pressure_MPa;
    end
end

function [pressure_MPa, source] = select_cached_pressure_guess(runtime, stage_name)
    pressure_MPa = NaN;
    source = '';
    if ~isstruct(runtime)
        return;
    end
    stage_key = pressure_stage_key(stage_name);
    if isempty(stage_key)
        return;
    end
    candidates = { ...
        [stage_key '_converged_pressure_MPa'], ['runtime_' stage_key '_converged_pressure_MPa']; ...
        [stage_key '_last_known_good_pressure_MPa'], ['runtime_' stage_key '_last_known_good_pressure_MPa']; ...
        [stage_key '_run_last_known_good_pressure_MPa'], ['runtime_' stage_key '_run_last_known_good_pressure_MPa']};
    for idx = 1:size(candidates, 1)
        value = get_option_field(runtime, candidates{idx, 1}, NaN);
        if isnumeric(value) && isscalar(value) && isfinite(value)
            pressure_MPa = value;
            source = candidates{idx, 2};
            return;
        end
    end
    generic_stage_name = char(string(get_option_field(runtime, 'run_last_known_good_pressure_stage_name', '')));
    value = get_option_field(runtime, 'run_last_known_good_pressure_MPa', NaN);
    if strcmpi(strtrim(generic_stage_name), strtrim(char(string(stage_name)))) && ...
            isnumeric(value) && isscalar(value) && isfinite(value)
        pressure_MPa = value;
        source = 'runtime_same_stage_run_last_known_good_pressure_MPa';
        return;
    end
end

function stage_key = pressure_stage_key(stage_name)
    switch lower(strtrim(char(string(stage_name))))
        case 'hold_exchange'
            stage_key = 'stage2';
        case 'cooldown_exchange'
            stage_key = 'stage4';
        otherwise
            stage_key = '';
    end
end

function value = get_option_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end

function value = get_stage_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
