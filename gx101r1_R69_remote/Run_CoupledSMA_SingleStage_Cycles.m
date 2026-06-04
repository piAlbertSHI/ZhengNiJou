function coupled_result = Run_CoupledSMA_SingleStage_Cycles(options)
% Run the coupled single-stage thermal SMA cycle.

    if nargin < 1 || isempty(options)
        options = Build_CoupledSMA_Default_Options();
    end
    options = normalize_coupled_options(options);

    ensure_dir(options.outputs_dir);
    ensure_dir(fullfile(options.outputs_dir, 'checkpoints'));
    addpath(options.root_dir, '-begin');

    runtime = Create_Simulink_Exchange_Runtime(options.exchange_options);
    runtime.outputs_dir = options.outputs_dir;
    runtime.checkpoints_dir = fullfile(options.outputs_dir, 'simulink_exchange_checkpoints');
    runtime.figures_dir = fullfile(options.outputs_dir, 'simulink_exchange_figures');
    runtime.save_checkpoints = options.save_checkpoints;
    runtime.save_plots = options.save_plots;
    runtime.store_raw_simout = options.store_raw_simout;

    coupled_result = empty_coupled_result(options);
    actuator_state = Initialize_SMA_Actuator_State(options.actuator);
    restart_checkpoint = '';
    run_tic = tic;

    try
        for cycle_index = 1:options.n_cycles
            [cycle_result, actuator_state, runtime, restart_checkpoint] = run_one_coupled_cycle( ...
                cycle_index, actuator_state, restart_checkpoint, runtime, options);
            coupled_result.cycle_results = append_struct(coupled_result.cycle_results, cycle_result);
            save_progress(coupled_result, options);
        end
        coupled_result.ok = true;
        coupled_result.final_checkpoint_path = restart_checkpoint;
        coupled_result.final_actuator_state = actuator_state;
        if ~isempty(restart_checkpoint) && exist(restart_checkpoint, 'file')
            coupled_result.final_state = GlobalXi_Checkpoint_To_Simulink_State(restart_checkpoint);
        end
    catch ME
        coupled_result.ok = false;
        coupled_result.failure_reason = ME.message;
        coupled_result.failure_report = getReport(ME, 'extended', 'hyperlinks', 'off');
        coupled_result.final_checkpoint_path = restart_checkpoint;
        coupled_result.final_actuator_state = actuator_state;
    end

    coupled_result.total_walltime_s = toc(run_tic);
    coupled_result.summary = build_coupled_summary(coupled_result);
    save_progress(coupled_result, options);
end

