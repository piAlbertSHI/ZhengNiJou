function result = Verify_HeatDriveECC_LongTask(mode, overrides)
% Verification entry point for the heat-driven ECC long task.

    if nargin < 1 || isempty(mode)
        mode = 'stage1';
    end
    if nargin < 2
        overrides = struct();
    end

    root_dir = fileparts(fileparts(mfilename('fullpath')));
    cd(root_dir);

    switch lower(string(mode))
        case "stage1"
            options = Build_HeatDriveECC_EighthRound_Defaults( ...
                merge_structs(struct('cycle_count', 1), overrides));
            stop_time_s = options.schedule.stage_end_s(1);
        case "onecycle"
            options = Build_HeatDriveECC_EighthRound_Defaults( ...
                merge_structs(struct('cycle_count', 1), overrides));
            stop_time_s = options.simulation.stop_time_s;
        case "threecycle"
            options = Build_HeatDriveECC_EighthRound_Defaults( ...
                merge_structs(struct('cycle_count', 3), overrides));
            stop_time_s = options.simulation.stop_time_s;
        otherwise
            error('HeatDriveECC:UnsupportedVerifyMode', ...
                'Unsupported verification mode: %s', mode);
    end

    model_name = options.model_name;
    Integrate_HeatDriveECC_Constitutive21_Interface(model_name, options, false);
    simOut = sim(model_name, ...
        'StopTime', num2str(stop_time_s, '%.15g'), ...
        'ReturnWorkspaceOutputs', 'on');

    result = summarize_simulation(simOut, options, mode, stop_time_s);
    outdir = fullfile(root_dir, 'outputs', 'long_task');
    if ~exist(outdir, 'dir')
        mkdir(outdir);
    end
    result_path = fullfile(outdir, sprintf('%s_check.mat', char(lower(string(mode)))));
    save(result_path, 'result', 'simOut', 'options', '-v7.3');
    result.result_path = result_path;

    print_summary(result);
end

function result = summarize_simulation(simOut, options, mode, stop_time_s)
    result = struct();
    result.mode = char(string(mode));
    result.stop_time_s = stop_time_s;
    result.vars = simOut.who;
    result.var_count = numel(result.vars);
    result.options_snapshot = struct( ...
        'Tc_K', options.system.Tc_K, ...
        'T0_K', options.system.T0_K, ...
        'Tshex_K', options.system.Tshex_K, ...
        'Thhex_K', options.system.Thhex_K, ...
        'Tchex_K', options.system.Tchex_K, ...
        'm_a_kg', options.equilibrium.m_a_kg, ...
        'm_r_kg', options.equilibrium.m_r_kg, ...
        'cp_sma_J_per_kgK', options.material.SMA.cp_J_per_kgK, ...
        'cp_se_J_per_kgK', options.material.SE.cp_J_per_kgK, ...
        'tau_cycle_s', options.schedule.tau_cycle_s, ...
        'stage_durations_s', options.schedule.stage_durations_s);

    signal_names = {'SMA_Tx21_internal', 'SE_Tx21_internal', ...
        'ECC_Q_SMA_constitutive_W', 'ECC_Q_SE_constitutive_W', ...
        'ECC_constitutive21_output', ...
        'shex_buffer_temp_out', 'hot_buffer_temp_out', 'cold_buffer_temp_out', ...
        'mass_flow_sma_stage13_kgps', ...
        'mass_flow_v1_cold_inlet_kgps', ...
        'mass_flow_v3_sma_to_hot_kgps', ...
        'mass_flow_v4_hot_inlet_kgps', ...
        'mass_flow_v6_sma_to_chip_cold_kgps', ...
        'sma_stage1_inlet_fluid_temp_out', 'sma_stage1_outlet_fluid_temp_out', ...
        'sma_stage3_inlet_fluid_temp_out', 'sma_stage3_outlet_fluid_temp_out', ...
        'sma_hold_pipe_node01_fluid_temp_out', ...
        'sma_hold_pipe_node11_fluid_temp_out', ...
        'sma_hold_pipe_node21_fluid_temp_out', ...
        'sma_cooldown_pipe_node01_fluid_temp_out', ...
        'sma_cooldown_pipe_node11_fluid_temp_out', ...
        'sma_cooldown_pipe_node21_fluid_temp_out', ...
        'sma_hold_node01_heatflow_W', ...
        'sma_hold_node11_heatflow_W', ...
        'sma_hold_node21_heatflow_W', ...
        'sma_cooldown_node01_heatflow_W', ...
        'sma_cooldown_node11_heatflow_W', ...
        'sma_cooldown_node21_heatflow_W', ...
        'hhex_sma_branch_inlet_fluid_temp_out', ...
        'hhex_sma_branch_outlet_fluid_temp_out'};
    result.signals = struct();
    for idx = 1:numel(signal_names)
        result.signals.(signal_names{idx}) = signal_stats(simOut, signal_names{idx});
    end

    result.constitutive = constitutive_stats(simOut, options.node_count);
    result.stage_sample_counts = stage_sample_counts(simOut, options);
end

function stats = signal_stats(simOut, name)
    stats = struct('present', false, 'sample_count', 0, 't_first', NaN, ...
        't_last', NaN, 'first', NaN, 'last', NaN, 'min', NaN, 'max', NaN, ...
        'mean', NaN, 'abs_max', NaN);
    if ~any(strcmp(simOut.who, name))
        return;
    end
    stats.present = true;
    [t, data] = signal_time_data(simOut.get(name));
    stats.sample_count = numel(t);
    if ~isempty(t)
        stats.t_first = double(t(1));
        stats.t_last = double(t(end));
    end
    values = double(data(:));
    values = values(isfinite(values));
    if isempty(values)
        return;
    end
    stats.first = values(1);
    stats.last = values(end);
    stats.min = min(values);
    stats.max = max(values);
    stats.mean = mean(values);
    stats.abs_max = max(abs(values));
