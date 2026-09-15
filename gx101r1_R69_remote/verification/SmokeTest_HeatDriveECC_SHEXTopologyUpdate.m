function result = SmokeTest_HeatDriveECC_SHEXTopologyUpdate()
% Build and update the canonical model without running a simulation.
% The result is a topology/update smoke test, not a physical validation run.

verification_root = fileparts(mfilename('fullpath'));
repo_root = fileparts(verification_root);
addpath(repo_root);
output_path = fullfile(repo_root, 'outputs_storage_audit', ...
    'shex_transfer_topology_update_20260915.json');
result = struct();
result.schema = 'heatdrive_ecc_shex_topology_update_smoke_v1';
result.model_name = 'heatdrive_ecc_coupled_se21';
result.simulation_run = false;
result.topology_update_pass = false;
result.sensor_blocks = struct();
result.error_message = '';
model_name = result.model_name;

try
    load_system(model_name);
    options = Build_HeatDriveECC_EighthRound_Defaults();
    if isfield(options, 'simulation') && isfield(options.simulation, ...
            'persist_model_configuration')
        options.simulation.persist_model_configuration = false;
    end
    [model_name, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(options); %#ok<ASGLU>
    set_param(model_name, 'SimulationCommand', 'update');
    result.sensor_blocks.SHEXFluidHeatFlowSensor = ~isempty(find_system( ...
        model_name, 'SearchDepth', Inf, 'Name', 'SHEXFluidHeatFlowSensor'));
    result.sensor_blocks.SHEXFluidHeatFlowPS = ~isempty(find_system( ...
        model_name, 'SearchDepth', Inf, 'Name', 'SHEXFluidHeatFlowPS'));
    result.sensor_blocks.ToWorkspace_shex_fluid_heat_flow_W = ~isempty(find_system( ...
        model_name, 'SearchDepth', Inf, 'Name', ...
        'ToWorkspace_shex_fluid_heat_flow_W'));
    result.topology_update_pass = all(struct2array(result.sensor_blocks));
catch err
    result.error_message = getReport(err, 'extended', 'hyperlinks', 'off');
end

result.completed_at = datestr(now, 31);
fid = fopen(output_path, 'w');
if fid < 0
    error('SHEXSmoke:WriteFailed', 'Cannot write %s', output_path);
end
fwrite(fid, jsonencode(result), 'char');
fclose(fid);
if bdIsLoaded(model_name)
    close_system(model_name, 0);
end
disp(jsonencode(result));
end
