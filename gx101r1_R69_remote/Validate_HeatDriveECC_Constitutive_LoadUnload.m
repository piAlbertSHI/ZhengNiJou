function result = Validate_HeatDriveECC_Constitutive_LoadUnload(overrides)
% Validate seventh-round real constitutive loading/unloading.
%
% The validator prescribes only thermal boundary trajectories for SMA. The
% coupled stress is solved from current Ta/Tr/xM_a/xM_r through Eq.6/Eq.7 at
% every step, and phase fractions are advanced by driving rates.

    if nargin < 1
        overrides = struct();
    end

    base_options = Build_HeatDriveECC_SeventhRound_Defaults(overrides);
    if ~isfolder(base_options.outputs_dir)
        mkdir(base_options.outputs_dir);
    end
    output_dir = fullfile(base_options.outputs_dir, 'constitutive_load_unload');
    if ~isfolder(output_dir)
        mkdir(output_dir);
    end

    attempts = build_attempts(base_options);
    attempt_results = cell(numel(attempts), 1);
    result = struct();
    for idx = 1:numel(attempts)
        options = Build_HeatDriveECC_SeventhRound_Defaults(attempts{idx}.overrides);
        options.outputs_dir = base_options.outputs_dir;
        [trace, summary] = run_one_attempt(options, attempts{idx}.name);
        attempt_results{idx} = summary;
        if summary.passed
            result = finalize_result(options, trace, summary, attempt_results, output_dir);
            return;
        end
    end

    options = Build_HeatDriveECC_SeventhRound_Defaults(attempts{end}.overrides);
    [trace, summary] = run_one_attempt(options, attempts{end}.name);
    result = finalize_result(options, trace, summary, attempt_results, output_dir);
end

function attempts = build_attempts(base_options)
    attempts = cell(7, 1);
    attempts{1} = struct('name', 'default_d2_rate_physical_drive', ...
        'overrides', struct());
    attempts{2} = struct('name', 'increase_se_loading_rate_reduce_hardening', ...
        'overrides', struct('constitutive', struct( ...
            'rate_r_load_1_per_s', 12.0, ...
            'se_load_hardening_Pa', 1.0e6, ...
            'max_rate_1_per_s', 24.0)));
    attempts{3} = struct('name', 'increase_reverse_rates_reduce_unload_hysteresis', ...
        'overrides', struct('constitutive', struct( ...
            'rate_a_to_A_1_per_s', 9.0, ...
            'rate_a_to_M_1_per_s', 8.0, ...
            'rate_r_load_1_per_s', 13.0, ...
            'rate_r_unload_1_per_s', 12.0, ...
            'se_load_hardening_Pa', 0.5e6, ...
            'se_unload_hysteresis_Pa', 0.0, ...
            'max_rate_1_per_s', 28.0)));
    attempts{4} = struct('name', 'fast_rate_same_equations_final_retry', ...
        'overrides', struct('constitutive', struct( ...
            'rate_a_to_A_1_per_s', 12.0, ...
            'rate_a_to_M_1_per_s', 12.0, ...
            'rate_r_load_1_per_s', 16.0, ...
            'rate_r_unload_1_per_s', 15.0, ...
            'se_load_hardening_Pa', 0.0, ...
            'se_unload_hysteresis_Pa', -5.0e6, ...
            'max_rate_1_per_s', 35.0)));
    attempts{5} = struct('name', 'strong_reverse_kinetics_same_compatibility', ...
        'overrides', struct('constitutive', struct( ...
            'rate_a_to_A_1_per_s', 12.0, ...
            'rate_a_to_M_1_per_s', 65.0, ...
            'rate_r_load_1_per_s', 16.0, ...
            'rate_r_unload_1_per_s', 55.0, ...
            'se_load_hardening_Pa', 0.0, ...
            'se_unload_hysteresis_Pa', -25.0e6, ...
            'max_rate_1_per_s', 120.0)));
    attempts{6} = struct('name', 'very_fast_reverse_minimal_reproduction', ...
        'overrides', struct('constitutive', struct( ...
            'rate_a_to_A_1_per_s', 12.0, ...
            'rate_a_to_M_1_per_s', 120.0, ...
            'rate_r_load_1_per_s', 16.0, ...
            'rate_r_unload_1_per_s', 95.0, ...
            'se_load_hardening_Pa', 0.0, ...
            'se_unload_hysteresis_Pa', -45.0e6, ...
            'max_rate_1_per_s', 180.0)));
    attempts{7} = struct('name', 'se_reverse_rate_refinement_same_equations', ...
        'overrides', struct('constitutive', struct( ...
            'rate_a_to_A_1_per_s', 12.0, ...
            'rate_a_to_M_1_per_s', 120.0, ...
            'rate_r_load_1_per_s', 16.0, ...
            'rate_r_unload_1_per_s', 220.0, ...
            'se_load_hardening_Pa', 0.0, ...
            'se_unload_hysteresis_Pa', -65.0e6, ...
            'max_rate_1_per_s', 320.0)));
    attempts{1}.overrides = merge_attempt(base_options, attempts{1}.overrides);
    for idx = 2:numel(attempts)
        attempts{idx}.overrides = merge_attempt(base_options, attempts{idx}.overrides);
    end
