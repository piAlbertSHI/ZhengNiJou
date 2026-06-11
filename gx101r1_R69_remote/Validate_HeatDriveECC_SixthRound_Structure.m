function validation = Validate_HeatDriveECC_SixthRound_Structure(options)
% Validate sixth-round model structure without running a long simulation.

    if nargin < 1 || isempty(options)
        options = Build_HeatDriveECC_SixthRound_Defaults();
    else
        options = Build_HeatDriveECC_SixthRound_Defaults(options);
    end

    Build_HeatDriveECC_SixthRound_Model(options.force_rebuild_model);
    model_name = options.model_name;
    load_system(model_name);
    cleanup = onCleanup(@() close_system(model_name, 0));

    checks = {};
    checks(end + 1, :) = {'model_exists', exist(options.model_path, 'file') > 0}; %#ok<AGROW>
    checks(end + 1, :) = {'source_model_untouched_available', exist(options.source_model_path, 'file') > 0}; %#ok<AGROW>
    checks(end + 1, :) = {'does_not_overwrite_fifth_model', ~strcmp(options.model_name, options.fifth_model_name)}; %#ok<AGROW>

    role_details = repmat(struct('name', '', 'exists', false, ...
        'has_valve_command', false, 'has_pressure_pi', false, ...
        'has_flow_sensor_v1', false, 'has_flow_sensor_v4', false, ...
        'has_temperature_probe', false), numel(options.branch_roles), 1);
    for idx = 1:numel(options.branch_roles)
        role = options.branch_roles{idx};
        role_path = [model_name '/' role.name];
        detail = role_details(idx);
        detail.name = role.name;
        detail.exists = getSimulinkBlockHandle(role_path) > 0;
        detail.has_valve_command = getSimulinkBlockHandle([role_path '/ValveCommandFromWorkspace']) > 0;
        detail.has_pressure_pi = getSimulinkBlockHandle([role_path '/PressurePI_TargetHold']) > 0 && ...
            getSimulinkBlockHandle([role_path '/PressurePI_TargetCooldown']) > 0;
        detail.has_flow_sensor_v1 = getSimulinkBlockHandle([role_path '/FlowSensor_V1_cold_inlet']) > 0;
        detail.has_flow_sensor_v4 = getSimulinkBlockHandle([role_path '/FlowSensor_V4_hot_inlet']) > 0;
        detail.has_temperature_probe = getSimulinkBlockHandle([role_path '/SMAHoldInletFluidTempSensor']) > 0 && ...
            getSimulinkBlockHandle([role_path '/SMACooldownInletFluidTempSensor']) > 0;
        role_details(idx) = detail;
        checks(end + 1, :) = {['role_exists_' role.name], detail.exists}; %#ok<AGROW>
        checks(end + 1, :) = {['role_has_valve_command_' role.name], detail.has_valve_command}; %#ok<AGROW>
        checks(end + 1, :) = {['role_has_pressure_pi_' role.name], detail.has_pressure_pi}; %#ok<AGROW>
        checks(end + 1, :) = {['role_has_flow_sensors_' role.name], detail.has_flow_sensor_v1 && detail.has_flow_sensor_v4}; %#ok<AGROW>
        checks(end + 1, :) = {['role_has_temperature_probes_' role.name], detail.has_temperature_probe}; %#ok<AGROW>
    end

    checks(end + 1, :) = {'has_stage_controller', ...
        getSimulinkBlockHandle([model_name '/SixthRoundStageAndRouteController']) > 0}; %#ok<AGROW>
    checks(end + 1, :) = {'has_mechanical_solver', ...
        getSimulinkBlockHandle([model_name '/MechanicalCouplingSolver']) > 0}; %#ok<AGROW>

    validation = struct();
    validation.schema_version = 'heatdrive_ecc_sixth_round_structure_validation_v1';
    validation.model_name = model_name;
    validation.model_path = options.model_path;
    validation.role_details = role_details;
    validation.checks = checks;
    validation.ok = all(cell2mat(checks(:, 2)));
end
