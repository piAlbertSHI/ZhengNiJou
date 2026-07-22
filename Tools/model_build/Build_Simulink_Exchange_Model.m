function target_model_path = Build_Simulink_Exchange_Model(force_rebuild, build_options)
% Generic Simulink exchange-model builder for the GX101R1 stage 2 / stage 4
% fluid exchange network.
%
% Despite the historical "solver51" naming on the previous file
% (Build_nixunhuan_solver51.m), this is the universal constructor: the
% historical radial SMA solver used 51 nodes, while the directional fluid
% strip inside the Simulink TL network can be rebuilt at the requested
% node count. For the current heat-driven SE branch, the wrapper builds two
% direct 21-node paths instead of the old mirrored 101-node paths.
%
% Configurable through build_options:
%   solid_block_name      - visible root subsystem name for the active solid
%                           heat exchanger core (default 'SMA'; use 'SE'
%                           for the heat-driven SE branch).
%   sma_node_count        - number of HoldPipe_NNN / CooldownPipe_NNN
%                           blocks built inside the solid core.
%   sma_tap_count         - thermal-port tap count on Subsystem2 (defaults
%                           to sma_node_count).
%   temperature_workspace_var, temperature_init_expr_template - how the
%                           initial radial temperature array is wired to
%                           the SMA solid network.
%   sma_interface_mode    - how the 51 / 101 fluid pipes map into the
%                           radial SMA solver.
%   r54_safe_profile_enabled - apply the R50 runner-equivalent fallback
%                           solver defaults.
%   r54_audit_probe_commenting_enabled - disable conservative audit-only
%                           To Workspace sinks for isolated smoke tests.
%   root_manifold_split_mode - root manifold prototype selector. The default
%                           'none' keeps the validated six-valve topology;
%                           'r52_supply_only' reproduces the failed R52
%                           supply-side split for explicit diagnostics only.
%                           'r60_full_split' adds the return-side hydraulic
%                           split. It intentionally keeps a single Simscape
%                           Solver Configuration because the SMA thermal
%                           liquid network is still one physical network.
%   cold_end_topology_mode - cold-side endpoint topology selector. The
%                           default 'r69_symmetric' builds a cold end that
%                           mirrors the hot end: one CHEX pipe, cold sink
%                           mass, and cold load. 'r68_split' remains an
%                           explicit fallback for the HX/return/transit
%                           prototype.

    if nargin < 1 || isempty(force_rebuild)
        force_rebuild = false;
    end
    if nargin < 2 || isempty(build_options)
        build_options = struct();
    end

    this_dir = fileparts(mfilename('fullpath'));
    build_config = build_model_config(this_dir, build_options);
    source_model_path = build_config.source_model_path;
    target_model_path = build_config.target_model_path;
    source_model_name = build_config.source_model_name;
    target_model_name = build_config.target_model_name;

    if exist(target_model_path, 'file') && ~force_rebuild && ...
            target_model_has_variable_pressure_source(target_model_path, target_model_name, ...
            build_config.root_manifold_split_mode) && ...
            target_model_has_pressurized_tanks(target_model_path, target_model_name) && ...
            target_model_has_sma_pipe_length_add(target_model_path, target_model_name) && ...
            target_model_has_core_exchange_contract(target_model_path, target_model_name, ...
            build_config.solid_block_name, build_config.sma_node_count, ...
            build_config.temperature_workspace_var) && ...
            target_model_has_cold_end_topology(target_model_path, target_model_name, ...
            build_config.cold_end_topology_mode)
        return;
    end
    source_model_available = exist(source_model_path, 'file') == 2;
    if ~source_model_available && ~exist(target_model_path, 'file')
        error('Build_Simulink_Exchange_Model:MissingSourceModel', ...
            'Source model not found and target model cannot be rebuilt in place: %s', source_model_path);
    end

    if bdIsLoaded(target_model_name)
        close_system(target_model_name, 0);
    end

    if source_model_available
        load_system(source_model_path);
        save_system(source_model_name, target_model_path);
        load_system(target_model_path);
    else
        load_system(target_model_path);
    end
    ensure_core_subsystem_name(target_model_name, build_config.solid_block_name);

    rebuild_sma_subsystem(target_model_name, ...
        build_config.solid_block_name, ...
        build_config.sma_node_count, ...
        build_config.sma_tap_count, ...
        build_config.temperature_workspace_var, ...
        build_config.temperature_init_expr_template, ...
        build_config.sma_interface_mode);
    rebuild_sma_fluid_network_if_needed(target_model_name, ...
        build_config.solid_block_name, ...
        build_config.sma_node_count, ...
        build_config.sma_interface_mode);
    rewrite_valve_monitor_chart(target_model_name);
    rename_root_valves(target_model_name);
    replace_root_boundary_buffers(target_model_name);
    configure_root_pressure_source_for_pressure_control(target_model_name);
    if any(strcmp(build_config.root_manifold_split_mode, {'r52_supply_only', 'r60_full_split', 'r63_full_split'}))
        split_root_manifold_tj1_cold_hot(target_model_name);
    end
    if strcmp(build_config.root_manifold_split_mode, 'r60_full_split')
        split_root_return_manifold_full(target_model_name);
    elseif strcmp(build_config.root_manifold_split_mode, 'r63_full_split')
        split_root_return_manifold_full(target_model_name);
    end
    configure_root_valve_startup_source(target_model_name);

    [hot_subsystem_path, cold_subsystem_path] = locate_exchange_subsystems(target_model_name);
    rebuild_hot_end_subsystem(hot_subsystem_path);
    rebuild_cold_end_subsystem(cold_subsystem_path, build_config.cold_end_topology_mode);
    normalize_tl_storage_initial_temperatures(target_model_name, hot_subsystem_path, cold_subsystem_path, ...
        build_config.solid_block_name);
    configure_tl_tank_pressures(target_model_name);
    add_root_observability_probes(target_model_name, build_config.solid_block_name);
    configure_root_pressure_pi_feedback(target_model_name);
    configure_r54_safe_profile(target_model_name, ...
        build_config.r54_safe_profile_enabled, ...
        build_config.r54_audit_probe_commenting_enabled);
    % insert_root_transit_pipe REMOVED after r19c experiment: adding an
    % adiabatic TL Pipe at root level between V6.RConn and cold_subsystem
    % made cycle 1 transport_ratio collapse from 0.84 to 0.49 because the
    % pipe absorbs cold from the SMA-outlet flow (fluid is colder than the
    % stored pipe content) and never releases it to CHEX. The pipe stores
    % cold without delivering it. Kept the inner-subsystem TransitPipe
    % (TransitPipe_V6_to_CHEX), which gives a +0.13 cycle-1 transport_ratio
    % improvement vs r17 baseline and does not cause this regression.
    apply_root_visual_layout(target_model_name, build_config.solid_block_name);
    apply_compact_visual_font_size(target_model_name, build_config.compact_visual_font_size);

    save_system(target_model_name);
    close_system(target_model_name, 0);
    if source_model_available && bdIsLoaded(source_model_name)
        close_system(source_model_name, 0);
    end
end

function ok = target_model_has_sma_pipe_length_add(target_model_path, target_model_name)
    model_was_loaded = bdIsLoaded(target_model_name);
    try
        if ~model_was_loaded
            load_system(target_model_path);
        end
        probe_blocks = find_system(target_model_name, ...
            'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', ...
            'Name', 'HoldPipe_001');
        if isempty(probe_blocks)
            ok = false;
        else
            ok = strcmp(strtrim(get_param(probe_blocks{1}, 'length_add')), ...
                'sma_pipe_segment_length_add_l');
        end
        if ~model_was_loaded
            close_system(target_model_name, 0);
        end
    catch
        ok = false;
        if ~model_was_loaded && bdIsLoaded(target_model_name)
            close_system(target_model_name, 0);
        end
    end
end

function ok = target_model_has_core_exchange_contract( ...
        target_model_path, target_model_name, solid_block_name, node_count, workspace_var_name)
    model_was_loaded = bdIsLoaded(target_model_name);
    ok = false;
    try
        if ~model_was_loaded
            load_system(target_model_path);
        end

        core_path = [target_model_name '/' char(string(solid_block_name))];
        if getSimulinkBlockHandle(core_path) <= 0
            if ~model_was_loaded
                close_system(target_model_name, 0);
            end
            return;
        end

        hold_blocks = find_system(core_path, ...
            'SearchDepth', 1, ...
            'Regexp', 'on', ...
            'Name', '^HoldPipe_[0-9][0-9][0-9]$');
        cooldown_blocks = find_system(core_path, ...
            'SearchDepth', 1, ...
            'Regexp', 'on', ...
            'Name', '^CooldownPipe_[0-9][0-9][0-9]$');
        temperature_sink_path = [core_path '/Subsystem2/' sprintf('ToWorkspace_%s', workspace_var_name)];
        ok = numel(hold_blocks) == node_count && ...
            numel(cooldown_blocks) == node_count && ...
            getSimulinkBlockHandle(temperature_sink_path) > 0 && ...
            strcmp(strtrim(get_param(temperature_sink_path, 'VariableName')), ...
            char(string(workspace_var_name)));

        if ~model_was_loaded
            close_system(target_model_name, 0);
        end
    catch
        ok = false;
        if ~model_was_loaded && bdIsLoaded(target_model_name)
            close_system(target_model_name, 0);
        end
    end
end

function ok = target_model_has_transit_pipe_v6_to_chex(target_model_path, target_model_name)
    model_was_loaded = bdIsLoaded(target_model_name);
    try
        if ~model_was_loaded
            load_system(target_model_path);
        end
        transit_blocks = find_system(target_model_name, ...
            'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', ...
            'Name', 'TransitPipe_V6_to_CHEX');
        ok = ~isempty(transit_blocks);
        if ~model_was_loaded
            close_system(target_model_name, 0);
        end
    catch
        ok = false;
        if ~model_was_loaded && bdIsLoaded(target_model_name)
            close_system(target_model_name, 0);
        end
    end
end

function ok = target_model_has_cold_end_topology(target_model_path, target_model_name, cold_end_topology_mode)
    cold_end_topology_mode = normalize_cold_end_topology_mode(cold_end_topology_mode);
    model_was_loaded = bdIsLoaded(target_model_name);
    ok = false;
    try
        if ~model_was_loaded
            load_system(target_model_path);
        end
        has_transit = ~isempty(find_system(target_model_name, ...
            'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', ...
            'Name', 'TransitPipe_V6_to_CHEX'));
        has_return = ~isempty(find_system(target_model_name, ...
            'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', ...
            'Name', 'ColdSinkReturnPipe'));
        has_hx_split = ~isempty(find_system(target_model_name, ...
            'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', ...
            'Name', 'ColdSinkHXPipe'));
        has_single_pipe = ~isempty(find_system(target_model_name, ...
            'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', ...
            'Name', 'ColdSinkPipe'));
        has_cold_ambient = ~isempty(find_system(target_model_name, ...
            'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', ...
            'Name', 'ColdSinkAmbientLink'));
        switch cold_end_topology_mode
            case 'r69_symmetric'
                ok = has_single_pipe && ~has_transit && ~has_return && ~has_hx_split && ~has_cold_ambient;
            otherwise
                ok = has_transit;
        end
        if ~model_was_loaded
            close_system(target_model_name, 0);
        end
    catch
        ok = false;
        if ~model_was_loaded && bdIsLoaded(target_model_name)
            close_system(target_model_name, 0);
        end
    end
end

function ok = target_model_has_variable_pressure_source(target_model_path, target_model_name, root_manifold_split_mode)
    if nargin < 3 || isempty(root_manifold_split_mode)
        root_manifold_split_mode = 'none';
    end
    root_manifold_split_mode = normalize_root_manifold_split_mode(root_manifold_split_mode);
    ok = false;
    try
        was_loaded = bdIsLoaded(target_model_name);
        load_system(target_model_path);
        pressure_sources = find_system(target_model_name, ...
            'SearchDepth', 1, ...
            'LookUnderMasks', 'all', ...
            'MaskType', 'Pressure Source (TL)');
        flow_sources = find_system(target_model_name, ...
            'SearchDepth', 1, ...
            'LookUnderMasks', 'all', ...
            'MaskType', sprintf('Flow Rate Source\n(TL)'));
        if numel(pressure_sources) >= 1 && isempty(flow_sources) && ...
                target_model_has_pressure_pi_feedback_source(target_model_name)
            ok = true;
        elseif target_model_has_pressure_pi_feedback_source(target_model_name)
            ok = true;
        elseif isempty(pressure_sources) && target_model_has_valve_front_mass_flow_sources(target_model_name)
            ok = true;
        elseif ~isempty(pressure_sources) || isempty(flow_sources) || ...
                ~target_model_has_root_mass_flow_source(target_model_name)
            ok = false;
        else
            ok = true;
        end
        ok = ok && target_model_has_valve_startup_source(target_model_name) && ...
            target_model_root_manifold_matches(target_model_name, root_manifold_split_mode);
        if ~was_loaded
            close_system(target_model_name, 0);
        end
    catch
        ok = false;
    end
end

function ok = target_model_root_manifold_matches(model_name, root_manifold_split_mode)
    root_manifold_split_mode = normalize_root_manifold_split_mode(root_manifold_split_mode);
    has_r52_split = target_model_has_split_root_manifold(model_name);
    switch root_manifold_split_mode
        case 'none'
            ok = ~has_r52_split;
        case 'r52_supply_only'
            ok = has_r52_split;
        case 'r60_full_split'
            ok = has_r52_split && target_model_has_full_root_manifold_split(model_name);
        case 'r63_full_split'
            ok = has_r52_split && target_model_has_full_root_manifold_split(model_name);
        otherwise
            ok = false;
    end
end

function ok = target_model_has_pressure_control_source(model_name)
    source_path = [model_name '/Pressure Source (TL)'];
    if getSimulinkBlockHandle(source_path) <= 0
        ok = false;
        return;
    end
    try
        pressure_expr = strtrim(char(string(get_param(source_path, 'pressure_differential'))));
        source_type = char(string(get_param(source_path, 'source_type')));
        ok = strcmp(pressure_expr, 'pressure_differential_MPa') && ...
            contains(source_type, 'constant');
    catch
        ok = false;
    end
end

function ok = target_model_has_split_root_manifold(model_name)
    cold_source_path = [model_name '/Pressure Source Cold (TL)'];
    hot_root_path = [model_name '/T-Junction (TL)1_hot_root'];
    shared_tj_path = [model_name '/T-Junction (TL)1'];
    ok = getSimulinkBlockHandle(cold_source_path) > 0 && ...
        getSimulinkBlockHandle(hot_root_path) > 0 && ...
        getSimulinkBlockHandle(shared_tj_path) > 0;
end

function ok = target_model_has_full_root_manifold_split(model_name)
    legacy_common_path = [model_name '/T-Junction (TL)'];
    old_return_path = [model_name '/T-Junction (TL)2'];
    old_hot_anchor_path = [model_name '/T-Junction (TL)3'];
    cold_source_path = [model_name '/Pressure Source Cold (TL)'];
    hot_source_path = [model_name '/Pressure Source (TL)'];
    cold_converter_path = [model_name '/PressurePI_ColdSimulinkPS'];
    cold_solver_path = [model_name '/Cold Solver Configuration'];
    cold_tank_path = [model_name '/Cold Tank (TL)'];
    cold_settings_path = [model_name '/Cold Thermal Liquid Settings (TL)'];
    ok = getSimulinkBlockHandle(legacy_common_path) <= 0 && ...
        getSimulinkBlockHandle(old_return_path) <= 0 && ...
        getSimulinkBlockHandle(old_hot_anchor_path) > 0 && ...
        getSimulinkBlockHandle(cold_source_path) > 0 && ...
        getSimulinkBlockHandle(hot_source_path) > 0 && ...
        getSimulinkBlockHandle(cold_converter_path) > 0 && ...
        getSimulinkBlockHandle(cold_solver_path) <= 0 && ...
        getSimulinkBlockHandle(cold_tank_path) <= 0 && ...
        getSimulinkBlockHandle(cold_settings_path) <= 0;
end

function mode = normalize_root_manifold_split_mode(mode)
    mode = lower(strtrim(char(string(mode))));
    switch mode
        case {'', 'none', 'off', 'false', 'baseline', 'six_valve'}
            mode = 'none';
        case {'r52', 'r52_supply_only', 'supply_only'}
            mode = 'r52_supply_only';
        case {'r60', 'r60_full_split', 'full_split', 'complete_split', 'return_split'}
            mode = 'r60_full_split';
        case {'r63', 'r63_full_split', 'full_split_r63', 'split_with_cold_solver'}
            mode = 'r63_full_split';
        otherwise
            error('Build_Simulink_Exchange_Model:InvalidRootManifoldSplitMode', ...
                'Unsupported root_manifold_split_mode: %s', mode);
    end
end

function mode = normalize_cold_end_topology_mode(mode)
    mode = lower(strtrim(char(string(mode))));
    switch mode
        case {'', 'current'}
            mode = 'r69_symmetric';
        case {'r68', 'r68_split', 'split'}
            mode = 'r68_split';
        case {'r69', 'r69_symmetric', 'symmetric', 'single_pipe', 'no_transit'}
            mode = 'r69_symmetric';
        otherwise
            error('Build_Simulink_Exchange_Model:InvalidColdEndTopologyMode', ...
                'Unsupported cold_end_topology_mode: %s', mode);
    end