function [cycle_result, actuator_state, runtime, next_restart_checkpoint] = run_one_coupled_cycle( ...
        cycle_index, actuator_state, restart_checkpoint, runtime, options)

    cycle_tic = tic;
    cycle_result = struct();
    cycle_result.cycle_index = cycle_index;
    cycle_result.ok = false;
    cycle_result.failure_reason = '';
    cycle_result.stage_reports = struct([]);
    cycle_result.checkpoints = struct();
    cycle_result.actuator_heat_load = struct();
    cycle_result.hold_exchange = struct();
    cycle_result.actuator_cool_unload = struct();
    cycle_result.cooldown_exchange = struct();

    checkpoint_dir = fullfile(options.outputs_dir, 'checkpoints');

    load_checkpoint = fullfile(checkpoint_dir, sprintf('cycle%03d_coupled_load_end.mat', cycle_index));
    [load_stage, actuator_state] = Run_CoupledSMA_LoadUnload_Stage( ...
        'heating_load', actuator_state, restart_checkpoint, options, load_checkpoint);
    cycle_result.actuator_heat_load = strip_heavy_solver(load_stage);
    cycle_result.stage_reports = append_struct(cycle_result.stage_reports, ...
        coupled_stage_report(1, 'actuator_heat_load', cycle_index, load_stage));
    assert_stage_ok(load_stage, 'actuator_heat_load');

    runtime.cycle_index = cycle_index;
    runtime.stage_index = 2;
    [hold_hook, runtime, hold_checkpoint, hold_restart_checkpoint, hold_report] = run_exchange_stage( ...
        'hold_exchange', 2, cycle_index, load_checkpoint, load_stage, runtime, options);
    cycle_result.hold_exchange = hold_hook;
    cycle_result.stage_reports = append_struct(cycle_result.stage_reports, hold_report);

    unload_checkpoint = fullfile(checkpoint_dir, sprintf('cycle%03d_coupled_unload_end.mat', cycle_index));
    [unload_stage, actuator_state] = Run_CoupledSMA_LoadUnload_Stage( ...
        'cooling_unload', actuator_state, hold_restart_checkpoint, options, unload_checkpoint);
    cycle_result.actuator_cool_unload = strip_heavy_solver(unload_stage);
    cycle_result.stage_reports = append_struct(cycle_result.stage_reports, ...
        coupled_stage_report(3, 'actuator_cool_unload', cycle_index, unload_stage));
    assert_stage_ok(unload_stage, 'actuator_cool_unload');

    runtime.cycle_index = cycle_index;
    runtime.stage_index = 4;
    [cooldown_hook, runtime, cooldown_checkpoint, cooldown_restart_checkpoint, cooldown_report] = run_exchange_stage( ...
        'cooldown_exchange', 4, cycle_index, unload_checkpoint, unload_stage, runtime, options);
    cycle_result.cooldown_exchange = cooldown_hook;
    cycle_result.stage_reports = append_struct(cycle_result.stage_reports, cooldown_report);

    cycle_result.checkpoints = struct( ...
        'load_end', load_checkpoint, ...
        'hold_end', hold_checkpoint, ...
        'hold_restart_balanced', hold_restart_checkpoint, ...
        'unload_end', unload_checkpoint, ...
        'cooldown_end', cooldown_checkpoint, ...
        'cooldown_restart_balanced', cooldown_restart_checkpoint);
    cycle_result.timing = struct('cycle_walltime_s', toc(cycle_tic));
    cycle_result.ok = true;
    next_restart_checkpoint = cooldown_restart_checkpoint;
end

function [hook_summary, runtime, exchange_checkpoint, restart_checkpoint, stage_report] = run_exchange_stage( ...
        stage_name, stage_index, cycle_index, input_checkpoint, prior_stage, runtime, options)

    stage_tic = tic;
    exchange_options = options.exchange_options;
    exchange_options.runtime = runtime;
    stage_info = exchange_stage_descriptor(stage_name, options);

    if logical(get_field(exchange_options, 'use_surrogate_exchange', false))
        hook = run_surrogate_exchange(input_checkpoint, stage_info, exchange_options);
    else
        hook = Run_Simulink_Exchange_Hook( ...
            GlobalXi_Checkpoint_To_Simulink_State(input_checkpoint), stage_info, exchange_options);
    end
    runtime = hook.runtime_out;

    checkpoint_dir = fullfile(options.outputs_dir, 'checkpoints');
    suffix = char(string(stage_name));
    exchange_checkpoint = fullfile(checkpoint_dir, sprintf('cycle%03d_%s_end.mat', cycle_index, suffix));
    pressure_MPa = prior_stage.summary.pressure_last_MPa;
    metadata = struct( ...
        'stage_name', stage_name, ...
        'pressure_MPa', pressure_MPa, ...
        'time_s', stage_info.t_end, ...
        'balance_options', get_field(options.exchange_options, 'restart_balance_options', struct()));
    if strcmp(stage_name, 'cooldown_exchange')
        metadata.target_pressure_MPa = 0.0;
    end
    [~, ~, checkpoint_report] = Build_GlobalXi_Checkpoint_From_Exchanged_T( ...
        input_checkpoint, hook.T_out, exchange_checkpoint, metadata);

    restart_checkpoint = fullfile(checkpoint_dir, sprintf('cycle%03d_%s_restart_balanced.mat', cycle_index, suffix));
    [~, ~, balance_report] = Build_GlobalXi_Restart_Balance_Checkpoint( ...
        input_checkpoint, exchange_checkpoint, restart_checkpoint, metadata);

    hook_report = get_field(hook, 'hook_report', struct());
    hook_report.stage_walltime_s = toc(stage_tic);
    hook_summary = struct( ...
        'stage_name', stage_name, ...
        'hook_report', hook_report, ...
        'checkpoint_report', checkpoint_report, ...
        'balance_report', balance_report, ...
        'T_out_min_K', min(hook.T_out(:)), ...
        'T_out_max_K', max(hook.T_out(:)), ...
        'runtime_out', runtime);
    stage_report = exchange_stage_report(stage_index, stage_name, cycle_index, ...
        exchange_checkpoint, restart_checkpoint, hook_report, checkpoint_report, balance_report);
