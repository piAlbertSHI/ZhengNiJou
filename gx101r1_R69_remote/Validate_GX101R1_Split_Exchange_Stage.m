function summary = Validate_GX101R1_Split_Exchange_Stage(options)
% Compare one full active exchange stage with two continuous half stages.

    if nargin < 1 || isempty(options)
        options = struct();
    end

    root_dir = fileparts(mfilename('fullpath'));
    stage_name = char(string(get_field(options, 'stage_name', 'cooldown_exchange')));
    if ~any(strcmp(stage_name, {'hold_exchange', 'cooldown_exchange'}))
        error('Validate_GX101R1_Split_Exchange_Stage:InvalidStage', ...
            'stage_name must be hold_exchange or cooldown_exchange.');
    end

    default_label = ['r12_', stage_name, '_split'];
    run_label = get_field(options, 'run_label', default_label);
    outputs_dir = get_field(options, 'outputs_dir', fullfile(root_dir, 'Output', run_label));
    if ~exist(outputs_dir, 'dir')
        mkdir(outputs_dir);
    end

    seed_run_result_path = get_field(options, 'seed_run_result_path', '');
    if isempty(seed_run_result_path)
        seed_run_result_path = run_seed_cycle(options, outputs_dir);
    end
    data = load(seed_run_result_path, 'run_result');
    run_result = data.run_result;

    [stage_descriptors, ~] = Build_FourStage_Cycle_Schedule(struct('P_max', 0.59e6));
    exchange_options = get_field(run_result.config, 'exchange_options', struct());
    exchange_options = merge_struct(exchange_options, get_field(options, 'exchange_options', struct()));
    exchange_options.run_label = run_label;
    exchange_options.outputs_dir = outputs_dir;
    exchange_options.save_checkpoints = true;
    exchange_options.save_plots = false;
    exchange_options.store_raw_simout = false;

    if strcmp(stage_name, 'hold_exchange')
        stage_descriptor = stage_descriptors(2);
        checkpoint_path = find_cycle_checkpoint(run_result, 1, 'load_adiabatic');
        base_runtime = initial_runtime(exchange_options, outputs_dir);
        full_stop_field = 'hotflush_stop_time_s';
    else
        stage_descriptor = stage_descriptors(4);
        checkpoint_path = find_cycle_checkpoint(run_result, 1, 'unload_adiabatic');
        hold_report = find_stage_report(run_result, 1, 'hold_exchange');
        base_runtime = runtime_from_hold_report(exchange_options, hold_report, outputs_dir);
        full_stop_field = 'coldflush_stop_time_s';
    end
    if isempty(checkpoint_path) || ~exist(checkpoint_path, 'file')
        error('Validate_GX101R1_Split_Exchange_Stage:MissingCheckpoint', ...
            'Cannot find seed checkpoint for %s.', stage_name);
    end

    state0 = GlobalXi_Checkpoint_To_Simulink_State(checkpoint_path);
    target_ratio = get_field(exchange_options, 'flush_volume_target_ratio', 1.0);
    full_time_s = get_field(options, 'full_stop_time_s', 0.4);
    half_time_s = full_time_s / 2.0;
    half_ratio = target_ratio / 2.0;

    full_options = exchange_options;
    full_options.(full_stop_field) = full_time_s;
    full_options.runtime = set_runtime_stage(base_runtime, 101, stage_index_for(stage_name), ...
        fullfile(outputs_dir, 'full'));
    full = Run_Simulink_Exchange_Hook(state0, stage_descriptor, full_options);

    half1_options = exchange_options;
    half1_options.(full_stop_field) = half_time_s;
    half1_options.flush_volume_target_ratio = half_ratio;
    half1_options.actual_flush_pressure_control_enable_for_target_duty = false;
    half1_options.runtime = set_runtime_stage(base_runtime, 201, stage_index_for(stage_name), ...
        fullfile(outputs_dir, 'half1'));
    half1 = Run_Simulink_Exchange_Hook(state0, stage_descriptor, half1_options);

    half2_options = exchange_options;
    half2_options.(full_stop_field) = half_time_s;
    half2_options.flush_volume_target_ratio = half_ratio;
    half2_options.actual_flush_pressure_control_enable_for_target_duty = false;
    half2_options.runtime = set_runtime_stage(half1.runtime_out, 202, stage_index_for(stage_name), ...
        fullfile(outputs_dir, 'half2'));
    half2 = Run_Simulink_Exchange_Hook(half1.state_out, stage_descriptor, half2_options);

    summary = compare_stage_outputs(stage_name, full, half1, half2);
    summary.stage_name = stage_name;
    summary.seed_run_result_path = seed_run_result_path;
    summary.seed_checkpoint_path = checkpoint_path;
    summary.outputs_dir = outputs_dir;
    summary.full_stop_time_s = full_time_s;
    summary.half_stop_time_s = half_time_s;
    summary.full_flush_volume_target_ratio = target_ratio;
    summary.half_flush_volume_target_ratio = half_ratio;
    summary.half_stage_pressure_retry_disabled = true;
    summary.acceptance_note = ['Full active exchange stage is compared with two half stages using runtime_out pipe-state ', ...
        'and T_x_101 carryover; half-stage pressure retry is disabled to avoid selecting a different hydraulic branch.'];

    mat_path = fullfile(outputs_dir, [stage_name, '_full_vs_split_summary.mat']);
    json_path = fullfile(outputs_dir, [stage_name, '_full_vs_split_summary.json']);
    save(mat_path, 'summary');
    write_json(json_path, summary);
