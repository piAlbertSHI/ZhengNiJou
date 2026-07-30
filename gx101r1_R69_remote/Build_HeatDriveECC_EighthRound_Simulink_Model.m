function [model_name, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(overrides)
% Build the heat-driven ECC Simulink mainline from the mature solver model.
%
% The target model is the single canonical Simulink model for this workspace.
% It was seeded from the mature heatdrive_ecc_coupled_se21 network and now
% must be maintained in-place: verified TL pump/pressure source, V1-V6
% valves, buffers, hot/cold heat exchangers, probes, and the SMA dual-path
% exchanger shell stay in this one .slx. The heat-driven ECC work extends
% this physical network; it must not create synthetic per-stage signal
% diagrams or additional .slx files.

    if nargin < 1
        overrides = struct();
    end
    options = Build_HeatDriveECC_EighthRound_Defaults(overrides);
    model_name = options.model_name;
    model_path = options.model_path;

    if ~exist(model_path, 'file')
        error('Build:ECC:MissingCanonicalModel', ...
            ['The canonical model is missing: %s\n', ...
            'Do not create a new .slx. Restore this file from git, then modify it in-place.'], ...
            model_path);
    end

    close_if_loaded(model_name, false);

    assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
    assign_mature_exchange_workspace(options, model_path);
    assign_constitutive_workspace(options);

    load_system(model_name);
    topology_audit = configure_dual_fluid_topology(model_name);
    configure_thermal_liquid_temperature_range(model_name, options);
    topology_audit = audit_dual_fluid_topology(model_name, topology_audit);
    options.validation.dual_fluid_domain_implemented = topology_audit.ok;
    options.validation.dual_fluid_domain_audit = topology_audit;
    assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
    configure_thermal_liquid_initial_pressure(model_name);
    set_param(model_name, ...
        'Solver', 'ode23t', ...
        'RelTol', '1e-2', ...
        'AbsTol', '1e-3', ...
        'MaxStep', '0.4', ...
        'InitialStep', 'auto', ...
        'ZeroCross', 'on', ...
        'StopTime', num2str(options.simulation.stop_time_s, '%.15g'), ...
        'SaveTime', 'on', ...
        'TimeSaveName', 'tout', ...
        'ReturnWorkspaceOutputs', 'on');

    mark_ecc_mainline(model_name);
    Integrate_HeatDriveECC_Constitutive21_Interface(model_name, options, false);
    configure_simscape_local_solver(model_name, options);
    save_system(model_name, model_path);
end

function audit = configure_dual_fluid_topology(model_name)
    % Qian uses water for SMA/SHEX and glycol-water for SE/HHEX/CHEX.
    % The HHEX already contains separate HotPipe and SMAHotPipe channels;
    % split only their formerly shared top-level hot buffer node.
    hot_buffer = [model_name '/HotFluidBuffer'];
    sma_buffer = [model_name '/SMAHotFluidBuffer'];
    if ~exist_block(sma_buffer)
        add_block(hot_buffer, sma_buffer, ...
            'MakeNameUnique', 'off', ...
            'Position', [1580 875 1630 925]);
    end

    settings_blocks = thermal_liquid_settings_blocks(model_name);
    if isempty(settings_blocks)
        error('Build:ECC:MissingThermalLiquidSettings', ...
            'The canonical model has no Thermal Liquid Settings block.');
    end
    sma_settings = [model_name '/SMA_ThermalLiquidSettings'];
    if ~exist_block(sma_settings)
        add_block(settings_blocks{1}, sma_settings, ...
            'MakeNameUnique', 'off', ...
            'Position', [1460 875 1520 935]);
    end

    hhex = find_hhex_parent(model_name);
    sma_v2 = [model_name '/SMA_V2_HHEX_to_pump'];
    if ~blocks_share_conserving_network(hhex, sma_buffer)
        delete_conserving_branch(hhex, 'LConn', 2);
    end
    if ~blocks_share_conserving_network(sma_v2, sma_buffer)
        delete_conserving_branch(sma_v2, 'LConn', 1);
    end

    connect_conserving_ports(model_name, sma_settings, 'RConn', 1, ...
        sma_buffer, 'LConn', 1);
    connect_conserving_ports(model_name, hhex, 'LConn', 2, ...
        sma_buffer, 'LConn', 1);
    connect_conserving_ports(model_name, sma_v2, 'LConn', 1, ...
        sma_buffer, 'LConn', 1);
    add_sma_hot_buffer_temperature_probe(model_name, sma_buffer);

    audit = struct( ...
        'schema_version', 'qian2019_dual_fluid_topology_audit_v1', ...
        'sma_settings_path', sma_settings, ...
        'se_settings_path', settings_blocks{1}, ...
        'sma_hot_buffer_path', sma_buffer, ...
        'hhex_path', hhex, ...
        'ok', false);
end

function audit = audit_dual_fluid_topology(model_name, audit)
    settings_blocks = thermal_liquid_settings_blocks(model_name);
    sma_settings = [model_name '/SMA_ThermalLiquidSettings'];
    se_settings = setdiff(settings_blocks, {sma_settings}, 'stable');
    if numel(se_settings) ~= 1
        audit.ok = false;
        audit.settings_count = numel(settings_blocks);
        audit.failure_reason = sprintf( ...
            'Expected one SMA and one SE settings block; found %d total.', ...
            numel(settings_blocks));
        return;
    end

    sma_buffer = [model_name '/SMAHotFluidBuffer'];
    se_buffer = [model_name '/HotFluidBuffer'];
    sma_v2 = [model_name '/SMA_V2_HHEX_to_pump'];
    se_v4 = [model_name '/V4_hot_inlet'];
    hhex = find_hhex_parent(model_name);
    audit.settings_count = numel(settings_blocks);
    audit.se_settings_path = se_settings{1};
    audit.sma_domain_connected = ...
        blocks_share_conserving_network(sma_settings, sma_buffer) && ...
        blocks_share_conserving_network(sma_settings, sma_v2) && ...
        blocks_share_conserving_network(sma_settings, hhex);
    audit.se_domain_connected = ...
        blocks_share_conserving_network(se_settings{1}, se_buffer) && ...
        blocks_share_conserving_network(se_settings{1}, se_v4);
    audit.domains_hydraulically_isolated = ...
        ~blocks_share_conserving_network(sma_settings, se_settings{1}) && ...
        ~blocks_share_conserving_network(sma_buffer, se_buffer) && ...
        ~blocks_share_conserving_network(sma_v2, se_v4);
    audit.buffer_probe_present = ...
        exist_block([model_name '/SMAHotFluidBufferTempSensor']) && ...
        exist_block([model_name '/ToWorkspace_sma_hot_buffer_temp_out']);
    audit.ok = audit.settings_count == 2 && ...
        audit.sma_domain_connected && audit.se_domain_connected && ...
        audit.domains_hydraulically_isolated && audit.buffer_probe_present;
    if audit.ok
        audit.failure_reason = '';
    else
        audit.failure_reason = ...
            'Two-domain connectivity or SMA hot-buffer probe audit failed.';
    end
end

function add_sma_hot_buffer_temperature_probe(model_name, sma_buffer)
    source_sensor = [model_name '/HotFluidBufferTempSensor'];
    source_converter = [model_name '/HotFluidBufferTempPS'];
    source_workspace = [model_name '/ToWorkspace_hot_buffer_temp_out'];
    sensor = [model_name '/SMAHotFluidBufferTempSensor'];
    converter = [model_name '/SMAHotFluidBufferTempPS'];
    workspace = [model_name '/ToWorkspace_sma_hot_buffer_temp_out'];
    if ~exist_block(sensor)
        add_block(source_sensor, sensor, 'MakeNameUnique', 'off', ...
            'Position', [1580 1020 1630 1060]);
    end
    if ~exist_block(converter)
        add_block(source_converter, converter, 'MakeNameUnique', 'off', ...
            'Position', [1660 1029 1690 1051]);
    end
    if ~exist_block(workspace)
        add_block(source_workspace, workspace, 'MakeNameUnique', 'off', ...
            'Position', [1730 1015 1945 1045]);
    end
    set_param(sensor, 'Position', [1580 1020 1630 1060]);
    set_param(converter, 'Position', [1660 1029 1690 1051]);
    set_param(workspace, 'Position', [1730 1015 1945 1045]);
    set_param(workspace, ...
        'VariableName', 'sma_hot_buffer_temp_out', ...
        'SaveFormat', 'Structure With Time');
    connect_conserving_ports(model_name, sensor, 'LConn', 1, ...
        sma_buffer, 'LConn', 1);
    connect_conserving_ports(model_name, sensor, 'RConn', 1, ...
        converter, 'LConn', 1);
    connect_signal_ports(model_name, converter, 1, workspace, 1);
end

function connect_conserving_ports(model_name, block_a, type_a, index_a, ...
        block_b, type_b, index_b)
    if blocks_share_conserving_network(block_a, block_b)
        return;
    end
    ports_a = get_param(block_a, 'PortHandles');
    ports_b = get_param(block_b, 'PortHandles');
    add_line(model_name, ports_a.(type_a)(index_a), ...
        ports_b.(type_b)(index_b), 'autorouting', 'on');
end

function connect_signal_ports(model_name, source, source_index, ...
        destination, destination_index)
    source_ports = get_param(source, 'PortHandles');
    destination_ports = get_param(destination, 'PortHandles');
    destination_line = get_param(destination_ports.Inport(destination_index), ...
        'Line');
    if destination_line > 0
        return;
    end
    add_line(model_name, source_ports.Outport(source_index), ...
        destination_ports.Inport(destination_index), 'autorouting', 'on');
end

function delete_conserving_branch(block_path, port_type, port_index)
    ports = get_param(block_path, 'PortHandles');
    line_handle = get_param(ports.(port_type)(port_index), 'Line');
    if line_handle > 0
        delete_line(line_handle);
    end
end

function tf = blocks_share_conserving_network(block_a, block_b)
    handle_a = getSimulinkBlockHandle(block_a);
    handle_b = getSimulinkBlockHandle(block_b);
    if handle_a <= 0 || handle_b <= 0
        tf = false;
        return;
    end
    if handle_a == handle_b
        tf = true;
        return;
    end

    queue = handle_a;
    visited = zeros(0, 1);
    tf = false;
    while ~isempty(queue)
        current = queue(1);
        queue(1) = [];
        if any(visited == current)
            continue;
        end
        visited(end + 1, 1) = current; %#ok<AGROW>

        % A top-level subsystem may contain multiple hydraulically isolated
        % channels coupled only by thermal ports (HHEX, SMA, and SE). Treat
        % it as a terminal boundary; primitive TL components remain
        % traversable across all conserving ports.
        if current ~= handle_a && ...
                strcmp(get_param(current, 'BlockType'), 'SubSystem')
            continue;
        end
        connectivity = get_param(current, 'PortConnectivity');
        neighbors = zeros(0, 1);
        for idx = 1:numel(connectivity)
            type = connectivity(idx).Type;
            if ~(startsWith(type, 'LConn') || startsWith(type, 'RConn'))
                continue;
            end
            neighbors = [neighbors; connectivity(idx).SrcBlock(:); ...
                connectivity(idx).DstBlock(:)]; %#ok<AGROW>
        end
        neighbors = unique(neighbors(neighbors > 0));
        if any(neighbors == handle_b)
            tf = true;
            return;
        end
        queue = [queue; neighbors(~ismember(neighbors, visited))]; %#ok<AGROW>
    end
end

function blocks = thermal_liquid_settings_blocks(model_name)
    candidates = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'BlockType', 'SimscapeBlock');
    blocks = cell(0, 1);
    for idx = 1:numel(candidates)
        try
            if strcmp(get_param(candidates{idx}, 'SourceFile'), ...
                    'foundation.thermal_liquid.utilities.thermal_liquid_settings')
                blocks{end + 1, 1} = candidates{idx}; %#ok<AGROW>
            end
        catch
        end
    end