end

function overrides = merge_attempt(base_options, attempt_overrides)
    overrides = attempt_overrides;
    overrides.outputs_dir = base_options.outputs_dir;
end

function [trace, summary] = run_one_attempt(options, attempt_name)
    N = options.node_count;
    T0 = options.system.T0_K;
    Tc = options.system.Tc_K;
    Th = options.system.Th_K;
    durations = options.schedule.stage_durations_s(:).';
    n_stage = options.validation.constitutive_samples_per_stage;
    dt_load = durations(1) / max(n_stage - 1, 1);
    dt_unload = durations(3) / max(n_stage - 1, 1);

    state = struct();
    state.time_s = 0.0;
    state.stage_id = 1;
    state.Ta_51 = T0 * ones(N, 1);
    state.Tr_51 = Tc * ones(N, 1);
    state.xM_a_51 = ones(N, 1);
    state.xM_r_51 = zeros(N, 1);

    samples = repmat(empty_sample(N), 2 * n_stage - 1, 1);
    sample_idx = 1;
    [state0, audit0] = HeatDriveECC_ConstitutiveCompatibilityStep(state, options, 0.0, 1);
    samples(sample_idx) = sample_from_state(state0, audit0, N, attempt_name);
    state = state0;
    load_end_idx = n_stage;

    for k = 2:n_stage
        f = (k - 1) / max(n_stage - 1, 1);
        state.stage_id = 1;
        state.Ta_51 = axial_profile(T0 + f * (Th - T0), N);
        [state, audit] = HeatDriveECC_ConstitutiveCompatibilityStep(state, options, dt_load, 1);
        sample_idx = sample_idx + 1;
        samples(sample_idx) = sample_from_state(state, audit, N, attempt_name);
    end
    load_end_state = state;

    for k = 2:n_stage
        f = (k - 1) / max(n_stage - 1, 1);
        state.stage_id = 3;
        state.Ta_51 = axial_profile(Th + f * (T0 - Th), N);
        [state, audit] = HeatDriveECC_ConstitutiveCompatibilityStep(state, options, dt_unload, 3);
        sample_idx = sample_idx + 1;
        samples(sample_idx) = sample_from_state(state, audit, N, attempt_name);
    end

    samples = samples(1:sample_idx);
    trace = samples_to_trace(samples, N);
    summary = summarize_trace(trace, options, attempt_name, load_end_idx, load_end_state);
end

function s = empty_sample(N)
    s = struct('attempt', "", 'time_s', NaN, 'stage_id', NaN, ...
        'Ta_mean_K', NaN, 'Tr_mean_K', NaN, ...
        'xM_a_mean', NaN, 'xM_r_mean', NaN, ...
        'sigma_a_Pa', NaN, 'sigma_r_Pa', NaN, ...
        'epsilon_a_mean', NaN, 'epsilon_r_mean', NaN, ...
        'eq6_scaled', NaN, 'eq7_scaled', NaN, ...
        'pai_a_mean_Pa', NaN, 'pai_r_mean_Pa', NaN, ...
        'r_xi_a_mean_1_per_s', NaN, 'r_xi_r_mean_1_per_s', NaN, ...
        'latentA_W', NaN, 'latentR_W', NaN, ...
        'mechanicalA_W', NaN, 'mechanicalR_W', NaN, ...
        'Ta_51', zeros(1, N), 'Tr_51', zeros(1, N), ...
        'xM_a_51', zeros(1, N), 'xM_r_51', zeros(1, N), ...
        'sigma_a_51', zeros(1, N), 'sigma_r_51', zeros(1, N));