end

function seed_run_result_path = run_seed_cycle(options, outputs_dir)
    seed_label = [get_field(options, 'run_label', 'r12_split'), '_seed1'];
    seed_dir = fullfile(outputs_dir, 'seed1');
    run_options = struct();
    run_options.nCycles = 1;
    run_options.run_label = seed_label;
    run_options.outputs_dir = seed_dir;
    run_options.save_checkpoints = true;
    run_options.save_plots = false;
    run_options.store_raw_simout = false;
    run_options.batch_light_mode = true;
    run_options.solver_options = struct('Pmax', 0.59e6, 'include_mechanical_heat', false);
    run_options.exchange_options = merge_struct(default_exchange_options(), get_field(options, 'exchange_options', struct()));
    run_options.exchange_options.outputs_dir = seed_dir;
    run_result = Run_GlobalXi_Simulink_Cycles(run_options); %#ok<NASGU>
    seed_run_result_path = fullfile(seed_dir, 'run_result.mat');
end

function opts = default_exchange_options()
    opts = struct( ...
        'cold_load_mode', 'no_load', ...
        'cold_load_heat_W', 0.0, ...
        'hot_sink_C_J_per_K', 41.8, ...
        'cold_sink_C_J_per_K', 4.18, ...
        'hot_sink_ambient_G_W_per_K', 0.05, ...
        'cold_sink_ambient_G_W_per_K', 1.0e-12, ...
        'cold_sink_ambient_G_hold_W_per_K', 1.0e-12, ...
        'cold_sink_ambient_G_cooldown_W_per_K', 1.0e-12, ...
        'cold_load_ambient_G_W_per_K', 1.0e-12, ...
        'chip_ambient_G_W_per_K', 1.0e-12, ...
        'cold_sink_fluid_G_hold_W_per_K', 1.0e-12, ...
        'cold_sink_fluid_G_cooldown_W_per_K', 500.0, ...
        'cold_load_to_cold_sink_G_hold_W_per_K', 1.0e-12, ...
        'cold_load_to_cold_sink_G_cooldown_W_per_K', 1.0e-12, ...
        'flow_control_mode', 'target_duty_pressure_v1', ...
        'flush_volume_target_ratio', 1.0, ...
        'hotflush_stop_time_s', 0.4, ...
        'coldflush_stop_time_s', 0.4, ...
        'sma_pipe_internal_volume_target_ml', 0.5);
end

function runtime = initial_runtime(exchange_options, outputs_dir)
    exchange_options.outputs_dir = outputs_dir;
    runtime = Create_Simulink_Exchange_Runtime(exchange_options);
end

function runtime = runtime_from_hold_report(exchange_options, hold_report, outputs_dir)
    exchange_options.outputs_dir = outputs_dir;
    runtime = Create_Simulink_Exchange_Runtime(exchange_options);
    runtime.hot_sink_temp_current = get_field(hold_report, 'hot_sink_temp_out', runtime.hot_sink_temp_current);
    runtime.cold_sink_temp_current = get_field(hold_report, 'cold_sink_temp_out', runtime.cold_sink_temp_current);
    runtime.cold_load_temp_current = get_field(hold_report, 'cold_load_temp_out', runtime.cold_load_temp_current);
    runtime.hot_buffer_temp_current = get_field(hold_report, 'hot_buffer_temp_out', runtime.hot_buffer_temp_current);
    runtime.cold_buffer_temp_current = get_field(hold_report, 'cold_buffer_temp_out', runtime.cold_buffer_temp_current);
    runtime.stage2_path_pipe_T_state_K = get_field(hold_report, 'stage2_path_pipe_T_state_out_K', ...
        get_field(hold_report, 'pipe_internal_fluid_mean_T_end_K', runtime.cold_buffer_temp_current));
    runtime.stage2_path_pipe_unreleased_cumulative_J = get_field(hold_report, ...
        'stage2_path_pipe_unreleased_cumulative_J', 0.0);
    runtime.hold_pipe_fluid_mean_T_current_K = runtime.stage2_path_pipe_T_state_K;
    runtime.pipe_energy_carryover_model = get_field(hold_report, 'pipe_energy_carryover_model', ...
        'path_mean_pipe_temperature_carryover_v1');
end

function runtime = set_runtime_stage(runtime, cycle_index, stage_index, outputs_dir)
    runtime.cycle_index = cycle_index;
    runtime.stage_index = stage_index;
    runtime.outputs_dir = outputs_dir;
    runtime.checkpoints_dir = fullfile(outputs_dir, 'simulink_exchange_checkpoints');
    runtime.figures_dir = fullfile(outputs_dir, 'simulink_exchange_figures');
    if ~exist(runtime.outputs_dir, 'dir')
        mkdir(runtime.outputs_dir);
    end
    if ~exist(runtime.checkpoints_dir, 'dir')
        mkdir(runtime.checkpoints_dir);
    end
