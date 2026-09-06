function record = Audit_HeatDriveECC_ConservativeChamber(output_root, physical_path)
% Build and test a diagnostic component without replacing production blocks.
    assert(~isfolder(output_root), 'Do not overwrite an experiment.');
    mkdir(output_root);
    record = struct('schema', 'heatdrive_ecc_conservative_chamber_trial_v1', ...
        'cases', {{}}, 'collection_pass', false, 'error_identifier', '', 'error_message', '', ...
        'source_options_path', physical_path, 'production_model_changed', false, ...
        'production_checkpoint_loaded', false, 'production_recovery_allowed', false);
    old_directory = pwd;
    directory_cleanup = onCleanup(@() cd(old_directory));
    try
        [code, commit] = system('git rev-parse HEAD');
        assert(code == 0, 'Cannot record source commit.');
        record.execution_commit = strtrim(commit);
        [code, dirty] = system('git status --porcelain');
        assert(code == 0 && isempty(strtrim(dirty)), 'Commit source before the experiment.');
        build_directory = fullfile(output_root, 'build');
        mkdir(build_directory);
        package = fullfile(fileparts(mfilename('fullpath')), 'simscape_inventory', '+ecc_inventory');
        copyfile(package, fullfile(build_directory, '+ecc_inventory'));
        cd(build_directory);
        ssc_build('ecc_inventory');
        addpath(build_directory);
        path_cleanup = onCleanup(@() rmpath(build_directory));
        load_system('ecc_inventory_lib');
        library_blocks = find_system('ecc_inventory_lib', 'SearchDepth', 1, 'Type', 'Block');
        library_blocks = setdiff(library_blocks, {'ecc_inventory_lib'});
        assert(isscalar(library_blocks), 'Expected one diagnostic library component.');
        cd(old_directory);
        saved = load(physical_path, 'options');
        [source, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(saved.options);
        source_cleanup = onCleanup(@() close_system(source, 0));
        source_settings = [source '/SMA_ThermalLiquidSettings'];
        solver = find_system(source, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'MaskType', 'Solver Configuration');
        assert(isscalar(solver), 'Require one source solver.');
        volume = saved.options.branch.sma_pump_manifold_volume_m3;
        area = saved.options.branch.connecting_pipe_flow_area_m2;
        for formulation = {'native', 'conservative'}
          for temperature = [300 380]
            for heat_input = [5 -5]
                for step = [.001 .0005 .00025]
                    model = 'ecc_conservative_chamber_trial';
                    assert(~bdIsLoaded(model), 'Trial model already in use.');
                    new_system(model);
                    cleanup = onCleanup(@() close_system(model, 0));
                    chamber = [model '/Chamber'];
                    if strcmp(formulation{1}, 'native')
                        add_block([source '/SMA_PumpInletConnectingPipeVolume'], chamber);
                        set_param(chamber, 'area_A', num2str(area, '%.17g'), 'area_A_unit', 'm^2', ...
                            'area_B', num2str(area, '%.17g'), 'area_B_unit', 'm^2');
                    else
                        add_block(library_blocks{1}, chamber);
                        set_param(chamber, 'area', num2str(area, '%.17g'), 'area_unit', 'm^2');
                    end
                    set_param(chamber, 'volume', num2str(volume, '%.17g'), 'volume_unit', 'm^3', ...
                        'p_I', '2.5', 'p_I_unit', 'MPa', 'p_I_priority', 'High', ...
                        'T_I', num2str(temperature), 'T_I_unit', 'K', 'T_I_priority', 'High');
                    add_block(source_settings, [model '/FluidSettings']);
                    add_block(solver{1}, [model '/Solver']);
                    add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source', [model '/Heat']);
                    add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', [model '/Reference']);
                    add_block('nesl_utility/Simulink-PS Converter', [model '/HeatCommandPS'], 'Unit', 'W');
                    add_block('simulink/Sources/Constant', [model '/HeatCommand'], 'Value', num2str(-heat_input));
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
                    names = {'T_I', 'p_I', 'rho_I', 'u_I', 'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'Q_H'};
                    if strcmp(formulation{1}, 'conservative')
                        names = [names {'stored_mass', 'stored_energy'}];
                    end
                    traces = cell(size(names));
                    for k = 1:numel(names)
                        series = node.child(names{k}).series;
                        t = double(time(series));
                        traces{k} = struct('name', names{k}, 'unit', series.unit, ...
                            'time_s', t(:), 'values', double(values(series)));
                    end
                    case_record = struct('formulation', formulation{1}, 'source_settings', source_settings, 'volume_m3', volume, ...
                        'area_m2', area, 'initial_temperature_K', temperature, 'initial_pressure_Pa', 2.5e6, ...
                        'heat_source_command_W', -heat_input, 'expected_Q_H_W', heat_input, 'stop_s', 1, ...
                        'local_solver_enabled', get_param([model '/Solver'], 'UseLocalSolver'), ...
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
          end
        end
        record.collection_pass = numel(record.cases) == 24;
        clear source_cleanup path_cleanup
    catch exception
        record.error_identifier = exception.identifier;
        record.error_message = exception.message;
    end
    fid = fopen(fullfile(output_root, 'conservative_chamber_result.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot save experiment outcome.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('CONSERVATIVE_CHAMBER_COLLECTION_PASS=%d CASES=%d\n', record.collection_pass, numel(record.cases));
    assert(record.collection_pass, 'HeatDriveECC:ConservativeChamberTrialFailed', '%s', record.error_message);
end

function name = only_port(path)
    ports = simscape.connectionPortProperties(path);
    assert(isscalar(ports), 'Expected one connection port at %s.', path);
    name = ports.Name;
end