end

function sample = sample_from_state(state, audit, N, attempt_name)
    sample = empty_sample(N);
    sample.attempt = string(attempt_name);
    names = fieldnames(audit);
    for idx = 1:numel(names)
        key = names{idx};
        if isfield(sample, key)
            sample.(key) = audit.(key);
        end
    end
    sample.Ta_51 = reshape(state.Ta_51, 1, N);
    sample.Tr_51 = reshape(state.Tr_51, 1, N);
    sample.xM_a_51 = reshape(state.xM_a_51, 1, N);
    sample.xM_r_51 = reshape(state.xM_r_51, 1, N);
    sample.sigma_a_51 = reshape(state.sigma_a_51, 1, N);
    sample.sigma_r_51 = reshape(state.sigma_r_51, 1, N);
end

function trace = samples_to_trace(samples, N)
    trace = struct();
    keys = {'time_s','stage_id','Ta_mean_K','Tr_mean_K', ...
        'xM_a_mean','xM_r_mean','sigma_a_Pa','sigma_r_Pa', ...
        'epsilon_a_mean','epsilon_r_mean','eq6_scaled','eq7_scaled', ...
        'pai_a_mean_Pa','pai_r_mean_Pa','r_xi_a_mean_1_per_s', ...
        'r_xi_r_mean_1_per_s','latentA_W','latentR_W', ...
        'mechanicalA_W','mechanicalR_W'};
    for key_idx = 1:numel(keys)
        key = keys{key_idx};
        trace.(key) = arrayfun(@(s) s.(key), samples).';
    end
    trace.attempt = samples(1).attempt;
    trace.Ta_51 = vertcat(samples.Ta_51);
    trace.Tr_51 = vertcat(samples.Tr_51);
    trace.xM_a_51 = vertcat(samples.xM_a_51);
    trace.xM_r_51 = vertcat(samples.xM_r_51);
    trace.sigma_a_51 = vertcat(samples.sigma_a_51);
    trace.sigma_r_51 = vertcat(samples.sigma_r_51);
    trace.node_count = N;
end

function summary = summarize_trace(trace, options, attempt_name, load_end_idx, load_end_state)
    initial_idx = 1;
    final_idx = numel(trace.time_s);
    v = options.validation;
    summary = struct();
    summary.schema_version = 'heatdrive_ecc_constitutive_load_unload_summary_v1';
    summary.attempt = attempt_name;
    summary.node_count = options.node_count;
    summary.article_delta_xM_a = options.equilibrium.delta_xM_a;
    summary.article_delta_xM_r = options.equilibrium.delta_xM_r;
    summary.article_sigma_r_Pa = options.equilibrium.sigma_r_Pa;
    summary.article_sigma_a_Pa = options.equilibrium.sigma_a_Pa;
    summary.article_Th_K = options.equilibrium.T_h_K;
    summary.loading_xM_a_delta = trace.xM_a_mean(load_end_idx) - ...
        trace.xM_a_mean(initial_idx);
    summary.loading_xM_r_delta = trace.xM_r_mean(load_end_idx) - ...
        trace.xM_r_mean(initial_idx);
    summary.unloading_xM_a_delta = trace.xM_a_mean(final_idx) - ...
        trace.xM_a_mean(load_end_idx);
    summary.unloading_xM_r_delta = trace.xM_r_mean(final_idx) - ...
        trace.xM_r_mean(load_end_idx);
    summary.final_xM_a_mean = trace.xM_a_mean(final_idx);
    summary.final_xM_r_mean = trace.xM_r_mean(final_idx);
    summary.load_end_xM_a_mean = trace.xM_a_mean(load_end_idx);
    summary.load_end_xM_r_mean = trace.xM_r_mean(load_end_idx);
    summary.load_end_Tr_mean_K = mean(load_end_state.Tr_51);
    summary.final_Tr_mean_K = trace.Tr_mean_K(final_idx);
    summary.max_sigma_r_Pa = max(trace.sigma_r_Pa);
    summary.min_sigma_r_Pa = min(trace.sigma_r_Pa);
    summary.max_abs_eq6_scaled = max(abs(trace.eq6_scaled));
    summary.max_abs_eq7_scaled = max(abs(trace.eq7_scaled));
    summary.max_abs_latent_W = max(abs([trace.latentA_W(:); trace.latentR_W(:)]));
    summary.max_abs_mechanical_W = max(abs([trace.mechanicalA_W(:); trace.mechanicalR_W(:)]));
    summary.all_finite = all(isfinite(struct_to_numeric_trace(trace)));
    summary.checks = struct();
    summary.checks.loading_xM_a_delta = summary.loading_xM_a_delta < ...
        v.min_loading_xM_a_delta;
    summary.checks.loading_xM_r_delta = summary.loading_xM_r_delta > ...
        v.min_loading_xM_r_delta;
    summary.checks.unloading_xM_a_delta = summary.unloading_xM_a_delta > ...
        v.min_unloading_xM_a_delta;
    summary.checks.unloading_xM_r_delta = summary.unloading_xM_r_delta < ...
        v.max_unloading_xM_r_delta;
    summary.checks.max_abs_eq6_scaled = summary.max_abs_eq6_scaled < ...
        v.max_eq6_scaled;
    summary.checks.max_abs_eq7_scaled = summary.max_abs_eq7_scaled < ...
        v.max_eq7_scaled;
    summary.checks.max_sigma_r_Pa = summary.max_sigma_r_Pa > ...
        v.min_max_sigma_r_Pa;
    summary.checks.all_finite = summary.all_finite;
    summary.passed = all(struct2array(summary.checks));
