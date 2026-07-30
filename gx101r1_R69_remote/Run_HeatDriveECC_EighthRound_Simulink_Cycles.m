function result = Run_HeatDriveECC_EighthRound_Simulink_Cycles(overrides)
% Run continuous coupled cycles and accept only physical Simscape logs.

    if nargin < 1
        overrides = struct();
    end
    [model_name, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(overrides);
    if ~exist(options.outputs_dir, 'dir')
        mkdir(options.outputs_dir);
    end

    clear HeatDriveECC_EighthRound_SimulinkStep
    assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
    sim_in = Simulink.SimulationInput(model_name);
    sim_in = sim_in.setModelParameter( ...
        'StopTime', num2str(options.simulation.stop_time_s, '%.15g'), ...
        'Solver', options.simulation.solver, ...
        'ReturnWorkspaceOutputs', 'on', ...
        'CaptureErrors', 'on');
    if strcmpi(options.simulation.solver, 'FixedStepDiscrete')
        sim_in = sim_in.setModelParameter( ...
            'FixedStep', num2str(options.simulation.fixed_step_s, '%.15g'));
    else
        sim_in = sim_in.setModelParameter( ...
            'MaxStep', num2str(options.simulation.fixed_step_s, '%.15g'), ...
            'RelTol', '1e-2', ...
            'AbsTol', '1e-3');
    end
    sim_in = sim_in.setVariable('EIGHTH_ROUND_OPTIONS', options);

    wall_start = tic;
    sim_out = sim(sim_in);
    walltime_s = toc(wall_start);
    if isprop(sim_out, 'ErrorMessage') && ~isempty(sim_out.ErrorMessage)
        error('Run:EighthRound:SimulinkFailed', '%s', sim_out.ErrorMessage);
    end

    physical = extract_physical_simscape_logs(sim_out, options);
    physical.walltime_s = walltime_s;
    physical.authority = 'physical_simscape_to_workspace_logs';
    physical.sim_call_count = 1;
    physical.legacy_surrogate_used_for_results = false;
    summary = Summarize_HeatDriveECC_EighthRound_Output(physical, options);

    stamp = datestr(now, 'yyyymmdd_HHMMSS');
    output_dir = fullfile(options.outputs_dir, ...
        sprintf('xu2019_table5_simscape_%dcycle_%s', ...
        options.cycle_count, stamp));
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    output_mat = fullfile(output_dir, 'physical_simscape_result.mat');
    available_simulink_variables = sim_out.who;
    provenance = struct( ...
        'authority', physical.authority, ...
        'legacy_surrogate_used_for_results', false, ...
        'sim_call_count', 1, ...
        'continuous_full_cycle_simulation', true, ...
        'walltime_s', walltime_s, ...
        'model_name', model_name);
    save(output_mat, 'physical', 'summary', 'options', 'provenance', ...
        'available_simulink_variables', '-v7.3');

    result = struct();
    result.model_name = model_name;
    result.model_path = options.model_path;
    result.options = options;
    result.time_s = physical.time_s;
    result.physical = physical;
    result.summary = summary;
    result.sim_out = sim_out;
    result.output_dir = output_dir;
    result.output_mat = output_mat;
    result.used_simulink_sim = true;
    result.authority = physical.authority;
    result.legacy_surrogate_used_for_results = false;
    result.figures = Plot_HeatDriveECC_EighthRound_Result(result, ...
        sprintf('%dcycle', options.cycle_count));
end

function physical = extract_physical_simscape_logs(sim_out, options)
    required = { ...
        'SMA_Tx21_internal', 'SE_Tx21_internal', ...
        'ECC_constitutive21_output', ...
        'ECC_Q_SMA_constitutive_W', 'ECC_Q_SE_constitutive_W', ...
        'SHEX_hot_sink_temp_out', 'hot_sink_temp_out', ...
        'cold_sink_temp_out', 'shex_buffer_temp_out', ...
        'hot_buffer_temp_out', 'cold_buffer_temp_out', ...
        'mass_flow_sma_stage13_kgps', ...
        'mass_flow_v1_cold_inlet_kgps', ...
        'mass_flow_v3_sma_to_hot_kgps', ...
        'mass_flow_v4_hot_inlet_kgps', ...
        'mass_flow_v6_sma_to_chip_cold_kgps', ...
        'pressure_command_se_MPa', 'pressure_command_sma_MPa', ...
        'sma_stage1_inlet_fluid_temp_out', ...
        'sma_stage1_outlet_fluid_temp_out', ...
        'sma_stage3_inlet_fluid_temp_out', ...
        'sma_stage3_outlet_fluid_temp_out', ...
        'probe_sma_stage2_port1_v1_side_T_K', ...
        'probe_sma_stage2_port2_v3_side_T_K', ...
        'probe_sma_stage4_port3_v4_side_T_K', ...
        'probe_sma_stage4_port4_v6_side_T_K'};
    available = sim_out.who;
    missing = setdiff(required, available);
    if ~isempty(missing)
        error('Run:EighthRound:MissingPhysicalSignals', ...
            'Missing required physical Simscape logs: %s', ...
            strjoin(missing, ', '));
    end

    [time_s, sma_T_21] = read_raw_signal(sim_out, ...
        'SMA_Tx21_internal');
    if size(sma_T_21, 2) ~= options.node_count
        error('Run:EighthRound:BadSMANodeCount', ...
            'SMA physical log has %d columns; expected %d.', ...
            size(sma_T_21, 2), options.node_count);
    end

    physical = struct();
    physical.time_s = time_s;
    physical.SMA_T_21_K = sma_T_21;
    physical.SE_T_21_K = read_on_grid(sim_out, ...
        'SE_Tx21_internal', time_s, 'linear');
    [physical.cycle_index, physical.stage_id, ...
        physical.stage_elapsed_s] = cycle_stage_from_time(time_s, options);

    physical.SHEX_T_K = read_on_grid(sim_out, ...
        'SHEX_hot_sink_temp_out', time_s, 'linear');
    physical.HHEX_T_K = read_on_grid(sim_out, ...
        'hot_sink_temp_out', time_s, 'linear');
    physical.CHEX_T_K = read_on_grid(sim_out, ...
        'cold_sink_temp_out', time_s, 'linear');
    physical.SHEX_buffer_T_K = read_on_grid(sim_out, ...
        'shex_buffer_temp_out', time_s, 'linear');
    physical.HHEX_buffer_T_K = read_on_grid(sim_out, ...
        'hot_buffer_temp_out', time_s, 'linear');
    physical.CHEX_buffer_T_K = read_on_grid(sim_out, ...
        'cold_buffer_temp_out', time_s, 'linear');

    physical.mdot_SMA_kgps = read_on_grid(sim_out, ...
        'mass_flow_sma_stage13_kgps', time_s, 'linear');
    physical.mdot_SE_stage2_in_kgps = read_on_grid(sim_out, ...
        'mass_flow_v1_cold_inlet_kgps', time_s, 'linear');
    physical.mdot_SE_stage2_out_kgps = read_on_grid(sim_out, ...
        'mass_flow_v3_sma_to_hot_kgps', time_s, 'linear');
    physical.mdot_SE_stage4_in_kgps = read_on_grid(sim_out, ...
        'mass_flow_v4_hot_inlet_kgps', time_s, 'linear');
    physical.mdot_SE_stage4_out_kgps = read_on_grid(sim_out, ...
        'mass_flow_v6_sma_to_chip_cold_kgps', time_s, 'linear');
    physical.pressure_command_SE_MPa = read_on_grid(sim_out, ...
        'pressure_command_se_MPa', time_s, 'previous');
    physical.pressure_command_SMA_MPa = read_on_grid(sim_out, ...
        'pressure_command_sma_MPa', time_s, 'previous');

    physical.SMA_stage1_Tin_K = read_on_grid(sim_out, ...
        'sma_stage1_inlet_fluid_temp_out', time_s, 'linear');
    physical.SMA_stage1_Tout_K = read_on_grid(sim_out, ...
        'sma_stage1_outlet_fluid_temp_out', time_s, 'linear');
    physical.SMA_stage3_Tin_K = read_on_grid(sim_out, ...
        'sma_stage3_inlet_fluid_temp_out', time_s, 'linear');
    physical.SMA_stage3_Tout_K = read_on_grid(sim_out, ...
        'sma_stage3_outlet_fluid_temp_out', time_s, 'linear');
    physical.SE_stage2_Tin_K = read_on_grid(sim_out, ...
        'probe_sma_stage2_port1_v1_side_T_K', time_s, 'linear');
    physical.SE_stage2_Tout_K = read_on_grid(sim_out, ...
        'probe_sma_stage2_port2_v3_side_T_K', time_s, 'linear');
    physical.SE_stage4_Tin_K = read_on_grid(sim_out, ...
        'probe_sma_stage4_port3_v4_side_T_K', time_s, 'linear');
    physical.SE_stage4_Tout_K = read_on_grid(sim_out, ...
        'probe_sma_stage4_port4_v6_side_T_K', time_s, 'linear');

    physical.Q_SMA_constitutive_21_W = read_on_grid(sim_out, ...
        'ECC_Q_SMA_constitutive_W', time_s, 'previous');
    physical.Q_SE_constitutive_21_W = read_on_grid(sim_out, ...
        'ECC_Q_SE_constitutive_W', time_s, 'previous');
    constitutive = read_on_grid(sim_out, ...
        'ECC_constitutive21_output', time_s, 'previous');
    physical.constitutive_output_252 = constitutive;
    physical = unpack_constitutive_state(physical, constitutive, options);
    physical = collect_temperature_probes(physical, sim_out, available, time_s);

    rho_fluid = 997.0;
    physical.fluid_density_kg_per_m3 = rho_fluid;
    physical.pump_power_SMA_W = abs(physical.pressure_command_SMA_MPa) * ...
        1.0e6 .* abs(physical.mdot_SMA_kgps) / rho_fluid;
    se_flow = max(abs(physical.mdot_SE_stage2_in_kgps), ...
        abs(physical.mdot_SE_stage4_in_kgps));
    physical.pump_power_SE_W = abs(physical.pressure_command_SE_MPa) * ...
        1.0e6 .* se_flow / rho_fluid;
end

function physical = unpack_constitutive_state(physical, values, options)
    N = options.node_count;
    expected_width = 12 * N;
    if size(values, 2) ~= expected_width
        error('Run:EighthRound:BadConstitutiveWidth', ...
            'Physical constitutive output has %d columns; expected %d.', ...
            size(values, 2), expected_width);
    end
    offset = 2 * N;
    names = {'xM_SMA_21','xM_SE_21','sigma_SMA_21_Pa', ...
        'sigma_SE_21_Pa','epsilon_SMA_21','epsilon_SE_21', ...
        'drive_SMA_21_Pa','drive_SE_21_Pa', ...
        'rate_xM_SMA_21_per_s','rate_xM_SE_21_per_s'};
    for idx = 1:numel(names)
        columns = offset + (1:N);
        physical.(names{idx}) = values(:, columns);
        offset = offset + N;
    end
end

function physical = collect_temperature_probes(physical, sim_out, available, time_s)
    probe_names = available(contains(available, 'temp', 'IgnoreCase', true) | ...
        contains(available, 'probe_', 'IgnoreCase', true));
    probes = struct();
    for idx = 1:numel(probe_names)
        name = probe_names{idx};
        try
            values = read_on_grid(sim_out, name, time_s, 'linear');
            if size(values, 2) == 1
                probes.(matlab.lang.makeValidName(name)) = values;
            end
        catch
            % Required probes are checked before this optional collection.
        end
    end
    physical.probes = probes;
    physical.probe_names = fieldnames(probes);
end

function values = read_on_grid(sim_out, name, query_time_s, method)
    [time_s, raw_values] = read_raw_signal(sim_out, name);
    if numel(time_s) == 1
        values = repmat(raw_values(1, :), numel(query_time_s), 1);
        return;
    end
    [time_s, unique_idx] = unique(time_s, 'last');
    raw_values = raw_values(unique_idx, :);
    values = interp1(time_s, raw_values, query_time_s, method, 'extrap');
end

function [time_s, values] = read_raw_signal(sim_out, name)
    raw = sim_out.get(name);
    if isa(raw, 'timeseries')
        time_s = double(raw.Time(:));
        values = double(raw.Data);
    elseif isstruct(raw) && isfield(raw, 'time') && isfield(raw, 'signals')
        time_s = double(raw.time(:));
        values = double(raw.signals.values);
    else
        error('Run:EighthRound:UnsupportedPhysicalSignal', ...
            'Signal %s has unsupported class %s.', name, class(raw));
    end
    values = squeeze(values);
    if isvector(values)
        values = values(:);
    elseif size(values, 1) ~= numel(time_s) && ...
            size(values, 2) == numel(time_s)
        values = values.';
    end
    if size(values, 1) ~= numel(time_s)
        error('Run:EighthRound:BadPhysicalSignalShape', ...
            'Signal %s has %d time samples and data size [%d %d].', ...
            name, numel(time_s), size(values, 1), size(values, 2));
    end
end

function [cycle_index, stage_id, stage_elapsed_s] = ...
        cycle_stage_from_time(time_s, options)
    tau = options.schedule.tau_cycle_s;
    ncycles = options.cycle_count;
    final_time = ncycles * tau;
    cycle_index = floor(time_s ./ tau) + 1;
    cycle_index = min(max(cycle_index, 1), ncycles);
    local_time = time_s - (cycle_index - 1) .* tau;
    final_mask = time_s >= final_time - 10.0 * eps(max(final_time, 1.0));
    local_time(final_mask) = tau;

    stage_id = 4 * ones(size(time_s));
    stage_elapsed_s = zeros(size(time_s));
    starts = options.schedule.stage_start_s(:).';
    ends = options.schedule.stage_end_s(:).';
    for stage = 1:4
        if stage < 4
            mask = local_time >= starts(stage) & local_time < ends(stage);
        else
            mask = local_time >= starts(stage) & local_time <= ends(stage) + eps(tau);
        end
        stage_id(mask) = stage;
        stage_elapsed_s(mask) = local_time(mask) - starts(stage);
    end
end
