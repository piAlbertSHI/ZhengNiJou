function record = Instrument_HeatDriveECC_PumpPressureProbes(model_name, output_root)
% Add diagnostic-only named pressure probes at the three TL source faces.
% This changes only the in-memory diagnostic model and never saves the SLX.

    if nargin < 2 || isempty(output_root)
        output_root = pwd;
    end
    assert(bdIsLoaded(model_name), ...
        'HeatDriveECC:PumpPressureProbeModelNotLoaded', ...
        'The diagnostic model must be loaded before instrumentation.');
    repo_root = fileparts(mfilename('fullpath'));
    verification_root = fullfile(repo_root, 'verification');
    if isempty(which('Map_HeatDriveECC_PhysicalPortHandles'))
        addpath(verification_root);
    end

    blocks = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'Type', 'Block', ...
        'MaskType', 'Pressure Source (TL)');
    assert(numel(blocks) == 3, ...
        'HeatDriveECC:PumpPressureProbeSourceCount', ...
        'Expected three TL pressure sources, found %d.', numel(blocks));

    scratch = [model_name '_pump_pressure_probe_mapping'];
    assert(~bdIsLoaded(scratch), ...
        'HeatDriveECC:PumpPressureProbeScratchExists', ...
        'Temporary port-mapping model already exists: %s.', scratch);
    new_system(scratch);
    scratch_cleanup = onCleanup(@() close_scratch_model(scratch));

    probe_records = cell(2 * numel(blocks), 1);
    probe_count = 0;
    record = struct('schema', 'heatdrive_ecc_pump_pressure_probe_contract_v1', ...
        'model_name', model_name, 'source_count', numel(blocks), ...
        'simulation_run', false, 'state_imported', false, ...
        'production_recovery_allowed', false, 'probes', {{}}, ...
        'output_root', output_root);
    for source_idx = 1:numel(blocks)
        source_path = blocks{source_idx};
        source_name = relative_block_path(model_name, source_path);
        prefix = pressure_probe_prefix(source_name);
        rows = Map_HeatDriveECC_PhysicalPortHandles(source_path, scratch);
        rows = rows(cellfun(@(row) ismember(row.name, {'A', 'B'}), rows));
        assert(numel(rows) == 2, ...
            'HeatDriveECC:PumpPressureProbePortMapping', ...
            'Expected named A/B ports for %s.', source_path);
        for port_idx = 1:numel(rows)
            row = rows{port_idx};
            suffix = lower(row.name);
            stem = sprintf('Diagnostic_%s_Pressure_%s', prefix, suffix);
            sensor_path = [model_name '/' stem 'Sensor'];
            converter_path = [model_name '/' stem 'PS'];
            workspace_path = [model_name '/ToWorkspace_' stem];
            variable_name = sprintf('pump_pressure_%s_port_%s_MPa', ...
                prefix, suffix);
            delete_block_with_lines(sensor_path);
            delete_block_with_lines(converter_path);
            delete_block_with_lines(workspace_path);

            add_block('fl_lib/Thermal Liquid/Sensors/Pressure & Temperature Sensor (TL)', ...
                sensor_path, 'Position', probe_position(source_idx, port_idx), ...
                'pressure', 'true', 'temperature', 'false');
            add_block('nesl_utility/PS-Simulink Converter', converter_path, ...
                'Position', probe_position(source_idx, port_idx) + [90 0 90 0], ...
                'VectorFormat', '1-D array', 'Unit', 'MPa');
            add_block('simulink/Sinks/To Workspace', workspace_path, ...
                'VariableName', variable_name, 'SaveFormat', 'Structure With Time', ...
                'Position', probe_position(source_idx, port_idx) + [180 0 360 0]);

            sensor_ports = get_param(sensor_path, 'PortHandles');
            converter_ports = get_param(converter_path, 'PortHandles');
            workspace_ports = get_param(workspace_path, 'PortHandles');
            add_line_safe(model_name, row.handle, sensor_ports.LConn(1));
            add_line_safe(model_name, sensor_ports.RConn(1), converter_ports.LConn(1));
            add_line_safe(model_name, converter_ports.Outport(1), workspace_ports.Inport(1));

            probe_count = probe_count + 1;
            probe_records{probe_count} = struct( ...
                'source_block', source_name, 'source_port_name', row.name, ...
                'source_port_side', row.side, 'source_port_index', row.index, ...
                'sensor_block', relative_block_path(model_name, sensor_path), ...
                'workspace_variable', variable_name, 'unit', 'MPa');
        end
    end
    record.probes = probe_records(1:probe_count);
    clear scratch_cleanup
    if ~exist(output_root, 'dir')
        mkdir(output_root);
    end
    contract_path = fullfile(output_root, 'pump_pressure_probe_contract.json');
    fid = fopen(contract_path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'HeatDriveECC:PumpPressureProbeContractOpenFailed', ...
        'Cannot write %s.', contract_path);
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    record.contract_path = contract_path;
    clear cleanup
end

function prefix = pressure_probe_prefix(source_name)
    if contains(source_name, 'SMA Pressure Source')
        prefix = 'sma';
    elseif contains(source_name, 'SE_Stage2_PistonPressureSource')
        prefix = 'se_stage2';
    elseif contains(source_name, 'SE_Stage4_PistonPressureSource')
        prefix = 'se_stage4';
    else
        error('HeatDriveECC:UnknownPumpPressureSource', ...
            'No diagnostic prefix is declared for %s.', source_name);
    end
end

function position = probe_position(source_idx, port_idx)
    position = [-220 + (source_idx - 1) * 180, ...
        80 + (port_idx - 1) * 90, -130 + (source_idx - 1) * 180, ...
        120 + (port_idx - 1) * 90];
end

function path = relative_block_path(model_name, block_path)
    prefix = [model_name '/'];
    assert(startsWith(block_path, prefix), ...
        'HeatDriveECC:PumpPressureProbeRelativePath', ...
        'Block %s is outside model %s.', block_path, model_name);
    path = block_path(numel(prefix) + 1:end);
end

function delete_block_with_lines(block_path)
    if getSimulinkBlockHandle(block_path) == -1
        return;
    end
    ports = get_param(block_path, 'PortHandles');
    groups = fieldnames(ports);
    for group_idx = 1:numel(groups)
        handles = ports.(groups{group_idx});
        for handle_idx = 1:numel(handles)
            try
                line = get_param(handles(handle_idx), 'Line');
                if isnumeric(line) && line ~= -1
                    delete_line(line);
                end
            catch
            end
        end
    end
    delete_block(block_path);
end

function add_line_safe(system_path, source_handle, destination_handle)
    try
        add_line(system_path, source_handle, destination_handle, 'autorouting', 'on');
    catch ME
        if ~contains(ME.message, 'already has a line') && ...
                ~contains(ME.message, 'already connected') && ...
                ~contains(ME.message, 'There is already a line')
            rethrow(ME);
        end
    end
end

function close_scratch_model(model_name)
    if bdIsLoaded(model_name)
        close_system(model_name, 0);
    end
end