end

function hook = run_surrogate_exchange(input_checkpoint, stage_info, exchange_options)
    state = GlobalXi_Checkpoint_To_Simulink_State(input_checkpoint);
    runtime = get_field(exchange_options, 'runtime', struct());
    stage_name = char(string(stage_info.stage_name));
    switch stage_name
        case 'hold_exchange'
            delta_T_K = -get_field(exchange_options, 'surrogate_hold_delta_T_K', 6.0);
            hot_Q_sign = 1.0;
            cold_Q_sign = 0.0;
        case 'cooldown_exchange'
            delta_T_K = get_field(exchange_options, 'surrogate_cooldown_delta_T_K', 4.0);
            hot_Q_sign = 0.0;
            cold_Q_sign = 1.0;
        otherwise
            delta_T_K = 0.0;
            hot_Q_sign = 0.0;
            cold_Q_sign = 0.0;
    end
    T_out = max(150.0, state.T(:) + delta_T_K);
    params = state.params;
    grid = state.grid;
    thermal_mass_J_per_K = estimate_refrigerant_heat_capacity(params, grid);
    Q_exchange_J = thermal_mass_J_per_K * abs(delta_T_K);

    runtime.last_stage_name = stage_name;
    runtime.last_exchange_sma_avg_T_K = mean(T_out);
    runtime.hot_sink_temp_current = get_field(runtime, 'hot_sink_temp_current', 293.0) + hot_Q_sign * 0.05;
    runtime.cold_sink_temp_current = get_field(runtime, 'cold_sink_temp_current', 293.0) - cold_Q_sign * 0.05;
    runtime.cold_load_temp_current = get_field(runtime, 'cold_load_temp_current', 293.0) - cold_Q_sign * 0.05;

    hook_report = struct( ...
        'handler', 'Run_CoupledSMA_SingleStage_Cycles:surrogate_exchange', ...
        'stage_name', stage_name, ...
        'exchange_backend_kind', 'surrogate_temperature_v1', ...
        'surrogate_exchange_used', true, ...
        'state_temperature_writeback_applied', true, ...
        'Q_hot_end_rejected_J', hot_Q_sign * Q_exchange_J, ...
        'Q_cold_end_absorbed_J', cold_Q_sign * Q_exchange_J, ...
        'Q_load_for_COP_J', cold_Q_sign * Q_exchange_J, ...
        'Wpump_stage_J', 0.0, ...
        'simulink_walltime_s', 0.0, ...
        'T_out_min_K', min(T_out), ...
        'T_out_max_K', max(T_out), ...
        'finite', all(isfinite(T_out)));

    hook = struct();
    hook.T_out = T_out;
    hook.runtime_out = runtime;
    hook.hook_report = hook_report;
end

