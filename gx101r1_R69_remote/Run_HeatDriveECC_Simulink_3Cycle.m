function result = Run_HeatDriveECC_Simulink_3Cycle(options)
% Run the fourth-round Simulink full-cycle 1D51 heat-driven ECC model.

    root_dir = fileparts(mfilename('fullpath'));
    addpath(root_dir);

    if nargin < 1 || isempty(options)
        options = Build_HeatDriveECC_Article_Defaults();
    elseif isfield(options, 'schema_version') && ...
            strcmp(options.schema_version, 'heatdrive_ecc_article_simulink_defaults_v1')
        % Use a fully built options struct as-is. Re-merging would recurse
        % into route_matrix struct arrays and corrupt the override contract.
        options = options;
    else
        options = Build_HeatDriveECC_Article_Defaults(options);
    end

    if options.cycle_count ~= 3
        error('Run_HeatDriveECC_Simulink_3Cycle:InvalidCycleCount', ...
            'Fourth-round validation requires exactly 3 cycles.');
    end

    if ~isfolder(options.outputs_dir)
        mkdir(options.outputs_dir);
    end

    model_path = Build_HeatDriveECC_Model(options);
    load_system(options.model_name);

    sim_in = Simulink.SimulationInput(options.model_name);
    sim_in = sim_in.setModelParameter( ...
        'StopTime', sprintf('%.15g', options.simulation.stop_time_s), ...
        'Solver', options.simulation.solver, ...
        'FixedStep', sprintf('%.15g', options.simulation.fixed_step_s), ...
        'ReturnWorkspaceOutputs', 'on');
    sim_out = sim(sim_in);

    yout = sim_out.get('heatdrive_ecc_yout');
    [time_s, values] = unpack_yout(yout);
    summary = summarize_run(time_s, values, options, model_path);
    probe_table = build_probe_table(time_s, values, options);
    stage_table = struct2table(summary.stage_summaries);

    result = struct();
    result.schema_version = 'heatdrive_ecc_simulink_3cycle_result_v1';
    result.options = options;
    result.model_name = options.model_name;
    result.model_path = model_path;
    result.output_dir = options.outputs_dir;
    result.time_s = time_s;
    result.values = values;
    result.summary = summary;
    result.stage_table = stage_table;
    result.probe_table = probe_table;

    result.result_mat_path = fullfile(options.outputs_dir, 'heatdrive_ecc_3cycle_result.mat');
    result.summary_json_path = fullfile(options.outputs_dir, 'heatdrive_ecc_3cycle_summary.json');
    result.stage_csv_path = fullfile(options.outputs_dir, 'heatdrive_ecc_3cycle_stage_summary.csv');
    result.probe_csv_path = fullfile(options.outputs_dir, 'heatdrive_ecc_3cycle_probe_table.csv');
    result.trend_plot_path = fullfile(options.outputs_dir, 'heatdrive_ecc_3cycle_trends.png');

    save(result.result_mat_path, 'result', '-v7.3');
    write_json(result.summary_json_path, summary);
    writetable(stage_table, result.stage_csv_path);
    writetable(probe_table, result.probe_csv_path);
    write_trend_plot(time_s, values, options, result.trend_plot_path);
end

function [time_s, values] = unpack_yout(yout)
    time_s = yout.time(:);
    values = yout.signals.values;
    values = squeeze(values);
    if size(values, 1) ~= numel(time_s) && size(values, 2) == numel(time_s)
        values = values.';
    end
    if size(values, 1) ~= numel(time_s)
        error('Run_HeatDriveECC_Simulink_3Cycle:InvalidYoutShape', ...
            'Cannot align Simulink output values with the time vector.');
    end
end