end

function idx = stage_index_for(stage_name)
    if strcmp(stage_name, 'hold_exchange')
        idx = 2;
    else
        idx = 4;
    end
end

function summary = compare_stage_outputs(stage_name, full, half1, half2)
    full_report = full.hook_report;
    half2_report = half2.hook_report;
    full_T = full.T_out(:);
    split_T = half2.T_out(:);
    full_Q = get_field(full_report, 'Q_sma_boundary_htf_J', get_field(full_report, 'Q_sma_htf_J', NaN));
    split_Q = get_field(half1.hook_report, 'Q_sma_boundary_htf_J', get_field(half1.hook_report, 'Q_sma_htf_J', 0.0)) + ...
        get_field(half2_report, 'Q_sma_boundary_htf_J', get_field(half2_report, 'Q_sma_htf_J', 0.0));
    if strcmp(stage_name, 'hold_exchange')
        full_end_T = get_field(full_report, 'hot_end_temp_out', get_field(full_report, 'hot_sink_temp_out', NaN));
        split_end_T = get_field(half2_report, 'hot_end_temp_out', get_field(half2_report, 'hot_sink_temp_out', NaN));
    else
        full_end_T = get_field(full_report, 'cold_end_temp_out', get_field(full_report, 'cold_sink_temp_out', NaN));
        split_end_T = get_field(half2_report, 'cold_end_temp_out', get_field(half2_report, 'cold_sink_temp_out', NaN));
    end
    q_rel_diff = abs(full_Q - split_Q) / max(abs(full_Q), eps);
    sma_avg_diff_K = abs(mean(full_T) - mean(split_T));
    end_temp_diff_K = abs(full_end_T - split_end_T);
    summary = struct( ...
        'ok', q_rel_diff <= 0.05 && sma_avg_diff_K <= 0.2 && end_temp_diff_K <= 0.2, ...
        'full_Q_sma_boundary_htf_J', full_Q, ...
        'split_Q_sma_boundary_htf_J', split_Q, ...
        'Q_sma_boundary_htf_rel_diff', q_rel_diff, ...
        'full_sma_avg_T_K', mean(full_T), ...
        'split_sma_avg_T_K', mean(split_T), ...
        'sma_avg_T_abs_diff_K', sma_avg_diff_K, ...
        'full_official_end_temp_K', full_end_T, ...
        'split_official_end_temp_K', split_end_T, ...
        'official_end_temp_abs_diff_K', end_temp_diff_K, ...
        'full_Q_internal_pipe_fluid_J', get_field(full_report, 'Q_internal_pipe_fluid_J', NaN), ...
        'split_Q_internal_pipe_fluid_J', get_field(half1.hook_report, 'Q_internal_pipe_fluid_J', 0.0) + ...
            get_field(half2_report, 'Q_internal_pipe_fluid_J', 0.0), ...
        'full_actual_active_flush_volume_ratio', get_field(full_report, 'actual_active_flush_volume_ratio', NaN), ...
        'split_actual_active_flush_volume_ratio', get_field(half1.hook_report, 'actual_active_flush_volume_ratio', 0.0) + ...
            get_field(half2_report, 'actual_active_flush_volume_ratio', 0.0), ...
        'half2_pipe_energy_carryover_model', get_field(half2_report, 'pipe_energy_carryover_model', ''), ...
        'half2_sma_fluid_T_init_source', get_field(half2_report, 'sma_fluid_T_init_source', ''));
end

function path_value = find_cycle_checkpoint(run_result, cycle_index, stage_name)
    path_value = '';
    report = find_stage_report(run_result, cycle_index, stage_name);
    if isstruct(report)
        path_value = get_field(report, 'checkpoint_path', '');
    end
end

function report = find_stage_report(run_result, cycle_index, stage_name)
    report = struct();
    cycles = reshape(get_field(run_result, 'cycle_results', struct([])), 1, []);
    for cidx = 1:numel(cycles)
        if get_field(cycles(cidx), 'cycle_index', NaN) ~= cycle_index
            continue;
        end
        reports = reshape(get_field(cycles(cidx), 'stage_reports', struct([])), 1, []);
        for ridx = 1:numel(reports)
            if strcmp(get_field(reports(ridx), 'stage_name', ''), stage_name)
                report = reports(ridx);
                return;
            end
        end
    end
end

function out = merge_struct(base, overlay)
    out = base;
    if ~isstruct(overlay)
        return;
    end
    names = fieldnames(overlay);
    for idx = 1:numel(names)
        out.(names{idx}) = overlay.(names{idx});
    end
end

function value = get_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end

function write_json(path_value, value)
    fid = fopen(path_value, 'w', 'n', 'UTF-8');
    if fid < 0
        error('Validate_GX101R1_Split_Exchange_Stage:CannotWriteJson', ...
            'Cannot write %s.', path_value);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
end