function stage_info = exchange_stage_descriptor(stage_name, options)
    schedule = get_field(options, 'stage_schedule', struct());
    if strcmp(stage_name, 'hold_exchange')
        duration_s = get_field(schedule, 'stage2_duration_s', get_field(options.exchange_options, 'hotflush_stop_time_s', 0.08));
        stage_info = struct('stage_name', 'hold_exchange', 't_start', 0.10, 't_end', 0.10 + duration_s);
    else
        duration_s = get_field(schedule, 'stage4_duration_s', get_field(options.exchange_options, 'coldflush_stop_time_s', 0.08));
        stage_info = struct('stage_name', 'cooldown_exchange', 't_start', 0.60, 't_end', 0.60 + duration_s);
    end
end

function report = coupled_stage_report(stage_index, stage_name, cycle_index, stage_result)
    s = stage_result.summary;
    report = struct();
    report.cycle_index = cycle_index;
    report.stage_index = stage_index;
    report.stage_name = stage_name;
    report.ok = stage_result.ok;
    report.failure_reason = stage_result.failure_reason;
    report.checkpoint_path = stage_result.refrigerant_checkpoint_out;
    report.final_pressure_MPa = s.pressure_last_MPa;
    report.pressure_min_MPa = s.pressure_min_MPa;
    report.pressure_max_MPa = s.pressure_max_MPa;
    report.actuator_T_first_K = s.actuator_T_first_K;
    report.actuator_T_last_K = s.actuator_T_last_K;
    report.actuator_xi_first = s.actuator_xi_first;
    report.actuator_xi_last = s.actuator_xi_last;
    report.coupling_residual_norm_median = s.coupling_residual_norm_median;
    report.coupling_residual_norm_max = s.coupling_residual_norm_max;
    report.all_finite = s.all_finite;
end

function report = exchange_stage_report(stage_index, stage_name, cycle_index, checkpoint_path, restart_checkpoint_path, ...
        hook_report, checkpoint_report, balance_report)
    report = struct();
    report.cycle_index = cycle_index;
    report.stage_index = stage_index;
    report.stage_name = stage_name;
    report.ok = true;
    report.failure_reason = '';
    report.checkpoint_path = checkpoint_path;
    report.restart_checkpoint_path = restart_checkpoint_path;
    report.exchange_backend_kind = get_field(hook_report, 'exchange_backend_kind', '');
    report.surrogate_exchange_used = logical(get_field(hook_report, 'surrogate_exchange_used', false));
    report.stage_walltime_s = get_field(hook_report, 'stage_walltime_s', NaN);
    report.simulink_walltime_s = get_field(hook_report, 'simulink_walltime_s', NaN);
    report.Q_hot_end_rejected_J = get_field(hook_report, 'Q_hot_end_rejected_J', ...
        get_field(hook_report, 'Q_hot_fluid_buffer_effective_drift_J', NaN));
    report.Q_cold_end_absorbed_J = get_field(hook_report, 'Q_cold_end_absorbed_J', ...
        get_field(hook_report, 'Q_load_for_COP_J', NaN));
    report.Q_load_for_COP_J = get_field(hook_report, 'Q_load_for_COP_J', NaN);
    report.Wpump_stage_J = get_field(hook_report, 'Wpump_stage_J', NaN);
    report.T_writeback_max_abs_delta_K = get_field(checkpoint_report, 'max_abs_delta_T_K', NaN);
    report.balance_pressure_after_MPa = get_field(balance_report, 'pressure_after_balance_MPa', NaN);
    report.finite = all(isfinite([report.T_writeback_max_abs_delta_K, ...
        get_field(balance_report, 'exchange_to_restart_max_abs_delta_Y', 0.0)]));
end