function summary = summarize_run(time_s, values, options, model_path)
    map = options.output_map;
    stage_summaries = repmat(empty_stage_summary(), options.cycle_count * 4, 1);
    row = 1;
    for cycle_idx = 1:options.cycle_count
        for stage_id = 1:4
            mask = round(values(:, map.cycle_index)) == cycle_idx & ...
                round(values(:, map.stage_id)) == stage_id;
            idx = find(mask);
            stage_summaries(row) = summarize_stage(time_s, values, options, idx, ...
                cycle_idx, stage_id);
            row = row + 1;
        end
    end

    summary = struct();
    summary.schema_version = 'heatdrive_ecc_simulink_3cycle_summary_v1';
    summary.model_name = options.model_name;
    summary.model_path = model_path;
    summary.output_dir = options.outputs_dir;
    summary.run_command = 'cd gx101r1_R69_remote; summary = Validate_HeatDriveECC_Simulink_3Cycle();';
    summary.simulink_executed = true;
    summary.core_block = 'heatdrive_ecc_1d51_fullcycle/HeatDriveECC_1D51_FullCycleCore';
    summary.core_block_type = 'Interpreted MATLAB Function driven by Simulink Clock';
    summary.cycle_count = options.cycle_count;
    summary.node_count_sma = options.node_count;
    summary.node_count_se = options.node_count;
    summary.sample_count = size(values, 1);
    summary.output_width = size(values, 2);
    summary.expected_output_width = map.output_width;
    summary.stage_summaries = stage_summaries;
    summary.min_stage_sample_count = min([stage_summaries.sample_count]);
    summary.max_abs_value = max(abs(values(:)));
    summary.max_eq6_scaled = max(abs(values(:, map.eq6_scaled)));
    summary.max_eq7_scaled = max(abs(values(:, map.eq7_scaled)));
    summary.max_force_residual_N = max(abs(values(:, map.force_residual_N)));
    summary.max_disp_residual_m = max(abs(values(:, map.disp_residual_m)));
    summary.stage_durations_s = options.schedule.stage_durations_s;
    summary.stage_duration_source = options.schedule.source;
    summary.not_legacy_timing = options.schedule.not_legacy_timing;
    summary.article = options.equilibrium;
    summary.final_T_a_mean_K = values(end, map.T_a_mean_K);
    summary.final_T_r_mean_K = values(end, map.T_r_mean_K);
    summary.final_xM_a_mean = values(end, map.xM_a_mean);
    summary.final_xM_r_mean = values(end, map.xM_r_mean);
    summary.final_sigma_r_Pa = values(end, map.sigma_r_Pa);
end

function out = empty_stage_summary()
    out = struct( ...
        'cycle_index', 0, ...
        'stage_id', 0, ...
        'stage_name', '', ...
        'sample_count', 0, ...
        'start_time_s', NaN, ...
        'end_time_s', NaN, ...
        'start_T_a_mean_K', NaN, ...
        'end_T_a_mean_K', NaN, ...
        'start_T_r_mean_K', NaN, ...
        'end_T_r_mean_K', NaN, ...
        'start_xM_a_mean', NaN, ...
        'end_xM_a_mean', NaN, ...
        'start_xM_r_mean', NaN, ...
        'end_xM_r_mean', NaN, ...
        'start_sigma_r_Pa', NaN, ...
        'end_sigma_r_Pa', NaN, ...
        'mean_Q_shex_W', NaN, ...
        'mean_Q_the_sma_W', NaN, ...
        'mean_Q_the_se_W', NaN, ...
        'mean_Q_rhe_W', NaN, ...
        'max_eq6_scaled', NaN, ...
        'max_eq7_scaled', NaN, ...
        'end_eq7_scaled', NaN);
end

