function record = Audit_HeatDriveECC_IsolatedTankCapacity(output_root, physical_path)
% Independent component identification, never a production checkpoint restart.
    assert(~isfile(fullfile(output_root, 'isolated_tank_result.json')), 'Do not overwrite a trial.');
    if ~isfolder(output_root), mkdir(output_root); end
    record = struct('schema', 'heatdrive_ecc_isolated_tank_capacity_v1', ...
        'cases', {{}}, 'collection_pass', false, 'error_identifier', '', 'error_message', '', ...
        'source_options_path', physical_path, 'production_simulation_run', false, ...
        'production_checkpoint_loaded', false, 'output_operating_point_saved', false, ...
        'production_recovery_allowed', false, 'temporal_convergence_verified', false);
    try
        [code, commit] = system('git rev-parse HEAD');
        assert(code == 0, 'Cannot record execution commit.');
        record.execution_commit = strtrim(commit);
        [code, dirty] = system('git status --porcelain');
        assert(code == 0 && isempty(strtrim(dirty)), 'Commit reviewed experiment source first.');
        saved = load(physical_path, 'options');
        [source, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(saved.options);
        source_cleanup = onCleanup(@() close_system(source, 0));
        blocks = find_system(source, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Type', 'Block');
        settings = {};
        for k = 1:numel(blocks)
            dialog = get_param(blocks{k}, 'DialogParameters');
            if isstruct(dialog) && all(isfield(dialog, {'rho_TLU_4', 'T_TLU', 'table_dimensions'}))
                settings{end + 1} = blocks{k}; %#ok<AGROW>
            end
        end
        water = [source '/SMA_ThermalLiquidSettings'];
        glycol = setdiff(settings, {water});
        assert(numel(settings) == 2 && isscalar(glycol), 'Expected separate water and glycol domains.');
        solver = find_system(source, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'MaskType', 'Solver Configuration');
        assert(isscalar(solver), 'Expected one source solver configuration.');
        tank_names = {'SHEXFluidBuffer', 'ColdFluidBuffer'};
        setting_names = {water, glycol{1}};
        temperatures = [380 280];
        heat_commands = [10 -10];
        areas = [.0005 .001 .002];
        for fluid = 1:2
            for area = areas
                model = 'ecc_isolated_tank_capacity';
                assert(~bdIsLoaded(model), 'Independent model name is already in use.');
                new_system(model);
                cleanup = onCleanup(@() close_system(model, 0));
                tank = [model '/Tank'];
                add_block([source '/' tank_names{fluid}], tank);
                add_block(setting_names{fluid}, [model '/FluidSettings']);
                add_block(solver{1}, [model '/Solver']);
                add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source', [model '/Heat']);
                add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', [model '/Reference']);
                add_block('nesl_utility/Simulink-PS Converter', [model '/HeatCommandPS'], 'Unit', 'W');
                add_block('simulink/Sources/Constant', [model '/HeatCommand'], 'Value', num2str(heat_commands(fluid)));
                set_param(tank, 'tank_area', num2str(area, '%.15g'), 'tank_area_unit', 'm^2', ...
                    'level', num2str(.0001 / area, '%.15g'), 'level_unit', 'm', ...
                    'T_I', num2str(temperatures(fluid)), 'T_I_unit', 'K', ...
                    'tank_pressure', '1', 'tank_pressure_unit', 'MPa');
                simscape.addConnection(tank, 'A', [model '/FluidSettings'], only_port([model '/FluidSettings']));
                simscape.addConnection(tank, 'A', [model '/Solver'], only_port([model '/Solver']));
                simscape.addConnection(tank, 'H', [model '/Heat'], 'A');
                simscape.addConnection([model '/Heat'], 'B', [model '/Reference'], only_port([model '/Reference']));
                add_line(model, 'HeatCommand/1', 'HeatCommandPS/1');
                converter_ports = get_param([model '/HeatCommandPS'], 'PortHandles');
                heat_ports = get_param([model '/Heat'], 'PortHandles');
                add_line(model, converter_ports.RConn(1), heat_ports.RConn(1));
                set_param([model '/Solver'], 'UseLocalSolver', 'on', ...
                    'LocalSolverChoice', 'NE_BACKWARD_EULER_ADVANCER', 'LocalSolverSampleTime', '.001');
                set_param(model, 'Solver', 'ode3', 'FixedStep', '.001', 'StopTime', '.1', ...
                    'SimscapeLogType', 'all', 'SimscapeLogName', 'simlog', ...
                    'SimscapeLogLimitData', 'off', 'ReturnWorkspaceOutputs', 'on', ...
                    'SaveTime', 'off', 'SaveOutput', 'off', 'SaveState', 'off', 'SaveFinalState', 'off');
                output = sim(model);
                node = simscape.logging.findNode(output.simlog, tank);
                names = {'mass', 'volume', 'T_I', 'p_I', 'rho_I', 'u_I', 'h_I', 'mdot_A', 'Phi_A', 'Q_H'};
                traces = cell(size(names));
                for k = 1:numel(names)
                    series = node.child(names{k}).series;
                    t = double(time(series));
                    traces{k} = struct('name', names{k}, 'unit', series.unit, ...
                        'time_s', t(:), 'values', double(values(series)));
                end
                case_record = struct('fluid_index', fluid, 'source_tank', tank_names{fluid}, ...
                    'source_settings', setting_names{fluid}, 'area_m2', area, 'initial_volume_m3', .0001, ...
                    'initial_temperature_K', temperatures(fluid), 'command_W', heat_commands(fluid), ...
                    'fixed_step_s', .001, 'stop_s', .1, 'local_solver', 'NE_BACKWARD_EULER_ADVANCER', ...
                    'hypothesized_dead_height_m', .001, 'hypothesis_fitted_from_trial', false);
                record_json = jsonencode(case_record);
                case_path = fullfile(output_root, sprintf('case_%d.mat', numel(record.cases) + 1));
                save(case_path, 'traces', 'record_json', '-v7.3');
                record.cases{end + 1} = case_record;
                clear cleanup output traces
            end
        end
        record.collection_pass = numel(record.cases) == 6;
        clear source_cleanup
    catch exception
        record.error_identifier = exception.identifier;
        record.error_message = exception.message;
    end
    fid = fopen(fullfile(output_root, 'isolated_tank_result.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot retain experiment outcome.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('ISOLATED_TANK_COLLECTION_PASS=%d CASES=%d\n', record.collection_pass, numel(record.cases));
    assert(record.collection_pass, 'HeatDriveECC:IsolatedTankTrialFailed', '%s', record.error_message);
end

function name = only_port(path)
    ports = simscape.connectionPortProperties(path);
    assert(isscalar(ports), 'Expected one connection port at %s.', path);
    name = ports.Name;
end
