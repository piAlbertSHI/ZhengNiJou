function summary = Validate_HeatDriveECC_FifthRound_Structure()
% Validate copied-origin and mature-component reuse before physics changes.

    root_dir = fileparts(mfilename('fullpath'));
    source_path = fullfile(root_dir, 'nixunhuan_solver101_internal.slx');
    source_hash_before = file_hash(source_path);
    model_path = Build_HeatDriveECC_Reconfigured_Model(true);
    source_hash_after = file_hash(source_path);
    [~, model_name] = fileparts(model_path);
    load_system(model_path);

    required = {
        [model_name '/SE_Refrigerant_1D51']
        [model_name '/SMA_Actuator_MatureLoop']
        [model_name '/SMA_Actuator_MatureLoop/SMA_Actuator_1D51']
        [model_name '/PressurePI_Kp']
        [model_name '/PressurePI_Ki']
        [model_name '/PressurePI_Integrator']
        [model_name '/PressurePI_Saturation']
        [model_name '/V1_cold_inlet']
        [model_name '/V6_sma_to_chip_cold']
        [model_name '/热端换热器']
        [model_name '/冷端换热器']
        [model_name '/SMA_Actuator_MatureLoop/PressurePI_Kp']
        [model_name '/SMA_Actuator_MatureLoop/PressurePI_Ki']
        [model_name '/SMA_Actuator_MatureLoop/V1_cold_inlet']
        [model_name '/SMA_Actuator_MatureLoop/V6_sma_to_chip_cold']
        [model_name '/SMA_Actuator_MatureLoop/热端换热器']
        [model_name '/SMA_Actuator_MatureLoop/冷端换热器']
        [model_name '/StageScheduler']
        [model_name '/ValveAndRouteController']
        [model_name '/MechanicalCouplingSolver']
        [model_name '/DynamicEnergyAudit']
        [model_name '/ProbeSemanticLogger']};

    present = false(size(required));
    for idx = 1:numel(required)
        present(idx) = getSimulinkBlockHandle(required{idx}) > 0;
    end
    hold_pipes = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'RegExp', 'on', 'Name', '^HoldPipe_[0-9]+$');
    cooldown_pipes = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'RegExp', 'on', 'Name', '^CooldownPipe_[0-9]+$');
    pi_kp = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'Name', 'PressurePI_Kp');
    valves = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'RegExp', 'on', 'Name', '^V[1-6]_.*');
    to_workspace = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'BlockType', 'ToWorkspace');
    top_blocks = find_system(model_name, 'SearchDepth', 1, 'Type', 'Block');

    summary = struct();
    summary.schema_version = 'heatdrive_ecc_fifth_round_structure_v1';
    summary.model_name = model_name;
    summary.model_path = model_path;
    summary.source_model_path = source_path;
    summary.source_sha256_before = source_hash_before;
    summary.source_sha256_after = source_hash_after;
    summary.source_model_unchanged = strcmp(source_hash_before, source_hash_after);
    summary.required_paths = required;
    summary.required_paths_present = present;
    summary.required_paths_ok = all(present);
    summary.hold_pipe_count = numel(hold_pipes);
    summary.cooldown_pipe_count = numel(cooldown_pipes);
    summary.pressure_pi_kp_instance_count = numel(pi_kp);
    summary.valve_instance_count = numel(valves);
    summary.to_workspace_count = numel(to_workspace);
    summary.top_level_block_count = numel(top_blocks) - 1;
    summary.not_single_function_prototype = summary.top_level_block_count > 50;
    summary.two_mature_loop_instances = summary.hold_pipe_count >= 202 && ...
        summary.cooldown_pipe_count >= 202 && ...
        summary.pressure_pi_kp_instance_count >= 2 && ...
        summary.valve_instance_count >= 12;
    summary.ok = summary.source_model_unchanged && summary.required_paths_ok && ...
        summary.not_single_function_prototype && summary.two_mature_loop_instances;

    close_system(model_name, 0);

    outputs_dir = fullfile(root_dir, 'Output', 'fifth_round_structure');
    if ~isfolder(outputs_dir)
        mkdir(outputs_dir);
    end
    save(fullfile(outputs_dir, 'fifth_round_structure_summary.mat'), 'summary');
    write_json(fullfile(outputs_dir, 'fifth_round_structure_summary.json'), summary);
end

function digest = file_hash(path_value)
    command = sprintf(['powershell -NoProfile -Command ', ...
        '"(Get-FileHash -Algorithm SHA256 -LiteralPath ''%s'').Hash"'], ...
        strrep(path_value, '''', ''''''));
    [status, text] = system(command);
    if status ~= 0
        error('Validate_HeatDriveECC_FifthRound_Structure:HashFailed', ...
            'Cannot calculate SHA256 for %s.', path_value);
    end
    digest = upper(strtrim(text));
end

function write_json(path_value, value)
    fid = fopen(path_value, 'w', 'n', 'UTF-8');
    if fid < 0
        error('Validate_HeatDriveECC_FifthRound_Structure:CannotWriteJson', ...
            'Cannot write %s.', path_value);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
end
