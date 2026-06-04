function summary = Validate_GX101R1_Split_Stage4(options)
% Compare one full cooldown stage with two continuous half cooldown stages.

    if nargin < 1 || isempty(options)
        options = struct();
    end

    root_dir = fileparts(mfilename('fullpath'));
    run_label = get_field(options, 'run_label', 'r3_split');
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

    unload_checkpoint_path = find_cycle_checkpoint(run_result, 1, 'unload_adiabatic');
    hold_report = find_stage_report(run_result, 1, 'hold_exchange');
    if isempty(unload_checkpoint_path) || ~exist(unload_checkpoint_path, 'file')
        error('Validate_GX101R1_Split_Stage4:MissingUnloadCheckpoint', ...
            'Cannot find cycle001 unload checkpoint.');
    end

    [stage_descriptors, ~] = Build_FourStage_Cycle_Schedule(struct('P_max', 0.59e6));
    stage4 = stage_descriptors(4);
    exchange_options = get_field(run_result.config, 'exchange_options', struct());
    exchange_options = merge_struct(exchange_options, get_field(options, 'exchange_options', struct()));
    exchange_options.run_label = run_label;
    exchange_options.outputs_dir = outputs_dir;
    exchange_options.save_checkpoints = true;
    exchange_options.save_plots = false;
    exchange_options.store_raw_simout = false;

    base_runtime = runtime_from_hold_report(exchange_options, hold_report, outputs_dir);
    state0 = GlobalXi_Checkpoint_To_Simulink_State(unload_checkpoint_path);

    full_options = exchange_options;
    full_options.coldflush_stop_time_s = 0.4;
    full_options.runtime = set_runtime_stage(base_runtime, 101, 4, fullfile(outputs_dir, 'full'));
    full = Run_Simulink_Exchange_Hook(state0, stage4, full_options);

    half_flush_volume_target_ratio = get_field(options, 'split_half_flush_volume_target_ratio', ...
        0.5 * get_field(exchange_options, 'flush_volume_target_ratio', 1.0));

    half1_options = exchange_options;
    half1_options.coldflush_stop_time_s = 0.2;
    half1_options.flush_volume_target_ratio = half_flush_volume_target_ratio;
    half1_options.runtime = set_runtime_stage(base_runtime, 201, 4, fullfile(outputs_dir, 'half1'));
    half1 = Run_Simulink_Exchange_Hook(state0, stage4, half1_options);

    half2_options = exchange_options;
    half2_options.coldflush_stop_time_s = 0.2;
    half2_options.flush_volume_target_ratio = half_flush_volume_target_ratio;
    half2_runtime = half1.runtime_out;
    half2_options.runtime = set_runtime_stage(half2_runtime, 202, 4, fullfile(outputs_dir, 'half2'));
    half2 = Run_Simulink_Exchange_Hook(half1.state_out, stage4, half2_options);

    summary = compare_stage_outputs(full, half1, half2);
    summary.split_half_flush_volume_target_ratio = half_flush_volume_target_ratio;
    summary.seed_run_result_path = seed_run_result_path;
    summary.unload_checkpoint_path = unload_checkpoint_path;
    summary.outputs_dir = outputs_dir;
    summary.acceptance_note = 'Full cooldown stage is compared with two continuous half stages using hook runtime_out carryover.';

    save(fullfile(outputs_dir, 'split_stage4_summary.mat'), 'summary');
    write_json(fullfile(outputs_dir, 'split_stage4_summary.json'), summary);
end

function seed_run_result_path = run_seed_cycle(options, outputs_dir)
    seed_label = [get_field(options, 'run_label', 'r3_split'), '_seed1'];
    seed_dir = fullfile(outputs_dir, 'seed1');
    run_options = struct();
    run_options.nCycles = 1;
    run_options.run_label = seed_label;
    run_options.outputs_dir = seed_dir;
    run_options.save_checkpoints = true;
    run_options.save_plots = false;
    run_options.store_raw_simout = false;
    run_options.batch_light_mode = true;
    run_options.exchange_options = merge_struct(default_exchange_options(), get_field(options, 'exchange_options', struct()));
    run_options.exchange_options.outputs_dir = seed_dir;
    run_result = Run_GlobalXi_Simulink_Cycles(run_options); %#ok<NASGU>
    seed_run_result_path = fullfile(seed_dir, 'run_result.mat');
end

function opts = default_exchange_options()
    opts = struct( ...
        'cold_load_mode', 'constant_load', ...
        'cold_load_heat_W', 1.0, ...
        'hot_sink_C_J_per_K', 41.8, ...
        'cold_load_to_cold_sink_G_hold_W_per_K', 1.0e-12, ...
        'cold_load_to_cold_sink_G_cooldown_W_per_K', 0.4, ...
        'flow_control_mode', 'target_duty_pressure_v1', ...
        'flush_volume_target_ratio', 1.0, ...
        'hotflush_stop_time_s', 0.4, ...
        'coldflush_stop_time_s', 0.4);