end

function hhex = find_hhex_parent(model_name)
    blocks = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'Name', 'SMAHotPipe');
    if numel(blocks) ~= 1
        error('Build:ECC:HHEXSMAHotPipe', ...
            'Expected one HHEX/SMAHotPipe block; found %d.', numel(blocks));
    end
    hhex = get_param(blocks{1}, 'Parent');
end

function configure_thermal_liquid_initial_pressure(model_name)
    % Keep every dynamic liquid volume on the same 0.5 MPa absolute-pressure
    % datum as the fluid property table.  Differential pump commands remain
    % unchanged and are still only a few kPa.
    blocks = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'BlockType', 'SimscapeBlock');
    for idx = 1:numel(blocks)
        try
            parameters = get_param(blocks{idx}, 'DialogParameters');
            if isfield(parameters, 'p0')
                set_param(blocks{idx}, 'p0', '0.5');
            end
        catch
            % Blocks without an initial liquid pressure need no update.
        end
    end
end

function configure_thermal_liquid_temperature_range(model_name, options)
    % The paper drives the actuator to 400 K.  The original two-dimensional
    % water table ends at 373.16 K and its low-pressure columns cannot be
    % extrapolated above saturation without mixing liquid and vapour data.
    % This network operates near 0.5 MPa with only kPa-scale pump pressure
    % differences, so use an IAPWS-IF97 liquid-water table at 0.5 MPa.  The
    % tabulated values are embedded to keep simulation runs dependency-free.
    T_water_K = (273.16:10:413.16).';
    rho_water_kg_per_m3 = [ ...
        1000.047692; 999.8910379; 998.3863142; 995.8262391; ...
        992.3948132; 988.2162820; 983.3792011; 977.9489783; ...
        971.9748358; 965.4939159; 958.5338333; 951.1143215; ...
        943.2483073; 934.9425941; 926.1982521];
    u_water_kJ_per_kg = [ ...
        0.009195591107; 42.04935692; 83.92921694; 125.7370066; ...
        167.5155824; 209.2925951; 251.0909039; 292.9318876; ...
        334.8364138; 376.8251884; 418.9190578; 461.1394123; ...
        503.5087057; 546.0510694; 588.7930050];
    nu_water_mm2_per_s = [ ...
        1.790149606; 1.305308358; 1.002847726; 0.8003847494; ...
        0.6576599304; 0.5530269976; 0.4739457078; 0.4127054691; ...
        0.3643312332; 0.3254838619; 0.2938478789; 0.2677732136; ...
        0.2460564680; 0.2278024090; 0.2123334626];
    k_water_mW_per_mK = [ ...
        555.9805115; 579.0574270; 598.2630374; 614.6297471; ...
        628.7193807; 640.8549223; 651.2352248; 659.9939082; ...
        667.2300958; 673.0243742; 677.4468439; 680.5609271; ...
        682.4249382; 683.0925227; 682.6125620];

    required_max_K = max(options.system.T_PSC_K + 5.0, 405.0);
    if required_max_K > T_water_K(end)
        error('Build:ECC:ThermalLiquidTableRange', ...
            'Required fluid temperature %.3f K exceeds the %.3f K water table.', ...
            required_max_K, T_water_K(end));
    end

    se_fluid = options.fluid.SE;
    T_se_K = T_water_K;
    rho_se_kg_per_m3 = se_fluid.rho_kg_per_m3 .* ones(size(T_se_K));
    u_se_kJ_per_kg = se_fluid.cp_J_per_kgK .* ...
        (T_se_K - T_se_K(1)) ./ 1000.0;
    nu_se_mm2_per_s = se_fluid.mu_Pa_s ./ ...
        se_fluid.rho_kg_per_m3 .* 1.0e6 .* ones(size(T_se_K));
    k_se_mW_per_mK = se_fluid.k_W_per_mK .* ...
        1000.0 .* ones(size(T_se_K));

    settings_blocks = thermal_liquid_settings_blocks(model_name);
    if numel(settings_blocks) ~= 2
        error('Build:ECC:DualFluidSettingsCount', ...
            'Expected two Thermal Liquid Settings blocks; found %d.', ...
            numel(settings_blocks));
    end
    sma_settings = [model_name '/SMA_ThermalLiquidSettings'];
    for idx = 1:numel(settings_blocks)
        if strcmp(settings_blocks{idx}, sma_settings)
            set_thermal_liquid_1d_table(settings_blocks{idx}, ...
                T_water_K, rho_water_kg_per_m3, u_water_kJ_per_kg, ...
                nu_water_mm2_per_s, k_water_mW_per_mK, 2.15);
        else
            set_thermal_liquid_1d_table(settings_blocks{idx}, ...
                T_se_K, rho_se_kg_per_m3, u_se_kJ_per_kg, ...
                nu_se_mm2_per_s, k_se_mW_per_mK, 2.0);
        end
    end
