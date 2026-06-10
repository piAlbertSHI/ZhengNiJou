function model_path = Build_HeatDriveECC_Reconfigured_Model(force_rebuild)
% Copy the mature solver101 model and assemble isolated SMA/SE fluid loops.

    if nargin < 1
        force_rebuild = false;
    end

    root_dir = fileparts(mfilename('fullpath'));
    source_name = 'nixunhuan_solver101_internal';
    source_path = fullfile(root_dir, [source_name '.slx']);
    model_name = 'heatdrive_ecc_reconfigured_from_solver101';
    model_path = fullfile(root_dir, [model_name '.slx']);

    if exist(model_path, 'file') && ~force_rebuild
        return;
    end
    if ~exist(source_path, 'file')
        error('Build_HeatDriveECC_Reconfigured_Model:MissingSource', ...
            'Mature source model not found: %s', source_path);
    end

    source_hash_before = file_hash(source_path);
    close_if_loaded(model_name);
    copyfile(source_path, model_path, 'f');

    load_system(source_path);
    load_system(model_path);
    set_param(model_name, 'Description', sprintf([ ...
        'Fifth-round heat-driven ECC assembly. Byte-copied from %s; ', ...
        'mature fluid components are reused and assigned to isolated SMA/SE loops.'], ...
        source_name));

    rename_block_if_present([model_name '/SMA'], 'SE_Refrigerant_1D51');
    rename_block_if_present([model_name '/Tank (TL)'], 'ColdFluidBuffer');
    prefix_workspace_sinks(model_name, 'se_loop_');
    set_from_workspace_variable([model_name '/ValveCommandFromWorkspace'], ...
        'L_valve_command_se');

    sma_loop_path = [model_name '/SMA_Actuator_MatureLoop'];
    delete_block_if_present(sma_loop_path);
    add_block('simulink/Ports & Subsystems/Subsystem', sma_loop_path, ...
        'Position', [1780 80 2060 330], ...
        'BackgroundColor', 'cyan');
    Simulink.SubSystem.deleteContents(sma_loop_path);
    Simulink.BlockDiagram.copyContentsToSubsystem(source_name, sma_loop_path);
    rename_block_if_present([sma_loop_path '/SMA'], 'SMA_Actuator_1D51');
    rename_block_if_present([sma_loop_path '/Tank (TL)'], 'ColdFluidBuffer');
    prefix_workspace_sinks(sma_loop_path, 'sma_loop_');
    set_from_workspace_variable([sma_loop_path '/ValveCommandFromWorkspace'], ...
        'L_valve_command_sma');

    add_role_subsystem(model_name, 'StageScheduler', [1780 390 1990 480], ...
        'Event-guard and maximum-duration stage schedule interface.');
    add_role_subsystem(model_name, 'ValveAndRouteController', [1780 510 1990 600], ...
        'Drives independent mature V1-V6 and Pressure PI target enables.');
    add_role_subsystem(model_name, 'MechanicalCouplingSolver', [1780 630 1990 720], ...
        'Eq.6/Eq.7 top-level coupling; same stress must drive constitutive update.');
    add_role_subsystem(model_name, 'DynamicEnergyAudit', [1780 750 1990 840], ...
        'Stage/cycle solid, fluid, HX, mechanical, and system energy audit.');
    add_role_subsystem(model_name, 'ProbeSemanticLogger', [1780 870 1990 960], ...
        'Physical probe aliases and semantic table source paths.');

    add_annotation(model_name, [1780 1000 2290 1110], sprintf([ ...
        'Fifth-round assembly origin: %s\\n', ...
        'Root mature network role: SE loop (HHEX_SE / CHEX-RHE).\\n', ...
        'Nested mature network role: SMA actuator loop (SHEX / HHEX_SMA).\\n', ...
        'Fluid networks are independent; only mechanical coupling crosses loops.'], ...
        source_name));

    save_system(model_name, model_path);
    close_system(model_name, 0);
    close_system(source_name, 0);

    source_hash_after = file_hash(source_path);
    if ~strcmp(source_hash_before, source_hash_after)
        error('Build_HeatDriveECC_Reconfigured_Model:SourceModified', ...
            'The mature source model changed while assembling the target model.');
    end
end

function prefix_workspace_sinks(system_path, prefix)
    sinks = find_system(system_path, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'BlockType', 'ToWorkspace');
    for idx = 1:numel(sinks)
        variable_name = get_param(sinks{idx}, 'VariableName');
        if ~startsWith(variable_name, prefix)
            set_param(sinks{idx}, 'VariableName', [prefix variable_name]);
        end
    end
end

function set_from_workspace_variable(path_value, variable_name)
    if getSimulinkBlockHandle(path_value) <= 0
        error('Build_HeatDriveECC_Reconfigured_Model:MissingValveCommand', ...
            'Missing mature valve command block: %s', path_value);
    end
    set_param(path_value, 'VariableName', variable_name);
end

function add_role_subsystem(model_name, block_name, position, description)
    path_value = [model_name '/' block_name];
    delete_block_if_present(path_value);
    add_block('simulink/Ports & Subsystems/Subsystem', path_value, ...
        'Position', position, ...
        'BackgroundColor', 'green');
    set_param(path_value, 'Description', description);
end

function add_annotation(model_name, position, text_value)
    annotation = Simulink.Annotation(model_name, text_value);
    annotation.Position = position;
    annotation.BackgroundColor = 'white';
end

function rename_block_if_present(path_value, new_name)
    if getSimulinkBlockHandle(path_value) <= 0
        return;
    end
    parent_path = get_param(path_value, 'Parent');
    target_path = [parent_path '/' new_name];
    if getSimulinkBlockHandle(target_path) <= 0
        set_param(path_value, 'Name', new_name);
    end
end

function delete_block_if_present(path_value)
    if getSimulinkBlockHandle(path_value) > 0
        delete_block(path_value);
    end
end

function close_if_loaded(model_name)
    if bdIsLoaded(model_name)
        set_param(model_name, 'Dirty', 'off');
        close_system(model_name, 0);
    end
end

function digest = file_hash(path_value)
    command = sprintf(['powershell -NoProfile -Command ', ...
        '"(Get-FileHash -Algorithm SHA256 -LiteralPath ''%s'').Hash"'], ...
        strrep(path_value, '''', ''''''));
    [status, text] = system(command);
    if status ~= 0
        error('Build_HeatDriveECC_Reconfigured_Model:HashFailed', ...
            'Cannot calculate SHA256 for %s.', path_value);
    end
    digest = upper(strtrim(text));
end
