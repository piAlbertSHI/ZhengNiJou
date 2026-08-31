function audit = Audit_HeatDriveECC_SourceHeatFlow()
% Audit the in-memory SHEX source heat-flow measurement topology.
% Build_HeatDriveECC_EighthRound_Simulink_Model configures the canonical
% model in memory and does not save or simulate it in this read-only audit.

    repo_root = fileparts(fileparts(mfilename('fullpath')));
    current_dir = pwd;
    cleanup_dir = onCleanup(@() cd(current_dir));
    cd(repo_root);
    [model_name, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model();
    cleanup_model = onCleanup(@() close_model_without_save(model_name));
    parent = [model_name '/SHEX'];
    source = [parent '/AmbientTempSource'];
    mass = [parent '/HotSinkMass'];
    sensor = [parent '/SHEXSourceToSinkHeatFlowSensor'];
    converter = [parent '/SHEXSourceToSinkHeatFlowPS'];
    sink = [parent '/ToWorkspace_shex_source_heat_flow_W'];

    required = {source, mass, sensor, converter, sink};
    audit.required_blocks_present = all(cellfun(@(p) ...
        getSimulinkBlockHandle(p) > 0, required));
    audit.source_to_sensor = port_has_line(source, 'LConn', 1) && ...
        port_has_line(sensor, 'LConn', 1);
    audit.sensor_to_mass = port_has_line(sensor, 'RConn', 2) && ...
        port_has_line(mass, 'LConn', 1);
    audit.sensor_to_converter = port_has_line(sensor, 'RConn', 1) && ...
        port_has_line(converter, 'LConn', 1);
    audit.converter_to_workspace = port_has_line(converter, 'Outport', 1) && ...
        port_has_line(sink, 'Inport', 1);
    audit.workspace_variable = strcmp(get_param(sink, 'VariableName'), ...
        'shex_source_heat_flow_W');
    audit.source_heat_flow_contract = ...
        audit.required_blocks_present && audit.source_to_sensor && ...
        audit.sensor_to_mass && audit.sensor_to_converter && ...
        audit.converter_to_workspace && audit.workspace_variable;
    audit.schema = 'heatdrive_ecc_shex_source_heat_flow_audit_v1';
    audit.model_name = model_name;
    fprintf('SHEX_SOURCE_HEAT_FLOW_AUDIT_PASS=%d\n', ...
        audit.source_heat_flow_contract);
    clear cleanup_model cleanup_dir
end

function tf = port_has_line(block, kind, idx)
    tf = false;
    handles = get_param(block, 'PortHandles');
    ports = handles.(kind);
    if numel(ports) < idx
        return;
    end
    line_handle = get_param(ports(idx), 'Line');
    tf = isnumeric(line_handle) && line_handle ~= -1;
end

function close_model_without_save(model_name)
    if bdIsLoaded(model_name)
        set_param(model_name, 'Dirty', 'off');
        close_system(model_name, 0);
    end
end
