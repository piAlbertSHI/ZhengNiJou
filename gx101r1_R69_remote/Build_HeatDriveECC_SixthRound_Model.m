function model_path = Build_HeatDriveECC_SixthRound_Model(force_rebuild)
% Build the sixth-round four-role-branch model from mature solver101 parts.
%
% This builder intentionally does not overwrite:
%   - nixunhuan_solver101_internal.slx
%   - heatdrive_ecc_reconfigured_from_solver101.slx

    if nargin < 1
        force_rebuild = false;
    end

    options = Build_HeatDriveECC_SixthRound_Defaults(struct( ...
        'force_rebuild_model', force_rebuild));
    model_name = options.model_name;
    model_path = options.model_path;
    source_name = options.source_model_name;
    source_path = options.source_model_path;

    if exist(model_path, 'file') && ~force_rebuild
        return;
    end
    if ~exist(source_path, 'file')
        error('Build_HeatDriveECC_SixthRound_Model:MissingSource', ...
            'Mature source model not found: %s', source_path);
    end

    source_hash_before = file_hash(source_path);
    close_if_loaded(model_name);
    load_system(source_path);

    if exist(model_path, 'file')
        delete(model_path);
    end
    new_system(model_name);
    load_system(model_name);
    set_param(model_name, 'StopTime', '0.02');
    set_param(model_name, 'Description', sprintf([ ...
        'Sixth-round four-physical-branch heat-driven ECC model. ', ...
        'Each role branch is copied from mature %s components; ', ...
        'original mature and fifth-round models are not overwritten.'], source_name));

    add_block('nesl_utility/Solver Configuration', ...
        [model_name '/TopLevelSolverConfiguration'], ...
        'Position', [30 30 110 90]);
    add_block('fl_lib/Thermal Liquid/Utilities/Thermal Liquid Settings (TL)', ...
        [model_name '/TopLevelThermalLiquidSettings'], ...
        'Position', [30 120 110 180]);

    roles = options.branch_roles;
    for idx = 1:numel(roles)
        add_copied_role_branch(model_name, source_name, roles{idx}, idx);
    end

    add_role_controller_skeleton(model_name);
    add_mechanical_solver_skeleton(model_name);
    add_annotation(model_name, [40 760 1240 890], sprintf([ ...
        'Sixth-round topology gate:\\n', ...
        'SMA_SHEX, SMA_THE, SE_THE, SE_RHE are independent role-branch instances.\\n', ...
        'They are mature solver101 copies for branch preflight; full-cycle coupling is not allowed ', ...
        'until branch preflights and offline mechanical preflight pass.\\n', ...
        'No q_shex=q_sma_hold or PECC=Qr proxy is present in sixth-round audit code.']));

    save_system(model_name, model_path);
    close_system(model_name, 0);
    close_system(source_name, 0);

    source_hash_after = file_hash(source_path);
    if ~strcmp(source_hash_before, source_hash_after)
        error('Build_HeatDriveECC_SixthRound_Model:SourceModified', ...
            'The mature source model changed while building the sixth-round model.');
    end
end

function add_copied_role_branch(model_name, source_name, role, idx)
    branch_path = [model_name '/' role.name];
    delete_block_if_present(branch_path);
    x0 = 170 + (idx - 1) * 360;
    add_block('simulink/Ports & Subsystems/Subsystem', branch_path, ...
        'Position', [x0 80 x0 + 280 310], ...
        'BackgroundColor', branch_color(role));
    Simulink.SubSystem.deleteContents(branch_path);
    Simulink.BlockDiagram.copyContentsToSubsystem(source_name, branch_path);
    prefix_workspace_sinks(branch_path, [lower(role.name) '_']);
    set_from_workspace_variable([branch_path '/ValveCommandFromWorkspace'], ...
        [lower(role.name) '_valve_command_ts']);
    replace_constant_with_workspace([branch_path '/PressurePI_TargetHold'], ...
        [lower(role.name) '_mdot_hold_target_ts']);
    replace_constant_with_workspace([branch_path '/PressurePI_TargetCooldown'], ...
        [lower(role.name) '_mdot_cool_target_ts']);
    set_branch_initial_temperature_aliases(branch_path, role);
    set_param(branch_path, 'Description', sprintf('%s: %s. Active path: %s.', ...
        role.name, role.description, role.active_path));
    add_annotation(model_name, [x0 325 x0 + 280 395], sprintf([ ...
        '%s\\nsolid role: %s\\nactive stage: %d\\nboundary T: %.6g K'], ...
        role.name, role.solid_role, role.active_stage, role.boundary_T_K));