function summary = build_coupled_summary(coupled_result)
    cycles = reshape(get_field(coupled_result, 'cycle_results', struct([])), 1, []);
    reports = collect_stage_reports(cycles);
    mechanical_reports = reports(ismember({reports.stage_name}, {'actuator_heat_load', 'actuator_cool_unload'}));
    exchange_reports = reports(ismember({reports.stage_name}, {'hold_exchange', 'cooldown_exchange'}));

    summary = struct();
    summary.ok = coupled_result.ok;
    summary.failure_reason = coupled_result.failure_reason;
    summary.n_cycles = numel(cycles);
    summary.stage_count = numel(reports);
    summary.all_stage_ok = ~isempty(reports) && all([reports.ok]);
    summary.surrogate_exchange_used = any(arrayfun(@(r) logical(get_field(r, 'surrogate_exchange_used', false)), reports));
    summary.pressure_max_MPa = finite_max(arrayfun(@(r) get_field(r, 'pressure_max_MPa', NaN), mechanical_reports));
    summary.pressure_min_MPa = finite_min(arrayfun(@(r) get_field(r, 'pressure_min_MPa', NaN), mechanical_reports));
    summary.coupling_residual_norm_median = finite_median(arrayfun(@(r) get_field(r, 'coupling_residual_norm_median', NaN), mechanical_reports));
    summary.coupling_residual_norm_max = finite_max(arrayfun(@(r) get_field(r, 'coupling_residual_norm_max', NaN), mechanical_reports));
    summary.actuator_heat_input_J = get_field(get_field(coupled_result, 'final_actuator_state', struct()), 'heat_input_J', NaN);
    summary.actuator_heat_rejected_J = get_field(get_field(coupled_result, 'final_actuator_state', struct()), 'heat_rejected_J', NaN);
    summary.actuator_latent_J = get_field(get_field(coupled_result, 'final_actuator_state', struct()), 'latent_J', NaN);
    summary.actuator_mechanical_work_J = get_field(get_field(coupled_result, 'final_actuator_state', struct()), 'mechanical_work_J', NaN);
    summary.hot_end_heat_J = finite_sum(arrayfun(@(r) get_field(r, 'Q_hot_end_rejected_J', NaN), exchange_reports));
    summary.cold_end_heat_J = finite_sum(arrayfun(@(r) get_field(r, 'Q_cold_end_absorbed_J', NaN), exchange_reports));
    summary.pump_work_J = finite_sum(arrayfun(@(r) get_field(r, 'Wpump_stage_J', NaN), exchange_reports));
    denom = summary.actuator_heat_input_J + max(summary.pump_work_J, 0.0);
    if isfinite(denom) && denom > 0
        summary.COP_estimate = summary.cold_end_heat_J / denom;
    else
        summary.COP_estimate = NaN;
    end
    summary.final_checkpoint_path = coupled_result.final_checkpoint_path;
    summary.outputs_dir = coupled_result.outputs_dir;
end

function reports = collect_stage_reports(cycles)
    reports = struct([]);
    for idx = 1:numel(cycles)
        stage_reports = reshape(get_field(cycles(idx), 'stage_reports', struct([])), 1, []);
        for ridx = 1:numel(stage_reports)
            reports = append_struct(reports, stage_reports(ridx));
        end
    end
end

function result = strip_heavy_solver(result)
    if isfield(result, 'solver_result') && isfield(result.solver_result, 'diagnostics_handle')
        result.solver_result.diagnostics_handle = struct();
    end
end

function options = normalize_coupled_options(options)
    defaults = Build_CoupledSMA_Default_Options();
    options = merge_structs_recursive(defaults, options);
    if isfield(options, 'nCycles') && ~isempty(options.nCycles)
        options.n_cycles = options.nCycles;
    end
    options.n_cycles = max(1, round(options.n_cycles));
    if ~isfield(options, 'root_dir') || isempty(options.root_dir)
        options.root_dir = fileparts(mfilename('fullpath'));
    end
    if ~is_absolute_path(options.outputs_dir)
        options.outputs_dir = fullfile(options.root_dir, options.outputs_dir);
    end
    options.exchange_options.outputs_dir = options.outputs_dir;
    options.exchange_options.run_label = get_field(options.exchange_options, 'run_label', 'coupled_single_stage');
    options.exchange_options.save_checkpoints = options.save_checkpoints;
    options.exchange_options.save_plots = options.save_plots;
    options.exchange_options.store_raw_simout = options.store_raw_simout;
    options.exchange_options.simulink_codegen_cache_root = fullfile(options.outputs_dir, 'codegen', 'cache');
