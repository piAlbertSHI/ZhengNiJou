function record = Audit_HeatDriveECC_DualChamberSwitch(output_root, physical_path, separate_boundaries, collect_failure_matrix, valve_transition_s, index_reduction, solver_tolerance, pipe_model, ablation_mode)
% Test the pressure-coupled pump pair with copied production route valves.
    if nargin < 3
        separate_boundaries = false;
    end
    assert(islogical(separate_boundaries) && isscalar(separate_boundaries), 'Require a logical boundary mode.');
    if nargin < 4
        collect_failure_matrix = false;
    end
    assert(islogical(collect_failure_matrix) && isscalar(collect_failure_matrix), 'Require a logical diagnostic mode.');
    if nargin < 5
        valve_transition_s = 0;
    end
    assert(isscalar(valve_transition_s) && isfinite(valve_transition_s) && valve_transition_s >= 0 && ...
        valve_transition_s <= .1, 'Invalid diagnostic valve transition.');
    if nargin < 6
        index_reduction = '';
    end
    assert(ischar(index_reduction) && ismember(index_reduction, {'', 'DerivativeReplacement', 'Projection'}), ...
        'Unsupported diagnostic index reduction.');
    if nargin < 7
        solver_tolerance = [];
    end
    assert(isempty(solver_tolerance) || (isscalar(solver_tolerance) && isfinite(solver_tolerance) && ...
        solver_tolerance > 0 && solver_tolerance <= .001), 'Invalid diagnostic solver tolerance.');
    if nargin < 8
        pipe_model = false;
    end
    if nargin < 9
        ablation_mode = '';
    end
    assert(ischar(ablation_mode) && ismember(ablation_mode, {'', 'no_friction_long_port', 'friction_short_port'}), ...
        'Unsupported diagnostic ablation.');
    if ~isempty(ablation_mode)
        assert(pipe_model && valve_transition_s == 0, 'Ablation requires the explicit hard-switch pipe baseline.');
    end
    assert(islogical(pipe_model) && isscalar(pipe_model), 'Require explicit pipe diagnostic mode.');
    if pipe_model
        assert(separate_boundaries && ismember(valve_transition_s, [0 .01]) && ...
            strcmp(index_reduction, 'DerivativeReplacement') && isequal(solver_tolerance, 1e-12), ...
            'Pipe comparison requires the explicit tight hard/finite-switch baseline.');
    end
    assert(~isfolder(output_root), 'Do not overwrite an experiment.');
    mkdir(output_root);
    record = struct('schema', 'heatdrive_ecc_dual_chamber_switch_trial_v1', ...
        'source_options_path', physical_path, 'cases', {{}}, 'collection_pass', false, ...
        'production_model_changed', false, 'production_checkpoint_loaded', false, ...
        'production_recovery_allowed', false, 'error_message', '');
    if separate_boundaries
        record.schema = 'heatdrive_ecc_dual_chamber_switch_trial_v2';
    end
    if valve_transition_s > 0
        assert(separate_boundaries, 'Finite-transition trials require separated boundaries.');
        record.schema = 'heatdrive_ecc_dual_chamber_switch_trial_v3';
        record.valve_transition_s = valve_transition_s;
    end
    if ~isempty(index_reduction)
        assert(valve_transition_s > 0 || pipe_model, 'Index-reduction comparison requires an explicit transition contract.');
        record.schema = 'heatdrive_ecc_dual_chamber_switch_trial_v4';
        record.index_reduction = index_reduction;
    end
    if ~isempty(solver_tolerance)
        assert(~isempty(index_reduction), 'Tolerance comparison requires explicit index reduction.');
        record.schema = 'heatdrive_ecc_dual_chamber_switch_trial_v5';
        record.solver_tolerance = solver_tolerance;
    end
    if pipe_model
        record.schema = 'heatdrive_ecc_dual_chamber_switch_trial_v6';
        if valve_transition_s == 0
            record.schema = 'heatdrive_ecc_dual_chamber_switch_trial_v7';
        end
        record.valve_transition_s = valve_transition_s;
        record.pipe_model = true;
        record.pipe_contract = struct('length_m', .2, 'diameter_m', .0032, ...
            'roughness_m', 15e-6, 'roughness_source', 'explicit Foundation Pipe TL default, not a Qian measured value', ...
            'length_add_m', 0, 'Re_lam', 2000, 'Re_tur', 4000, 'shape_factor', 64, ...
            'inertia', false, 'wall_heat_flow_W', 0, 'production_qualification', false);
    end
    record.collect_failure_matrix = collect_failure_matrix;
    formulations = {'native', 'conservative'};
    expected_cases = 12;
    if ~isempty(ablation_mode)
        record.schema = 'heatdrive_ecc_dual_chamber_switch_trial_v8';
        record.ablation_mode = ablation_mode;
        record.friction_scale = double(strcmp(ablation_mode, 'friction_short_port'));
        record.convection_length_m = .1;
        if record.friction_scale == 1
            record.convection_length_m = .0032;
        end
        formulations = {'conservative'};
        expected_cases = 6;
    end
    record.failed_cases = {};
    attempted = 0;
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
        if pipe_model
            package = fullfile(fileparts(mfilename('fullpath')), 'simscape_inventory_pipe', '+ecc_inventory');
        end
        if ~isempty(ablation_mode)
            package = fullfile(fileparts(mfilename('fullpath')), 'simscape_inventory_ablation', '+ecc_inventory');
        end
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
        record.source_solver_parameters = parameters(solver{1});
        volume = saved.options.branch.sma_pump_manifold_volume_m3;
        area = saved.options.branch.connecting_pipe_flow_area_m2;
        if pipe_model
            assert(abs(saved.options.branch.connecting_pipe_length_m-.2) < 1e-12 && ...
                abs(saved.options.branch.connecting_pipe_diameter_m-.0032) < 1e-12 && ...
                abs(volume-area*.2) < 1e-15, 'Pipe geometry differs from the frozen article contract.');
        end
        valves = {'SMA_V1_SHEX_to_pump', 'SMA_V2_HHEX_to_pump', ...
            'SMA_V3_pump_to_heat_path', 'SMA_V4_pump_to_cool_path'};
        record.source_valve_parameters = cell(1, 4);
        for j = 1:4
            record.source_valve_parameters{j} = parameters([source '/' valves{j}]);
        end
        record.source_pressure_parameters = parameters([source '/SMA Pressure Source (TL)']);
        for formulation = formulations
          for power_mode = {'none', 'isentropic'}
            for step = [.001 .0005 .00025]
                attempted = attempted + 1;
                model = 'ecc_dual_chamber_switch_trial';
                assert(~bdIsLoaded(model), 'Trial model already in use.');
                new_system(model);
                cleanup = onCleanup(@() close_system(model, 0));
                names = {'Inlet', 'Outlet'};
                for j = 1:2
                    chamber = [model '/' names{j}];
                    if strcmp(formulation{1}, 'native')
                        if pipe_model
                            add_block('fl_lib/Thermal Liquid/Elements/Pipe (TL)', chamber);
                            set_param(chamber, 'length', '.2', 'length_unit', 'm', 'Dh', '.0032', 'Dh_unit', 'm', ...
                                'area', num2str(area, '%.17g'), 'area_unit', 'm^2', ...
                                'roughness', '15e-6', 'roughness_unit', 'm', 'length_add', '0', 'length_add_unit', 'm', ...
                                'Re_lam', '2000', 'Re_tur', '4000', 'shape_factor', '64', ...
                                'dynamic_compressibility', 'true', 'inertia', 'false', ...
                                'p0', '2.5', 'p0_unit', 'MPa', 'T0', '340', 'T0_unit', 'K');
                        else
                            add_block([source '/SMA_Pump' names{j} 'ConnectingPipeVolume'], chamber);
                            set_param(chamber, 'area_A', num2str(area, '%.17g'), 'area_A_unit', 'm^2', ...
                                'area_B', num2str(area, '%.17g'), 'area_B_unit', 'm^2');
                        end
                    else
                        add_block(blocks{1}, chamber);
                        set_param(chamber, 'area', num2str(area, '%.17g'), 'area_unit', 'm^2');
                        if ~isempty(ablation_mode)
                            set_param(chamber, 'friction_scale', num2str(record.friction_scale), ...
                                'convection_length', num2str(record.convection_length_m, '%.17g'), 'convection_length_unit', 'm');
                        end
                    end
                    if ~pipe_model || strcmp(formulation{1}, 'conservative')
                        set_param(chamber, 'volume', num2str(volume, '%.17g'), 'volume_unit', 'm^3', ...
                            'p_I_specify', 'on', 'T_I_specify', 'on', ...
                            'p_I', '2.5', 'p_I_unit', 'MPa', 'p_I_priority', 'High', ...
                            'T_I', '340', 'T_I_unit', 'K', 'T_I_priority', 'High');
                    end
                end
                add_block([source '/SMA_ThermalLiquidSettings'], [model '/FluidSettings']);
                add_block(solver{1}, [model '/Solver']);
                if ~isempty(index_reduction)
                    set_param([model '/Solver'], 'IndexReductionMethod', index_reduction);
                end
                if ~isempty(solver_tolerance)
                    tolerance_text = num2str(solver_tolerance, '%.17g');
                    set_param([model '/Solver'], 'ResidualTolerance', tolerance_text, 'ConsistencyTolSource', 'LOCAL', ...
                        'ConsistencyAbsTol', tolerance_text, 'ConsistencyRelTol', tolerance_text);
                end
                add_block([source '/SMA Pressure Source (TL)'], [model '/Pump']);
                set_param([model '/Pump'], 'power_spec', ['foundation.enum.power_spec.' power_mode{1}]);
                add_command(model, 'Pump', 'Pressure', 'Pa', .01, 0, 260);
                for j = 1:4
                    block = sprintf('%s/V%d', model, j);
                    add_block([source '/' valves{j}], block);
                    hot = mod(j, 2) == 1;
                    add_command(model, sprintf('V%d', j), sprintf('Valve%d', j), '1', .5, double(hot), double(~hot), valve_transition_s);
                end
                reservoir_names = {'InletReservoir','OutletReservoir','HotReturn','ColdReturn'};
                reservoir_roles = {'inlet_reservoir','outlet_reservoir','hot_return','cold_return'};
                reservoir_count = 2 + 2*separate_boundaries;
                for j = 1:reservoir_count
                    reservoir = [model '/' reservoir_names{j}];
                    add_block('fl_lib/Thermal Liquid/Elements/Reservoir (TL)', reservoir);
                    set_param(reservoir, 'pressure_spec', 'foundation.enum.pressure_spec.specified', ...
                        'reservoir_pressure', '2.5', 'reservoir_pressure_unit', 'MPa', ...
                        'reservoir_temperature', num2str(380-80*mod(j-1,2)), 'reservoir_temperature_unit', 'K', ...
                        'area', num2str(area, '%.17g'), 'area_unit', 'm^2');
                end
                simscape.addConnection([model '/InletReservoir'], 'A', [model '/V1'], 'A');
                simscape.addConnection([model '/OutletReservoir'], 'A', [model '/V2'], 'A');
                return_names = {'InletReservoir','OutletReservoir'};
                if separate_boundaries
                    return_names = {'HotReturn','ColdReturn'};
                end
                simscape.addConnection([model '/' return_names{1}], 'A', [model '/V3'], 'B');
                simscape.addConnection([model '/' return_names{2}], 'A', [model '/V4'], 'B');
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
                sim_input = Simulink.SimulationInput(model);
                sim_input = setModelParameter(sim_input, 'CaptureErrors', 'on');
                output = sim(sim_input);
                if ~isempty(output.ErrorMessage)
                    traces = collect_leaves(output.simlog, '');
                    diagnostic = struct('formulation', formulation{1}, 'power_mode', power_mode{1}, ...
                        'local_step_s', step, 'separate_boundaries', separate_boundaries, ...
                        'simulation_error', output.ErrorMessage, 'production_recovery_allowed', false, ...
                        'attempted_case_index', attempted);
                    if valve_transition_s > 0 || pipe_model
                        diagnostic.valve_transition_s = valve_transition_s;
                    end
                    if ~isempty(index_reduction)
                        diagnostic.index_reduction = get_param([model '/Solver'], 'IndexReductionMethod');
                    end
                    if ~isempty(solver_tolerance)
                        diagnostic.solver_tolerance = solver_tolerance;
                    end
                    if pipe_model
                        diagnostic.pipe_model = true;
                    end
                    if ~isempty(ablation_mode)
                        diagnostic.ablation_mode = ablation_mode;
                        diagnostic.friction_scale = record.friction_scale;
                        diagnostic.convection_length_m = record.convection_length_m;
                    end
                    diagnostic_json = jsonencode(diagnostic);
                    failure_name = 'failed_partial_native_traces.mat';
                    if collect_failure_matrix
                        failure_name = sprintf('failed_case_%d.mat', attempted);
                    end
                    save(fullfile(output_root, failure_name), 'traces', 'diagnostic_json', '-v7.3');
                    record.failed_cases{end+1} = diagnostic;
                    if collect_failure_matrix
                        clear cleanup output traces
                        continue;
                    end
                    error('HeatDriveECC:DualSwitchSimulationFailed', '%s', output.ErrorMessage);
                end
                fields = {'T_I', 'p_I', 'rho_I', 'u_I', 'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'Q_H'};
                if strcmp(formulation{1}, 'conservative')
                    fields = {'T_I', 'p_I', 'rho_I', 'u_I', 'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'Q_H', 'stored_mass', 'stored_energy'};
                end
                if pipe_model
                    fields = {'T_I', 'p_I', 'rho_I', 'u_I', 'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'Q_H', ...
                        'A.p', 'B.p', 'A.T', 'B.T', 'pressure_loss_A', 'pressure_loss_B'};
                    if strcmp(formulation{1}, 'conservative')
                        fields = {'T_I', 'p_I', 'rho_I', 'u_I', 'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'Q_H', ...
                            'stored_mass', 'stored_energy', 'A.p', 'B.p', 'A.T', 'B.T', 'pressure_loss_A', 'pressure_loss_B'};
                    end
                end
                packets = cell(1, 7 + reservoir_count);
                for j = 1:2
                    packets{j} = extract(simscape.logging.findNode(output.simlog, [model '/' names{j}]), lower(names{j}), fields);
                end
                packets{3} = extract(simscape.logging.findNode(output.simlog, [model '/Pump']), 'pump', ...
                    {'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'power', 'rho_A', 'rho_B'});
                valve_fields = {'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B'};
                if valve_transition_s > 0 || pipe_model
                    valve_fields = {'mdot_A', 'mdot_B', 'Phi_A', 'Phi_B', 'L', 'A.T', 'B.T', 'A.p', 'B.p'};
                end
                for j = 1:4
                    packets{3+j} = extract(simscape.logging.findNode(output.simlog, sprintf('%s/V%d', model, j)), ...
                        sprintf('v%d', j), valve_fields);
                end
                for j = 1:reservoir_count
                    packets{7+j} = extract(simscape.logging.findNode(output.simlog, [model '/' reservoir_names{j}]), ...
                        reservoir_roles{j}, {'mdot_A', 'Phi_A', 'p_I', 'T_I'});
                end
                case_record = struct('formulation', formulation{1}, 'power_mode', power_mode{1}, 'local_step_s', step, ...
                    'volume_each_m3', volume, 'area_m2', area, 'initial_temperature_K', 340, 'initial_pressure_Pa', 2.5e6, ...
                    'hot_reservoir_K', 380, 'cold_reservoir_K', 300, 'reservoir_pressure_Pa', 2.5e6, ...
                    'pressure_step_time_s', .01, 'command_pressure_Pa', 260, 'route_switch_time_s', .5, 'stop_s', 1, ...
                    'local_solver', get_param([model '/Solver'], 'LocalSolverChoice'), ...
                    'global_solver', get_param(model, 'Solver'), 'global_step_s', str2double(get_param(model, 'FixedStep')));
                if separate_boundaries
                    case_record.boundary_mode = 'separate_supply_return';
                end
                if valve_transition_s > 0 || pipe_model
                    case_record.valve_transition_s = valve_transition_s;
                end
                if ~isempty(index_reduction)
                    case_record.index_reduction = get_param([model '/Solver'], 'IndexReductionMethod');
                end
                if ~isempty(solver_tolerance)
                    case_record.solver_tolerances = struct('ResidualTolerance', get_param([model '/Solver'], 'ResidualTolerance'), ...
                        'ConsistencyTolSource', get_param([model '/Solver'], 'ConsistencyTolSource'), ...
                        'ConsistencyAbsTol', get_param([model '/Solver'], 'ConsistencyAbsTol'), ...
                        'ConsistencyRelTol', get_param([model '/Solver'], 'ConsistencyRelTol'));
                end
                if pipe_model
                    case_record.pipe_contract = record.pipe_contract;
                    case_record.actual_inlet_parameters = parameters([model '/Inlet']);
                    case_record.actual_outlet_parameters = parameters([model '/Outlet']);
                end
                if ~isempty(ablation_mode)
                    case_record.ablation_mode = ablation_mode;
                    case_record.friction_scale = record.friction_scale;
                    case_record.convection_length_m = record.convection_length_m;
                end
                record_json = jsonencode(case_record);
                save(fullfile(output_root, sprintf('case_%d.mat', attempted)), 'packets', 'record_json', '-v7.3');
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
        record.collection_pass = numel(record.cases) == expected_cases;
        record.attempted_cases = attempted;
        if ~record.collection_pass
            record.error_message = sprintf('%d independent cases failed; no failed state was reused.', numel(record.failed_cases));
        end
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

function add_command(model, block_name, command_name, unit, switch_time, before, after, transition_s)
    if nargin < 8
        transition_s = 0;
    end
    ps = [model '/' command_name 'PS'];
    command_path = [model '/' command_name 'Command'];
    add_block('nesl_utility/Simulink-PS Converter', ps, 'Unit', unit);
    if transition_s == 0
        add_block('simulink/Sources/Step', command_path, 'Time', num2str(switch_time), ...
            'Before', num2str(before), 'After', num2str(after));
        add_line(model, [command_name 'Command/1'], [command_name 'PS/1']);
    else
        add_block('simulink/Sources/Ramp', command_path, 'start', num2str(switch_time), ...
            'slope', num2str((after-before)/transition_s, '%.17g'), 'InitialOutput', num2str(before));
        add_block('simulink/Discontinuities/Saturation', [model '/' command_name 'Limits'], ...
            'LowerLimit', num2str(min(before, after)), 'UpperLimit', num2str(max(before, after)));
        add_line(model, [command_name 'Command/1'], [command_name 'Limits/1']);
        add_line(model, [command_name 'Limits/1'], [command_name 'PS/1']);
    end
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
        selected = node;
        parts = strsplit(names{k}, '.');
        for j = 1:numel(parts)
            selected = selected.child(parts{j});
        end
        series = selected.series;
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

function traces = collect_leaves(node, prefix)
    traces = {};
    series = node.series;
    if ~isempty(series) && series.points > 0
        t = double(time(series));
        traces = {struct('name', prefix, 'unit', series.unit, 'time_s', t(:), 'values', double(values(series)))};
    end
    names = node.childIds;
    for j = 1:numel(names)
        traces = [traces, collect_leaves(node.child(names{j}), [prefix '/' names{j}])]; %#ok<AGROW>
    end
end