end

function set_branch_initial_temperature_aliases(branch_path, role)
    % Mature blocks keep their internal parameters. Only their workspace
    % variable names are isolated so branch preflights can set role-specific
    % thermal boundaries without cross-contaminating other role branches.
    prefix_initial_temperature_variables(branch_path, [lower(role.name) '_']);
end

function add_role_controller_skeleton(model_name)
    block_path = [model_name '/SixthRoundStageAndRouteController'];
    add_block('simulink/Ports & Subsystems/Subsystem', block_path, ...
        'Position', [170 460 560 620], 'BackgroundColor', 'green');
    Simulink.SubSystem.deleteContents(block_path);
    add_block('simulink/Sources/From Workspace', [block_path '/StageIdFromWorkspace'], ...
        'VariableName', 'sixth_stage_id_ts', ...
        'Interpolate', 'off', ...
        'OutputAfterFinalValue', 'Holding final value', ...
        'Position', [40 40 180 70]);
    add_block('simulink/Sinks/To Workspace', [block_path '/StageIdLog'], ...
        'VariableName', 'sixth_stage_id_log', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [230 40 360 70]);
    add_line(block_path, 'StageIdFromWorkspace/1', 'StageIdLog/1', ...
        'autorouting', 'on');
end

function add_mechanical_solver_skeleton(model_name)
    block_path = [model_name '/MechanicalCouplingSolver'];
    add_block('simulink/Ports & Subsystems/Subsystem', block_path, ...
        'Position', [640 460 1040 620], 'BackgroundColor', 'yellow');
    Simulink.SubSystem.deleteContents(block_path);
    add_block('simulink/Sources/From Workspace', [block_path '/MechanicalInputFromWorkspace'], ...
        'VariableName', 'sixth_mechanical_preflight_input_ts', ...
        'Interpolate', 'on', ...
        'OutputAfterFinalValue', 'Holding final value', ...
        'Position', [35 45 210 75]);
    add_block('simulink/User-Defined Functions/Interpreted MATLAB Function', ...
        [block_path '/ConstitutiveKernel'], ...
        'MATLABFcn', 'HeatDriveECC_SixthRound_MechanicalStep', ...
        'OutputDimensions', '120', ...
        'SampleTime', '0.001', ...
        'Position', [250 30 430 90]);
    add_block('simulink/Sinks/To Workspace', [block_path '/MechanicalAuditLog'], ...
        'VariableName', 'sixth_mechanical_audit', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [470 45 620 75]);
    add_line(block_path, 'MechanicalInputFromWorkspace/1', 'ConstitutiveKernel/1', ...
        'autorouting', 'on');
    add_line(block_path, 'ConstitutiveKernel/1', 'MechanicalAuditLog/1', ...
        'autorouting', 'on');
end