function summary = summarize_stage(time_s, values, options, idx, cycle_idx, stage_id)
    map = options.output_map;
    summary = empty_stage_summary();
    summary.cycle_index = cycle_idx;
    summary.stage_id = stage_id;
    summary.stage_name = options.schedule.stage_names{stage_id};
    summary.sample_count = numel(idx);
    if isempty(idx)
        return;
    end

    first = idx(1);
    last = idx(end);
    summary.start_time_s = time_s(first);
    summary.end_time_s = time_s(last);
    summary.start_T_a_mean_K = values(first, map.T_a_mean_K);
    summary.end_T_a_mean_K = values(last, map.T_a_mean_K);
    summary.start_T_r_mean_K = values(first, map.T_r_mean_K);
    summary.end_T_r_mean_K = values(last, map.T_r_mean_K);
    summary.start_xM_a_mean = values(first, map.xM_a_mean);
    summary.end_xM_a_mean = values(last, map.xM_a_mean);
    summary.start_xM_r_mean = values(first, map.xM_r_mean);
    summary.end_xM_r_mean = values(last, map.xM_r_mean);
    summary.start_sigma_r_Pa = values(first, map.sigma_r_Pa);
    summary.end_sigma_r_Pa = values(last, map.sigma_r_Pa);
    summary.mean_Q_shex_W = mean(values(idx, map.Q_shex_W));
    summary.mean_Q_the_sma_W = mean(values(idx, map.Q_the_sma_W));
    summary.mean_Q_the_se_W = mean(values(idx, map.Q_the_se_W));
    summary.mean_Q_rhe_W = mean(values(idx, map.Q_rhe_W));
    summary.max_eq6_scaled = max(abs(values(idx, map.eq6_scaled)));
    summary.max_eq7_scaled = max(abs(values(idx, map.eq7_scaled)));
    summary.end_eq7_scaled = abs(values(last, map.eq7_scaled));
end

function probe_table = build_probe_table(time_s, values, options)
    map = options.output_map;
    samples_per_stage = options.simulation.stage_probe_samples;
    specs = probe_specs();

    probe_id = {};
    probe_name = {};
    component = {};
    cycle_index = [];
    stage_id = [];
    stage_name = {};
    sample_in_stage = [];
    time_col = [];
    temperature_K = [];
    temperature_C = [];
    route_id = [];
    valve_state_id = [];

    row = 0;
    for cycle_idx = 1:options.cycle_count
        for sid = 1:4
            stage_idx = find(round(values(:, map.cycle_index)) == cycle_idx & ...
                round(values(:, map.stage_id)) == sid);
            if isempty(stage_idx)
                continue;
            end
            pick = round(linspace(1, numel(stage_idx), ...
                min(samples_per_stage, numel(stage_idx))));
            selected_idx = stage_idx(pick);
            for p = 1:size(specs, 1)
                column_key = specs{p, 3};
                node_idx = specs{p, 4};
                if node_idx > 0
                    col = map.(column_key)(node_idx);
                else
                    col = map.(column_key);
                end
                for sample_idx = 1:numel(selected_idx)
                    i = selected_idx(sample_idx);
                    row = row + 1;
                    probe_id{row, 1} = sprintf('P%02d', p); %#ok<AGROW>
                    probe_name{row, 1} = specs{p, 1}; %#ok<AGROW>
                    component{row, 1} = specs{p, 2}; %#ok<AGROW>
                    cycle_index(row, 1) = cycle_idx; %#ok<AGROW>
                    stage_id(row, 1) = sid; %#ok<AGROW>
                    stage_name{row, 1} = options.schedule.stage_names{sid}; %#ok<AGROW>
                    sample_in_stage(row, 1) = sample_idx; %#ok<AGROW>
                    time_col(row, 1) = time_s(i); %#ok<AGROW>
                    temperature_K(row, 1) = values(i, col); %#ok<AGROW>
                    temperature_C(row, 1) = values(i, col) - 273.15; %#ok<AGROW>
                    route_id(row, 1) = values(i, map.route_id); %#ok<AGROW>
                    valve_state_id(row, 1) = 100 * values(i, map.stage_id) + ...
                        10 * values(i, map.valve1_position) + ...
                        values(i, map.valve2_position); %#ok<AGROW>
                end
            end
        end
    end

    probe_table = table(probe_id, probe_name, component, cycle_index, ...
        stage_id, stage_name, sample_in_stage, time_col, temperature_K, ...
        temperature_C, route_id, valve_state_id, ...
        'VariableNames', {'probe_id','probe_name','component','cycle_index', ...
        'stage_id','stage_name','sample_in_stage','time_s','temperature_K', ...
        'temperature_C','route_id','valve_state_id'});