end

function result = empty_coupled_result(options)
    result = struct();
    result.ok = false;
    result.failure_reason = '';
    result.failure_report = '';
    result.options = options;
    result.outputs_dir = options.outputs_dir;
    result.cycle_results = struct([]);
    result.final_checkpoint_path = '';
    result.final_state = struct();
    result.final_actuator_state = struct();
    result.summary = struct();
    result.total_walltime_s = NaN;
end

function save_progress(coupled_result, options)
    save(fullfile(options.outputs_dir, 'coupled_result.mat'), 'coupled_result', '-v7.3');
    if isfield(coupled_result, 'summary') && isstruct(coupled_result.summary) && ...
            ~isempty(fieldnames(coupled_result.summary))
        write_json(fullfile(options.outputs_dir, 'coupled_summary.json'), coupled_result.summary);
    end
end

function assert_stage_ok(stage_result, stage_name)
    if ~(isstruct(stage_result) && isfield(stage_result, 'ok') && stage_result.ok)
        error('Run_CoupledSMA_SingleStage_Cycles:StageFailed', ...
            '%s failed: %s', stage_name, get_field(stage_result, 'failure_reason', 'unknown'));
    end
end

function C_J_per_K = estimate_refrigerant_heat_capacity(params, grid)
    rho = get_field(params, 'rho', 6500.0);
    c = get_field(params, 'c_A', 450.0);
    R = get_field(params, 'R', get_field(grid, 'R', 40.0e-3));
    t_delta = get_field(params, 't_delta', 0.2e-3);
    volume = pi * R ^ 2 * t_delta;
    C_J_per_K = max(rho * volume * c, eps);
end

function out = append_struct(out, item)
    if isempty(out)
        out = item;
    else
        [out, item] = align_struct_fields(out, item);
        out(end + 1) = item;
    end
end

function [a, b] = align_struct_fields(a, b)
    fields = unique([fieldnames(a); fieldnames(b)], 'stable');
    for idx = 1:numel(fields)
        name = fields{idx};
        if ~isfield(a, name)
            for j = 1:numel(a)
                a(j).(name) = [];
            end
        end
        if ~isfield(b, name)
            b.(name) = [];
        end
    end
    b = orderfields(b, a);
end

function out = merge_structs_recursive(out, in)
    if ~isstruct(in)
        return;
    end
    names = fieldnames(in);
    for idx = 1:numel(names)
        name = names{idx};
        if isfield(out, name) && isstruct(out.(name)) && isstruct(in.(name))
            out.(name) = merge_structs_recursive(out.(name), in.(name));
        else
            out.(name) = in.(name);
        end
    end
end

function value = get_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end

function ensure_dir(path_value)
    if ~exist(path_value, 'dir')
        mkdir(path_value);
    end
end

function tf = is_absolute_path(path_text)
    path_text = char(string(path_text));
    tf = ~isempty(regexp(path_text, '^[a-zA-Z]:[\\/]', 'once')) || startsWith(path_text, '\\');
end

function write_json(path_value, value)
    fid = fopen(path_value, 'w', 'n', 'UTF-8');
    if fid < 0
        error('Run_CoupledSMA_SingleStage_Cycles:JsonOpenFailed', 'Could not write %s.', path_value);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
    clear cleaner
end

function value = finite_sum(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = sum(values);
    end
end

function value = finite_min(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = min(values);
    end
end

function value = finite_max(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = max(values);
    end
end

function value = finite_median(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = median(values);
    end
end