end

function c = constitutive_stats(simOut, N)
    c = struct('present', false);
    if ~any(strcmp(simOut.who, 'ECC_constitutive21_output'))
        return;
    end
    [t, data] = signal_time_data(simOut.get('ECC_constitutive21_output'));
    if isempty(t) || isempty(data)
        return;
    end
    y = squeeze(data);
    if size(y, 1) ~= numel(t)
        y = y.';
    end
    if size(y, 2) < 12 * N
        return;
    end
    state = y(:, (2 * N + 1):end);
    xA = state(:, 1:N);
    xR = state(:, (N + 1):(2 * N));
    sigmaA = state(:, (2 * N + 1):(3 * N));
    sigmaR = state(:, (3 * N + 1):(4 * N));
    epsA = state(:, (4 * N + 1):(5 * N));
    epsR = state(:, (5 * N + 1):(6 * N));

    c.present = true;
    c.sample_count = numel(t);
    c.t_first = double(t(1));
    c.t_last = double(t(end));
    c.xM_a_first = mean(xA(1, :));
    c.xM_a_last = mean(xA(end, :));
    c.xM_a_min = min(xA(:));
    c.xM_a_max = max(xA(:));
    c.xM_r_first = mean(xR(1, :));
    c.xM_r_last = mean(xR(end, :));
    c.xM_r_min = min(xR(:));
    c.xM_r_max = max(xR(:));
    c.sigma_a_last_Pa = mean(sigmaA(end, :));
    c.sigma_r_last_Pa = mean(sigmaR(end, :));
    c.sigma_a_abs_max_Pa = max(abs(sigmaA(:)));
    c.sigma_r_abs_max_Pa = max(abs(sigmaR(:)));
    c.epsilon_a_last = mean(epsA(end, :));
    c.epsilon_r_last = mean(epsR(end, :));
end

function counts = stage_sample_counts(simOut, options)
    counts = struct();
    if ~any(strcmp(simOut.who, 'ECC_constitutive21_output'))
        return;
    end
    [t, ~] = signal_time_data(simOut.get('ECC_constitutive21_output'));
    if isempty(t)
        return;
    end
    tau = options.schedule.tau_cycle_s;
    ends = options.schedule.stage_end_s(:).';
    ids = zeros(size(t));
    for idx = 1:numel(t)
        local_t = mod(t(idx), tau);
        stage_id = find(local_t <= ends + 1.0e-12, 1, 'first');
        if isempty(stage_id)
            stage_id = 4;
        end
        ids(idx) = stage_id;
    end
    for stage_id = 1:4
        counts.(sprintf('stage%d', stage_id)) = sum(ids == stage_id);
    end
end

function [t, data] = signal_time_data(sig)
    if isa(sig, 'timeseries')
        t = sig.Time;
        data = sig.Data;
    elseif isstruct(sig) && isfield(sig, 'time')
        t = sig.time;
        data = sig.signals.values;
    else
        t = [];
        data = [];
    end
end

function print_summary(result)
    fprintf('VERIFY_MODE=%s STOP=%.15g VARS=%d SAVED=%s\n', ...
        result.mode, result.stop_time_s, result.var_count, result.result_path);
    names = fieldnames(result.signals);
    for idx = 1:numel(names)
        s = result.signals.(names{idx});
        fprintf(['SIG %s present=%d n=%d t_last=%.15g first=%.9g ', ...
            'last=%.9g min=%.9g max=%.9g absmax=%.9g\n'], ...
            names{idx}, s.present, s.sample_count, s.t_last, ...
            s.first, s.last, s.min, s.max, s.abs_max);
    end
    c = result.constitutive;
    if isfield(c, 'sample_count')
        fprintf(['CONSTITUTIVE n=%d t_last=%.15g xA %.9g->%.9g ', ...
            'range[%.9g %.9g] xR %.9g->%.9g range[%.9g %.9g] ', ...
            'sigmaAmax=%.9g sigmaRmax=%.9g\n'], ...
            c.sample_count, c.t_last, c.xM_a_first, c.xM_a_last, ...
            c.xM_a_min, c.xM_a_max, c.xM_r_first, c.xM_r_last, ...
            c.xM_r_min, c.xM_r_max, c.sigma_a_abs_max_Pa, ...
            c.sigma_r_abs_max_Pa);
    end
    if ~isempty(fieldnames(result.stage_sample_counts))
        fprintf('STAGE_COUNTS s1=%d s2=%d s3=%d s4=%d\n', ...
            result.stage_sample_counts.stage1, result.stage_sample_counts.stage2, ...
            result.stage_sample_counts.stage3, result.stage_sample_counts.stage4);
    end
end

function out = merge_structs(out, overrides)
    if ~isstruct(overrides) || isempty(fieldnames(overrides))
        return;
    end
    names = fieldnames(overrides);
    for idx = 1:numel(names)
        key = names{idx};
        if isfield(out, key) && isstruct(out.(key)) && isstruct(overrides.(key))
            out.(key) = merge_structs(out.(key), overrides.(key));
        else
            out.(key) = overrides.(key);
        end
    end
end