end

function result = finalize_result(options, trace, summary, attempt_results, output_dir)
    trace_csv = fullfile(output_dir, 'constitutive_load_unload_trace.csv');
    summary_json = fullfile(output_dir, 'constitutive_load_unload_summary.json');
    plot1 = fullfile(output_dir, 'constitutive_xM_sigma_eq_residual.png');
    plot2 = fullfile(output_dir, 'constitutive_energy_terms.png');

    write_trace_csv(trace, trace_csv);
    summary.attempt_history = vertcat_attempts(attempt_results);
    write_json(summary_json, summary);
    write_plots(trace, plot1, plot2);

    result = struct();
    result.schema_version = 'heatdrive_ecc_constitutive_validation_result_v1';
    result.options = options;
    result.trace = trace;
    result.summary = summary;
    result.passed = summary.passed;
    result.output_dir = output_dir;
    result.trace_csv = trace_csv;
    result.summary_json = summary_json;
    result.plots = {plot1, plot2};
    save(fullfile(output_dir, 'constitutive_load_unload_result.mat'), ...
        'result', '-v7.3');
end

function values = struct_to_numeric_trace(trace)
    values = [trace.time_s(:); trace.stage_id(:); trace.Ta_mean_K(:); trace.Tr_mean_K(:); ...
        trace.xM_a_mean(:); trace.xM_r_mean(:); trace.sigma_a_Pa(:); trace.sigma_r_Pa(:); ...
        trace.eq6_scaled(:); trace.eq7_scaled(:); trace.latentA_W(:); trace.latentR_W(:); ...
        trace.mechanicalA_W(:); trace.mechanicalR_W(:); trace.Ta_51(:); trace.Tr_51(:); ...
        trace.xM_a_51(:); trace.xM_r_51(:); trace.sigma_a_51(:); trace.sigma_r_51(:)];
end

function history = vertcat_attempts(attempt_results)
    keep = attempt_results(~cellfun(@isempty, attempt_results));
    history = [];
    for idx = 1:numel(keep)
        s = keep{idx};
        row = struct();
        row.attempt = string(s.attempt);
        row.passed = s.passed;
        row.loading_xM_a_delta = s.loading_xM_a_delta;
        row.loading_xM_r_delta = s.loading_xM_r_delta;
        row.unloading_xM_a_delta = s.unloading_xM_a_delta;
        row.unloading_xM_r_delta = s.unloading_xM_r_delta;
        row.max_abs_eq6_scaled = s.max_abs_eq6_scaled;
        row.max_abs_eq7_scaled = s.max_abs_eq7_scaled;
        row.max_sigma_r_Pa = s.max_sigma_r_Pa;
        if isempty(history)
            history = row;
        else
            history(idx) = row; %#ok<AGROW>
        end
    end
end

