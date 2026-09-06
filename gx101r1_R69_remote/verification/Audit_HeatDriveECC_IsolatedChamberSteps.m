function record = Audit_HeatDriveECC_IsolatedChamberSteps(output_root, physical_path)
% Actual local-step intervention in an isolated component, not an OP restart.
    assert(~isfolder(output_root), 'Do not overwrite an experiment.');
    mkdir(output_root);
    record = struct('schema', 'heatdrive_ecc_isolated_chamber_steps_v1', ...
        'cases', {{}}, 'collection_pass', false, 'error_identifier', '', 'error_message', '', ...
        'source_options_path', physical_path, 'production_checkpoint_loaded', false, ...
        'production_recovery_allowed', false, 'whole_model_convergence_verified', false);
    try
        [code, commit] = system('git rev-parse HEAD');
        assert(code == 0, 'Cannot record source commit.');
        record.execution_commit = strtrim(commit);
        [code, dirty] = system('git status --porcelain');
        assert(code == 0 && isempty(strtrim(dirty)), 'Commit reviewed source before experiment.');
        saved = load(physical_path, 'options');
        [source, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(saved.options);
        source_cleanup = onCleanup(@() close_system(source, 0));
        source_chamber = [source '/SMA_PumpInletConnectingPipeVolume'];
        source_settings = [source '/SMA_ThermalLiquidSettings'];
        solver = find_system(source, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'MaskType', 'Solver Configuration');
        assert(isscalar(solver), 'Require one source solver.');
        volume = saved.options.branch.sma_pump_manifold_volume_m3;
        area = saved.options.branch.connecting_pipe_flow_area_m2;
        for temperature = [300 380]
            for step = [.001 .0005 .00025]
                model = 'ecc_isolated_chamber_steps';
                assert(~bdIsLoaded(model), 'Trial model already in use.');
                new_system(model);
                cleanup = onCleanup(@() close_system(model, 0));
                chamber = [model '/Chamber'];
                add_block(source_chamber, chamber);
                set_param(chamber, 'num_ports', 'foundation.enum.num_ports.one', ...
                    'volume', num2str(volume, '%.17g'), 'volume_unit', 'm^3', ...
                    'area_A', num2str(area, '%.17g'), 'area_A_unit', 'm^2', ...
                    'p_I', '1', 'p_I_unit', 'MPa', 'p_I_priority', 'High', ...
                    'T_I', num2str(temperature), 'T_I_unit', 'K', 'T_I_priority', 'High');
                add_block(source_settings, [model '/FluidSettings']);
                add_block(solver{1}, [model '/Solver']);
                add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source', [model '/Heat']);
                add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', [model '/Reference']);
                add_block('nesl_utility/Simulink-PS Converter', [model '/HeatCommandPS'], 'Unit', 'W');
                add_block('simulink/Sources/Constant', [model '/HeatCommand'], 'Value', '-10');
                simscape.addConnection(chamber, 'A', [model '/FluidSettings'], only_port([model '/FluidSettings']));
                simscape.addConnection(chamber, 'A', [model '/Solver'], only_port([model '/Solver']));
                simscape.addConnection(chamber, 'H', [model '/Heat'], 'A');
                simscape.addConnection([model '/Heat'], 'B', [model '/Reference'], only_port([model '/Reference']));
                add_line(model, 'HeatCommand/1', 'HeatCommandPS/1');
                ps = get_param([model '/HeatCommandPS'], 'PortHandles');
                heat = get_param([model '/Heat'], 'PortHandles');
                add_line(model, ps.RConn(1), heat.RConn(1));
                set_param([model '/Solver'], 'UseLocalSolver', 'on', ...
                    'LocalSolverChoice', 'NE_BACKWARD_EULER_ADVANCER', ...
                    'LocalSolverSampleTime', num2str(step, '%.17g'));
                set_param(model, 'Solver', 'ode3', 'FixedStep', num2str(step, '%.17g'), 'StopTime', '1', ...
                    'SimscapeLogType', 'all', 'SimscapeLogName', 'simlog', 'SimscapeLogLimitData', 'off', ...
                    'ReturnWorkspaceOutputs', 'on', 'SaveTime', 'off', 'SaveOutput', 'off', ...
                    'SaveState', 'off', 'SaveFinalState', 'off');
                set_param(model, 'SimulationCommand', 'update');
                output = sim(model);
                node = simscape.logging.findNode(output.simlog, chamber);
                names = {'T_I', 'p_I', 'rho_I', 'u_I', 'h_I', 'mdot_A', 'Phi_A', 'Q_H'};
                traces = cell(size(names));
                for k = 1:numel(names)
                    series = node.child(names{k}).series;
                    t = double(time(series));
                    traces{k} = struct('name', names{k}, 'unit', series.unit, ...
                        'time_s', t(:), 'values', double(values(series)));
                end
                case_record = struct('source_chamber', source_chamber, 'source_settings', source_settings, ...
                    'volume_m3', volume, 'area_m2', area, 'initial_temperature_K', temperature, ...
                    'initial_pressure_Pa', 1e6, 'heat_source_command_W', -10, 'expected_Q_H_W', 10, ...
                    'stop_s', 1, 'local_solver_enabled', get_param([model '/Solver'], 'UseLocalSolver'), ...
                    'local_solver', get_param([model '/Solver'], 'LocalSolverChoice'), ...
                    'local_step_s', str2double(get_param([model '/Solver'], 'LocalSolverSampleTime')), ...
                    'global_solver', get_param(model, 'Solver'), ...
                    'global_step_s', str2double(get_param(model, 'FixedStep')));
                record_json = jsonencode(case_record);
                save(fullfile(output_root, sprintf('case_%d.mat', numel(record.cases) + 1)), ...
                    'traces', 'record_json', '-v7.3');
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
    fid = fopen(fullfile(output_root, 'isolated_chamber_result.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot save experiment outcome.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('ISOLATED_CHAMBER_COLLECTION_PASS=%d CASES=%d\n', record.collection_pass, numel(record.cases));
    assert(record.collection_pass, 'HeatDriveECC:IsolatedChamberTrialFailed', '%s', record.error_message);
end

function name = only_port(path)
    ports = simscape.connectionPortProperties(path);
    assert(isscalar(ports), 'Expected one connection port at %s.', path);
    name = ports.Name;
end
