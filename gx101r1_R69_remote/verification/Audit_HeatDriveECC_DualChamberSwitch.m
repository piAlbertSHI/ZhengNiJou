function record = Audit_HeatDriveECC_DualChamberSwitch(output_root, physical_path)
% Test the pressure-coupled pump pair with copied production route valves.
    assert(~isfolder(output_root), 'Do not overwrite an experiment.');
    mkdir(output_root);
    record = struct('schema', 'heatdrive_ecc_dual_chamber_switch_trial_v1', ...
        'source_options_path', physical_path, 'cases', {{}}, 'collection_pass', false, ...
        'production_model_changed', false, 'production_checkpoint_loaded', false, ...
        'production_recovery_allowed', false, 'error_message', '');
    old = pwd;
    directory_cleanup = onCleanup(@() cd(old));
    try
        [code, commit] = system('git rev-parse HEAD');
        assert(code == 0, 'Cannot identify source commit.');
        record.execution_commit = strtrim(commit);
        [code, dirty] = system('git status --porcelain');
        assert(code == 0 && isempty(strtrim(dirty)), 'Commit source before execution.');
        build = fullfile(output_root, 'build');
        mkdir(build);
        package = fullfile(fileparts(mfilename('fullpath')), 'simscape_inventory', '+ecc_inventory');
        copyfile(package, fullfile(build, '+ecc_inventory'));
        cd(build);
        ssc_build('ecc_inventory');
        addpath(build);
        path_cleanup = onCleanup(@() rmpath(build));
        load_system('ecc_inventory_lib');
        blocks = find_system('ecc_inventory_lib', 'SearchDepth', 1, 'Type', 'Block');
        blocks = setdiff(blocks, {'ecc_inventory_lib'});
        assert(isscalar(blocks), 'Expected one conservative component.');
        cd(old);
        saved = load(physical_path, 'options');
        [source, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(saved.options);
        source_cleanup = onCleanup(@() close_system(source, 0));
        solver = find_system(source, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'MaskType', 'Solver Configuration');
        assert(isscalar(solver), 'Expected one physical solver.');
        volume = saved.options.branch.sma_pump_manifold_volume_m3;
        area = saved.options.branch.connecting_pipe_flow_area_m2;
        valves = {'SMA_V1_SHEX_to_pump', 'SMA_V2_HHEX_to_pump', ...
            'SMA_V3_pump_to_heat_path', 'SMA_V4_pump_to_cool_path'};
        record.source_valve_parameters = cell(1, 4);
        for j = 1:4
            record.source_valve_parameters{j} = parameters([source '/' valves{j}]);
        end
        record.source_pressure_parameters = parameters([source '/SMA Pressure Source (TL)']);
        for formulation = {'native', 'conservative'}
          for power_mode = {'none', 'isentropic'}
            for step = [.001 .0005 .00025]
                model = 'ecc_dual_chamber_switch_trial';
                assert(~bdIsLoaded(model), 'Trial model already in use.');
                new_system(model);
                cleanup = onCleanup(@() close_system(model, 0));
                names = {'Inlet', 'Outlet'};
                for j = 1:2
                    chamber = [model '/' names{j}];
                    if strcmp(formulation{1}, 'native')
                        add_block([source '/SMA_Pump' names{j} 'ConnectingPipeVolume'], chamber);
                        set_param(chamber, 'area_A', num2str(area, '%.17g'), 'area_A_unit', 'm^2', ...
                            'area_B', num2str(area, '%.17g'), 'area_B_unit', 'm^2');
                    else
                        add_block(blocks{1}, chamber);
                        set_param(chamber, 'area', num2str(area, '%.17g'), 'area_unit', 'm^2');
                    end
                    set_param(chamber, 'volume', num2str(volume, '%.17g'), 'volume_unit', 'm^3', ...
                        'p_I_specify', 'on', 'T_I_specify', 'on', ...
                        'p_I', '2.5', 'p_I_unit', 'MPa', 'p_I_priority', 'High', ...
                        'T_I', '340', 'T_I_unit', 'K', 'T_I_priority', 'High');
                end
                add_block([source '/SMA_ThermalLiquidSettings'], [model '/FluidSettings']);
                add_block(solver{1}, [model '/Solver']);
                add_block([source '/SMA Pressure Source (TL)'], [model '/Pump']);
                set_param([model '/Pump'], 'power_spec', ['foundation.enum.power_spec.' power_mode{1}]);
                add_command(model, 'Pump', 'Pressure', 'Pa', .01, 0, 260);
                for j = 1:4
                    block = sprintf('%s/V%d', model, j);
                    add_block([source '/' valves{j}], block);
                    hot = mod(j, 2) == 1;
                    add_command(model, sprintf('V%d', j), sprintf('Valve%d', j), '1', .5, double(hot), double(~hot));
                end
                for j = 1:2
                    reservoir = [model '/' names{j} 'Reservoir'];
                    add_block('fl_lib/Thermal Liquid/Elements/Reservoir (TL)', reservoir);
                    set_param(reservoir, 'pressure_spec', 'foundation.enum.pressure_spec.specified', ...
                        'reservoir_pressure', '2.5', 'reservoir_pressure_unit', 'MPa', ...
                        'reservoir_temperature', num2str(380-80*(j-1)), 'reservoir_temperature_unit', 'K', ...
                        'area', num2str(area, '%.17g'), 'area_unit', 'm^2');
                end
                simscape.addConnection([model '/InletReservoir'], 'A', [model '/V1'], 'A');
                simscape.addConnection([model '/InletReservoir'], 'A', [model '/V3'], 'B');
                simscape.addConnection([model '/OutletReservoir'], 'A', [model '/V2'], 'A');
                simscape.addConnection([model '/OutletReservoir'], 'A', [model '/V4'], 'B');
                simscape.addConnection([model '/V1'], 'B', [model '/Inlet'], 'A');
                simscape.addConnection([model '/V2'], 'B', [model '/Inlet'], 'A');
                simscape.addConnection([model '/Inlet'], 'B', [model '/Pump'], 'A');
                simscape.addConnection([model '/Pump'], 'B', [model '/Outlet'], 'A');
                simscape.addConnection([model '/Outlet'], 'B', [model '/V3'], 'A');
                simscape.addConnection([model '/Outlet'], 'B', [model '/V4'], 'A');
                simscape.addConnection([model '/Inlet'], 'A', [model '/FluidSettings'], only_port([model '/FluidSettings']));
                simscape.addConnection([model '/Inlet'], 'A', [model '/Solver'], only_port([model '/Solver']));
                set_param([model '/Solver'], 'UseLocalSolver', 'on', 'LocalSolverChoice', 'NE_BACKWARD_EULER_ADVANCER', ...
                    'LocalSolverSampleTime', num2str(step, '%.17g'));
                set_param(model, 'Solver', 'ode3', 'FixedStep', num2str(step, '%.17g'), 'StopTime', '1', ...
                    'SimscapeLogType', 'all', 'SimscapeLogName', 'simlog', 'SimscapeLogLimitData', 'off', ...
                    'ReturnWorkspaceOutputs', 'on', 'SaveTime', 'off', 'SaveOutput', 'off', 'SaveState', 'off', 'SaveFinalState', 'off');
                set_param(model, 'SimulationCommand', 'update');
                output = sim(model);
                fields = {'T_I', 'p_I', 'rho_I', 'u_I', 'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'Q_H'};
                if strcmp(formulation{1}, 'conservative')
                    fields = {'T_I', 'p_I', 'rho_I', 'u_I', 'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'Q_H', 'stored_mass', 'stored_energy'};
                end
                packets = cell(1, 9);
                for j = 1:2
                    packets{j} = extract(simscape.logging.findNode(output.simlog, [model '/' names{j}]), lower(names{j}), fields);
                end
                packets{3} = extract(simscape.logging.findNode(output.simlog, [model '/Pump']), 'pump', ...
                    {'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'power', 'rho_A', 'rho_B'});
                for j = 1:4
                    packets{3+j} = extract(simscape.logging.findNode(output.simlog, sprintf('%s/V%d', model, j)), ...
                        sprintf('v%d', j), {'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B'});
                end
                for j = 1:2
                    packets{7+j} = extract(simscape.logging.findNode(output.simlog, [model '/' names{j} 'Reservoir']), ...
                        [lower(names{j}) '_reservoir'], {'mdot_A', 'Phi_A', 'p_I', 'T_I'});
                end
                case_record = struct('formulation', formulation{1}, 'power_mode', power_mode{1}, 'local_step_s', step, ...
                    'volume_each_m3', volume, 'area_m2', area, 'initial_temperature_K', 340, 'initial_pressure_Pa', 2.5e6, ...
                    'hot_reservoir_K', 380, 'cold_reservoir_K', 300, 'reservoir_pressure_Pa', 2.5e6, ...
                    'pressure_step_time_s', .01, 'command_pressure_Pa', 260, 'route_switch_time_s', .5, 'stop_s', 1, ...
                    'local_solver', get_param([model '/Solver'], 'LocalSolverChoice'), ...
                    'global_solver', get_param(model, 'Solver'), 'global_step_s', str2double(get_param(model, 'FixedStep')));
                record_json = jsonencode(case_record);
                save(fullfile(output_root, sprintf('case_%d.mat', numel(record.cases)+1)), 'packets', 'record_json', '-v7.3');
                record.cases{end+1} = case_record;
                for j = 1:2
                    node = simscape.logging.findNode(output.simlog, [model '/' names{j}]);
                    assert(abs(first_si(node, 'T_I', 'K')-340) < 1e-9 && abs(first_si(node, 'p_I', 'Pa')-2.5e6) < 1e-4, ...
                        'HeatDriveECC:InitialTrialStateMismatch', 'Unpaired actual initial state.');
                end
                clear cleanup output packets
            end
          end
        end
        record.collection_pass = numel(record.cases) == 12;
        clear source_cleanup path_cleanup
    catch exception
        record.error_identifier = exception.identifier;
        record.error_message = exception.message;
        record.error_report = getReport(exception, 'extended', 'hyperlinks', 'off');
    end
    fid = fopen(fullfile(output_root, 'dual_switch_result.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot retain experiment outcome.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('DUAL_SWITCH_COLLECTION_PASS=%d CASES=%d\n', record.collection_pass, numel(record.cases));
    assert(record.collection_pass, 'HeatDriveECC:DualSwitchTrialFailed', '%s', record.error_message);
end

function add_command(model, block_name, command_name, unit, switch_time, before, after)
    ps = [model '/' command_name 'PS'];
    command_path = [model '/' command_name 'Command'];
    add_block('nesl_utility/Simulink-PS Converter', ps, 'Unit', unit);
    add_block('simulink/Sources/Step', command_path, 'Time', num2str(switch_time), ...
        'Before', num2str(before), 'After', num2str(after));
    add_line(model, [command_name 'Command/1'], [command_name 'PS/1']);
    scratch = 'ecc_dual_switch_port_map';
    new_system(scratch);
    cleanup = onCleanup(@() close_system(scratch, 0));
    block = [model '/' block_name];
    mapped = Map_HeatDriveECC_PhysicalPortHandles(block, scratch, 'foundation.thermal_liquid.thermal_liquid');
    handles = get_param(block, 'PortHandles');
    input = setdiff([handles.LConn(:); handles.RConn(:)], cellfun(@(row) row.handle, mapped));
    assert(numel(mapped) == 2 && isscalar(input), 'Require two TL ports and one control.');
    ps_handles = get_param(ps, 'PortHandles');
    add_line(model, ps_handles.RConn(1), input);
end

function packet = extract(node, role, names)
    traces = cell(size(names));
    for k = 1:numel(names)
        series = node.child(names{k}).series;
        t = double(time(series));
        traces{k} = struct('name', names{k}, 'unit', series.unit, 'time_s', t(:), 'values', double(values(series)));
    end
    packet = struct('role', role, 'traces', {traces});
end

function name = only_port(path)
    ports = simscape.connectionPortProperties(path);
    assert(isscalar(ports), 'Require one physical port.');
    name = ports.Name;
end

function number = first_si(node, name, unit)
    series = node.child(name).series;
    numbers = double(values(series));
    number = value(simscape.Value(numbers(1), series.unit), unit);
end

function result = parameters(path)
    names = fieldnames(get_param(path, 'DialogParameters'));
    result = struct('path', path, 'values', struct());
    for j = 1:numel(names)
        result.values.(names{j}) = get_param(path, names{j});
    end
end