end

function ok = target_model_has_pressure_pi_feedback_source(model_name)
    source_path = [model_name '/Pressure Source (TL)'];
    converter_path = [model_name '/PressurePI_SimulinkPS'];
    if getSimulinkBlockHandle(source_path) <= 0 || getSimulinkBlockHandle(converter_path) <= 0
        ok = false;
        return;
    end
    try
        ok = contains(char(string(get_param(source_path, 'source_type'))), 'controlled');
    catch
        ok = false;
    end
end

function ok = target_model_has_valve_front_mass_flow_sources(model_name)
    hold_path = [model_name '/MassFlowSource_hold_valve_front'];
    cooldown_path = [model_name '/MassFlowSource_cooldown_valve_front'];
    restriction_path = [model_name '/RootBypassRestriction_R39'];
    if getSimulinkBlockHandle(hold_path) <= 0 || ...
            getSimulinkBlockHandle(cooldown_path) <= 0 || ...
            getSimulinkBlockHandle(restriction_path) <= 0
        ok = false;
        return;
    end
    try
        ok = strcmp(strtrim(get_param(hold_path, 'mass_flow')), 'mdot_hold_source_kgps') && ...
            strcmp(strtrim(get_param(cooldown_path, 'mass_flow')), 'mdot_cooldown_source_kgps') && ...
            contains(char(string(get_param(hold_path, 'flow_type'))), 'mass') && ...
            contains(char(string(get_param(cooldown_path, 'flow_type'))), 'mass');
    catch
        ok = false;
    end
end

function ok = target_model_has_root_mass_flow_source(model_name)
    block_path = [model_name '/Pressure Source (TL)'];
    if getSimulinkBlockHandle(block_path) <= 0
        ok = false;
        return;
    end
    try
        ok = strcmp(strtrim(get_param(block_path, 'mass_flow')), 'mdot_root_source_kgps') && ...
            contains(char(string(get_param(block_path, 'flow_type'))), 'mass');
    catch
        ok = false;
    end
end

function ok = target_model_has_pressurized_tanks(target_model_path, target_model_name)
    ok = false;
    model_was_loaded = bdIsLoaded(target_model_name);
    try
        if ~model_was_loaded
            load_system(target_model_path);
        end
        tank_blocks = find_system(target_model_name, ...
            'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', ...
            'MaskType', 'Tank (TL)');
        if isempty(tank_blocks)
            return;
        end
        ok = true;
        for idx = 1:numel(tank_blocks)
            pressure_spec = char(string(get_param(tank_blocks{idx}, 'pressure_spec')));
            tank_pressure = char(string(get_param(tank_blocks{idx}, 'tank_pressure')));
            ok = ok && contains(lower(pressure_spec), 'specified') && ...
                strcmp(strtrim(tank_pressure), 'tank_pressure_MPa');
        end
        if ~model_was_loaded
            close_system(target_model_name, 0);
        end
    catch
        if ~model_was_loaded && bdIsLoaded(target_model_name)
            close_system(target_model_name, 0);
        end
        ok = false;
    end
end

function ok = target_model_has_valve_startup_source(model_name)
    ok = false;
    try
        sources = find_system(model_name, ...
            'SearchDepth', 1, ...
            'BlockType', 'FromWorkspace');
        for idx = 1:numel(sources)
            try
                if strcmp(strtrim(get_param(sources{idx}, 'VariableName')), 'L_valve_command')
                    ok = true;
                    return;
                end
            catch
            end
        end
    catch
        ok = false;
    end
end

function build_config = build_model_config(this_dir, build_options)
    build_config = struct( ...
        'source_model_path', fullfile(this_dir, 'nixunhuan_singal.slx'), ...
        'source_model_name', 'nixunhuan_singal', ...
        'target_model_path', fullfile(this_dir, 'nixunhuan_solver51.slx'), ...
        'target_model_name', 'nixunhuan_solver51', ...
        'solid_block_name', 'SMA', ...
        'sma_node_count', 51, ...
        'sma_tap_count', 12, ...
        'sma_interface_mode', 'legacy_taps', ...
        'temperature_workspace_var', 'Tx51', ...
        'temperature_init_expr_template', 'solver_T_init_51(%d)', ...
        'compact_visual_font_size', 5, ...
        'root_manifold_split_mode', 'none', ...
        'cold_end_topology_mode', 'r69_symmetric', ...
        'r54_safe_profile_enabled', true, ...
        'r54_audit_probe_commenting_enabled', false);

    build_config = override_build_field(build_config, build_options, 'target_model_path');
    build_config = override_build_field(build_config, build_options, 'target_model_name');
    build_config = override_build_field(build_config, build_options, 'solid_block_name');
    build_config = override_build_field(build_config, build_options, 'sma_node_count');
    build_config = override_build_field(build_config, build_options, 'sma_tap_count');
    build_config = override_build_field(build_config, build_options, 'sma_interface_mode');
    build_config = override_build_field(build_config, build_options, 'temperature_workspace_var');
    build_config = override_build_field(build_config, build_options, 'temperature_init_expr_template');
    build_config = override_build_field(build_config, build_options, 'compact_visual_font_size');
    build_config = override_build_field(build_config, build_options, 'root_manifold_split_mode');
    build_config = override_build_field(build_config, build_options, 'cold_end_topology_mode');
    build_config = override_build_field(build_config, build_options, 'r54_safe_profile_enabled');
    build_config = override_build_field(build_config, build_options, 'r54_audit_probe_commenting_enabled');
    build_config.root_manifold_split_mode = normalize_root_manifold_split_mode( ...
        build_config.root_manifold_split_mode);
    build_config.cold_end_topology_mode = normalize_cold_end_topology_mode( ...
        build_config.cold_end_topology_mode);
    build_config.solid_block_name = char(string(build_config.solid_block_name));
    if isempty(strtrim(build_config.solid_block_name))
        error('Build_Simulink_Exchange_Model:InvalidSolidBlockName', ...
            'solid_block_name must be a nonempty Simulink block name.');
    end
end

function build_config = override_build_field(build_config, build_options, field_name)
    if isstruct(build_options) && isfield(build_options, field_name) && ~isempty(build_options.(field_name))
        build_config.(field_name) = build_options.(field_name);
    end
end

function ensure_core_subsystem_name(model_name, solid_block_name)
    solid_block_name = char(string(solid_block_name));
    target_path = [model_name '/' solid_block_name];
    if getSimulinkBlockHandle(target_path) > 0
        return;
    end

    historical_path = [model_name '/SMA'];
    if getSimulinkBlockHandle(historical_path) > 0
        set_param(historical_path, 'Name', solid_block_name);
        return;
    end

    error('Build_Simulink_Exchange_Model:MissingSolidCore', ...
        'Could not find root solid core block "%s" or historical "SMA".', solid_block_name);
end

function rebuild_sma_subsystem(model_name, solid_block_name, node_count, tap_count, workspace_var_name, temperature_init_expr_template, interface_mode)
    subsystem_path = [model_name '/' char(string(solid_block_name)) '/Subsystem2'];
    if nargin < 6 || isempty(interface_mode)
        interface_mode = 'legacy_taps';
    end
    interface_mode = char(string(interface_mode));
    if strcmp(interface_mode, 'dual_path_serial_nodewise')
        port_count = 2 * node_count;
    else
        port_count = tap_count;
    end

    sync_pmio_connection_ports(subsystem_path, port_count);
    delete_contents_except_ports(subsystem_path);

    add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', ...
        [subsystem_path '/ThermalReference51'], ...
        'Position', [150 40 190 80]);

    add_block('simulink/Signal Routing/Mux', ...
        [subsystem_path '/TempMux51'], ...
        'Inputs', num2str(node_count), ...
        'Position', [1040 140 1045 140 + 24 * node_count]);

    add_block('simulink/Sinks/To Workspace', ...
        [subsystem_path '/' sprintf('ToWorkspace_%s', workspace_var_name)], ...
        'VariableName', workspace_var_name, ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [1120 200 1225 230]);

    add_line(subsystem_path, 'TempMux51/1', ...
        sprintf('ToWorkspace_%s/1', workspace_var_name), 'autorouting', 'on');

    ref_handles = get_param([subsystem_path '/ThermalReference51'], 'PortHandles');
    mux_handles = get_param([subsystem_path '/TempMux51'], 'PortHandles');

    mass_paths = cell(node_count, 1);
    sensor_paths = cell(node_count, 1);

    y0 = 80;
    dy = 48;
    for idx = 1:node_count
        y = y0 + (idx - 1) * dy;
        mass_name = sprintf('NodeMass_%02d', idx);
        sensor_name = sprintf('NodeTempSensor_%02d', idx);
        ps_name = sprintf('NodeTempPS_%02d', idx);

        mass_paths{idx} = [subsystem_path '/' mass_name];
        sensor_paths{idx} = [subsystem_path '/' sensor_name];

        add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass', mass_paths{idx}, ...
            'Position', [250 y 305 y + 26], ...
            'mass', 'solver51_node_mass', ...
            'sp_heat', 'solver51_node_cp', ...
            'T_specify', 'on', ...
            'T', sprintf(temperature_init_expr_template, idx));

        add_block('fl_lib/Thermal/Thermal Sensors/Temperature Sensor', sensor_paths{idx}, ...
            'Position', [420 y - 2 470 y + 28]);

        add_block('nesl_utility/PS-Simulink Converter', [subsystem_path '/' ps_name], ...
            'Position', [620 y 640 y + 20], ...
            'VectorFormat', '1-D array', ...
            'Unit', 'K');

        add_line(subsystem_path, get_port(mass_paths{idx}, 'LConn', 1), get_port(sensor_paths{idx}, 'LConn', 1), 'autorouting', 'on');
        add_line(subsystem_path, get_port(sensor_paths{idx}, 'RConn', 1), ref_handles.LConn(1), 'autorouting', 'on');
        add_line(subsystem_path, get_port(sensor_paths{idx}, 'RConn', 2), get_port([subsystem_path '/' ps_name], 'LConn', 1), 'autorouting', 'on');
        add_line(subsystem_path, get_port([subsystem_path '/' ps_name], 'Outport', 1), mux_handles.Inport(idx), 'autorouting', 'on');
    end

    for idx = 1:node_count - 1
        y = y0 + (idx - 1) * dy + 12;
        cond_name = sprintf('NodeCond_%02d_%02d', idx, idx + 1);
        cond_path = [subsystem_path '/' cond_name];
        add_block('fl_lib/Thermal/Thermal Elements/Conductive Heat Transfer', cond_path, ...
            'Position', [330 y 375 y + dy], ...
            'area', 'solver51_cond_area', ...
            'thickness', 'solver51_cond_dx', ...
            'th_cond', 'solver51_cond_k');

        add_line(subsystem_path, get_port(mass_paths{idx}, 'LConn', 1), get_port(cond_path, 'LConn', 1), 'autorouting', 'on');
        add_line(subsystem_path, get_port(cond_path, 'RConn', 1), get_port(mass_paths{idx + 1}, 'LConn', 1), 'autorouting', 'on');
    end

    if strcmp(interface_mode, 'dual_path_serial_nodewise')
        for node_idx = 1:node_count
            hold_conn_path = [subsystem_path sprintf('/Conn%d', node_idx)];
            cooldown_conn_path = [subsystem_path sprintf('/Conn%d', node_count + node_idx)];
            add_line(subsystem_path, get_port(hold_conn_path, 'RConn', 1), ...
                get_port(mass_paths{node_idx}, 'LConn', 1), 'autorouting', 'on');
            add_line(subsystem_path, get_port(cooldown_conn_path, 'RConn', 1), ...
                get_port(mass_paths{node_idx}, 'LConn', 1), 'autorouting', 'on');
        end
    else
        tap_indices = build_uniform_tap_indices(node_count, tap_count);
        for tap_idx = 1:tap_count
            conn_path = [subsystem_path sprintf('/Conn%d', tap_idx)];
            add_line(subsystem_path, get_port(conn_path, 'RConn', 1), get_port(mass_paths{tap_indices(tap_idx)}, 'LConn', 1), 'autorouting', 'on');
        end
    end
end

function rebuild_sma_fluid_network_if_needed(model_name, solid_block_name, node_count, interface_mode)
    if nargin < 4 || ~strcmp(char(string(interface_mode)), 'dual_path_serial_nodewise')
        return;
    end

    sma_path = [model_name '/' char(string(solid_block_name))];
    subsystem_path = [sma_path '/Subsystem2'];
    clear_sma_fluid_network_except_ports_and_nodes(sma_path);

    hold_pipe_paths = cell(node_count, 1);
    cooldown_pipe_paths = cell(node_count, 1);
    y0 = 120;
    dy = 36;

    for node_idx = 1:node_count
        y = y0 + (node_idx - 1) * dy;
        hold_pipe_paths{node_idx} = [sma_path sprintf('/HoldPipe_%03d', node_idx)];
        add_pipe_block(hold_pipe_paths{node_idx}, [260 y 350 y + 28], ...
            'sma_fluid_T_init', 'sma_pipe_segment_l', 'sma_pipe_segment_length_add_l');
        hold_gate_path = [sma_path sprintf('/HoldThermalGate_%03d', node_idx)];
        add_sma_pipe_thermal_gate_block(hold_gate_path, [370 y 410 y + 28], ...
            'sma_hold_pipe_to_sma_G_W_per_K');
        connect_physical_ports(sma_path, ...
            get_port(hold_pipe_paths{node_idx}, 'LConn', 2), ...
            get_port(hold_gate_path, 'LConn', 1));
        connect_physical_ports(sma_path, ...
            get_port(hold_gate_path, 'RConn', 1), ...
            get_port(subsystem_path, 'RConn', node_idx));

        cooldown_node_idx = node_count + node_idx;
        cooldown_pipe_paths{node_idx} = [sma_path sprintf('/CooldownPipe_%03d', node_idx)];
        add_pipe_block(cooldown_pipe_paths{node_idx}, [500 y 590 y + 28], ...
            'sma_fluid_T_init', 'sma_pipe_segment_l', 'sma_pipe_segment_length_add_l');
        cooldown_gate_path = [sma_path sprintf('/CooldownThermalGate_%03d', node_idx)];
        add_sma_pipe_thermal_gate_block(cooldown_gate_path, [610 y 650 y + 28], ...
            'sma_cooldown_pipe_to_sma_G_W_per_K');
        connect_physical_ports(sma_path, ...
            get_port(cooldown_pipe_paths{node_idx}, 'LConn', 2), ...
            get_port(cooldown_gate_path, 'LConn', 1));
        connect_physical_ports(sma_path, ...
            get_port(cooldown_gate_path, 'RConn', 1), ...
            get_port(subsystem_path, 'RConn', cooldown_node_idx));
    end

    % Stage 2 root flow is opposite the historical Conn1/Conn2 labels.
    % Wire it so accepted x-index order remains cold side 1 -> hot side 101.
    connect_physical_ports(sma_path, get_port([sma_path '/Conn1'], 'RConn', 1), get_port(hold_pipe_paths{node_count}, 'RConn', 1));
    for node_idx = node_count:-1:2
        connect_physical_ports(sma_path, get_port(hold_pipe_paths{node_idx}, 'LConn', 1), ...
            get_port(hold_pipe_paths{node_idx - 1}, 'RConn', 1));
    end
    connect_physical_ports(sma_path, get_port(hold_pipe_paths{1}, 'LConn', 1), get_port([sma_path '/Conn2'], 'RConn', 1));

    % Stage 4 root flow is likewise wired so x-index order is hot side 101 -> cold side 1.
    connect_physical_ports(sma_path, get_port([sma_path '/Conn3'], 'RConn', 1), get_port(cooldown_pipe_paths{1}, 'RConn', 1));
    for node_idx = 1:node_count - 1
        connect_physical_ports(sma_path, get_port(cooldown_pipe_paths{node_idx}, 'LConn', 1), ...
            get_port(cooldown_pipe_paths{node_idx + 1}, 'RConn', 1));
    end
    connect_physical_ports(sma_path, get_port(cooldown_pipe_paths{node_count}, 'LConn', 1), get_port([sma_path '/Conn4'], 'RConn', 1));
end

function clear_sma_fluid_network_except_ports_and_nodes(sma_path)
    delete_all_lines(sma_path);

    blocks = find_system(sma_path, 'SearchDepth', 1, 'Type', 'Block');
    for idx = 1:numel(blocks)
        block_path = blocks{idx};
        if strcmp(block_path, sma_path)
            continue;
        end
        block_name = get_param(block_path, 'Name');
        if startsWith(block_name, 'Conn') || strcmp(block_name, 'Subsystem2')
            continue;
        end
        delete_block(block_path);
    end

    delete_all_lines(sma_path);
end