end

function set_thermal_liquid_1d_table(block, T_K, rho_kg_per_m3, ...
        u_kJ_per_kg, nu_mm2_per_s, k_mW_per_mK, bulk_modulus_GPa)
    set_param(block, ...
        'table_dimensions', '1', ...
        'T_TLU', mat2str(T_K, 15), ...
        'p_atm', '0.5', ...
        'T_min_1D', num2str(T_K(1), '%.15g'), ...
        'T_max_1D', num2str(T_K(end), '%.15g'), ...
        'p_min_1D', '0.45', ...
        'p_max_1D', '5', ...
        'rho_parameterization_1D', '1', ...
        'rho_TLU_4', mat2str(rho_kg_per_m3, 15), ...
        'beta_const_4', num2str(bulk_modulus_GPa, '%.15g'), ...
        'p_ref_4', '0.5', ...
        'u_parameterization_1D', '1', ...
        'u_TLU_4', mat2str(u_kJ_per_kg, 15), ...
        'nu_TLU_2', mat2str(nu_mm2_per_s, 15), ...
        'k_TLU_2', mat2str(k_mW_per_mK, 15), ...
        'properties_range_check', 'simscape.enum.assert.action.warn');
end

function close_if_loaded(model_name, save_changes)
    if bdIsLoaded(model_name)
        if save_changes
            close_system(model_name, 1);
        else
            set_param(model_name, 'Dirty', 'off');
            close_system(model_name, 0);
        end
    end