function prefix_initial_temperature_variables(system_path, prefix)
    names = {
        'ambient_T_init'
        'hot_sink_T_init'
        'cold_sink_T_init'
        'cold_load_T_init'
        'chip_T_init'
        'hot_fluid_buffer_T_init'
        'cold_fluid_buffer_T_init'
        'hot_side_fluid_T_init'
        'cold_hx_pipe_T_init'
        'cold_return_pipe_T_init'
        'transit_pipe_T_init'
        'cold_load_heat_W'
        'chip_heat_W'
        'solver_T_init_101_internal'};
    blocks = find_system(system_path, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'Type', 'Block');
    for block_idx = 1:numel(blocks)
        params = get_param(blocks{block_idx}, 'DialogParameters');
        if ~isstruct(params)
            continue;
        end
        param_names = fieldnames(params);
        for param_idx = 1:numel(param_names)
            param_name = param_names{param_idx};
            try
                value = get_param(blocks{block_idx}, param_name);
                if ~(ischar(value) || isstring(value))
                    continue;
                end
                updated = char(value);
                for name_idx = 1:numel(names)
                    updated = regexprep(updated, ...
                        ['(?<![A-Za-z0-9_])' names{name_idx} '(?![A-Za-z0-9_])'], ...
                        [prefix names{name_idx}]);
                end
                if ~strcmp(updated, char(value))
                    set_param(blocks{block_idx}, param_name, updated);
                end
            catch
            end
        end
    end
end

function prefix_workspace_sinks(system_path, prefix)
    sinks = find_system(system_path, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'BlockType', 'ToWorkspace');
    for idx = 1:numel(sinks)
        try
            old_name = get_param(sinks{idx}, 'VariableName');
            if startsWith(old_name, prefix)
                continue;
            end
            set_param(sinks{idx}, 'VariableName', [prefix old_name]);
        catch
        end
    end
end

function set_from_workspace_variable(block_path, variable_name)
    if getSimulinkBlockHandle(block_path) <= 0
        return;
    end
    set_param(block_path, 'VariableName', variable_name, ...
        'Interpolate', 'on', ...
        'OutputAfterFinalValue', 'Holding final value');
end

function replace_constant_with_workspace(block_path, variable_name)
    if getSimulinkBlockHandle(block_path) <= 0
        return;
    end
    parent_path = get_param(block_path, 'Parent');
    position = get_param(block_path, 'Position');
    ports = get_param(block_path, 'PortHandles');
    line_handle = get_param(ports.Outport(1), 'Line');
    destinations = [];
    if line_handle ~= -1
        destinations = get_param(line_handle, 'DstPortHandle');
        delete_line(line_handle);
    end
    delete_block(block_path);
    add_block('simulink/Sources/From Workspace', block_path, ...
        'VariableName', variable_name, ...
        'Interpolate', 'on', ...
        'OutputAfterFinalValue', 'Holding final value', ...
        'Position', position);
    new_ports = get_param(block_path, 'PortHandles');
    for idx = 1:numel(destinations)
        add_line(parent_path, new_ports.Outport(1), destinations(idx), ...
            'autorouting', 'on');
    end
end

function color = branch_color(role)
    if strcmp(role.solid_role, 'sma')
        color = 'cyan';
    else
        color = 'lightBlue';
    end
end

function delete_block_if_present(block_path)
    if getSimulinkBlockHandle(block_path) > 0
        delete_block(block_path);
    end
end

function add_annotation(system_path, position, text_value)
    annotation = Simulink.Annotation(system_path, text_value);
    annotation.Position = position;
    annotation.Interpreter = 'off';
end

function close_if_loaded(model_name)
    if bdIsLoaded(model_name)
        close_system(model_name, 0);
    end
end

function hash = file_hash(path_value)
    engine = java.security.MessageDigest.getInstance('SHA-256');
    stream = java.io.FileInputStream(java.io.File(path_value));
    cleanup = onCleanup(@() stream.close());
    buffer = zeros(1, 8192, 'uint8');
    while true
        count = stream.read(buffer, 0, numel(buffer));
        if count < 0
            break;
        end
        engine.update(buffer(1:count));
    end
    hash = lower(reshape(dec2hex(typecast(engine.digest(), 'uint8'))', 1, []));
end
