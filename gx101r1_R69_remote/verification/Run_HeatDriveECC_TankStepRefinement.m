function record = Run_HeatDriveECC_TankStepRefinement(repo, output_root)
% Independent closed-tank heat tests, never a production restart or correction.
    assert(~isfolder(output_root), 'Do not overwrite a trial.');
    [code, commit] = system('git rev-parse HEAD');
    assert(code == 0, 'Cannot record source commit.');
    [code, dirty] = system('git status --porcelain');
    assert(code == 0 && isempty(strtrim(dirty)), 'Commit reviewed source first.');
    mkdir(output_root);
    diary(fullfile(output_root, 'matlab_diary.log'));
    diary_cleanup = onCleanup(@() diary('off'));
    generation = Simulink.fileGenControl('getConfig');
    generation_cleanup = onCleanup(@() Simulink.fileGenControl('setConfig', 'config', generation));
    Simulink.fileGenControl('set', 'CacheFolder', fullfile(output_root, 'cache'), ...
        'CodeGenFolder', fullfile(output_root, 'codegen'), 'createDir', true);
    record = struct('schema', 'heatdrive_ecc_tank_step_refinement_v1', ...
        'execution_commit', strtrim(commit), 'cases', {{}}, 'collection_pass', false, ...
        'error_identifier', '', 'error_message', '', 'production_recovery_allowed', false, ...
        'checkpoint_loaded', false, 'checkpoint_saved', false, ...
        'model_or_property_correction_applied', false, 'time_step_convergence_verified', false);
    try
        root = fullfile(repo, 'outputs_storage_audit', 'cold_chamber_public_coordinates_cycle_20260909');
        configuration = fullfile(root, 'native', 'configuration.mat');
        record.configuration_sha256 = file_hash(configuration);
        saved = load(configuration, 'options');
        options = saved.options;
        options.simulation.persist_model_configuration = false;
        options.simulation.resume_checkpoint_path = '';
        options.branch.independent_conservative_chamber_diagnostic = false;
        record.canonical_model_sha256 = file_hash(options.model_path);
        [source, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(options);
        source_cleanup = onCleanup(@() close_system(source, 0));
        topology = Export_HeatDriveECC_TLConnectivity(source);
        settings = topology.blocks(cellfun(@(b) strcmp(b.source_file, ...
            'foundation.thermal_liquid.utilities.thermal_liquid_settings'), topology.blocks));
        assert(numel(settings) == 2, 'Expected two fluid tables.');
        water = [source '/SMA_ThermalLiquidSettings'];
        setting_paths = cellfun(@(b) b.block_path, settings, 'UniformOutput', false);
        glycol = setdiff(setting_paths, {water});
        assert(isscalar(glycol), 'Expected one glycol domain.');
        solvers = find_system(source, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'MaskType', 'Solver Configuration');
        assert(isscalar(solvers), 'Expected one source solver configuration.');
        tank_names = {'ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer'};
        setting_names = {glycol{1}, glycol{1}, water, water};
        temperatures = [276.95, 303.15, 393.15, 303.15];
        steps = [.001, .0005, .00025];
        for k = 1:numel(tank_names)
            for dt = steps
                model = 'ecc_tank_step_refinement';
                assert(~bdIsLoaded(model), 'Independent model name already in use.');
                new_system(model);
                model_cleanup = onCleanup(@() close_system(model, 0));
                tank = [model '/Tank'];
                add_block([source '/' tank_names{k}], tank);
                add_block(setting_names{k}, [model '/FluidSettings']);
                add_block(solvers{1}, [model '/Solver']);
                add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source', [model '/Heat']);
                add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', [model '/Reference']);
                add_block('nesl_utility/Simulink-PS Converter', [model '/HeatCommandPS'], 'Unit', 'W');
                % Heat A is connected to tank H: negative source command heats tank.
                add_block('simulink/Sources/Constant', [model '/HeatCommand'], 'Value', '-10');
                set_param(tank, 'tank_area', '.001', 'tank_area_unit', 'm^2', ...
                    'level', '.1', 'level_unit', 'm', 'T_I', num2str(temperatures(k), '%.17g'), ...
                    'T_I_unit', 'K', 'tank_pressure', '1', 'tank_pressure_unit', 'MPa');
                simscape.addConnection(tank, 'A', [model '/FluidSettings'], only_port([model '/FluidSettings']));
                simscape.addConnection(tank, 'A', [model '/Solver'], only_port([model '/Solver']));
                simscape.addConnection(tank, 'H', [model '/Heat'], 'A');
                simscape.addConnection([model '/Heat'], 'B', [model '/Reference'], only_port([model '/Reference']));
                add_line(model, 'HeatCommand/1', 'HeatCommandPS/1');
                ps = get_param([model '/HeatCommandPS'], 'PortHandles');
                heat = get_param([model '/Heat'], 'PortHandles');
                add_line(model, ps.RConn(1), heat.RConn(1));
                step_text = num2str(dt, '%.17g');
                set_param([model '/Solver'], 'UseLocalSolver', 'on', ...
                    'LocalSolverChoice', 'NE_BACKWARD_EULER_ADVANCER', 'LocalSolverSampleTime', step_text);
                set_param(model, 'Solver', 'ode3', 'FixedStep', step_text, 'StartTime', '0', 'StopTime', '.1', ...
                    'SimscapeLogType', 'all', 'SimscapeLogName', 'simlog', 'SimscapeLogLimitData', 'off', ...
                    'ReturnWorkspaceOutputs', 'on', 'SaveTime', 'off', 'SaveOutput', 'off', ...
                    'LoadInitialState', 'off', 'SaveState', 'off', 'SaveFinalState', 'off');
                output = sim(model);
                node = simscape.logging.findNode(output.simlog, tank);
                names = {'mass', 'volume', 'T_I', 'p_I', 'rho_I', 'u_I', 'h_I', 'mdot_A', 'Phi_A', 'Q_H'};
                traces = cell(size(names));
                for j = 1:numel(names)
                    series = node.child(names{j}).series;
                    t = double(time(series));
                    traces{j} = struct('name', names{j}, 'unit', series.unit, ...
                        'time_s', t(:), 'values', double(values(series)));
                end
                case_record = struct('source_tank', tank_names{k}, 'source_settings', setting_names{k}, ...
                    'area_m2', .001, 'initial_volume_m3', .0001, 'initial_temperature_K', temperatures(k), ...
                    'heat_into_tank_W', 10, 'command_W', -10, 'fixed_step_s', dt, 'stop_s', .1, ...
                    'local_solver', 'NE_BACKWARD_EULER_ADVANCER', 'closed_mass_port', true);
                record_json = jsonencode(case_record);
                filename = sprintf('case_%02d.mat', numel(record.cases)+1);
                file = fullfile(output_root, filename);
                save(file, 'traces', 'record_json', '-v7.3');
                case_record.file = filename;
                case_record.sha256 = file_hash(file);
                record.cases{end+1} = case_record;
                clear model_cleanup output node traces
            end
        end
        assert(strcmp(file_hash(options.model_path), record.canonical_model_sha256), 'Canonical model changed.');
        record.collection_pass = numel(record.cases) == 12;
        clear source_cleanup
    catch exception
        record.error_identifier = exception.identifier;
        record.error_message = getReport(exception, 'extended', 'hyperlinks', 'off');
    end
    fid = fopen(fullfile(output_root, 'tank_step_execution.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot retain outcome.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('%s\n', jsonencode(struct('collection_pass', record.collection_pass, ...
        'completed_cases', numel(record.cases), 'production_recovery_allowed', false)));
    assert(record.collection_pass, 'HeatDriveECC:TankStepFailed', '%s', record.error_message);
end

function name = only_port(block)
    ports = simscape.connectionPortProperties(block);
    assert(isscalar(ports), 'Expected one port.');
    name = ports.Name;
end

function hash = file_hash(file)
    digest = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(file, 'rb'); assert(fid >= 0, 'Cannot read input.');
    cleanup = onCleanup(@() fclose(fid));
    while ~feof(fid), digest.update(fread(fid, 8*1024*1024, '*uint8')); end
    hash = upper(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
end
