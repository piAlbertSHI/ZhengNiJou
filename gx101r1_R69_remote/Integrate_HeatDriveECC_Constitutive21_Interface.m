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
    expose_component(model_name, 'SMA');
    expose_component(model_name, 'SE');
    add_top_level_constitutive_loop(model_name, options);
    make_to_workspace_names_unique(model_name);
    add_or_update_note(model_name);
    set_param(model_name, 'SimulationCommand', 'update');
    if save_changes
        save_system(model_name);
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
    assignin('base', 'constitutive_output_width', 12 * options.node_count);
end

function assign_exchange_workspace(options)
    exchange_options = struct( ...
        'model_path', options.model_path, ...
        'exchange_backend_kind', 'simulink_axial_21', ...
        'ambient_T_init', options.system.T0_K, ...
        'hot_sink_T_init', options.system.T0_K, ...
        'cold_sink_T_init', options.system.Tc_K, ...
        'cold_load_T_init', options.system.Tc_K, ...
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

function sample_time_s = get_constitutive_sample_time(options)
    if isfield(options.constitutive, 'simulink_sample_time_s')
        sample_time_s = options.constitutive.simulink_sample_time_s;
    else
        sample_time_s = options.simulation.fixed_step_s;
    end
end

function expose_component(model_name, component_name)
    component = [model_name '/' component_name];
    inner = [component '/Subsystem2'];
    N = 21;

    ensure_block('simulink/Sources/In1', [inner '/ConstitutiveHeat21_W'], ...
        'Position', [1100 760 1130 780]);
    ensure_block('simulink/Signal Routing/Demux', [inner '/ConstitutiveHeatDemux21'], ...
        'Outputs', num2str(N), ...
        'Position', [1165 650 1170 1075]);
    ensure_block('simulink/Sinks/Out1', [inner '/NodeTemp21Out'], ...
        'Position', [1120 260 1150 280]);
    if exist_block([inner '/ToWorkspace_Tx21_internal'])
        set_param([inner '/ToWorkspace_Tx21_internal'], ...
            'VariableName', [component_name '_Tx21_internal']);
    end
    safe_add_line(inner, 'TempMux51/1', 'NodeTemp21Out/1');
    safe_add_line(inner, 'ConstitutiveHeat21_W/1', 'ConstitutiveHeatDemux21/1');

    for idx = 1:N
        y = 75 + (idx - 1) * 48;
        converter = sprintf('%s/ConstitutiveHeatPS_%02d', inner, idx);
        source = sprintf('%s/ConstitutiveHeatSource_%02d', inner, idx);
        ensure_block('nesl_utility/Simulink-PS Converter', converter, ...
            'Unit', 'W', ...
            'Position', [1210 y 1270 (y + 24)]);
        ensure_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source', source, ...
            'Position', [1320 (y - 10) 1370 (y + 42)]);
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