end

function assign_mature_exchange_workspace(options, model_path)
    shex_T_init = get_system_temperature(options, 'Tshex_K', options.system.Th_K);
    shex_source_T_init = get_system_temperature(options, 'Tshex_source_K', ...
        get_system_temperature(options, 'T_PSC_K', shex_T_init));
    hhex_T_init = get_system_temperature(options, 'Thhex_K', options.system.T0_K);
    chex_T_init = get_system_temperature(options, 'Tchex_K', options.system.Tc_K);
    axial_heat_transfer_scale = compute_axial_heat_transfer_scale(options);
    exchange_options = struct( ...
        'model_path', model_path, ...
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

    names = fieldnames(sim_params);
    for idx = 1:numel(names)
        assignin('base', names{idx}, sim_params.(names{idx}));
    end
end

function assign_constitutive_workspace(options)
    sample_time_s = options.constitutive.simulink_sample_time_s;
    assignin('base', 'constitutive_sample_time_s', sample_time_s);
    assignin('base', 'constitutive_state21_initial', ...
        Initialize_HeatDriveECC_ConstitutiveVector21(options));
    assignin('base', 'constitutive_output_width', ...
        options.constitutive.simulink_output_width);
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

function configure_simscape_local_solver(model_name, options)
    if ~isfield(options, 'simscape') || ~isstruct(options.simscape) || ...
            ~isfield(options.simscape, 'local_solver_enabled') || ...
            ~options.simscape.local_solver_enabled
        return;
    end
    solver_blocks = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'MaskType', 'Solver Configuration');
    if isempty(solver_blocks)
        solver_blocks = find_system(model_name, 'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', 'Name', 'Solver Configuration');
    end
    choice = get_option_or_default(options.simscape, ...
        'local_solver_choice', 'NE_BACKWARD_EULER_ADVANCER');
    sample_time_s = get_option_or_default(options.simscape, ...
        'local_solver_sample_time_s', 1.0e-3);
    for idx = 1:numel(solver_blocks)
        set_param(solver_blocks{idx}, 'UseLocalSolver', 'on');
        set_param(solver_blocks{idx}, 'LocalSolverChoice', choice);
        set_param(solver_blocks{idx}, 'LocalSolverSampleTime', ...
            num2str(sample_time_s, '%.15g'));
    end