end

function runtime = runtime_from_hold_report(exchange_options, hold_report, outputs_dir)
    exchange_options.outputs_dir = outputs_dir;
    runtime = Create_Simulink_Exchange_Runtime(exchange_options);
    runtime.hot_sink_temp_current = get_field(hold_report, 'hot_sink_temp_out', runtime.hot_sink_temp_current);
    runtime.cold_sink_temp_current = get_field(hold_report, 'cold_sink_temp_out', runtime.cold_sink_temp_current);
    runtime.cold_load_temp_current = get_field(hold_report, 'cold_load_temp_out', runtime.cold_load_temp_current);
    runtime.chip_temp_current = runtime.cold_load_temp_current;
    runtime.hot_buffer_temp_current = get_field(hold_report, 'hot_buffer_temp_out', runtime.hot_buffer_temp_current);
    runtime.cold_buffer_temp_current = get_field(hold_report, 'cold_buffer_temp_out', runtime.cold_buffer_temp_current);
    runtime.hold_pipe_fluid_mean_T_current_K = get_field(hold_report, 'pipe_internal_fluid_mean_T_end_K', ...
        get_field(hold_report, 'Q_internal_pipe_fluid_mean_T_end_K', runtime.cold_buffer_temp_current));
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

function summary = compare_stage_outputs(full, half1, half2)
    full_report = full.hook_report;
    half2_report = half2.hook_report;
    full_T = full.T_out(:);
    split_T = half2.T_out(:);
    summary = struct();
    summary.ok = true;
    summary.full_cold_sink_temp_out = get_field(full_report, 'cold_sink_temp_out', NaN);
    summary.split_cold_sink_temp_out = get_field(half2_report, 'cold_sink_temp_out', NaN);
    summary.cold_sink_abs_diff_K = abs(summary.full_cold_sink_temp_out - summary.split_cold_sink_temp_out);
    summary.full_cold_load_temp_out = get_field(full_report, 'cold_load_temp_out', NaN);
    summary.split_cold_load_temp_out = get_field(half2_report, 'cold_load_temp_out', NaN);
    summary.cold_load_abs_diff_K = abs(summary.full_cold_load_temp_out - summary.split_cold_load_temp_out);
    summary.sma_T_max_abs_diff_K = max(abs(full_T - split_T));
    summary.full_Q_sma_htf_J = get_field(full_report, 'Q_sma_htf_J', NaN);
    summary.split_Q_sma_htf_J = get_field(half1.hook_report, 'Q_sma_htf_J', 0.0) + ...
        get_field(half2_report, 'Q_sma_htf_J', 0.0);
    summary.Q_sma_htf_abs_diff_J = abs(summary.full_Q_sma_htf_J - summary.split_Q_sma_htf_J);
    summary.full_Q_internal_pipe_fluid_J = get_field(full_report, 'Q_internal_pipe_fluid_J', NaN);
    summary.split_Q_internal_pipe_fluid_J = get_field(half1.hook_report, 'Q_internal_pipe_fluid_J', 0.0) + ...
        get_field(half2_report, 'Q_internal_pipe_fluid_J', 0.0);
    summary.Q_internal_pipe_abs_diff_J = abs(summary.full_Q_internal_pipe_fluid_J - summary.split_Q_internal_pipe_fluid_J);
    summary.full_actual_active_flush_volume_ratio = get_field(full_report, 'actual_active_flush_volume_ratio', NaN);
    summary.split_actual_active_flush_volume_ratio = get_field(half1.hook_report, 'actual_active_flush_volume_ratio', 0.0) + ...
        get_field(half2_report, 'actual_active_flush_volume_ratio', 0.0);
    summary.flush_abs_diff_vs_full = abs(summary.full_actual_active_flush_volume_ratio - ...
        summary.split_actual_active_flush_volume_ratio);
    summary.flush_rel_diff_vs_full = summary.flush_abs_diff_vs_full / ...
        max(abs(summary.full_actual_active_flush_volume_ratio), eps);
    summary.flush_equivalent_ok = isfinite(summary.flush_abs_diff_vs_full) && ...
        summary.flush_rel_diff_vs_full <= 0.05;
    summary.half1_pipe_energy_carryover_model = get_field(half1.hook_report, 'pipe_energy_carryover_model', '');
    summary.half2_sma_fluid_T_init_source = get_field(half2_report, 'sma_fluid_T_init_source', '');
    summary.ok = isfinite(summary.cold_sink_abs_diff_K) && ...
        isfinite(summary.sma_T_max_abs_diff_K) && summary.flush_equivalent_ok;
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
        error('Validate_GX101R1_Split_Stage4:CannotWriteJson', ...
            'Cannot write %s.', path_value);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
end