end

function specs = probe_specs()
    specs = {
        'SMA_node_01', 'SMA', 'T_a_51', 1;
        'SMA_node_13', 'SMA', 'T_a_51', 13;
        'SMA_node_26', 'SMA', 'T_a_51', 26;
        'SMA_node_39', 'SMA', 'T_a_51', 39;
        'SMA_node_51', 'SMA', 'T_a_51', 51;
        'SMA_mean', 'SMA', 'T_a_mean_K', 0;
        'SMA_min', 'SMA', 'T_a_min_K', 0;
        'SMA_max', 'SMA', 'T_a_max_K', 0;
        'SMA_HTF_in', 'SMA_loop', 'SMA_HTF_in_K', 0;
        'SMA_HTF_out', 'SMA_loop', 'SMA_HTF_out_K', 0;
        'SMA_boundary', 'SMA_loop', 'SMA_boundary_K', 0;
        'SE_node_01', 'SE', 'T_r_51', 1;
        'SE_node_13', 'SE', 'T_r_51', 13;
        'SE_node_26', 'SE', 'T_r_51', 26;
        'SE_node_39', 'SE', 'T_r_51', 39;
        'SE_node_51', 'SE', 'T_r_51', 51;
        'SE_mean', 'SE', 'T_r_mean_K', 0;
        'SE_min', 'SE', 'T_r_min_K', 0;
        'SE_max', 'SE', 'T_r_max_K', 0;
        'SE_HTF_in', 'SE_loop', 'SE_HTF_in_K', 0;
        'SE_HTF_out', 'SE_loop', 'SE_HTF_out_K', 0;
        'SE_boundary', 'SE_loop', 'SE_boundary_K', 0;
        'SHEX_in', 'SHEX', 'SHEX_in_K', 0;
        'SHEX_out', 'SHEX', 'SHEX_out_K', 0;
        'THE_SMA', 'THE', 'THE_SMA_K', 0;
        'THE_SE', 'THE', 'THE_SE_K', 0;
        'RHE_in', 'RHE', 'RHE_in_K', 0;
        'RHE_out', 'RHE', 'RHE_out_K', 0};
end

function write_trend_plot(time_s, values, options, plot_path)
    map = options.output_map;
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 1100 760]);
    subplot(3, 1, 1);
    plot(time_s, values(:, map.T_a_mean_K), 'r-', ...
        time_s, values(:, map.T_r_mean_K), 'b-', 'LineWidth', 1.1);
    ylabel('Temperature K');
    legend({'SMA mean','SE mean'}, 'Location', 'best');
    grid on;

    subplot(3, 1, 2);
    plot(time_s, values(:, map.xM_a_mean), 'r-', ...
        time_s, values(:, map.xM_r_mean), 'b-', 'LineWidth', 1.1);
    ylabel('xM mean');
    legend({'SMA xM','SE xM'}, 'Location', 'best');
    grid on;

    subplot(3, 1, 3);
    plot(time_s, values(:, map.sigma_r_Pa) ./ 1.0e6, 'k-', ...
        time_s, values(:, map.Q_shex_W), 'r--', ...
        time_s, values(:, map.Q_the_se_W), 'm--', ...
        time_s, values(:, map.Q_rhe_W), 'b--', 'LineWidth', 1.1);
    xlabel('Time s');
    ylabel('MPa or W');
    legend({'SE stress MPa','SHEX W','THE-SE W','RHE W'}, 'Location', 'best');
    grid on;

    saveas(fig, plot_path);
    close(fig);
end

function write_json(path, value)
    fid = fopen(path, 'w');
    if fid < 0
        error('Run_HeatDriveECC_Simulink_3Cycle:CannotWriteJson', ...
            'Cannot open JSON output file: %s', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
    delete(cleaner);
end