end

function value = get_option_or_default(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end

function mark_ecc_mainline(model_name)
    add_or_update_note(model_name, 'ECC_Mainline_Note', ...
        ['ECC mainline is heatdrive_ecc_coupled_se21.slx.', newline, ...
        'Retained verified TL network: pressure source, V1-V6, active SE21 shell, hot/cold HX, buffers, and probes.', newline, ...
        'SMA/SE remain separate thermal modules; the coupled constitutive interface injects 21-node latent/mechanical heat sources.'], ...
        [40 10 820 75]);

    add_or_update_note(model_name, 'ECC_Route_Map', ...
        ['Article route target on one static valve-controlled network:', newline, ...
        'S1: SHEX -> SMA actuator during SMA heat/load.', newline, ...
        'S2: SE refrigerant -> THE/HHEX during loaded heat rejection.', newline, ...
        'S3: THE/HHEX -> SMA actuator during SMA cool/unload.', newline, ...
        'S4: CHEX -> SE refrigerant during cold-side heat absorption.'], ...
        [840 10 1480 105]);

    tag_block(model_name, 'Pressure Source (TL)', ...
        'ECC pump / pressure source retained from mature model');
    tag_block(model_name, 'ValveCommandFromWorkspace', ...
        'Four-stage valve command input for route gates');
    tag_block(model_name, 'V1_cold_inlet', ...
        'Retained mature route gate V1');
    tag_block(model_name, 'V2_hot_return', ...
        'Retained mature route gate V2');
    tag_block(model_name, 'V3_sma_to_hot', ...
        'Retained mature route gate V3');
    tag_block(model_name, 'V4_hot_inlet', ...
        'Retained mature route gate V4');
    tag_block(model_name, 'V5_cold_return', ...
        'Retained mature route gate V5');
    tag_block(model_name, 'V6_sma_to_chip_cold', ...
        'Retained mature route gate V6');
    tag_block(model_name, 'SE', ...
        'Active dual-path SE21 exchanger shell; ECC solid law is handled separately');
    tag_heat_exchanger_blocks(model_name);
end

function tag_heat_exchanger_blocks(model_name)
    hx_blocks = find_system(model_name, 'SearchDepth', 1, 'BlockType', 'SubSystem');
    for idx = 1:numel(hx_blocks)
        block_name = get_param(hx_blocks{idx}, 'Name');
        block_type = lower(block_name);
        if contains(block_name, '热端') || contains(block_type, 'hot')
            tag_block(model_name, block_name, ...
                'HHEX/THE exchanger retained from mature model');
        elseif contains(block_name, '冷端') || contains(block_type, 'cold')
            tag_block(model_name, block_name, ...
                'CHEX exchanger retained from mature model');
        end
    end
end

function add_or_update_note(model_name, tag, text, position)
    existing = find_system(model_name, 'FindAll', 'on', ...
        'Type', 'annotation', 'Tag', tag);
    for idx = 1:numel(existing)
        try
            delete(existing(idx));
        catch
        end
    end
    ann = Simulink.Annotation(model_name, text);
    ann.Tag = tag;
    ann.Position = position;
end

function tag_block(model_name, block_name, text)
    block_path = [model_name '/' block_name];
    if ~bdIsLoaded(model_name) || ~exist_block(block_path)
        return;
    end
    try
        set_param(block_path, 'AttributesFormatString', text);
    catch
        % Cosmetic tags are optional; topology is carried by the copied model.
    end
end

function tf = exist_block(block_path)
    try
        get_param(block_path, 'Handle');
        tf = true;
    catch
        tf = false;
    end
end