function sync_pmio_connection_ports(subsystem_path, port_count)
    if port_count < 1
        error('Build_Simulink_Exchange_Model:InvalidPortCount', ...
            'Solid-core thermal interface port count must be positive.');
    end

    template_path = [subsystem_path '/Conn1'];
    if getSimulinkBlockHandle(template_path) <= 0
        add_block('built-in/PMIOPort', template_path, ...
            'Port', '1', ...
            'Side', 'Right', ...
            'Position', [30 80 60 100]);
    end

    for idx = 1:port_count
        conn_path = [subsystem_path sprintf('/Conn%d', idx)];
        if getSimulinkBlockHandle(conn_path) <= 0
            add_block(template_path, conn_path, 'MakeNameUnique', 'off');
        end
        y = 80 + (idx - 1) * 24;
        set_param(conn_path, ...
            'Port', num2str(idx), ...
            'Side', 'Right', ...
            'Position', [30 y 60 y + 18]);
    end

    conn_blocks = find_system(subsystem_path, ...
        'SearchDepth', 1, ...
        'Regexp', 'on', ...
        'Name', '^Conn[0-9]+$');
    for idx = 1:numel(conn_blocks)
        block_name = get_param(conn_blocks{idx}, 'Name');
        token = regexp(block_name, '^Conn([0-9]+)$', 'tokens', 'once');
        if isempty(token)
            continue;
        end
        conn_index = str2double(token{1});
        if conn_index > port_count
            delete_block_if_present_with_lines(conn_blocks{idx});
        end
    end
end

function rewrite_valve_monitor_chart(model_name)
    rt = sfroot;
    chart = rt.find('-isa', 'Stateflow.EMChart', 'Path', [model_name '/MATLAB Function']);
    if isempty(chart)
        return;
    end

    chart.Script = sprintf([ ...
        'function y = fcn(v1_cold_inlet,v2_hot_return,v3_sma_to_hot,v4_hot_inlet,v5_cold_return,v6_sma_to_chip_cold)\n' ...
        '%%#codegen\n' ...
        'y = [v1_cold_inlet, v2_hot_return, v3_sma_to_hot, v4_hot_inlet, v5_cold_return, v6_sma_to_chip_cold];\n']);
end

function rename_root_valves(model_name)
    sid_map = { ...
        '825', 'V1_cold_inlet'; ...
        '827', 'V2_hot_return'; ...
        '828', 'V3_sma_to_hot'; ...
        '829', 'V4_hot_inlet'; ...
        '830', 'V5_cold_return'; ...
        '831', 'V6_sma_to_chip_cold'};

    for idx = 1:size(sid_map, 1)
        rename_block_if_present(model_name, sid_map{idx, 1}, sid_map{idx, 2});
    end
end

function replace_root_boundary_buffers(model_name)
    hot_res_path = find_block_by_sid(model_name, '961');
    cold_res_path = find_block_by_sid(model_name, '963');

    if getSimulinkBlockHandle([model_name '/HotFluidBuffer']) <= 0
        replace_reservoir_with_tank_buffer(hot_res_path, 'HotFluidBuffer', ...
            'hot_fluid_buffer_T_init');
    end
    if getSimulinkBlockHandle([model_name '/ColdFluidBuffer']) <= 0
        replace_reservoir_with_tank_buffer(cold_res_path, 'ColdFluidBuffer', ...
            'cold_fluid_buffer_T_init');
    end
end

function configure_root_pressure_source_for_pressure_control(model_name)
    pressure_sources = find_system(model_name, ...
        'SearchDepth', 1, ...
        'LookUnderMasks', 'all', ...
        'MaskType', 'Pressure Source (TL)');
    flow_sources = find_system(model_name, ...
        'SearchDepth', 1, ...
        'LookUnderMasks', 'all', ...
        'MaskType', sprintf('Flow Rate Source\n(TL)'));
    if isempty(pressure_sources)
        error('Build_Simulink_Exchange_Model:MissingRootPressureSource', ...
            'Could not locate the root Pressure Source (TL) for pressure control.');
    end
    if ~isempty(flow_sources)
        error('Build_Simulink_Exchange_Model:UnexpectedRootFlowSource', ...
            'Root Flow Rate Source (TL) exists in the default model; restore clean pressure topology first.');
    end
    source_path = pressure_sources{1};
    set_param(source_path, ...
        'source_type', 'foundation.enum.constant_controlled.constant', ...
        'pressure_differential', 'pressure_differential_MPa', ...
        'pressure_differential_unit', 'MPa', ...
        'area', 'pipe_fa');
end

function split_root_manifold_tj1_cold_hot(model_name)
% R52: physically separate the cold and hot buffer root nodes without adding
% valves or serial TL restrictions. Existing T-Junction (TL)1 becomes the
% cold root; a cloned T-junction becomes the hot root. A duplicated pressure
% source lets the cold path close without rejoining cold/hot into one node.
    tj_cold_path = [model_name '/T-Junction (TL)1'];
    tj_hot_path = [model_name '/T-Junction (TL)1_hot_root'];
    tj_hot_anchor_path = [model_name '/T-Junction (TL)3'];
    tj_common_path = [model_name '/T-Junction (TL)'];
    source_hot_path = [model_name '/Pressure Source (TL)'];
    source_cold_path = [model_name '/Pressure Source Cold (TL)'];

    required = {tj_cold_path, tj_hot_anchor_path, tj_common_path, source_hot_path, ...
        [model_name '/ColdFluidBuffer'], [model_name '/HotFluidBuffer'], ...
        [model_name '/V1_cold_inlet'], [model_name '/V4_hot_inlet']};
    for idx = 1:numel(required)
        if getSimulinkBlockHandle(required{idx}) <= 0
            error('Build_Simulink_Exchange_Model:R52MissingRootBlock', ...
                'Required R52 root split block is missing: %s', required{idx});
        end
    end

    delete_block_if_present_with_lines(source_cold_path);
    delete_block_if_present_with_lines(tj_hot_path);

    add_block(source_hot_path, source_cold_path, ...
        'MakeNameUnique', 'off', ...
        'Position', [720 675 760 715]);
    set_param(source_cold_path, ...
        'source_type', 'foundation.enum.constant_controlled.constant', ...
        'pressure_differential', 'pressure_differential_MPa', ...
        'pressure_differential_unit', 'MPa', ...
        'area', 'pipe_fa');

    add_block(tj_cold_path, tj_hot_path, ...
        'MakeNameUnique', 'off', ...
        'Position', [720 725 760 765]);

    split_ports = [
        get_port(tj_cold_path, 'LConn', 1)
        get_port(tj_cold_path, 'RConn', 1)
        get_port(tj_cold_path, 'RConn', 2)
        get_port(tj_hot_anchor_path, 'LConn', 1)
        get_port(tj_common_path, 'LConn', 1)
        get_port([model_name '/ColdFluidBuffer'], 'LConn', 1)
        get_port([model_name '/V1_cold_inlet'], 'LConn', 1)
        get_port([model_name '/HotFluidBuffer'], 'LConn', 1)
        get_port([model_name '/V4_hot_inlet'], 'LConn', 1)
        ];
    for idx = 1:numel(split_ports)
        delete_lines_touching_port(split_ports(idx));
    end

    % Cold root: ColdFluidBuffer + V1 + cold pressure source.
    connect_physical_ports(model_name, get_port(tj_cold_path, 'LConn', 1), ...
        get_port([model_name '/ColdFluidBuffer'], 'LConn', 1));
    connect_physical_ports(model_name, get_port(tj_cold_path, 'RConn', 1), ...
        get_port([model_name '/V1_cold_inlet'], 'LConn', 1));
    connect_physical_ports(model_name, get_port(tj_cold_path, 'RConn', 2), ...
        get_port(source_cold_path, 'LConn', 1));

    % Hot root: HotFluidBuffer + V4 + existing hot-root anchor T-J(3).
    connect_physical_ports(model_name, get_port(tj_hot_path, 'LConn', 1), ...
        get_port([model_name '/HotFluidBuffer'], 'LConn', 1));
    connect_physical_ports(model_name, get_port(tj_hot_path, 'RConn', 1), ...
        get_port([model_name '/V4_hot_inlet'], 'LConn', 1));
    connect_physical_ports(model_name, get_port(tj_hot_path, 'RConn', 2), ...
        get_port(tj_hot_anchor_path, 'LConn', 1));

    % Cold source closes stage-2 through the same common return manifold used
    % by V2/V5. The existing source remains the hot-loop source.
    connect_physical_ports(model_name, get_port(source_cold_path, 'RConn', 1), ...
        get_port(tj_common_path, 'LConn', 1));
end

function split_root_return_manifold_full(model_name)
% R60/R63: complete the R52 split by removing the shared return manifold.
% The cold pressure source closes directly through V2 and the hot source
% closes directly through V5. R64 tested moving pressure sources onto the
% V1/V4 supply branches, but cycle1 stage2 did not finish after >17 min;
% keep the fast validated hydraulic layout as the mainline while the deeper
% isolation strategy is reworked.
    old_common_path = [model_name '/T-Junction (TL)'];
    legacy_cold_bridge_path = [model_name '/T-Junction (TL)_cold_bridge'];
    old_return_path = [model_name '/T-Junction (TL)2'];
    source_hot_path = [model_name '/Pressure Source (TL)'];
    source_cold_path = [model_name '/Pressure Source Cold (TL)'];
    v2_return_path = [model_name '/V2_hot_return'];
    v5_return_path = [model_name '/V5_cold_return'];
    cold_solver_path = [model_name '/Cold Solver Configuration'];
    cold_tank_path = [model_name '/Cold Tank (TL)'];
    cold_settings_path = [model_name '/Cold Thermal Liquid Settings (TL)'];

    required = {old_common_path, old_return_path, source_hot_path, source_cold_path, ...
        v2_return_path, v5_return_path, [model_name '/T-Junction (TL)1'], ...
        [model_name '/T-Junction (TL)1_hot_root'], [model_name '/T-Junction (TL)3']};
    for idx = 1:numel(required)
        if getSimulinkBlockHandle(required{idx}) <= 0
            error('Build_Simulink_Exchange_Model:R60MissingRootBlock', ...
                'Required R60 full split block is missing: %s', required{idx});
        end
    end

    delete_block_if_present_with_lines(cold_solver_path);
    delete_block_if_present_with_lines(cold_tank_path);
    delete_block_if_present_with_lines(cold_settings_path);
    delete_block_if_present_with_lines(legacy_cold_bridge_path);

    delete_lines_touching_port(get_port(old_common_path, 'LConn', 1));
    delete_lines_touching_port(get_port(old_common_path, 'RConn', 1));
    delete_lines_touching_port(get_port(old_common_path, 'RConn', 2));
    delete_lines_touching_port(get_port(old_return_path, 'LConn', 1));
    delete_lines_touching_port(get_port(old_return_path, 'RConn', 1));
    delete_lines_touching_port(get_port(old_return_path, 'RConn', 2));
    delete_lines_touching_port(get_port(source_cold_path, 'RConn', 1));
    delete_lines_touching_port(get_port(source_hot_path, 'RConn', 1));
    delete_lines_touching_port(get_port(v2_return_path, 'LConn', 1));
    delete_lines_touching_port(get_port(v5_return_path, 'LConn', 1));

    delete_block_if_present_with_lines(old_common_path);
    delete_block_if_present_with_lines(old_return_path);

    connect_physical_ports(model_name, get_port(source_cold_path, 'RConn', 1), ...
        get_port(v2_return_path, 'LConn', 1));
    connect_physical_ports(model_name, get_port(source_hot_path, 'RConn', 1), ...
        get_port(v5_return_path, 'LConn', 1));
end