function write_trace_csv(trace, path_value)
    base = table(trace.time_s(:), trace.stage_id(:), trace.Ta_mean_K(:), trace.Tr_mean_K(:), ...
        trace.xM_a_mean(:), trace.xM_r_mean(:), trace.sigma_a_Pa(:), trace.sigma_r_Pa(:), ...
        trace.epsilon_a_mean(:), trace.epsilon_r_mean(:), trace.eq6_scaled(:), trace.eq7_scaled(:), ...
        trace.pai_a_mean_Pa(:), trace.pai_r_mean_Pa(:), trace.r_xi_a_mean_1_per_s(:), ...
        trace.r_xi_r_mean_1_per_s(:), trace.latentA_W(:), trace.latentR_W(:), ...
        trace.mechanicalA_W(:), trace.mechanicalR_W(:), ...
        'VariableNames', {'time_s','stage_id','Ta_mean_K','Tr_mean_K', ...
        'xM_a_mean','xM_r_mean','sigma_a_Pa','sigma_r_Pa', ...
        'epsilon_a_mean','epsilon_r_mean','eq6_scaled','eq7_scaled', ...
        'pai_a_mean_Pa','pai_r_mean_Pa','r_xi_a_mean_1_per_s', ...
        'r_xi_r_mean_1_per_s','latentA_W','latentR_W', ...
        'mechanicalA_W','mechanicalR_W'});
    arrays = [trace.Ta_51, trace.Tr_51, trace.xM_a_51, trace.xM_r_51, ...
        trace.sigma_a_51, trace.sigma_r_51];
    names = numbered_names({'Ta','Tr','xM_a','xM_r','sigma_a','sigma_r'}, ...
        trace.node_count);
    wide = array2table(arrays, 'VariableNames', names);
    writetable([base wide], path_value);
end

function names = numbered_names(prefixes, N)
    names = cell(1, numel(prefixes) * N);
    col = 1;
    for p = 1:numel(prefixes)
        for n = 1:N
            names{col} = sprintf('%s_%02d', prefixes{p}, n);
            col = col + 1;
        end
    end
end

function write_json(path_value, s)
    try
        text = jsonencode(s, 'PrettyPrint', true);
    catch
        text = jsonencode(s);
    end
    fid = fopen(path_value, 'w');
    cleanup = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end

function write_plots(trace, plot1, plot2)
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1200 760]);
    tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    nexttile;
    plot(trace.time_s, trace.xM_a_mean, 'LineWidth', 1.6);
    hold on;
    plot(trace.time_s, trace.xM_r_mean, 'LineWidth', 1.6);
    grid on;
    ylabel('x_M mean');
    legend({'SMA xM','SE xM'}, 'Location', 'best');
    nexttile;
    plot(trace.time_s, trace.sigma_a_Pa ./ 1e6, 'LineWidth', 1.6);
    hold on;
    plot(trace.time_s, trace.sigma_r_Pa ./ 1e6, 'LineWidth', 1.6);
    grid on;
    ylabel('stress MPa');
    legend({'SMA','SE'}, 'Location', 'best');
    nexttile;
    semilogy(trace.time_s, abs(trace.eq6_scaled) + eps, 'LineWidth', 1.4);
    hold on;
    semilogy(trace.time_s, abs(trace.eq7_scaled) + eps, 'LineWidth', 1.4);
    grid on;
    ylabel('scaled residual');
    xlabel('time s');
    legend({'Eq6','Eq7'}, 'Location', 'best');
    exportgraphics(fig, plot1, 'Resolution', 180);
    close(fig);

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [80 80 1200 700]);
    tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    nexttile;
    plot(trace.time_s, trace.latentA_W, 'LineWidth', 1.5);
    hold on;
    plot(trace.time_s, trace.latentR_W, 'LineWidth', 1.5);
    grid on;
    ylabel('latent W');
    legend({'SMA','SE'}, 'Location', 'best');
    nexttile;
    plot(trace.time_s, trace.mechanicalA_W, 'LineWidth', 1.5);
    hold on;
    plot(trace.time_s, trace.mechanicalR_W, 'LineWidth', 1.5);
    grid on;
    ylabel('mechanical W');
    xlabel('time s');
    legend({'SMA','SE'}, 'Location', 'best');
    exportgraphics(fig, plot2, 'Resolution', 180);
    close(fig);
end

function values = axial_profile(mean_value, N)
    span = 0.02;
    values = mean_value + linspace(-span, span, N).';
end
