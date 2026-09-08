function record = Run_HeatDriveECC_ConservativeBufferTrial(repo, output_root)
% Independent closed-heat and bidirectional-flow candidate qualification.
    assert(~isfolder(output_root), 'Do not overwrite a trial.');
    [code, commit] = system('git rev-parse HEAD'); assert(code == 0, 'Cannot record source.');
    [code, dirty] = system('git status --porcelain');
    assert(code == 0 && isempty(strtrim(dirty)), 'Commit reviewed source first.');
    mkdir(output_root); diary(fullfile(output_root, 'matlab_diary.log'));
    diary_cleanup = onCleanup(@() diary('off'));
    old = pwd; oldpath = path; path_cleanup = onCleanup(@() restore_path(old, oldpath));
    generation = Simulink.fileGenControl('getConfig');
    generation_cleanup = onCleanup(@() Simulink.fileGenControl('setConfig', 'config', generation));
    Simulink.fileGenControl('set', 'CacheFolder', fullfile(output_root, 'cache'), ...
        'CodeGenFolder', fullfile(output_root, 'codegen'), 'createDir', true);
    record = struct('schema', 'heatdrive_ecc_conservative_buffer_trial_v1', ...
        'execution_commit', strtrim(commit), 'cases', {{}}, 'collection_pass', false, ...
        'error_identifier', '', 'error_message', '', 'production_recovery_allowed', false, ...
        'checkpoint_loaded', false, 'checkpoint_saved', false, 'mainline_model_modified', false, ...
        'auxiliary_capacity_policy', 'constant cold-reference rho*cp*area*0.001; not legacy-equivalent');
    try
        root = fullfile(repo, 'outputs_storage_audit', 'cold_chamber_public_coordinates_cycle_20260909');
        configuration = fullfile(root, 'native', 'configuration.mat');
        record.configuration_sha256 = file_hash(configuration);
        saved = load(configuration, 'options'); options = saved.options;
        options.simulation.persist_model_configuration = false;
        options.simulation.resume_checkpoint_path = '';
        options.branch.independent_conservative_chamber_diagnostic = false;
        record.canonical_model_sha256 = file_hash(options.model_path);
        build = fullfile(output_root, 'component_build'); mkdir(build);
        copyfile(fullfile(repo, 'verification', 'simscape_buffer', '+ecc_buffer'), fullfile(build, '+ecc_buffer'));
        cd(build); ssc_build('ecc_buffer'); addpath(build); load_system('ecc_buffer_lib'); cd(repo);
        lib = find_system('ecc_buffer_lib', 'SearchDepth', 1, 'Type', 'Block');
        lib = setdiff(lib, {'ecc_buffer_lib'}); assert(isscalar(lib), 'Expected one candidate component.');
        [source, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(options);
        source_cleanup = onCleanup(@() close_system(source, 0));
        topology = Export_HeatDriveECC_TLConnectivity(source);
        settings = topology.blocks(cellfun(@(b) strcmp(b.source_file, ...
            'foundation.thermal_liquid.utilities.thermal_liquid_settings'), topology.blocks));
        water = [source '/SMA_ThermalLiquidSettings'];
        setting_paths = cellfun(@(b) b.block_path, settings, 'UniformOutput', false);
        glycol = setdiff(setting_paths, {water});
        assert(numel(settings) == 2 && isscalar(glycol), 'Expected two original fluid domains.');
        setting_names = {glycol{1}, glycol{1}, water, water};
        tank_names = {'ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer'};
        solvers = find_system(source, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'MaskType', 'Solver Configuration');
        assert(isscalar(solvers), 'Expected one source solver configuration.');
        modes = {'heating', 'cooling', 'inflow', 'outflow'};
        heat_inputs = [10, -10, 0, 0]; flows = [0, 0, .001, -.001];
        for k = 1:4
            initial_file = fullfile(repo, 'outputs_storage_audit', 'isolated_tank_step_refinement_20260909', ...
                sprintf('case_%02d.mat', (k-1)*3+1));
            initial = load(initial_file, 'traces');
            temp = initial_value(initial.traces, 'T_I', 'K');
            mass = initial_value(initial.traces, 'mass', 'kg');
            rho = initial_value(initial.traces, 'rho_I', 'kg/m^3');
            u = initial_value(initial.traces, 'u_I', 'J/kg');
            area = .001; gravity = 9.81; pressure = 1e6;
            volume = mass/rho;
            energy = mass*u+pressure*volume+mass*gravity*volume/area/2;
            for j = 1:4
                model = 'ecc_conservative_buffer_trial';
                assert(~bdIsLoaded(model), 'Independent model already loaded.');
                new_system(model); model_cleanup = onCleanup(@() close_system(model, 0));
                tank = [model '/Buffer']; add_block(lib{1}, tank);
                set_param(tank, 'tank_area', '.001', 'tank_area_unit', 'm^2', ...
                    'port_area', '.0001', 'port_area_unit', 'm^2', 'gravity', '9.81', 'gravity_unit', 'm/s^2', ...
                    'p_environment', '1', 'p_environment_unit', 'MPa', ...
                    'reference_temperature', num2str(temp, '%.17g'), 'reference_temperature_unit', 'K', ...
                    'auxiliary_depth', '.001', 'auxiliary_depth_unit', 'm', ...
                    'stored_mass_specify', 'on', 'stored_mass_priority', 'High', 'stored_mass', num2str(mass, '%.17g'), 'stored_mass_unit', 'kg', ...
                    'stored_energy_specify', 'on', 'stored_energy_priority', 'High', 'stored_energy', num2str(energy, '%.17g'), 'stored_energy_unit', 'J', ...
                    'T_I_specify', 'on', 'T_I_priority', 'Low', 'T_I', num2str(temp, '%.17g'), 'T_I_unit', 'K');
                add_block(setting_names{k}, [model '/FluidSettings']); add_block(solvers{1}, [model '/Solver']);
                simscape.addConnection(tank, 'A', [model '/FluidSettings'], only_port([model '/FluidSettings']));
                simscape.addConnection(tank, 'A', [model '/Solver'], only_port([model '/Solver']));
                add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source', [model '/Heat']);
                add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference', [model '/Reference']);
                add_block('nesl_utility/Simulink-PS Converter', [model '/HeatCommandPS'], 'Unit', 'W');
                add_block('simulink/Sources/Constant', [model '/HeatCommand'], 'Value', num2str(-heat_inputs(j)));
                simscape.addConnection(tank, 'H', [model '/Heat'], 'A');
                simscape.addConnection([model '/Heat'], 'B', [model '/Reference'], only_port([model '/Reference']));
                add_line(model, 'HeatCommand/1', 'HeatCommandPS/1');
                ps = get_param([model '/HeatCommandPS'], 'PortHandles'); heat = get_param([model '/Heat'], 'PortHandles');
                add_line(model, ps.RConn(1), heat.RConn(1));
                if flows(j) ~= 0
                    add_block('fl_lib/Thermal Liquid/Sources/Flow Rate Source (TL)', [model '/FlowSource']);
                    set_param([model '/FlowSource'], 'source_type', 'foundation.enum.constant_controlled.constant', ...
                        'flow_type', 'foundation.enum.mass_volumetric_flow.mass', ...
                        'mass_flow', num2str(flows(j), '%.17g'), 'mass_flow_unit', 'kg/s', ...
                        'power_spec', 'foundation.enum.power_spec.none');
                    add_block('fl_lib/Thermal Liquid/Elements/Reservoir (TL)', [model '/Reservoir']);
                    set_param([model '/Reservoir'], 'pressure_spec', 'foundation.enum.pressure_spec.specified', ...
                        'reservoir_pressure', '1', 'reservoir_pressure_unit', 'MPa', ...
                        'reservoir_temperature', num2str(temp+3, '%.17g'), 'reservoir_temperature_unit', 'K');
                    simscape.addConnection([model '/Reservoir'], 'A', [model '/FlowSource'], 'A');
                    simscape.addConnection([model '/FlowSource'], 'B', tank, 'A');
                end
                set_param([model '/Solver'], 'UseLocalSolver', 'on', ...
                    'LocalSolverChoice', 'NE_BACKWARD_EULER_ADVANCER', 'LocalSolverSampleTime', '.001');
                set_param(model, 'Solver', 'ode3', 'FixedStep', '.001', 'StartTime', '0', 'StopTime', '.1', ...
                    'SimscapeLogType', 'all', 'SimscapeLogName', 'simlog', 'SimscapeLogLimitData', 'off', ...
                    'ReturnWorkspaceOutputs', 'on', 'SaveTime', 'off', 'SaveOutput', 'off', ...
                    'LoadInitialState', 'off', 'SaveState', 'off', 'SaveFinalState', 'off');
                output = sim(model); node = simscape.logging.findNode(output.simlog, tank);
                names = {'stored_mass', 'stored_energy', 'T_I', 'p_I', 'p_A', 'rho_I', 'u_I', 'u_port', ...
                    'volume', 'level', 'fluid_internal_energy', 'environment_pv_energy', 'gravitational_energy', ...
                    'auxiliary_energy', 'auxiliary_capacity', 'mdot_A', 'Phi_A', 'Q_H'};
                traces = cell(size(names));
                for n = 1:numel(names)
                    series = node.child(names{n}).series; t = double(time(series));
                    traces{n} = struct('name', names{n}, 'unit', series.unit, 'time_s', t(:), 'values', double(values(series)));
                end
                case_record = struct('source_tank', tank_names{k}, 'source_settings', setting_names{k}, ...
                    'mode', modes{j}, 'initial_source_file', initial_file, 'initial_source_sha256', file_hash(initial_file), ...
                    'initial_temperature_K', temp, 'initial_mass_kg', mass, 'initial_energy_J', energy, ...
                    'area_m2', area, 'port_area_m2', .0001, 'gravity_m_s2', gravity, 'p_environment_Pa', pressure, ...
                    'auxiliary_depth_m', .001, 'heat_into_buffer_W', heat_inputs(j), 'mass_into_buffer_kg_s', flows(j), ...
                    'fixed_step_s', .001, 'stop_s', .1, 'initial_source_time_s', 0);
                record_json = jsonencode(case_record); filename = sprintf('case_%02d.mat', numel(record.cases)+1);
                file = fullfile(output_root, filename); save(file, 'traces', 'record_json', '-v7.3');
                case_record.file = filename; case_record.sha256 = file_hash(file);
                record.cases{end+1} = case_record;
                clear model_cleanup output node traces
            end
        end
        assert(strcmp(file_hash(options.model_path), record.canonical_model_sha256), 'Canonical model changed.');
        record.collection_pass = numel(record.cases) == 16;
        clear source_cleanup
    catch exception
        record.error_identifier = exception.identifier;
        record.error_message = getReport(exception, 'extended', 'hyperlinks', 'off');
    end
    fid = fopen(fullfile(output_root, 'buffer_trial_execution.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot retain outcome.'); file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('%s\n', jsonencode(struct('collection_pass', record.collection_pass, ...
        'completed_cases', numel(record.cases), 'production_recovery_allowed', false)));
    assert(record.collection_pass, 'HeatDriveECC:BufferTrialFailed', '%s', record.error_message);
end

function result = initial_value(rows, name, unit)
    selected = rows(cellfun(@(r) strcmp(r.name, name), rows));
    assert(isscalar(selected) && selected{1}.time_s(1) == 0, 'Require independent cold initial sample.');
    result = value(simscape.Value(selected{1}.values(1), selected{1}.unit), unit);
end

function name = only_port(block)
    ports = simscape.connectionPortProperties(block); assert(isscalar(ports), 'Expected one port.'); name = ports.Name;
end

function hash = file_hash(file)
    digest = java.security.MessageDigest.getInstance('SHA-256'); fid = fopen(file, 'rb'); assert(fid >= 0, 'Missing input.');
    cleanup = onCleanup(@() fclose(fid));
    while ~feof(fid), digest.update(fread(fid, 8*1024*1024, '*uint8')); end
    hash = upper(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
end

function restore_path(folder, oldpath)
    cd(folder); path(oldpath);
end