function configure_root_pressure_pi_feedback(model_name)
% R59: make the verified R42/R44/R50 pressure-PI topology part of the
% canonical builder. Rebuilding from nixunhuan_singal.slx must not silently
% fall back to the slow open-loop pressure source.
    source_path = [model_name '/Pressure Source (TL)'];
    cold_source_path = [model_name '/Pressure Source Cold (TL)'];
    required_sensors = { ...
        [model_name '/FlowSensor_V1_cold_inlet_PS'], ...
        [model_name '/FlowSensor_V4_hot_inlet_PS']};
    if getSimulinkBlockHandle(source_path) <= 0
        error('Build_Simulink_Exchange_Model:MissingPressurePISource', ...
            'Cannot configure pressure PI because the root pressure source is missing.');
    end
    for idx = 1:numel(required_sensors)
        if getSimulinkBlockHandle(required_sensors{idx}) <= 0
            error('Build_Simulink_Exchange_Model:MissingPressurePISensor', ...
                'Cannot configure pressure PI because the required sensor is missing: %s', ...
                required_sensors{idx});
        end
    end

    set_param(source_path, ...
        'source_type', 'foundation.enum.constant_controlled.controlled', ...
        'pressure_differential', 'pressure_differential_MPa', ...
        'pressure_differential_unit', 'MPa', ...
        'area', 'pipe_fa');
    if getSimulinkBlockHandle(cold_source_path) > 0
        set_param(cold_source_path, ...
            'source_type', 'foundation.enum.constant_controlled.controlled', ...
            'pressure_differential', 'pressure_differential_MPa', ...
            'pressure_differential_unit', 'MPa', ...
            'area', 'pipe_fa');
    end
    delete_existing_pressure_pi_blocks(model_name);

    add_block('simulink/Sources/Constant', [model_name '/PressurePI_TargetHold'], ...
        'Value', 'mdot_hold_source_kgps', 'Position', [540 1180 620 1210]);
    add_block('simulink/Sources/Constant', [model_name '/PressurePI_TargetCooldown'], ...
        'Value', 'mdot_cooldown_source_kgps', 'Position', [540 1225 620 1255]);
    add_block('simulink/Math Operations/Gain', [model_name '/PressurePI_PassthruV1'], ...
        'Gain', '1', 'Position', [930 1165 960 1195]);
    add_block('simulink/Math Operations/Gain', [model_name '/PressurePI_PassthruV4'], ...
        'Gain', '1', 'Position', [930 1225 960 1255]);
    add_block('simulink/Math Operations/Sum', [model_name '/PressurePI_ErrorSum'], ...
        'Inputs', '++--', 'Position', [1005 1175 1035 1250]);
    add_block('simulink/Math Operations/Gain', [model_name '/PressurePI_ErrorNormalizer'], ...
        'Gain', 'pressure_pi_error_normalization_gain_kgps_inv', ...
        'Position', [1055 1195 1125 1235]);
    add_block('simulink/Continuous/Transfer Fcn', [model_name '/PressurePI_ErrorLag'], ...
        'Numerator', '1', ...
        'Denominator', '[pressure_pi_error_filter_tau_s 1]', ...
        'Position', [1150 1195 1220 1235]);
    add_block('simulink/Math Operations/Gain', [model_name '/PressurePI_Kp'], ...
        'Gain', 'pressure_pi_kp_MPa_per_kgps', 'Position', [1255 1195 1315 1230]);
    add_block('simulink/Math Operations/Gain', [model_name '/PressurePI_Ki'], ...
        'Gain', 'pressure_pi_ki_MPa_per_kgps_s', 'Position', [1255 1240 1315 1275]);
    add_block('simulink/Continuous/Integrator', [model_name '/PressurePI_Integrator'], ...
        'InitialCondition', '0', ...
        'UpperSaturationLimit', '0.005', ...
        'LowerSaturationLimit', '-0.005', ...
        'LimitOutput', 'on', ...
        'Position', [1325 1240 1365 1275]);
    add_block('simulink/Sources/Constant', [model_name '/PressurePI_Bias'], ...
        'Value', 'pressure_pi_bias_MPa', 'Position', [1255 1290 1315 1320]);
    add_block('simulink/Math Operations/Sum', [model_name '/PressurePI_BiasSum'], ...
        'Inputs', '+++', 'Position', [1380 1195 1415 1300]);
    add_block('simulink/Discontinuities/Saturation', [model_name '/PressurePI_Saturation'], ...
        'LowerLimit', 'pressure_pi_min_MPa', ...
        'UpperLimit', 'pressure_pi_max_MPa', ...
        'Position', [1460 1210 1525 1250]);
    add_block('nesl_utility/Simulink-PS Converter', [model_name '/PressurePI_SimulinkPS'], ...
        'Unit', 'MPa', 'Position', [1570 1212 1600 1248]);
    if getSimulinkBlockHandle(cold_source_path) > 0
        add_block('simulink/Sources/Constant', [model_name '/PressurePI_HotSourceGate'], ...
            'Value', 'double(abs(mdot_cooldown_source_kgps) > 0)', ...
            'Position', [1460 1160 1535 1190]);
        add_block('simulink/Sources/Constant', [model_name '/PressurePI_ColdSourceGate'], ...
            'Value', 'double(abs(mdot_hold_source_kgps) > 0)', ...
            'Position', [1460 1300 1535 1330]);
        add_block('simulink/Math Operations/Product', [model_name '/PressurePI_HotSourceProduct'], ...
            'Inputs', '**', 'Position', [1540 1190 1565 1230]);
        add_block('simulink/Math Operations/Product', [model_name '/PressurePI_ColdSourceProduct'], ...
            'Inputs', '**', 'Position', [1540 1280 1565 1320]);
        set_param([model_name '/PressurePI_SimulinkPS'], ...
            'Position', [1605 1200 1635 1236]);
        add_block('nesl_utility/Simulink-PS Converter', [model_name '/PressurePI_ColdSimulinkPS'], ...
            'Unit', 'MPa', 'Position', [1605 1288 1635 1324]);
    end

    add_line(model_name, get_port([model_name '/PressurePI_TargetHold'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_ErrorSum'], 'Inport', 1), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_TargetCooldown'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_ErrorSum'], 'Inport', 2), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/FlowSensor_V1_cold_inlet_PS'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_PassthruV1'], 'Inport', 1), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/FlowSensor_V4_hot_inlet_PS'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_PassthruV4'], 'Inport', 1), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_PassthruV1'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_ErrorSum'], 'Inport', 3), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_PassthruV4'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_ErrorSum'], 'Inport', 4), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_ErrorSum'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_ErrorNormalizer'], 'Inport', 1), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_ErrorNormalizer'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_ErrorLag'], 'Inport', 1), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_ErrorLag'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_Kp'], 'Inport', 1), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_ErrorLag'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_Ki'], 'Inport', 1), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_Kp'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_BiasSum'], 'Inport', 1), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_Ki'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_Integrator'], 'Inport', 1), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_Integrator'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_BiasSum'], 'Inport', 2), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_Bias'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_BiasSum'], 'Inport', 3), 'autorouting', 'on');
    add_line(model_name, get_port([model_name '/PressurePI_BiasSum'], 'Outport', 1), ...
        get_port([model_name '/PressurePI_Saturation'], 'Inport', 1), 'autorouting', 'on');
    if getSimulinkBlockHandle([model_name '/PressurePI_ColdSimulinkPS']) > 0
        add_line(model_name, get_port([model_name '/PressurePI_Saturation'], 'Outport', 1), ...
            get_port([model_name '/PressurePI_HotSourceProduct'], 'Inport', 1), 'autorouting', 'on');
        add_line(model_name, get_port([model_name '/PressurePI_HotSourceGate'], 'Outport', 1), ...
            get_port([model_name '/PressurePI_HotSourceProduct'], 'Inport', 2), 'autorouting', 'on');
        add_line(model_name, get_port([model_name '/PressurePI_HotSourceProduct'], 'Outport', 1), ...
            get_port([model_name '/PressurePI_SimulinkPS'], 'Inport', 1), 'autorouting', 'on');
        add_line(model_name, get_port([model_name '/PressurePI_Saturation'], 'Outport', 1), ...
            get_port([model_name '/PressurePI_ColdSourceProduct'], 'Inport', 1), 'autorouting', 'on');
        add_line(model_name, get_port([model_name '/PressurePI_ColdSourceGate'], 'Outport', 1), ...
            get_port([model_name '/PressurePI_ColdSourceProduct'], 'Inport', 2), 'autorouting', 'on');
        add_line(model_name, get_port([model_name '/PressurePI_ColdSourceProduct'], 'Outport', 1), ...
            get_port([model_name '/PressurePI_ColdSimulinkPS'], 'Inport', 1), 'autorouting', 'on');
    else
        add_line(model_name, get_port([model_name '/PressurePI_Saturation'], 'Outport', 1), ...
            get_port([model_name '/PressurePI_SimulinkPS'], 'Inport', 1), 'autorouting', 'on');
    end

    source_ports = get_param(source_path, 'PortHandles');
    converter_ports = get_param([model_name '/PressurePI_SimulinkPS'], 'PortHandles');
    add_line(model_name, converter_ports.RConn(1), source_ports.LConn(2), 'autorouting', 'on');
    if getSimulinkBlockHandle(cold_source_path) > 0
        cold_source_ports = get_param(cold_source_path, 'PortHandles');
        cold_converter_ports = get_param([model_name '/PressurePI_ColdSimulinkPS'], 'PortHandles');
        add_line(model_name, cold_converter_ports.RConn(1), cold_source_ports.LConn(2), 'autorouting', 'on');
    end
end

function delete_existing_pressure_pi_blocks(model_name)
    names = {'PressurePI_TargetHold', 'PressurePI_TargetCooldown', ...
        'PressurePI_AbsV1', 'PressurePI_AbsV4', ...
        'PressurePI_PassthruV1', 'PressurePI_PassthruV4', ...
        'PressurePI_ErrorSum', 'PressurePI_ErrorNormalizer', ...
        'PressurePI_ErrorLag', 'PressurePI_Kp', 'PressurePI_Ki', ...
        'PressurePI_Integrator', 'PressurePI_Bias', 'PressurePI_BiasSum', ...
        'PressurePI_Saturation', 'PressurePI_HotSourceGate', ...
        'PressurePI_ColdSourceGate', 'PressurePI_HotSourceProduct', ...
        'PressurePI_ColdSourceProduct', 'PressurePI_SimulinkPS', ...
        'PressurePI_ColdSimulinkPS'};
    for idx = 1:numel(names)
        delete_block_if_present_with_lines([model_name '/' names{idx}]);
    end
end

function conn = capture_root_connection(port_handle)
conn = struct('other_port_handle', -1);
line = get_param(port_handle, 'Line');
if line == -1
    return;
end
src = get_param(line, 'SrcPortHandle');
dst = get_param(line, 'DstPortHandle');
if port_handle == src
    conn.other_port_handle = dst;
else
    conn.other_port_handle = src;
end
end

function delete_root_line(port_handles)
for idx = 1:numel(port_handles)
    line = get_param(port_handles(idx), 'Line');
    if line ~= -1
        delete_line(line);
    end
end
end

function restore_root_connection(source_path, port_kind, conn)
if conn.other_port_handle == -1
    return;
end
ports = get_param(source_path, 'PortHandles');
add_line(bdroot(source_path), ports.(port_kind), conn.other_port_handle, 'autorouting', 'on');
end

function configure_root_valve_startup_source(model_name)
% Replace the root valve command constant with a time-series input.
% The time series is built in Build_Simulink_Exchange_Params as L_valve_command.
    source_path = [model_name '/ValveCommandFromWorkspace'];
    source_exists = ~isempty(find_system(model_name, ...
        'SearchDepth', 1, ...
        'Name', 'ValveCommandFromWorkspace'));

    dst_handles = [];
    constant_blocks = find_system(model_name, ...
        'SearchDepth', 1, ...
        'BlockType', 'Constant', ...
        'Value', 'L_valve');
    for idx = 1:numel(constant_blocks)
        line_handles = get_param(constant_blocks{idx}, 'LineHandles');
        out_line = line_handles.Outport;
        if out_line ~= -1
            try
                dst_handles = [dst_handles, get_param(out_line, 'DstPortHandle')]; %#ok<AGROW>
                delete_line(out_line);
            catch
            end
        end
        delete_block(constant_blocks{idx});
    end

    if ~source_exists
        add_block('simulink/Sources/From Workspace', source_path, ...
            'Position', [715 934 790 976], ...
            'VariableName', 'L_valve_command');
    else
        set_param(source_path, 'VariableName', 'L_valve_command');
    end

    source_handles = get_param(source_path, 'PortHandles');
    if isempty(dst_handles)
        demux_blocks = find_system(model_name, 'SearchDepth', 1, 'BlockType', 'Demux');
        if isempty(demux_blocks)
            error('Build_Simulink_Exchange_Model:MissingValveDemux', ...
                'Could not locate the root valve command Demux.');
        end
        demux_handles = get_param(demux_blocks{1}, 'PortHandles');
        dst_handles = demux_handles.Inport(1);
    end

    out_line = get_param(source_path, 'LineHandles');
    if out_line.Outport == -1
        add_line(model_name, source_handles.Outport(1), dst_handles(1), 'autorouting', 'on');
    end
end

function replace_reservoir_with_tank_buffer(reservoir_path, buffer_name, init_temp_expr)
    if isempty(reservoir_path) || ~bdIsLoaded(bdroot(reservoir_path))
        error('Build_Simulink_Exchange_Model:MissingReservoirPath', ...
            'Reservoir path is invalid for %s.', buffer_name);
    end

    parent_path = get_param(reservoir_path, 'Parent');
    pos = get_param(reservoir_path, 'Position');
    rotation = get_param(reservoir_path, 'BlockRotation');
    mirror = get_param(reservoir_path, 'BlockMirror');
    remote_port_handle = capture_remote_physical_port(reservoir_path);

    delete_attached_lines(reservoir_path);
    delete_block(reservoir_path);

    tank_path = [parent_path '/' buffer_name];

    add_block('SimscapeFluids_lib/Thermal Liquid/Tanks & Accumulators/Tank (TL)', tank_path, ...
        'Position', pos, ...
        'BlockRotation', rotation, ...
        'BlockMirror', mirror, ...
        'tank_area', 'fluid_buffer_tank_area_m2', ...
        'inlet_height_A', '0', ...
        'max_capacity', 'fluid_buffer_max_capacity_m3', ...
        'level_specify', 'on', ...
        'level', 'fluid_buffer_tank_level_m', ...
        'T_I_specify', 'on', ...
        'T_I', init_temp_expr);

    connect_physical_ports(parent_path, remote_port_handle, get_port(tank_path, 'LConn', 1));
end

function [hot_subsystem_path, cold_subsystem_path] = locate_exchange_subsystems(model_name)
    hot_subsystem_path = find_block_by_sid(model_name, '927');
    cold_subsystem_path = find_block_by_sid(model_name, '970');

    if isempty(hot_subsystem_path) || isempty(cold_subsystem_path)
        error('Build_Simulink_Exchange_Model:MissingExchangeSubsystems', ...
            'Unable to locate hot/cold exchanger subsystems in %s.', model_name);
    end
end

function rebuild_hot_end_subsystem(subsystem_path)
    delete_contents_except_ports(subsystem_path);

    pipe_path = [subsystem_path '/HotPipe'];
    mass_path = [subsystem_path '/HotSinkMass'];
    sensor_path = [subsystem_path '/HotSinkTempSensor'];
    ps_path = [subsystem_path '/HotSinkTempPS'];
    thermal_ref_path = [subsystem_path '/HotSinkTempRef'];
    ambient_source_path = [subsystem_path '/AmbientTempSource'];
    ambient_link_path = [subsystem_path '/HotSinkAmbientLink'];
    fluid_link_path = [subsystem_path '/HotSinkFluidLink'];
    toworkspace_hot_path = [subsystem_path '/ToWorkspace_hot_sink_temp_out'];
    toworkspace_alias_path = [subsystem_path '/ToWorkspace_hot_source_out'];

    add_pipe_block(pipe_path, [470 104 570 171], 'hot_side_fluid_T_init');
    add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass', mass_path, ...
        'Position', [680 76 720 104], ...
        'mass', 'hot_sink_mass_kg', ...
        'sp_heat', 'thermal_mass_cp_ref', ...
        'T_specify', 'on', ...
        'T', 'hot_sink_T_init');
    add_block('fl_lib/Thermal/Thermal Sensors/Temperature Sensor', sensor_path, ...
        'Position', [760 68 808 108]);
    add_block('nesl_utility/PS-Simulink Converter', ps_path, ...
        'Position', [845 74 875 96], ...
        'VectorFormat', '1-D array', ...
        'Unit', 'K');
    add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', thermal_ref_path, ...
        'Position', [815 130 855 165]);
    add_block('fl_lib/Thermal/Thermal Sources/Temperature Source', ambient_source_path, ...
        'Position', [680 150 720 180], ...
        'temperature', 'ambient_T_init');
    add_block('fl_lib/Thermal/Thermal Elements/Conductive Heat Transfer', ambient_link_path, ...
        'Position', [620 125 660 185], ...
        'area', '1', ...
        'thickness', '1', ...
        'th_cond', 'hot_sink_ambient_G_W_per_K');
    add_block('fl_lib/Thermal/Thermal Elements/Conductive Heat Transfer', fluid_link_path, ...
        'Position', [610 70 650 110], ...
        'area', '1', ...
        'thickness', '1', ...
        'th_cond', 'hot_sink_fluid_G_W_per_K');
    add_block('simulink/Sinks/To Workspace', toworkspace_hot_path, ...
        'VariableName', 'hot_sink_temp_out', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [910 60 1045 85]);
    add_block('simulink/Sinks/To Workspace', toworkspace_alias_path, ...
        'VariableName', 'hot_source_out', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [910 100 1045 125]);

    add_line(subsystem_path, get_port(pipe_path, 'RConn', 1), get_port([subsystem_path '/Conn1'], 'RConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(pipe_path, 'LConn', 1), get_port([subsystem_path '/Conn2'], 'RConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(mass_path, 'LConn', 1), get_port(fluid_link_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(fluid_link_path, 'RConn', 1), get_port(pipe_path, 'LConn', 2), 'autorouting', 'on');
    add_line(subsystem_path, get_port(mass_path, 'LConn', 1), get_port(sensor_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(sensor_path, 'RConn', 1), get_port(thermal_ref_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(sensor_path, 'RConn', 2), get_port(ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(ps_path, 'Outport', 1), get_port(toworkspace_hot_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(ps_path, 'Outport', 1), get_port(toworkspace_alias_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(mass_path, 'LConn', 1), get_port(ambient_link_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(ambient_link_path, 'RConn', 1), get_port(ambient_source_path, 'LConn', 1), 'autorouting', 'on');

    [~, hot_hx_port1_ps_path] = add_fluid_temp_probe(subsystem_path, 'HotHXInletFluidTemp', ...
        get_port([subsystem_path '/Conn1'], 'RConn', 1), ...
        'hot_hx_inlet_fluid_temp_out', ...
        [510 18 560 58], [595 24 625 46], [655 18 810 43]);
    [~, hot_hx_port2_ps_path] = add_fluid_temp_probe(subsystem_path, 'HotHXOutletFluidTemp', ...
        get_port([subsystem_path '/Conn2'], 'RConn', 1), ...
        'hot_hx_outlet_fluid_temp_out', ...
        [510 208 560 248], [595 214 625 236], [655 208 820 233]);
    add_workspace_alias(subsystem_path, hot_hx_port1_ps_path, ...
        'ToWorkspace_probe_hot_hx_port1_v3_side_T_K', 'probe_hot_hx_port1_v3_side_T_K', ...
        [655 48 885 73]);
    add_workspace_alias(subsystem_path, hot_hx_port2_ps_path, ...
        'ToWorkspace_probe_hot_hx_port2_v2_return_side_T_K', 'probe_hot_hx_port2_v2_return_side_T_K', ...
        [655 238 910 263]);

    layout_hot_end_subsystem_visuals(subsystem_path);
end

function rebuild_cold_end_subsystem(subsystem_path, cold_end_topology_mode)
    if nargin < 2 || isempty(cold_end_topology_mode)
        cold_end_topology_mode = 'r69_symmetric';
    end
    cold_end_topology_mode = normalize_cold_end_topology_mode(cold_end_topology_mode);
    if strcmp(cold_end_topology_mode, 'r69_symmetric')
        rebuild_cold_end_subsystem_r69_symmetric(subsystem_path);
        return;
    end

    delete_contents_except_ports(subsystem_path);

    cold_hx_pipe_path = [subsystem_path '/ColdSinkHXPipe'];
    cold_return_pipe_path = [subsystem_path '/ColdSinkReturnPipe'];
    transit_pipe_path = [subsystem_path '/TransitPipe_V6_to_CHEX'];
    cold_load_mass_path = [subsystem_path '/ColdLoadMass'];
    cold_load_sensor_path = [subsystem_path '/ColdLoadTempSensor'];
    cold_load_ps_path = [subsystem_path '/ColdLoadTempPS'];
    cold_load_heat_source_path = [subsystem_path '/ColdLoadHeatSource'];
    cold_load_heat_conv_path = [subsystem_path '/ColdLoadHeatPS'];
    cold_load_heat_const_path = [subsystem_path '/ColdLoadHeatConstant'];
    cold_load_ref_path = [subsystem_path '/ColdLoadHeatRef'];
    cold_load_ambient_source_path = [subsystem_path '/ColdLoadAmbientTempSource'];
    cold_load_ambient_link_path = [subsystem_path '/ColdLoadAmbientLink'];
    cold_load_to_sink_link_path = [subsystem_path '/ColdLoadToColdSinkLink'];
    cold_mass_path = [subsystem_path '/ColdSinkMass'];
    cold_sensor_path = [subsystem_path '/ColdSinkTempSensor'];
    cold_ps_path = [subsystem_path '/ColdSinkTempPS'];
    cold_ref_path = [subsystem_path '/ColdSinkTempRef'];
    cold_ambient_source_path = [subsystem_path '/ColdAmbientTempSource'];
    cold_ambient_link_path = [subsystem_path '/ColdSinkAmbientLink'];
    cold_fluid_link_path = [subsystem_path '/ColdSinkFluidLink'];
    cold_mass_to_pipe_heat_sensor_path = [subsystem_path '/ColdSinkMassToPipeHeatFlowSensor'];
    cold_mass_to_pipe_heat_ps_path = [subsystem_path '/ColdSinkMassToPipeHeatFlowPS'];
    cold_mass_to_pipe_heat_out_path = [subsystem_path '/ToWorkspace_Qdot_cold_sink_mass_to_pipe_W'];
    cold_pipe_thermal_port_sensor_path = [subsystem_path '/ColdSinkHXPipeThermalPortTempSensor'];
    cold_pipe_thermal_port_ps_path = [subsystem_path '/ColdSinkHXPipeThermalPortTempPS'];
    cold_pipe_thermal_port_out_path = [subsystem_path '/ToWorkspace_cold_sink_hx_pipe_thermal_port_temp_out'];
    cold_load_temp_out_path = [subsystem_path '/ToWorkspace_cold_load_temp_out'];
    cold_temp_out_path = [subsystem_path '/ToWorkspace_cold_sink_temp_out'];

    add_pipe_block(cold_hx_pipe_path, [560 104 660 171], 'cold_hx_pipe_T_init', ...
        'cold_hx_pipe_length_m', '0');
    add_pipe_block(cold_return_pipe_path, [420 104 520 171], 'cold_return_pipe_T_init', ...
        'cold_return_pipe_length_m', '0');
    % TransitPipe captures the V6 valve + connection-line fluid volume between
    % the SMA cooldown outlet and the CHEX inlet. Wall is adiabatic (no thermal
    % port), so its internal energy state is preserved across idle stages.
    add_pipe_block(transit_pipe_path, [695 104 795 171], 'transit_pipe_T_init', ...
        'transit_pipe_length_m', '0');

    add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass', cold_load_mass_path, ...
        'Position', [960 62 1000 90], ...
        'mass', 'cold_load_mass_kg', ...
        'sp_heat', 'thermal_mass_cp_ref', ...
        'T_specify', 'on', ...
        'T', 'cold_load_T_init');
    add_block('fl_lib/Thermal/Thermal Sensors/Temperature Sensor', cold_load_sensor_path, ...
        'Position', [1035 56 1083 96]);
    add_block('nesl_utility/PS-Simulink Converter', cold_load_ps_path, ...
        'Position', [1118 62 1148 84], ...
        'VectorFormat', '1-D array', ...
        'Unit', 'K');
    add_block('simulink/Sinks/To Workspace', cold_load_temp_out_path, ...
        'VariableName', 'cold_load_temp_out', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [1180 48 1315 73]);
    add_block('simulink/Sources/Constant', cold_load_heat_const_path, ...
        'Value', 'cold_load_heat_W', ...
        'Position', [960 155 995 175]);
    add_block('nesl_utility/Simulink-PS Converter', cold_load_heat_conv_path, ...
        'Position', [1010 150 1080 180], ...
        'Unit', 'W');
    add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source', cold_load_heat_source_path, ...
        'Position', [1105 134 1155 186]);
    add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', cold_load_ref_path, ...
        'Position', [1180 145 1220 180]);
    add_block('fl_lib/Thermal/Thermal Sources/Temperature Source', cold_load_ambient_source_path, ...
        'Position', [960 110 1000 138], ...
        'temperature', 'ambient_T_init');
    add_block('fl_lib/Thermal/Thermal Elements/Conductive Heat Transfer', cold_load_ambient_link_path, ...
        'Position', [900 92 940 152], ...
        'area', '1', ...
        'thickness', '1', ...
        'th_cond', 'cold_load_ambient_G_W_per_K');
    add_block('fl_lib/Thermal/Thermal Elements/Conductive Heat Transfer', cold_load_to_sink_link_path, ...
        'Position', [900 44 940 84], ...
        'area', '1', ...
        'thickness', '1', ...
        'th_cond', 'cold_load_to_cold_sink_G_W_per_K');

    add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass', cold_mass_path, ...
        'Position', [725 240 765 268], ...
        'mass', 'cold_sink_mass_kg', ...
        'sp_heat', 'thermal_mass_cp_ref', ...
        'T_specify', 'on', ...
        'T', 'cold_sink_T_init');
    add_block('fl_lib/Thermal/Thermal Sensors/Temperature Sensor', cold_sensor_path, ...
        'Position', [800 234 848 274]);
    add_block('nesl_utility/PS-Simulink Converter', cold_ps_path, ...
        'Position', [883 240 913 262], ...
        'VectorFormat', '1-D array', ...
        'Unit', 'K');
    add_block('simulink/Sinks/To Workspace', cold_temp_out_path, ...
        'VariableName', 'cold_sink_temp_out', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [945 226 1090 251]);
    add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', cold_ref_path, ...
        'Position', [865 300 905 335]);
    add_block('fl_lib/Thermal/Thermal Sources/Temperature Source', cold_ambient_source_path, ...
        'Position', [725 288 765 316], ...
        'temperature', 'ambient_T_init');
    add_block('fl_lib/Thermal/Thermal Elements/Conductive Heat Transfer', cold_ambient_link_path, ...
        'Position', [665 270 705 330], ...
        'area', '1', ...
        'thickness', '1', ...
        'th_cond', 'cold_sink_ambient_G_W_per_K');
    add_block('fl_lib/Thermal/Thermal Elements/Conductive Heat Transfer', cold_fluid_link_path, ...
        'Position', [665 222 705 262], ...
        'area', '1', ...
        'thickness', '1', ...
        'th_cond', 'cold_sink_fluid_G_W_per_K');
    add_block(sprintf('fl_lib/Thermal/Thermal Sensors/Heat Flow Rate\nSensor'), ...
        cold_mass_to_pipe_heat_sensor_path, ...
        'Position', [612 212 652 272]);
    add_block('nesl_utility/PS-Simulink Converter', cold_mass_to_pipe_heat_ps_path, ...
        'Position', [725 196 755 218], ...
        'VectorFormat', '1-D array', ...
        'Unit', 'W');
    add_block('simulink/Sinks/To Workspace', cold_mass_to_pipe_heat_out_path, ...
        'VariableName', 'Qdot_cold_sink_mass_to_pipe_W', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [785 190 1045 215]);
    add_workspace_alias(subsystem_path, cold_mass_to_pipe_heat_ps_path, ...
        'ToWorkspace_Qdot_cold_sink_mass_to_hx_pipe_W', 'Qdot_cold_sink_mass_to_hx_pipe_W', ...
        [785 220 1065 245]);
    add_block('fl_lib/Thermal/Thermal Sensors/Temperature Sensor', cold_pipe_thermal_port_sensor_path, ...
        'Position', [612 166 660 206]);
    add_block('nesl_utility/PS-Simulink Converter', cold_pipe_thermal_port_ps_path, ...
        'Position', [725 156 755 178], ...
        'VectorFormat', '1-D array', ...
        'Unit', 'K');
    add_block('simulink/Sinks/To Workspace', cold_pipe_thermal_port_out_path, ...
        'VariableName', 'cold_sink_hx_pipe_thermal_port_temp_out', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [785 150 1065 175]);

    % Stage 4 flow direction inside cold_subsystem:
    %   Conn2 (V6/SMA side) -> TransitPipe -> ColdSinkHXPipe -> ColdSinkReturnPipe -> Conn1.
    % Only ColdSinkHXPipe is thermally coupled to ColdSinkMass. ColdSinkReturnPipe
    % preserves hydraulic/storage carryover but must not exchange heat directly
    % with the 1 ml cold sink mass.
    add_line(subsystem_path, get_port(transit_pipe_path, 'RConn', 1), get_port([subsystem_path '/Conn2'], 'RConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(transit_pipe_path, 'LConn', 1), get_port(cold_hx_pipe_path, 'RConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_hx_pipe_path, 'LConn', 1), get_port(cold_return_pipe_path, 'RConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_return_pipe_path, 'LConn', 1), get_port([subsystem_path '/Conn1'], 'RConn', 1), 'autorouting', 'on');

    add_line(subsystem_path, get_port(cold_load_mass_path, 'LConn', 1), get_port(cold_load_to_sink_link_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_to_sink_link_path, 'RConn', 1), get_port(cold_mass_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_mass_path, 'LConn', 1), get_port(cold_load_sensor_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_sensor_path, 'RConn', 1), get_port(cold_load_ref_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_sensor_path, 'RConn', 2), get_port(cold_load_ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_ps_path, 'Outport', 1), get_port(cold_load_temp_out_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_heat_const_path, 'Outport', 1), get_port(cold_load_heat_conv_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_heat_conv_path, 'RConn', 1), get_port(cold_load_heat_source_path, 'RConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_mass_path, 'LConn', 1), get_port(cold_load_heat_source_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_heat_source_path, 'RConn', 2), get_port(cold_load_ref_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_mass_path, 'LConn', 1), get_port(cold_load_ambient_link_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_ambient_link_path, 'RConn', 1), get_port(cold_load_ambient_source_path, 'LConn', 1), 'autorouting', 'on');

    add_line(subsystem_path, get_port(cold_mass_path, 'LConn', 1), get_port(cold_mass_to_pipe_heat_sensor_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_mass_to_pipe_heat_sensor_path, 'RConn', 2), get_port(cold_fluid_link_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_mass_to_pipe_heat_sensor_path, 'RConn', 1), get_port(cold_mass_to_pipe_heat_ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_mass_to_pipe_heat_ps_path, 'Outport', 1), get_port(cold_mass_to_pipe_heat_out_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_fluid_link_path, 'RConn', 1), get_port(cold_hx_pipe_path, 'LConn', 2), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_hx_pipe_path, 'LConn', 2), get_port(cold_pipe_thermal_port_sensor_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_pipe_thermal_port_sensor_path, 'RConn', 1), get_port(cold_ref_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_pipe_thermal_port_sensor_path, 'RConn', 2), get_port(cold_pipe_thermal_port_ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_pipe_thermal_port_ps_path, 'Outport', 1), get_port(cold_pipe_thermal_port_out_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_mass_path, 'LConn', 1), get_port(cold_sensor_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_sensor_path, 'RConn', 1), get_port(cold_ref_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_sensor_path, 'RConn', 2), get_port(cold_ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_ps_path, 'Outport', 1), get_port(cold_temp_out_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_mass_path, 'LConn', 1), get_port(cold_ambient_link_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_ambient_link_path, 'RConn', 1), get_port(cold_ambient_source_path, 'LConn', 1), 'autorouting', 'on');

    [~, transit_inlet_ps_path] = add_fluid_temp_probe(subsystem_path, 'TransitPipeInletFluidTemp', ...
        get_port([subsystem_path '/Conn2'], 'RConn', 1), ...
        'transit_pipe_inlet_fluid_temp_out', ...
        [500 18 550 58], [585 24 615 46], [645 18 820 43]);
    [~, cold_hx_inlet_ps_path] = add_fluid_temp_probe(subsystem_path, 'ColdHXInletFluidTemp', ...
        get_port(cold_hx_pipe_path, 'RConn', 1), ...
        'cold_hx_inlet_fluid_temp_out', ...
        [505 178 555 218], [590 184 620 206], [650 178 825 203]);
    [~, cold_hx_outlet_ps_path] = add_fluid_temp_probe(subsystem_path, 'ColdHXOutletFluidTemp', ...
        get_port(cold_hx_pipe_path, 'LConn', 1), ...
        'cold_hx_outlet_fluid_temp_out', ...
        [505 252 555 292], [590 258 620 280], [650 252 825 277]);
    add_workspace_alias(subsystem_path, cold_hx_outlet_ps_path, ...
        'ToWorkspace_cold_return_inlet_fluid_temp_out', 'cold_return_inlet_fluid_temp_out', ...
        [650 278 845 303]);
    [~, cold_return_outlet_ps_path] = add_fluid_temp_probe(subsystem_path, 'ColdReturnOutletFluidTemp', ...
        get_port([subsystem_path '/Conn1'], 'RConn', 1), ...
        'cold_return_outlet_fluid_temp_out', ...
        [500 342 550 382], [585 348 615 370], [645 342 835 367]);
    add_workspace_alias(subsystem_path, cold_hx_inlet_ps_path, ...
        'ToWorkspace_transit_to_chex_fluid_temp_out', 'transit_to_chex_fluid_temp_out', ...
        [650 208 1000 233]);
    add_workspace_alias(subsystem_path, cold_hx_inlet_ps_path, ...
        'ToWorkspace_probe_transit_pipe_outlet_T_K', 'probe_transit_pipe_outlet_T_K', ...
        [650 232 1000 257]);
    add_workspace_alias(subsystem_path, transit_inlet_ps_path, ...
        'ToWorkspace_probe_transit_pipe_inlet_T_K', 'probe_transit_pipe_inlet_T_K', ...
        [645 118 970 143]);

    add_workspace_alias(subsystem_path, cold_load_ps_path, ...
        'ToWorkspace_chip_temp_out', 'chip_temp_out', ...
        [1180 78 1315 103]);
    add_workspace_alias(subsystem_path, transit_inlet_ps_path, ...
        'ToWorkspace_probe_chip_pipe_port_conn2_v6_sma_side_T_K', 'probe_chip_pipe_port_conn2_v6_sma_side_T_K', ...
        [645 88 940 113]);
    add_workspace_alias(subsystem_path, cold_hx_outlet_ps_path, ...
        'ToWorkspace_probe_chip_to_cold_junction_T_K', 'probe_chip_to_cold_junction_T_K', ...
        [835 88 1085 113]);
    add_workspace_alias(subsystem_path, cold_return_outlet_ps_path, ...
        'ToWorkspace_probe_cold_hx_port_conn1_v5_return_side_T_K', 'probe_cold_hx_port_conn1_v5_return_side_T_K', ...
        [645 372 970 397]);
    add_workspace_alias(subsystem_path, transit_inlet_ps_path, ...
        'ToWorkspace_chip_inlet_fluid_temp_out', 'chip_inlet_fluid_temp_out', ...
        [835 58 995 83]);
    add_workspace_alias(subsystem_path, cold_hx_outlet_ps_path, ...
        'ToWorkspace_chip_outlet_fluid_temp_out', 'chip_outlet_fluid_temp_out', ...
        [835 118 995 143]);
    add_workspace_alias(subsystem_path, transit_inlet_ps_path, ...
        'ToWorkspace_cold_subsystem_inlet_fluid_temp_out', 'cold_subsystem_inlet_fluid_temp_out', ...
        [645 58 835 83]);
    add_workspace_alias(subsystem_path, cold_return_outlet_ps_path, ...
        'ToWorkspace_cold_subsystem_outlet_fluid_temp_out', 'cold_subsystem_outlet_fluid_temp_out', ...
        [645 402 850 427]);
end

function rebuild_cold_end_subsystem_r69_symmetric(subsystem_path)
    delete_contents_except_ports(subsystem_path);

    cold_pipe_path = [subsystem_path '/ColdSinkPipe'];
    cold_load_mass_path = [subsystem_path '/ColdLoadMass'];
    cold_load_sensor_path = [subsystem_path '/ColdLoadTempSensor'];
    cold_load_ps_path = [subsystem_path '/ColdLoadTempPS'];
    cold_load_heat_source_path = [subsystem_path '/ColdLoadHeatSource'];
    cold_load_heat_conv_path = [subsystem_path '/ColdLoadHeatPS'];
    cold_load_heat_const_path = [subsystem_path '/ColdLoadHeatConstant'];
    cold_load_ref_path = [subsystem_path '/ColdLoadHeatRef'];
    cold_load_to_sink_link_path = [subsystem_path '/ColdLoadToColdSinkLink'];
    cold_mass_path = [subsystem_path '/ColdSinkMass'];
    cold_sensor_path = [subsystem_path '/ColdSinkTempSensor'];
    cold_ps_path = [subsystem_path '/ColdSinkTempPS'];
    cold_ref_path = [subsystem_path '/ColdSinkTempRef'];
    cold_fluid_link_path = [subsystem_path '/ColdSinkFluidLink'];
    cold_mass_to_pipe_heat_sensor_path = [subsystem_path '/ColdSinkMassToPipeHeatFlowSensor'];
    cold_mass_to_pipe_heat_ps_path = [subsystem_path '/ColdSinkMassToPipeHeatFlowPS'];
    cold_mass_to_pipe_heat_out_path = [subsystem_path '/ToWorkspace_Qdot_cold_sink_mass_to_pipe_W'];
    cold_pipe_thermal_port_sensor_path = [subsystem_path '/ColdSinkPipeThermalPortTempSensor'];
    cold_pipe_thermal_port_ps_path = [subsystem_path '/ColdSinkPipeThermalPortTempPS'];
    cold_pipe_thermal_port_out_path = [subsystem_path '/ToWorkspace_cold_sink_pipe_thermal_port_temp_out'];
    cold_load_temp_out_path = [subsystem_path '/ToWorkspace_cold_load_temp_out'];
    cold_temp_out_path = [subsystem_path '/ToWorkspace_cold_sink_temp_out'];

    add_pipe_block(cold_pipe_path, [470 104 570 171], 'cold_side_fluid_T_init', ...
        'cold_pipe_or_CHEX_length_m', '0');

    add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass', cold_load_mass_path, ...
        'Position', [860 42 900 70], ...
        'mass', 'cold_load_mass_kg', ...
        'sp_heat', 'thermal_mass_cp_ref', ...
        'T_specify', 'on', ...
        'T', 'cold_load_T_init');
    add_block('fl_lib/Thermal/Thermal Sensors/Temperature Sensor', cold_load_sensor_path, ...
        'Position', [940 36 988 76]);
    add_block('nesl_utility/PS-Simulink Converter', cold_load_ps_path, ...
        'Position', [1024 42 1054 64], ...
        'VectorFormat', '1-D array', ...
        'Unit', 'K');
    add_block('simulink/Sinks/To Workspace', cold_load_temp_out_path, ...
        'VariableName', 'cold_load_temp_out', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [1085 28 1220 53]);
    add_block('simulink/Sources/Constant', cold_load_heat_const_path, ...
        'Value', 'cold_load_heat_W', ...
        'Position', [860 130 895 150]);
    add_block('nesl_utility/Simulink-PS Converter', cold_load_heat_conv_path, ...
        'Position', [910 125 980 155], ...
        'Unit', 'W');
    add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source', cold_load_heat_source_path, ...
        'Position', [1010 109 1060 161]);
    add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', cold_load_ref_path, ...
        'Position', [1085 120 1125 155]);
    add_block('fl_lib/Thermal/Thermal Elements/Conductive Heat Transfer', cold_load_to_sink_link_path, ...
        'Position', [800 48 840 88], ...
        'area', '1', ...
        'thickness', '1', ...
        'th_cond', 'cold_load_to_cold_sink_G_W_per_K');

    add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass', cold_mass_path, ...
        'Position', [680 76 720 104], ...
        'mass', 'cold_sink_mass_kg', ...
        'sp_heat', 'thermal_mass_cp_ref', ...
        'T_specify', 'on', ...
        'T', 'cold_sink_T_init');
    add_block('fl_lib/Thermal/Thermal Sensors/Temperature Sensor', cold_sensor_path, ...
        'Position', [760 68 808 108]);
    add_block('nesl_utility/PS-Simulink Converter', cold_ps_path, ...
        'Position', [845 74 875 96], ...
        'VectorFormat', '1-D array', ...
        'Unit', 'K');
    add_block('simulink/Sinks/To Workspace', cold_temp_out_path, ...
        'VariableName', 'cold_sink_temp_out', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [910 60 1045 85]);
    add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', cold_ref_path, ...
        'Position', [815 130 855 165]);
    add_block('fl_lib/Thermal/Thermal Elements/Conductive Heat Transfer', cold_fluid_link_path, ...
        'Position', [610 70 650 110], ...
        'area', '1', ...
        'thickness', '1', ...
        'th_cond', 'cold_sink_fluid_G_W_per_K');
    add_block(sprintf('fl_lib/Thermal/Thermal Sensors/Heat Flow Rate\nSensor'), ...
        cold_mass_to_pipe_heat_sensor_path, ...
        'Position', [560 60 600 120]);
    add_block('nesl_utility/PS-Simulink Converter', cold_mass_to_pipe_heat_ps_path, ...
        'Position', [680 26 710 48], ...
        'VectorFormat', '1-D array', ...
        'Unit', 'W');
    add_block('simulink/Sinks/To Workspace', cold_mass_to_pipe_heat_out_path, ...
        'VariableName', 'Qdot_cold_sink_mass_to_pipe_W', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [735 20 995 45]);
    add_workspace_alias(subsystem_path, cold_mass_to_pipe_heat_ps_path, ...
        'ToWorkspace_Qdot_cold_sink_mass_to_hx_pipe_W', 'Qdot_cold_sink_mass_to_hx_pipe_W', ...
        [735 48 1015 73]);
    add_block('fl_lib/Thermal/Thermal Sensors/Temperature Sensor', cold_pipe_thermal_port_sensor_path, ...
        'Position', [560 160 608 200]);
    add_block('nesl_utility/PS-Simulink Converter', cold_pipe_thermal_port_ps_path, ...
        'Position', [680 166 710 188], ...
        'VectorFormat', '1-D array', ...
        'Unit', 'K');
    add_block('simulink/Sinks/To Workspace', cold_pipe_thermal_port_out_path, ...
        'VariableName', 'cold_sink_pipe_thermal_port_temp_out', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [735 160 1015 185]);
    add_workspace_alias(subsystem_path, cold_pipe_thermal_port_ps_path, ...
        'ToWorkspace_cold_sink_hx_pipe_thermal_port_temp_out', 'cold_sink_hx_pipe_thermal_port_temp_out', ...
        [735 190 1015 215]);

    % Stage 4 flow direction mirrors the hot end with reversed side labels:
    % Conn2 (V6/SMA side) -> ColdSinkPipe -> Conn1 (cold return side).
    connect_physical_ports(subsystem_path, get_port(cold_pipe_path, 'RConn', 1), get_port([subsystem_path '/Conn2'], 'RConn', 1));
    connect_physical_ports(subsystem_path, get_port(cold_pipe_path, 'LConn', 1), get_port([subsystem_path '/Conn1'], 'RConn', 1));

    add_line(subsystem_path, get_port(cold_load_mass_path, 'LConn', 1), get_port(cold_load_to_sink_link_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_to_sink_link_path, 'RConn', 1), get_port(cold_mass_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_mass_path, 'LConn', 1), get_port(cold_load_sensor_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_sensor_path, 'RConn', 1), get_port(cold_load_ref_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_sensor_path, 'RConn', 2), get_port(cold_load_ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_ps_path, 'Outport', 1), get_port(cold_load_temp_out_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_heat_const_path, 'Outport', 1), get_port(cold_load_heat_conv_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_heat_conv_path, 'RConn', 1), get_port(cold_load_heat_source_path, 'RConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_mass_path, 'LConn', 1), get_port(cold_load_heat_source_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_load_heat_source_path, 'RConn', 2), get_port(cold_load_ref_path, 'LConn', 1), 'autorouting', 'on');

    add_line(subsystem_path, get_port(cold_mass_path, 'LConn', 1), get_port(cold_mass_to_pipe_heat_sensor_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_mass_to_pipe_heat_sensor_path, 'RConn', 2), get_port(cold_fluid_link_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_mass_to_pipe_heat_sensor_path, 'RConn', 1), get_port(cold_mass_to_pipe_heat_ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_mass_to_pipe_heat_ps_path, 'Outport', 1), get_port(cold_mass_to_pipe_heat_out_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_fluid_link_path, 'RConn', 1), get_port(cold_pipe_path, 'LConn', 2), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_pipe_path, 'LConn', 2), get_port(cold_pipe_thermal_port_sensor_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_pipe_thermal_port_sensor_path, 'RConn', 1), get_port(cold_ref_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_pipe_thermal_port_sensor_path, 'RConn', 2), get_port(cold_pipe_thermal_port_ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_pipe_thermal_port_ps_path, 'Outport', 1), get_port(cold_pipe_thermal_port_out_path, 'Inport', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_mass_path, 'LConn', 1), get_port(cold_sensor_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_sensor_path, 'RConn', 1), get_port(cold_ref_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_sensor_path, 'RConn', 2), get_port(cold_ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(subsystem_path, get_port(cold_ps_path, 'Outport', 1), get_port(cold_temp_out_path, 'Inport', 1), 'autorouting', 'on');

    [~, cold_hx_inlet_ps_path] = add_fluid_temp_probe(subsystem_path, 'ColdHXInletFluidTemp', ...
        get_port([subsystem_path '/Conn2'], 'RConn', 1), ...
        'cold_hx_inlet_fluid_temp_out', ...
        [510 18 560 58], [595 24 625 46], [655 18 840 43]);
    [~, cold_hx_outlet_ps_path] = add_fluid_temp_probe(subsystem_path, 'ColdHXOutletFluidTemp', ...
        get_port([subsystem_path '/Conn1'], 'RConn', 1), ...
        'cold_hx_outlet_fluid_temp_out', ...
        [510 208 560 248], [595 214 625 236], [655 208 850 233]);
    add_workspace_alias(subsystem_path, cold_hx_inlet_ps_path, ...
        'ToWorkspace_probe_chip_pipe_port_conn2_v6_sma_side_T_K', 'probe_chip_pipe_port_conn2_v6_sma_side_T_K', ...
        [655 48 955 73]);
    add_workspace_alias(subsystem_path, cold_hx_outlet_ps_path, ...
        'ToWorkspace_probe_chip_to_cold_junction_T_K', 'probe_chip_to_cold_junction_T_K', ...
        [655 238 925 263]);
    add_workspace_alias(subsystem_path, cold_hx_outlet_ps_path, ...
        'ToWorkspace_probe_cold_hx_port_conn1_v5_return_side_T_K', 'probe_cold_hx_port_conn1_v5_return_side_T_K', ...
        [655 268 985 293]);
    add_workspace_alias(subsystem_path, cold_hx_inlet_ps_path, ...
        'ToWorkspace_chip_inlet_fluid_temp_out', 'chip_inlet_fluid_temp_out', ...
        [860 18 1040 43]);
    add_workspace_alias(subsystem_path, cold_hx_outlet_ps_path, ...
        'ToWorkspace_chip_outlet_fluid_temp_out', 'chip_outlet_fluid_temp_out', ...
        [860 208 1045 233]);
    add_workspace_alias(subsystem_path, cold_hx_inlet_ps_path, ...
        'ToWorkspace_cold_subsystem_inlet_fluid_temp_out', 'cold_subsystem_inlet_fluid_temp_out', ...
        [860 48 1070 73]);
    add_workspace_alias(subsystem_path, cold_hx_outlet_ps_path, ...
        'ToWorkspace_cold_subsystem_outlet_fluid_temp_out', 'cold_subsystem_outlet_fluid_temp_out', ...
        [860 238 1080 263]);
    add_workspace_alias(subsystem_path, cold_hx_outlet_ps_path, ...
        'ToWorkspace_cold_return_outlet_fluid_temp_out', 'cold_return_outlet_fluid_temp_out', ...
        [860 268 1085 293]);

    layout_cold_end_subsystem_visuals_r69(subsystem_path);
end

function layout_hot_end_subsystem_visuals(subsystem_path)
    layout_exchange_subsystem_font(subsystem_path, 5);
    layout = {
        'Conn1', [80 160 110 180]
        'Conn2', [80 330 110 350]
        'HotPipe', [230 160 365 228]
        'HotSinkFluidLink', [445 170 485 210]
        'HotSinkMass', [570 172 610 200]
        'HotSinkTempSensor', [675 160 725 210]
        'HotSinkTempPS', [775 172 805 196]
        'HotSinkTempRef', [675 250 715 285]
        'HotSinkAmbientLink', [520 260 560 320]
        'AmbientTempSource', [610 275 650 305]
        'ToWorkspace_hot_sink_temp_out', [880 155 1160 180]
        'ToWorkspace_hot_source_out', [880 190 1160 215]
        'HotHXInletFluidTempSensor', [205 70 255 110]
        'HotHXInletFluidTempPS', [295 80 325 102]
        'ToWorkspace_hot_hx_inlet_fluid_temp_out', [880 30 1170 55]
        'ToWorkspace_probe_hot_hx_port1_v3_side_T_K', [880 65 1170 90]
        'HotHXOutletFluidTempSensor', [205 310 255 350]
        'HotHXOutletFluidTempPS', [295 320 325 342]
        'ToWorkspace_hot_hx_outlet_fluid_temp_out', [880 310 1170 335]
        'ToWorkspace_probe_hot_hx_port2_v2_return_side_T_K', [880 345 1170 370]
    };
    apply_subsystem_block_layout(subsystem_path, layout);
    reroute_subsystem_lines_if_available(subsystem_path);
end

function layout_cold_end_subsystem_visuals_r69(subsystem_path)
    layout_exchange_subsystem_font(subsystem_path, 5);
    layout = {
        'Conn2', [80 160 110 180]
        'Conn1', [520 160 550 180]
        'ColdSinkPipe', [230 145 380 215]
        'ColdSinkFluidLink', [430 245 470 285]
        'ColdSinkMassToPipeHeatFlowSensor', [510 230 550 300]
        'ColdSinkMass', [630 245 670 273]
        'ColdSinkTempSensor', [720 235 770 285]
        'ColdSinkTempPS', [815 247 845 271]
        'ColdSinkTempRef', [720 320 760 355]
        'ToWorkspace_cold_sink_temp_out', [930 230 1260 255]
        'ToWorkspace_Qdot_cold_sink_mass_to_pipe_W', [930 265 1260 290]
        'ToWorkspace_Qdot_cold_sink_mass_to_hx_pipe_W', [930 300 1260 325]
        'ColdSinkPipeThermalPortTempSensor', [510 330 558 370]
        'ColdSinkPipeThermalPortTempPS', [610 340 640 362]
        'ToWorkspace_cold_sink_pipe_thermal_port_temp_out', [930 335 1260 360]
        'ToWorkspace_cold_sink_hx_pipe_thermal_port_temp_out', [930 370 1260 395]
        'ColdLoadToColdSinkLink', [520 430 560 470]
        'ColdLoadMass', [630 425 670 453]
        'ColdLoadTempSensor', [720 415 770 465]
        'ColdLoadTempPS', [815 427 845 451]
        'ColdLoadHeatConstant', [630 525 665 545]
        'ColdLoadHeatPS', [700 518 770 550]
        'ColdLoadHeatSource', [815 500 865 552]
        'ColdLoadHeatRef', [920 510 960 545]
        'ToWorkspace_cold_load_temp_out', [930 420 1260 445]
        'ColdHXInletFluidTempSensor', [190 60 240 100]
        'ColdHXInletFluidTempPS', [280 70 310 92]
        'ToWorkspace_cold_hx_inlet_fluid_temp_out', [930 20 1260 45]
        'ToWorkspace_probe_chip_pipe_port_conn2_v6_sma_side_T_K', [930 55 1260 80]
        'ToWorkspace_chip_inlet_fluid_temp_out', [930 90 1260 115]
        'ToWorkspace_cold_subsystem_inlet_fluid_temp_out', [930 125 1260 150]
        'ColdHXOutletFluidTempSensor', [410 60 460 100]
        'ColdHXOutletFluidTempPS', [500 70 530 92]
        'ToWorkspace_cold_hx_outlet_fluid_temp_out', [1280 20 1620 45]
        'ToWorkspace_probe_chip_to_cold_junction_T_K', [1280 55 1620 80]
        'ToWorkspace_probe_cold_hx_port_conn1_v5_return_side_T_K', [1280 90 1620 115]
        'ToWorkspace_chip_outlet_fluid_temp_out', [1280 125 1620 150]
        'ToWorkspace_cold_subsystem_outlet_fluid_temp_out', [1280 160 1620 185]
        'ToWorkspace_cold_return_outlet_fluid_temp_out', [1280 195 1620 220]
    };
    apply_subsystem_block_layout(subsystem_path, layout);
    reroute_subsystem_lines_if_available(subsystem_path);
end

function normalize_tl_storage_initial_temperatures(model_name, hot_subsystem_path, cold_subsystem_path, solid_block_name)
    assign_initial_temperature_if_present([model_name '/HotFluidBuffer'], 'T_I', 'hot_fluid_buffer_T_init');
    assign_initial_temperature_if_present([model_name '/ColdFluidBuffer'], 'T_I', 'cold_fluid_buffer_T_init');
    assign_initial_temperature_if_present([model_name '/Tank (TL)'], 'T_I', 'root_hot_loop_T_init');

    assign_initial_temperature_if_present([hot_subsystem_path '/HotPipe'], 'T0', 'hot_side_fluid_T_init');
    assign_initial_temperature_if_present([cold_subsystem_path '/ColdSinkPipe'], 'T0', 'cold_side_fluid_T_init');
    assign_initial_temperature_if_present([cold_subsystem_path '/ColdSinkHXPipe'], 'T0', 'cold_hx_pipe_T_init');
    assign_initial_temperature_if_present([cold_subsystem_path '/ColdSinkReturnPipe'], 'T0', 'cold_return_pipe_T_init');
    assign_initial_temperature_if_present([cold_subsystem_path '/TransitPipe_V6_to_CHEX'], 'T0', 'transit_pipe_T_init');

    core_path = [model_name '/' char(string(solid_block_name))];
    sma_blocks = find_system(core_path, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        'ReferenceBlock', 'fl_lib/Thermal Liquid/Elements/Pipe (TL)');
    for idx = 1:numel(sma_blocks)
        assign_initial_temperature_if_present(sma_blocks{idx}, 'T0', 'sma_fluid_T_init');
    end
end

function configure_tl_tank_pressures(model_name)
% Use a pressurized closed-loop reference so reversed exchange driving does not
% pull the low-pressure side below the valid thermal-liquid pressure range.
    tank_blocks = find_system(model_name, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        'MaskType', 'Tank (TL)');
    for idx = 1:numel(tank_blocks)
        tank_path = tank_blocks{idx};
        configured = false;
        pressure_specs = { ...
            'fluids.thermal_liquid.tanks_accumulators.enum.TankPressureSpec.Specified', ...
            'foundation.enum.pressure_spec.specified'};
        for spec_idx = 1:numel(pressure_specs)
            try
                set_param(tank_path, 'pressure_spec', pressure_specs{spec_idx});
                configured = true;
                break;
            catch
            end
        end
        if ~configured
            error('Build_Simulink_Exchange_Model:TankPressureSpecFailed', ...
                'Failed to set specified tank pressure on %s.', tank_path);
        end
        set_param(tank_path, ...
            'tank_pressure', 'tank_pressure_MPa', ...
            'tank_pressure_unit', 'MPa');
    end
end

function assign_initial_temperature_if_present(block_path, parameter_name, value_expr)
    if isempty(block_path) || ~ischar(block_path)
        return;
    end
    block_handle = getSimulinkBlockHandle(block_path);
    if isempty(block_handle) || block_handle <= 0
        return;
    end
    try
        ref_block = get_param(block_path, 'ReferenceBlock');
    catch
        ref_block = '';
    end
    try
        if strcmp(parameter_name, 'T_I') && contains(ref_block, 'Tank (TL)')
            set_param(block_path, 'T_I_specify', 'on');
        end
        set_param(block_path, parameter_name, value_expr);
    catch ME
        error('Build_Simulink_Exchange_Model:SetInitialTempFailed', ...
            'Failed to set %s on %s: %s', parameter_name, block_path, ME.message);
    end
end

function add_root_observability_probes(model_name, solid_block_name)
    solid_name = char(string(solid_block_name));
    if ~strcmp(solid_name, 'SMA')
        delete_legacy_sma_named_root_probe_blocks(model_name);
    end

    v1_path = [model_name '/V1_cold_inlet'];
    v3_path = [model_name '/V3_sma_to_hot'];
    v4_path = [model_name '/V4_hot_inlet'];
    v6_path = [model_name '/V6_sma_to_chip_cold'];
    sma_path = [model_name '/' char(string(solid_block_name))];
    hot_buffer_path = [model_name '/HotFluidBuffer'];
    cold_buffer_path = [model_name '/ColdFluidBuffer'];

    insert_flow_sensor_probe(model_name, ...
        get_port(v1_path, 'RConn', 1), get_port(sma_path, 'LConn', 1), ...
        'FlowSensor_V1_cold_inlet', 'mass_flow_v1_cold_inlet_kgps', ...
        [730 560 785 615], [820 572 850 594], [885 566 1065 591]);
    insert_flow_sensor_probe(model_name, ...
        get_port(sma_path, 'LConn', 2), get_port(v3_path, 'LConn', 1), ...
        'FlowSensor_V3_sma_to_hot', 'mass_flow_v3_sma_to_hot_kgps', ...
        [1110 560 1165 615], [1200 572 1230 594], [1265 566 1445 591]);
    insert_flow_sensor_probe(model_name, ...
        get_port(v4_path, 'RConn', 1), get_port(sma_path, 'LConn', 3), ...
        'FlowSensor_V4_hot_inlet', 'mass_flow_v4_hot_inlet_kgps', ...
        [730 820 785 875], [820 832 850 854], [885 826 1065 851]);
    insert_flow_sensor_probe(model_name, ...
        get_port(sma_path, 'LConn', 4), get_port(v6_path, 'LConn', 1), ...
        'FlowSensor_V6_sma_to_chip_cold', 'mass_flow_v6_sma_to_chip_cold_kgps', ...
        [1110 820 1165 875], [1200 832 1230 854], [1265 826 1475 851]);

    [~, hot_buffer_ps_path] = add_fluid_temp_probe(model_name, 'HotFluidBufferTemp', ...
        get_port(hot_buffer_path, 'LConn', 1), 'hot_buffer_temp_out', ...
        [255 720 305 760], [340 726 370 748], [405 720 545 745]);
    [~, cold_buffer_ps_path] = add_fluid_temp_probe(model_name, 'ColdFluidBufferTemp', ...
        get_port(cold_buffer_path, 'LConn', 1), 'cold_buffer_temp_out', ...
        [255 500 305 540], [340 506 370 528], [405 500 555 525]);
    [~, sma_stage2_port1_ps_path] = add_fluid_temp_probe(model_name, [solid_name 'HoldInletFluidTemp'], ...
        get_port(sma_path, 'LConn', 1), 'sma_hold_inlet_fluid_temp_out', ...
        [845 500 895 540], [930 506 960 528], [995 500 1165 525]);
    [~, sma_stage2_port2_ps_path] = add_fluid_temp_probe(model_name, [solid_name 'HoldOutletFluidTemp'], ...
        get_port(sma_path, 'LConn', 2), 'sma_hold_outlet_fluid_temp_out', ...
        [1025 500 1075 540], [1110 506 1140 528], [1175 500 1355 525]);
    [~, sma_stage4_port3_ps_path] = add_fluid_temp_probe(model_name, [solid_name 'CooldownInletFluidTemp'], ...
        get_port(sma_path, 'LConn', 3), 'sma_cooldown_inlet_fluid_temp_out', ...
        [845 760 895 800], [930 766 960 788], [995 760 1185 785]);
    [~, sma_stage4_port4_ps_path] = add_fluid_temp_probe(model_name, [solid_name 'CooldownOutletFluidTemp'], ...
        get_port(sma_path, 'LConn', 4), 'sma_cooldown_outlet_fluid_temp_out', ...
        [1025 760 1075 800], [1110 766 1140 788], [1175 760 1375 785]);
    add_fluid_temp_probe(model_name, 'V1ColdInletColdSideFluidTemp', ...
        get_port(v1_path, 'LConn', 1), 'probe_v1_cold_inlet_cold_buffer_side_T_K', ...
        [660 455 710 495], [745 461 775 483], [810 455 1115 480]);
    add_fluid_temp_probe(model_name, ['V1ColdInlet' solid_name 'SideFluidTemp'], ...
        get_port(v1_path, 'RConn', 1), 'probe_v1_cold_inlet_sma_side_T_K', ...
        [660 605 710 645], [745 611 775 633], [810 605 1085 630]);
    add_fluid_temp_probe(model_name, ['V3' solid_name 'ToHot' solid_name 'SideFluidTemp'], ...
        get_port(v3_path, 'LConn', 1), 'probe_v3_sma_to_hot_sma_side_T_K', ...
        [1240 605 1290 645], [1325 611 1355 633], [1390 605 1680 630]);
    add_fluid_temp_probe(model_name, ['V3' solid_name 'ToHotHotSideFluidTemp'], ...
        get_port(v3_path, 'RConn', 1), 'probe_v3_sma_to_hot_hot_hx_side_T_K', ...
        [1240 455 1290 495], [1325 461 1355 483], [1390 455 1690 480]);
    add_fluid_temp_probe(model_name, 'V4HotInletHotSideFluidTemp', ...
        get_port(v4_path, 'LConn', 1), 'probe_v4_hot_inlet_hot_buffer_side_T_K', ...
        [660 715 710 755], [745 721 775 743], [810 715 1120 740]);
    add_fluid_temp_probe(model_name, ['V4HotInlet' solid_name 'SideFluidTemp'], ...
        get_port(v4_path, 'RConn', 1), 'probe_v4_hot_inlet_sma_side_T_K', ...
        [660 865 710 905], [745 871 775 893], [810 865 1095 890]);
    add_fluid_temp_probe(model_name, ['V6' solid_name 'ToChip' solid_name 'SideFluidTemp'], ...
        get_port(v6_path, 'LConn', 1), 'probe_v6_sma_to_chip_sma_side_T_K', ...
        [1240 865 1290 905], [1325 871 1355 893], [1390 865 1690 890]);
    add_fluid_temp_probe(model_name, ['V6' solid_name 'ToChipChipSideFluidTemp'], ...
        get_port(v6_path, 'RConn', 1), 'probe_v6_sma_to_chip_chip_side_T_K', ...
        [1240 715 1290 755], [1325 721 1355 743], [1390 715 1700 740]);

    add_workspace_alias(model_name, hot_buffer_ps_path, ...
        'ToWorkspace_probe_root_hot_buffer_fluid_T_K', 'probe_root_hot_buffer_fluid_T_K', ...
        [405 750 650 775]);
    add_workspace_alias(model_name, cold_buffer_ps_path, ...
        'ToWorkspace_probe_root_cold_buffer_fluid_T_K', 'probe_root_cold_buffer_fluid_T_K', ...
        [405 530 660 555]);
    add_workspace_alias(model_name, sma_stage2_port1_ps_path, ...
        'ToWorkspace_probe_sma_stage2_port1_v1_side_T_K', 'probe_sma_stage2_port1_v1_side_T_K', ...
        [995 530 1300 555]);
    add_workspace_alias(model_name, sma_stage2_port2_ps_path, ...
        'ToWorkspace_probe_sma_stage2_port2_v3_side_T_K', 'probe_sma_stage2_port2_v3_side_T_K', ...
        [1175 530 1490 555]);
    add_workspace_alias(model_name, sma_stage4_port3_ps_path, ...
        'ToWorkspace_probe_sma_stage4_port3_v4_side_T_K', 'probe_sma_stage4_port3_v4_side_T_K', ...
        [995 790 1300 815]);
    add_workspace_alias(model_name, sma_stage4_port4_ps_path, ...
        'ToWorkspace_probe_sma_stage4_port4_v6_side_T_K', 'probe_sma_stage4_port4_v6_side_T_K', ...
        [1175 790 1490 815]);
end

function delete_legacy_sma_named_root_probe_blocks(model_name)
    legacy_names = { ...
        'SMAHoldInletFluidTempSensor', 'SMAHoldInletFluidTempPS', ...
        'SMAHoldOutletFluidTempSensor', 'SMAHoldOutletFluidTempPS', ...
        'SMACooldownInletFluidTempSensor', 'SMACooldownInletFluidTempPS', ...
        'SMACooldownOutletFluidTempSensor', 'SMACooldownOutletFluidTempPS', ...
        'V1ColdInletSMASideFluidTempSensor', 'V1ColdInletSMASideFluidTempPS', ...
        'V3SMAToHotSMASideFluidTempSensor', 'V3SMAToHotSMASideFluidTempPS', ...
        'V3SMAToHotHotSideFluidTempSensor', 'V3SMAToHotHotSideFluidTempPS', ...
        'V4HotInletSMASideFluidTempSensor', 'V4HotInletSMASideFluidTempPS', ...
        'V6SMAToChipSMASideFluidTempSensor', 'V6SMAToChipSMASideFluidTempPS', ...
        'V6SMAToChipChipSideFluidTempSensor', 'V6SMAToChipChipSideFluidTempPS'};
    for idx = 1:numel(legacy_names)
        delete_block_if_present_with_lines([model_name '/' legacy_names{idx}]);
    end
end

function configure_r54_safe_profile(model_name, enabled, audit_probe_commenting_enabled)
    if nargin < 2 || isempty(enabled) || ~logical(enabled)
        return;
    end

    set_param(model_name, ...
        'Solver', 'ode23t', ...
        'RelTol', '1e-2', ...
        'AbsTol', '1e-3', ...
        'MaxStep', '0.4', ...
        'InitialStep', 'auto', ...
        'ZeroCross', 'on');

    if nargin < 3 || isempty(audit_probe_commenting_enabled) || ...
            ~logical(audit_probe_commenting_enabled)
        return;
    end

    audit_only_variables = { ...
        'probe_v1_cold_inlet_cold_buffer_side_T_K', ...
        'probe_v1_cold_inlet_sma_side_T_K', ...
        'probe_v3_sma_to_hot_sma_side_T_K', ...
        'probe_v4_hot_inlet_hot_buffer_side_T_K', ...
        'probe_v4_hot_inlet_sma_side_T_K', ...
        'probe_v6_sma_to_chip_sma_side_T_K'};

    blocks = find_system(model_name, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        'BlockType', 'ToWorkspace');
    for idx = 1:numel(blocks)
        variable_name = strtrim(get_param(blocks{idx}, 'VariableName'));
        if ~any(strcmp(variable_name, audit_only_variables))
            continue;
        end
        try
            set_param(blocks{idx}, 'Commented', 'through');
        catch
            % To Workspace is a sink block, so Simulink cannot comment it
            % through. Commenting the sink itself disables audit logging
            % without changing upstream physical or signal connectivity.
            set_param(blocks{idx}, 'Commented', 'on');
        end
    end
end

function [sensor_path, ps_path, toworkspace_path] = add_fluid_temp_probe(parent_path, probe_base_name, node_port_handle, variable_name, sensor_pos, ps_pos, workspace_pos)
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

    connect_physical_ports(parent_path, node_port_handle, get_port(sensor_path, 'LConn', 1));
    add_line(parent_path, get_port(sensor_path, 'RConn', 1), get_port(ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(parent_path, get_port(ps_path, 'Outport', 1), get_port(toworkspace_path, 'Inport', 1), 'autorouting', 'on');
end

function add_workspace_alias(parent_path, ps_path, alias_block_name, variable_name, workspace_pos)
    alias_path = [parent_path '/' alias_block_name];
    delete_block_if_present_with_lines(alias_path);
    add_block('simulink/Sinks/To Workspace', alias_path, ...
        'VariableName', variable_name, ...
        'SaveFormat', 'Structure With Time', ...
        'Position', workspace_pos);
    add_line(parent_path, get_port(ps_path, 'Outport', 1), get_port(alias_path, 'Inport', 1), 'autorouting', 'on');
end

function insert_flow_sensor_probe(parent_path, upstream_port, downstream_port, sensor_name, variable_name, sensor_pos, ps_pos, workspace_pos)
    sensor_path = [parent_path '/' sensor_name];
    ps_path = [parent_path '/' sensor_name '_PS'];
    toworkspace_path = [parent_path '/ToWorkspace_' variable_name];

    delete_block_if_present_with_lines(toworkspace_path);
    delete_block_if_present_with_lines(ps_path);
    delete_block_if_present_with_lines(sensor_path);

    delete_line_if_present(parent_path, upstream_port, downstream_port);
    delete_line_if_present(parent_path, downstream_port, upstream_port);

    add_block('fl_lib/Thermal Liquid/Sensors/Flow Rate Sensor (TL)', sensor_path, ...
        'Position', sensor_pos, ...
        'mass_flow_measure', 'true', ...
        'volumetric_flow_measure', 'false', ...
        'energy_flow_measure', 'false');
    add_block('nesl_utility/PS-Simulink Converter', ps_path, ...
        'Position', ps_pos, ...
        'VectorFormat', '1-D array', ...
        'Unit', 'kg/s');
    add_block('simulink/Sinks/To Workspace', toworkspace_path, ...
        'VariableName', variable_name, ...
        'SaveFormat', 'Structure With Time', ...
        'Position', workspace_pos);

    connect_physical_ports(parent_path, upstream_port, get_port(sensor_path, 'LConn', 1));
    connect_physical_ports(parent_path, get_port(sensor_path, 'RConn', 1), downstream_port);
    add_line(parent_path, get_port(sensor_path, 'RConn', 2), get_port(ps_path, 'LConn', 1), 'autorouting', 'on');
    add_line(parent_path, get_port(ps_path, 'Outport', 1), get_port(toworkspace_path, 'Inport', 1), 'autorouting', 'on');
end

function delete_lines_touching_port(port_handle)
    % Robustly remove the Simulink line attached to a physical port. Walks down
    % into LineChildren to remove leaf branches first, then removes the parent.
    % delete_line(parent,a,b) silently fails for some Thermal-Liquid networks
    % because the line is stored as a tee with nested children rather than a
    % flat src/dst pair.
    if ~isnumeric(port_handle) || port_handle <= 0
        return;
    end
    ln = get_param(port_handle, 'Line');
    if isempty(ln) || ln == -1 || ln <= 0
        return;
    end
    remove_line_recursive(ln, []);
end

function remove_line_recursive(ln, visited)
    if ~isnumeric(ln) || isempty(ln) || ln == -1 || ln <= 0
        return;
    end
    if nargin < 2 || isempty(visited)
        visited = [];
    end
    if any(visited == ln)
        return;
    end
    visited(end + 1) = ln; %#ok<AGROW>
    try
        children = get_param(ln, 'LineChildren');
    catch
        children = [];
    end
    if ~isempty(children)
        children = unique(children(children ~= -1 & children > 0));
        for k = numel(children):-1:1
            remove_line_recursive(children(k), visited);
        end
    end
    try
        delete_line(ln);
    catch
    end
end

function insert_root_transit_pipe(model_name, cold_subsystem_path)
    % Add an explicit TL Pipe at ROOT level between V6.RConn and
    % cold_subsystem.Conn2 (external boundary). This captures the V6-to-
    % subsystem implicit fluid volume that, without an explicit block, is
    % defaulted by Simscape to ambient/293K at every stage init, causing
    % the cold fluid arriving from SMA-outlet to be "warmed up" at the
    % subsystem boundary. With explicit T0 = transit_pipe_T_init (runtime
    % carryforward), the boundary state preserves the previous stage 4
    % end temperature across cycles.
    v6_path = [model_name '/V6_sma_to_chip_cold'];
    if isempty(find_system(model_name, 'SearchDepth', 1, 'Name', 'V6_sma_to_chip_cold')) || ...
            isempty(cold_subsystem_path)
        return;
    end
    block_path = [model_name '/TransitPipe_V6_to_subsystem'];
    upstream_port = get_port(v6_path, 'RConn', 1);
    downstream_port = get_port(cold_subsystem_path, 'RConn', 1);

    % We run this BEFORE add_root_observability_probes, so the existing
    % V6.RConn ↔ cold_subsystem.Conn2 wire is a clean direct line (no probe
    % tee yet). delete_line works for that case.
    delete_line_if_present(model_name, upstream_port, downstream_port);
    delete_line_if_present(model_name, downstream_port, upstream_port);

    add_pipe_block(block_path, [1750 100 1850 167], 'transit_pipe_T_init', ...
        'transit_pipe_length_m', '0');

    % Probes at both ends of the root-level transit pipe.
    [~, root_in_ps_path] = add_fluid_temp_probe(model_name, 'RootTransitInletFluidTemp', ...
        get_port(block_path, 'RConn', 1), ...
        'root_transit_pipe_inlet_fluid_temp_out', ...
        [1685 38 1735 78], [1770 44 1800 66], [1830 38 2080 63]);
    [~, root_out_ps_path] = add_fluid_temp_probe(model_name, 'RootTransitOutletFluidTemp', ...
        get_port(block_path, 'LConn', 1), ...
        'root_transit_pipe_outlet_fluid_temp_out', ...
        [1885 38 1935 78], [1970 44 2000 66], [2030 38 2300 63]);
    add_workspace_alias(model_name, root_in_ps_path, ...
        'ToWorkspace_probe_root_transit_pipe_inlet_T_K', 'probe_root_transit_pipe_inlet_T_K', ...
        [1830 78 2080 103]);
    add_workspace_alias(model_name, root_out_ps_path, ...
        'ToWorkspace_probe_root_transit_pipe_outlet_T_K', 'probe_root_transit_pipe_outlet_T_K', ...
        [2030 78 2300 103]);

    % Flow direction in stage 4: V6.RConn -> TransitPipe.RConn -> TransitPipe.LConn -> cold_subsystem.Conn2(external)
    connect_physical_ports(model_name, upstream_port, get_port(block_path, 'RConn', 1));
    connect_physical_ports(model_name, get_port(block_path, 'LConn', 1), downstream_port);
end

function add_pipe_block(block_path, position, init_temp_expr, length_expr, length_add_expr)
    if nargin < 3 || isempty(init_temp_expr)
        init_temp_expr = 'T_fluid';
    end
    if nargin < 4 || isempty(length_expr)
        length_expr = 'tube_l';
    end
    if nargin < 5 || isempty(length_add_expr)
        length_add_expr = '0';
    end
    add_block('fl_lib/Thermal Liquid/Elements/Pipe (TL)', block_path, ...
        'Position', position, ...
        'BlockRotation', '180', ...
        'length', length_expr, ...
        'length_add', length_add_expr, ...
        'area', 'pipe_fa', ...
        'Dh', 'D_e', ...
        'Nu_lam', 'nuh', ...
        'T0', init_temp_expr);
end

function add_sma_pipe_thermal_gate_block(block_path, position, conductance_expr)
    add_block('fl_lib/Thermal/Thermal Elements/Conductive Heat Transfer', block_path, ...
        'Position', position, ...
        'area', '1', ...
        'thickness', '1', ...
        'th_cond', conductance_expr);
end

function delete_block_if_present_with_lines(block_path)
    if getSimulinkBlockHandle(block_path) <= 0
        return;
    end
    ports = get_param(block_path, 'PortHandles');
    fields = fieldnames(ports);
    for fidx = 1:numel(fields)
        values = ports.(fields{fidx});
        for idx = 1:numel(values)
            delete_lines_touching_port(values(idx));
        end
    end
    delete_block(block_path);
end

function rename_block_if_present(model_name, sid_or_name, new_name)
    block_path = find_block_by_sid(model_name, sid_or_name);
    if isempty(block_path)
        block_path = find_single_block(model_name, sid_or_name);
    end
    if isempty(block_path)
        return;
    end
    set_param(block_path, 'Name', new_name);
end

function block_path = find_single_block(model_name, block_name)
    matches = find_system(model_name, 'SearchDepth', 1, 'Name', block_name);
    if isempty(matches)
        block_path = '';
    else
        block_path = matches{1};
    end
end

function block_path = find_block_by_sid(model_name, sid_text)
    block_path = '';
    try
        handle = Simulink.ID.getHandle(sprintf('%s:%s', model_name, char(string(sid_text))));
    catch
        handle = -1;
    end

    if isempty(handle) || isequal(handle, -1) || ~isnumeric(handle) || handle <= 0
        return;
    end

    try
        block_path = getfullname(handle);
    catch
        block_path = '';
    end
end

function remote_port_handle = capture_remote_physical_port(block_path)
    port_connectivity = get_param(block_path, 'PortConnectivity');
    for idx = 1:numel(port_connectivity)
        src_ports = port_connectivity(idx).SrcPort;
        dst_ports = port_connectivity(idx).DstPort;

        src_ports = src_ports(src_ports ~= -1);
        dst_ports = dst_ports(dst_ports ~= -1);

        if ~isempty(src_ports)
            remote_port_handle = src_ports(1);
            return;
        end
        if ~isempty(dst_ports)
            remote_port_handle = dst_ports(1);
            return;
        end
    end

    error('Build_Simulink_Exchange_Model:ReservoirReconnectFailed', ...
        'Unable to resolve the remote fluid port connected to %s.', block_path);
end

function connect_physical_ports(parent_path, port_a, port_b)
    try
        add_line(parent_path, port_a, port_b, 'autorouting', 'on');
    catch
        add_line(parent_path, port_b, port_a, 'autorouting', 'on');
    end
end

function delete_contents_except_ports(subsystem_path)
    delete_all_lines(subsystem_path);

    blocks = find_system(subsystem_path, 'SearchDepth', 1, 'Type', 'Block');
    for idx = 1:numel(blocks)
        block_path = blocks{idx};
        if strcmp(block_path, subsystem_path)
            continue;
        end
        block_name = get_param(block_path, 'Name');
        if startsWith(block_name, 'Conn')
            continue;
        end
        delete_block(block_path);
    end

    delete_all_lines(subsystem_path);
end

function delete_attached_lines(block_path)
    line_handles = get_param(block_path, 'LineHandles');
    line_groups = struct2cell(line_handles);
    for group_id = 1:numel(line_groups)
        handles = line_groups{group_id};
        handles = handles(handles ~= -1);
        for idx = 1:numel(handles)
            try
                delete_line(handles(idx));
            catch
            end
        end
    end
end

function delete_line_if_present(parent_path, port_a, port_b)
    try
        delete_line(parent_path, port_a, port_b);
    catch
    end
end

function delete_all_lines(subsystem_path)
    lines = get_param(subsystem_path, 'Lines');
    for idx = 1:numel(lines)
        if lines(idx).Handle ~= -1
            try
                delete_line(lines(idx).Handle);
            catch
            end
        end
    end
end

function port_handle = get_port(block_path, port_type, index)
    handles = get_param(block_path, 'PortHandles');
    values = handles.(port_type);
    port_handle = values(index);
end

function tap_indices = build_uniform_tap_indices(node_count, tap_count)
    tap_indices = round(linspace(1, node_count, tap_count));
    tap_indices(1) = 1;
    tap_indices(end) = node_count;
end

function apply_compact_visual_font_size(model_name, font_size)
    font_size_text = num2str(font_size);

    root_font_params = {'DefaultBlockFontSize', 'DefaultAnnotationFontSize', ...
        'DefaultLineFontSize'};
    for idx = 1:numel(root_font_params)
        try
            set_param(model_name, root_font_params{idx}, font_size_text);
        catch
        end
    end

    blocks = find_system(model_name, ...
        'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', ...
        'Type', 'Block');
    for idx = 1:numel(blocks)
        try
            set_param(blocks{idx}, 'FontSize', font_size_text);
        catch
        end
    end

    annotations = find_system(model_name, ...
        'FindAll', 'on', ...
        'Type', 'annotation');
    for idx = 1:numel(annotations)
        try
            set_param(annotations(idx), 'FontSize', font_size_text);
        catch
        end
    end

    lines = find_system(model_name, ...
        'FindAll', 'on', ...
        'Type', 'line');
    for idx = 1:numel(lines)
        try
            set_param(lines(idx), 'FontSize', font_size_text);
        catch
        end
    end
end

function apply_root_visual_layout(model_name, solid_block_name)
    solid_name = char(string(solid_block_name));
    % Root-level visual cleanup only. Do not change block parameters,
    % ports, or connections.
    layout = {
        'ColdFluidBufferTempSensor', [80 270 130 310]
        'ColdFluidBufferTempPS', [155 279 185 301]
        'ToWorkspace_cold_buffer_temp_out', [230 258 430 282]
        'ToWorkspace_probe_root_cold_buffer_fluid_T_K', [230 292 560 316]
        'HotFluidBufferTempSensor', [80 720 130 760]
        'HotFluidBufferTempPS', [155 729 185 751]
        'ToWorkspace_hot_buffer_temp_out', [230 708 430 732]
        'ToWorkspace_probe_root_hot_buffer_fluid_T_K', [230 742 560 766]

        'V1ColdInletColdSideFluidTempSensor', [620 255 670 295]
        'V1ColdInletColdSideFluidTempPS', [705 264 735 286]
        'FlowSensor_V1_cold_inlet', [780 325 835 380]
        'FlowSensor_V1_cold_inlet_PS', [870 339 900 361]
        ['V1ColdInlet' solid_name 'SideFluidTempSensor'], [620 405 670 445]
        ['V1ColdInlet' solid_name 'SideFluidTempPS'], [705 414 735 436]
        [solid_name 'HoldInletFluidTempSensor'], [910 255 960 295]
        [solid_name 'HoldInletFluidTempPS'], [995 264 1025 286]
        [solid_name 'HoldOutletFluidTempSensor'], [1230 255 1280 295]
        [solid_name 'HoldOutletFluidTempPS'], [1315 264 1345 286]
        'FlowSensor_V3_sma_to_hot', [1420 325 1475 380]
        'FlowSensor_V3_sma_to_hot_PS', [1510 339 1540 361]
        ['V3' solid_name 'ToHot' solid_name 'SideFluidTempSensor'], [1230 405 1280 445]
        ['V3' solid_name 'ToHot' solid_name 'SideFluidTempPS'], [1315 414 1345 436]
        ['V3' solid_name 'ToHotHotSideFluidTempSensor'], [1590 255 1640 295]
        ['V3' solid_name 'ToHotHotSideFluidTempPS'], [1675 264 1705 286]
        '冷端换热器', [1740 305 1825 350]

        'V4HotInletHotSideFluidTempSensor', [620 705 670 745]
        'V4HotInletHotSideFluidTempPS', [705 714 735 736]
        'FlowSensor_V4_hot_inlet', [780 775 835 830]
        'FlowSensor_V4_hot_inlet_PS', [870 789 900 811]
        ['V4HotInlet' solid_name 'SideFluidTempSensor'], [620 855 670 895]
        ['V4HotInlet' solid_name 'SideFluidTempPS'], [705 864 735 886]
        [solid_name 'CooldownInletFluidTempSensor'], [910 705 960 745]
        [solid_name 'CooldownInletFluidTempPS'], [995 714 1025 736]
        [solid_name 'CooldownOutletFluidTempSensor'], [1230 705 1280 745]
        [solid_name 'CooldownOutletFluidTempPS'], [1315 714 1345 736]
        'FlowSensor_V6_sma_to_chip_cold', [1420 775 1475 830]
        'FlowSensor_V6_sma_to_chip_cold_PS', [1510 789 1540 811]
        ['V6' solid_name 'ToChip' solid_name 'SideFluidTempSensor'], [1230 855 1280 895]
        ['V6' solid_name 'ToChip' solid_name 'SideFluidTempPS'], [1315 864 1345 886]
        ['V6' solid_name 'ToChipChipSideFluidTempSensor'], [1590 705 1640 745]
        ['V6' solid_name 'ToChipChipSideFluidTempPS'], [1675 714 1705 736]
        '热端换热器', [1740 765 1825 810]

        char(string(solid_block_name)), [1020 480 1160 620]
        'ColdFluidBuffer', [520 315 560 355]
        'HotFluidBuffer', [520 765 560 805]
        'Pressure Source (TL)', [605 760 645 800]
        'Tank (TL)', [610 835 670 895]
        'T-Junction (TL)3', [590 700 630 740]
        'T-Junction (TL)1', [1010 190 1050 230]
        'T-Junction (TL)', [1160 190 1200 230]
        'T-Junction (TL)2', [1310 190 1350 230]
        'V1_cold_inlet', [1010 120 1050 160]
        'V2_hot_return', [1010 665 1050 705]
        'V3_sma_to_hot', [1160 120 1200 160]
        'V4_hot_inlet', [1310 120 1350 160]
        'V5_cold_return', [1460 120 1500 160]
        'V6_sma_to_chip_cold', [1610 120 1650 160]

        'ToWorkspace_probe_v1_cold_inlet_cold_buffer_side_T_K', [1880 220 2250 244]
        'ToWorkspace_sma_hold_inlet_fluid_temp_out', [1880 252 2250 276]
        'ToWorkspace_probe_sma_stage2_port1_v1_side_T_K', [1880 284 2250 308]
        'ToWorkspace_mass_flow_v1_cold_inlet_kgps', [1880 316 2250 340]
        'ToWorkspace_probe_v1_cold_inlet_sma_side_T_K', [1880 348 2250 372]
        'ToWorkspace_sma_hold_outlet_fluid_temp_out', [1880 380 2250 404]
        'ToWorkspace_probe_sma_stage2_port2_v3_side_T_K', [1880 412 2250 436]
        'ToWorkspace_mass_flow_v3_sma_to_hot_kgps', [1880 444 2250 468]
        'ToWorkspace_probe_v3_sma_to_hot_sma_side_T_K', [1880 476 2250 500]
        'ToWorkspace_probe_v3_sma_to_hot_hot_hx_side_T_K', [1880 508 2250 532]

        'ToWorkspace_probe_v4_hot_inlet_hot_buffer_side_T_K', [1880 670 2250 694]
        'ToWorkspace_sma_cooldown_inlet_fluid_temp_out', [1880 702 2250 726]
        'ToWorkspace_probe_sma_stage4_port3_v4_side_T_K', [1880 734 2250 758]
        'ToWorkspace_mass_flow_v4_hot_inlet_kgps', [1880 766 2250 790]
        'ToWorkspace_probe_v4_hot_inlet_sma_side_T_K', [1880 798 2250 822]
        'ToWorkspace_sma_cooldown_outlet_fluid_temp_out', [1880 830 2250 854]
        'ToWorkspace_probe_sma_stage4_port4_v6_side_T_K', [1880 862 2250 886]
        'ToWorkspace_mass_flow_v6_sma_to_chip_cold_kgps', [1880 894 2250 918]
        'ToWorkspace_probe_v6_sma_to_chip_sma_side_T_K', [1880 926 2250 950]
        'ToWorkspace_probe_v6_sma_to_chip_chip_side_T_K', [1880 958 2250 982]

        'ValveCommandFromWorkspace', [520 1015 620 1055]
        'Demux', [670 970 715 1085]
        'MATLAB Function', [430 1065 500 1195]
        sprintf('Simulink-PS\nConverter'), [760 948 775 964]
        sprintf('Simulink-PS\nConverter1'), [760 968 775 984]
        sprintf('Simulink-PS\nConverter2'), [760 988 775 1004]
        sprintf('Simulink-PS\nConverter3'), [760 1008 775 1024]
        sprintf('Simulink-PS\nConverter4'), [760 1028 775 1044]
        sprintf('Simulink-PS\nConverter5'), [760 1048 775 1064]
        sprintf('Solver\nConfiguration'), [430 900 470 945]
        '热流体设置', [430 835 470 875]
    };

    for idx = 1:size(layout, 1)
        set_root_block_position_if_present(model_name, layout{idx, 1}, layout{idx, 2});
    end

    reroute_root_lines_if_available(model_name);
end

function set_root_block_position_if_present(model_name, block_name, position)
    block_path = [model_name '/' char(string(block_name))];
    try
        if getSimulinkBlockHandle(block_path) ~= -1
            set_param(block_path, 'Position', position);
        end
    catch
    end
end

function apply_subsystem_block_layout(subsystem_path, layout)
    for idx = 1:size(layout, 1)
        set_subsystem_block_position_if_present(subsystem_path, layout{idx, 1}, layout{idx, 2});
    end
end

function set_subsystem_block_position_if_present(subsystem_path, block_name, position)
    block_path = [subsystem_path '/' char(string(block_name))];
    try
        if getSimulinkBlockHandle(block_path) ~= -1
            set_param(block_path, 'Position', position);
        end
    catch
    end
end

function layout_exchange_subsystem_font(subsystem_path, font_size)
    font_size_text = num2str(font_size);
    try
        set_param(subsystem_path, ...
            'DefaultBlockFontSize', font_size_text, ...
            'DefaultAnnotationFontSize', font_size_text, ...
            'DefaultLineFontSize', font_size_text);
    catch
    end
    try
        blocks = find_system(subsystem_path, ...
            'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', ...
            'Type', 'Block');
        for idx = 1:numel(blocks)
            try
                set_param(blocks{idx}, 'FontSize', font_size_text);
            catch
            end
        end
    catch
    end
    try
        lines = find_system(subsystem_path, 'FindAll', 'on', 'Type', 'line');
        for idx = 1:numel(lines)
            try
                set_param(lines(idx), 'FontSize', font_size_text);
            catch
            end
        end
    catch
    end
end

function reroute_subsystem_lines_if_available(subsystem_path)
    try
        lines = find_system(subsystem_path, ...
            'SearchDepth', 1, ...
            'FindAll', 'on', ...
            'Type', 'line');
        for idx = 1:numel(lines)
            try
                Simulink.BlockDiagram.routeLine(lines(idx));
            catch
            end
        end
    catch
    end
end

function reroute_root_lines_if_available(model_name)
    try
        lines = find_system(model_name, 'SearchDepth', 1, 'FindAll', 'on', 'Type', 'line');
        for idx = 1:numel(lines)
            try
                Simulink.BlockDiagram.routeLine(lines(idx));
            catch
            end
        end
    catch
    end
end
