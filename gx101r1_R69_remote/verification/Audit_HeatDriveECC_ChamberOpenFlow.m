function record = Audit_HeatDriveECC_ChamberOpenFlow(output_root, physical_path, outlet_area_m2)
% Open-port direction and reversal tests, not a production model restart.
    if nargin < 3
        outlet_area_m2 = 0;
    end
    assert(isscalar(outlet_area_m2) && isfinite(outlet_area_m2) && outlet_area_m2 >= 0, 'Invalid outlet area.');
    assert(~isfolder(output_root), 'Do not overwrite an experiment.');
    mkdir(output_root);
    record = struct('schema', 'heatdrive_ecc_chamber_open_flow_trial_v1', ...
        'cases', {{}}, 'collection_pass', false, 'error_identifier', '', 'error_message', '', ...
        'source_options_path', physical_path, 'production_model_changed', false, ...
        'production_checkpoint_loaded', false, 'production_recovery_allowed', false);
    if outlet_area_m2 > 0
        record.schema = 'heatdrive_ecc_chamber_restricted_flow_trial_v1';
        record.outlet_area_m2 = outlet_area_m2;
    end
    old_directory = pwd;
    directory_cleanup = onCleanup(@() cd(old_directory));
    try
        [code, commit] = system('git rev-parse HEAD');
        assert(code == 0, 'Cannot record source commit.');
        record.execution_commit = strtrim(commit);
        [code, dirty] = system('git status --porcelain');
        assert(code == 0 && isempty(strtrim(dirty)), 'Commit source before experiment.');
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
        assert(isscalar(library_blocks), 'Expected one diagnostic component.');
        cd(old_directory);
        saved = load(physical_path, 'options');
        [source, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(saved.options);
        source_cleanup = onCleanup(@() close_system(source, 0));
        settings = [source '/SMA_ThermalLiquidSettings'];
        solver = find_system(source, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'MaskType', 'Solver Configuration');
        assert(isscalar(solver), 'Require one source solver.');
        volume = saved.options.branch.sma_pump_manifold_volume_m3;
        area = saved.options.branch.connecting_pipe_flow_area_m2;
        assert(outlet_area_m2 < area, 'Restriction must be smaller than the port.');
        for formulation = {'native', 'conservative'}
          for mode = {'forward', 'reverse', 'reversal'}
            for step = [.001 .0005 .00025]
                model = 'ecc_chamber_open_flow_trial';
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
                    'p_I_specify', 'on', 'T_I_specify', 'on', ...
                    'p_I', '2.5', 'p_I_unit', 'MPa', 'p_I_priority', 'High', ...
                    'T_I', '340', 'T_I_unit', 'K', 'T_I_priority', 'High');
                add_block(settings, [model '/FluidSettings']);
                add_block(solver{1}, [model '/Solver']);
                add_block('fl_lib/Thermal Liquid/Sources/Flow Rate Source (TL)', [model '/FlowSource']);
                set_param([model '/FlowSource'], 'source_type', 'foundation.enum.constant_controlled.controlled', ...
                    'flow_type', 'foundation.enum.mass_volumetric_flow.mass', ...
                    'power_spec', 'foundation.enum.power_spec.isentropic', 'area', num2str(area, '%.17g'), 'area_unit', 'm^2');
                for reservoir = {'HotReservoir', 'ColdReservoir'}
                    path = [model '/' reservoir{1}];
                    add_block('fl_lib/Thermal Liquid/Elements/Reservoir (TL)', path);
                    temperature = 300 + 80 * strcmp(reservoir{1}, 'HotReservoir');
                    set_param(path, 'pressure_spec', 'foundation.enum.pressure_spec.specified', ...
                        'reservoir_pressure', '2.5', 'reservoir_pressure_unit', 'MPa', ...
                        'reservoir_temperature', num2str(temperature), 'reservoir_temperature_unit', 'K', ...
                        'area', num2str(area, '%.17g'), 'area_unit', 'm^2');
                end
                add_block('nesl_utility/Simulink-PS Converter', [model '/FlowCommandPS'], 'Unit', 'kg/s');
                if strcmp(mode{1}, 'reversal')
                    add_block('simulink/Sources/Step', [model '/FlowCommand'], ...
                        'Time', '.5', 'Before', '.0002', 'After', '-.0002');
                else
                    rate = .0002 * (1 - 2 * strcmp(mode{1}, 'reverse'));
                    add_block('simulink/Sources/Constant', [model '/FlowCommand'], 'Value', num2str(rate, '%.17g'));
                end
                add_line(model, 'FlowCommand/1', 'FlowCommandPS/1');
                ps = get_param([model '/FlowCommandPS'], 'PortHandles');
                port = simscape.connectionPortProperties([model '/FlowSource']);
                input = port(arrayfun(@(p) strcmp(char(p.Name), 'M'), port));
                assert(isscalar(input), 'Expected one mass-flow command port.');
                % The physical input is located by the public port mapper.
                scratch = 'ecc_open_flow_port_map';
                assert(~bdIsLoaded(scratch), 'Port-map scratch model already in use.');
                new_system(scratch);
                scratch_cleanup = onCleanup(@() close_system(scratch, 0));
                mapped = Map_HeatDriveECC_PhysicalPortHandles([model '/FlowSource'], scratch, ...
                    'foundation.thermal_liquid.thermal_liquid');
                handles = get_param([model '/FlowSource'], 'PortHandles');
                selected = setdiff([handles.LConn(:); handles.RConn(:)], cellfun(@(row) row.handle, mapped));
                assert(numel(mapped) == 2 && isscalar(selected), 'Expected exactly two liquid ports and one control input.');
                add_line(model, ps.RConn(1), selected);
                clear scratch_cleanup
                simscape.addConnection([model '/HotReservoir'], 'A', [model '/FlowSource'], 'A');
                simscape.addConnection([model '/FlowSource'], 'B', chamber, 'A');
                if outlet_area_m2 > 0
                    restriction = [model '/OutletRestriction'];
                    add_block('fl_lib/Thermal Liquid/Elements/Local Restriction (TL)', restriction);
                    set_param(restriction, 'restriction_type', 'foundation.enum.restriction_type.fixed', ...
                        'restriction_area', num2str(outlet_area_m2, '%.17g'), 'restriction_area_unit', 'm^2', ...
                        'area', num2str(area, '%.17g'), 'area_unit', 'm^2', 'Cd', '.64', 'Re_c', '150');
                    simscape.addConnection(chamber, 'B', restriction, 'A');
                    simscape.addConnection(restriction, 'B', [model '/ColdReservoir'], 'A');
                else
                    simscape.addConnection(chamber, 'B', [model '/ColdReservoir'], 'A');
                end
                simscape.addConnection(chamber, 'A', [model '/FluidSettings'], only_port([model '/FluidSettings']));
                simscape.addConnection(chamber, 'A', [model '/Solver'], only_port([model '/Solver']));
                set_param([model '/Solver'], 'UseLocalSolver', 'on', ...
                    'LocalSolverChoice', 'NE_BACKWARD_EULER_ADVANCER', ...
                    'LocalSolverSampleTime', num2str(step, '%.17g'));
                set_param(model, 'Solver', 'ode3', 'FixedStep', num2str(step, '%.17g'), 'StopTime', '1', ...
                    'SimscapeLogType', 'all', 'SimscapeLogName', 'simlog', 'SimscapeLogLimitData', 'off', ...
                    'ReturnWorkspaceOutputs', 'on', 'SaveTime', 'off', 'SaveOutput', 'off', ...
                    'SaveState', 'off', 'SaveFinalState', 'off');
                set_param(model, 'SimulationCommand', 'update');
                output = sim(model);
                if strcmp(formulation{1}, 'conservative')
                    names = {'T_I', 'p_I', 'rho_I', 'u_I', 'mdot_A', 'mdot_B', ...
                        'Phi_A', 'Phi_B', 'Q_H', 'stored_mass', 'stored_energy'};
                else
                    names = {'T_I', 'p_I', 'rho_I', 'u_I', 'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'Q_H'};
                end
                chamber_node = simscape.logging.findNode(output.simlog, chamber);
                source_names = {'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'power'};
                if outlet_area_m2 > 0
                    source_names = [source_names, {'rho_A', 'rho_B'}];
                end
                packets = {extract(chamber_node, 'chamber', names), ...
                    extract(simscape.logging.findNode(output.simlog, [model '/FlowSource']), ...
                        'flow_source', source_names), ...
                    extract(simscape.logging.findNode(output.simlog, [model '/HotReservoir']), ...
                        'hot_reservoir', {'mdot_A', 'Phi_A', 'p_I', 'T_I'}), ...
                    extract(simscape.logging.findNode(output.simlog, [model '/ColdReservoir']), ...
                        'cold_reservoir', {'mdot_A', 'Phi_A', 'p_I', 'T_I'})};
                if outlet_area_m2 > 0
                    packets{end+1} = extract(simscape.logging.findNode(output.simlog, restriction), ...
                        'outlet_restriction', {'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B'});
                end
                case_record = struct('formulation', formulation{1}, 'mode', mode{1}, ...
                    'source_settings', settings, 'volume_m3', volume, 'area_m2', area, ...
                    'initial_temperature_K', 340, 'pressure_Pa', 2.5e6, ...
                    'hot_reservoir_K', 380, 'cold_reservoir_K', 300, 'flow_magnitude_kg_s', .0002, ...
                    'reversal_time_s', .5, 'stop_s', 1, ...
                    'local_solver_enabled', get_param([model '/Solver'], 'UseLocalSolver'), ...
                    'local_solver', get_param([model '/Solver'], 'LocalSolverChoice'), ...
                    'local_step_s', str2double(get_param([model '/Solver'], 'LocalSolverSampleTime')), ...
                    'global_solver', get_param(model, 'Solver'), ...
                    'global_step_s', str2double(get_param(model, 'FixedStep')));
                if outlet_area_m2 > 0
                    case_record.boundary_mode = 'finite_outlet_restriction';
                    case_record.outlet_area_m2 = str2double(get_param(restriction, 'restriction_area'));
                    case_record.restriction_type = get_param(restriction, 'restriction_type');
                    case_record.discharge_coefficient = str2double(get_param(restriction, 'Cd'));
                    case_record.critical_reynolds_number = str2double(get_param(restriction, 'Re_c'));
                    case_record.pressure_recovery = get_param(restriction, 'pressure_recovery');
                end
                record_json = jsonencode(case_record);
                save(fullfile(output_root, sprintf('case_%d.mat', numel(record.cases) + 1)), 'packets', 'record_json', '-v7.3');
                record.cases{end + 1} = case_record;
                assert(abs(first_si(chamber_node, 'T_I', 'K')-340) <= 1e-9 && ...
                    abs(first_si(chamber_node, 'p_I', 'Pa')-2.5e6) <= 1e-4, ...
                    'HeatDriveECC:InitialTrialStateMismatch', 'Actual initial state is not paired.');
                clear cleanup output packets
            end
          end
        end
        record.collection_pass = numel(record.cases) == 18;
        clear source_cleanup path_cleanup
    catch exception
        record.error_identifier = exception.identifier;
        record.error_message = exception.message;
        record.error_report = getReport(exception, 'extended', 'hyperlinks', 'off');
    end
    fid = fopen(fullfile(output_root, 'open_flow_result.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot retain experiment outcome.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('OPEN_FLOW_COLLECTION_PASS=%d CASES=%d\n', record.collection_pass, numel(record.cases));
    assert(record.collection_pass, 'HeatDriveECC:OpenFlowTrialFailed', '%s', record.error_message);
end

function packet = extract(node, role, names)
    traces = cell(size(names));
    for k = 1:numel(names)
        series = node.child(names{k}).series;
        t = double(time(series));
        traces{k} = struct('name', names{k}, 'unit', series.unit, ...
            'time_s', t(:), 'values', double(values(series)));
    end
    packet = struct('role', role, 'traces', {traces});
end

function name = only_port(path)
    ports = simscape.connectionPortProperties(path);
    assert(isscalar(ports), 'Expected one connection port at %s.', path);
    name = ports.Name;
end

function number = first_si(node, name, unit)
    series = node.child(name).series;
    numbers = double(values(series));
    quantity = simscape.Value(numbers(1), series.unit);
    number = value(quantity, unit);
end
