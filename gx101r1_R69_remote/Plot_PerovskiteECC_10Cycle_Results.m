function plot_paths = Plot_PerovskiteECC_10Cycle_Results(result_path, plots_dir)
% Plot the article 10-cycle Perovskite ECC result for visual inspection.

    root_dir = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(result_path)
        result_path = fullfile(root_dir, 'outputs_perovskite_article_10cycle', ...
            'perovskite_article_10cycle_result.mat');
    end
    if ~exist(result_path, 'file')
        run_result = Run_PerovskiteECC_Article_Cycles();
        result_path = run_result.output_paths.result_mat;
    end
    if nargin < 2 || isempty(plots_dir)
        plots_dir = fullfile(fileparts(result_path), 'plots');
    end
    if ~exist(plots_dir, 'dir')
        mkdir(plots_dir);
    end

    loaded = load(result_path, 'result');
    result = loaded.result;
    traces = build_stage_traces(result);
    write_stage_trace_csv(traces, fullfile(plots_dir, 'perovskite_10cycle_stage_trace.csv'));

    plot_paths = struct();
    plot_paths.temperature_means = plot_temperature_means(traces, result, plots_dir);
    plot_paths.cold_end = plot_cold_end(traces, result, plots_dir);
    plot_paths.phase_fraction = plot_phase_fraction(traces, plots_dir);
    plot_paths.performance = plot_performance(result, plots_dir);
    plot_paths.temperature_heatmap = plot_temperature_heatmap(traces, plots_dir);
    plot_paths.latent_and_rate = plot_latent_and_rate(traces, plots_dir);
    plot_paths.stage_trace_csv = fullfile(plots_dir, 'perovskite_10cycle_stage_trace.csv');
end

function traces = build_stage_traces(result)
    stage_count = result.summary.stage_count;
    node_count = result.summary.node_count_sma;
    traces.stage_ordinal = zeros(stage_count, 1);
    traces.cycle_index = zeros(stage_count, 1);
    traces.stage_index = zeros(stage_count, 1);
    traces.stage_name = strings(stage_count, 1);
    traces.SMA_T_mean_K = zeros(stage_count, 1);
    traces.SE_T_mean_K = zeros(stage_count, 1);
    traces.SMA_xM_mean = zeros(stage_count, 1);
    traces.SE_xM_mean = zeros(stage_count, 1);
    traces.SE_T_min_K = zeros(stage_count, 1);
    traces.SE_T_max_K = zeros(stage_count, 1);
    traces.SE_node1_T_K = zeros(stage_count, 1);
    traces.SE_node51_T_K = zeros(stage_count, 1);
    traces.SE_cold_end_proxy_K = zeros(stage_count, 1);
    traces.SE_cold_inlet_proxy_K = zeros(stage_count, 1);
    traces.SMA_q_latent_mean_W_per_m3 = zeros(stage_count, 1);
    traces.SE_q_latent_mean_W_per_m3 = zeros(stage_count, 1);
    traces.SMA_r_xi_mean_1_per_s = zeros(stage_count, 1);
    traces.SE_r_xi_mean_1_per_s = zeros(stage_count, 1);
    traces.SMA_T_matrix_K = zeros(node_count, stage_count);
    traces.SE_T_matrix_K = zeros(node_count, stage_count);

    cursor = 0;
    for cidx = 1:numel(result.cycle_results)
        cycle = result.cycle_results(cidx);
        for sidx = 1:numel(cycle.stages)
            cursor = cursor + 1;
            stage = cycle.stages(sidx);
            traces.stage_ordinal(cursor) = cursor;
            traces.cycle_index(cursor) = cidx;
            traces.stage_index(cursor) = sidx;
            traces.stage_name(cursor) = string(stage.stage_report.stage_name);
            traces.SMA_T_mean_K(cursor) = mean(stage.SMA.T_51);
            traces.SE_T_mean_K(cursor) = mean(stage.SE.T_51);
            traces.SMA_xM_mean(cursor) = mean(stage.SMA.xM_51);
            traces.SE_xM_mean(cursor) = mean(stage.SE.xM_51);
            traces.SE_T_min_K(cursor) = min(stage.SE.T_51);
            traces.SE_T_max_K(cursor) = max(stage.SE.T_51);
            traces.SE_node1_T_K(cursor) = stage.SE.T_51(1);
            traces.SE_node51_T_K(cursor) = stage.SE.T_51(end);
            traces.SE_cold_end_proxy_K(cursor) = min(stage.SE.T_51);
            traces.SE_cold_inlet_proxy_K(cursor) = stage.SE.T_51(end);
            traces.SMA_q_latent_mean_W_per_m3(cursor) = mean(stage.SMA.q_latent_51);
            traces.SE_q_latent_mean_W_per_m3(cursor) = mean(stage.SE.q_latent_51);
            traces.SMA_r_xi_mean_1_per_s(cursor) = mean(stage.SMA.r_xi_51);
            traces.SE_r_xi_mean_1_per_s(cursor) = mean(stage.SE.r_xi_51);
            traces.SMA_T_matrix_K(:, cursor) = stage.SMA.T_51(:);
            traces.SE_T_matrix_K(:, cursor) = stage.SE.T_51(:);
        end
    end
end

function write_stage_trace_csv(traces, csv_path)
    T = table(traces.stage_ordinal, traces.cycle_index, traces.stage_index, traces.stage_name, ...
        traces.SMA_T_mean_K, traces.SE_T_mean_K, traces.SMA_xM_mean, traces.SE_xM_mean, ...
        traces.SE_T_min_K, traces.SE_T_max_K, traces.SE_node1_T_K, traces.SE_node51_T_K, ...
        traces.SE_cold_end_proxy_K, traces.SE_cold_inlet_proxy_K, ...
        traces.SMA_r_xi_mean_1_per_s, traces.SE_r_xi_mean_1_per_s, ...
        traces.SMA_q_latent_mean_W_per_m3, traces.SE_q_latent_mean_W_per_m3, ...
        'VariableNames', {'stage_ordinal', 'cycle_index', 'stage_index', 'stage_name', ...
        'SMA_T_mean_K', 'SE_core_T_mean_K', 'SMA_xM_mean', 'SE_core_xM_mean', ...
        'SE_T_min_K', 'SE_T_max_K', 'SE_node1_T_K', 'SE_node51_T_K', ...
        'cold_end_proxy_K', 'cold_inlet_proxy_K', ...
        'SMA_r_xi_mean_1_per_s', 'SE_r_xi_mean_1_per_s', ...
        'SMA_q_latent_mean_W_per_m3', 'SE_q_latent_mean_W_per_m3'});
    writetable(T, csv_path);
end

function path = plot_temperature_means(traces, result, plots_dir)
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1100, 520]);
    plot(traces.stage_ordinal, traces.SMA_T_mean_K, '-o', 'LineWidth', 1.5, 'MarkerSize', 4);
    hold on;
    plot(traces.stage_ordinal, traces.SE_T_mean_K, '-s', 'LineWidth', 1.5, 'MarkerSize', 4);
    yline(result.summary.ecc.T_h_K, '--', 'Th', 'LabelHorizontalAlignment', 'left');
    yline(result.options.system.T0_K, ':', 'T0', 'LabelHorizontalAlignment', 'left');
    yline(result.options.system.T_c_K, ':', 'Tc', 'LabelHorizontalAlignment', 'left');
    decorate_stage_axis(traces, '10-cycle mean temperature at stage endpoints');
    ylabel('Temperature (K)');
    legend({'Actuator SMA mean', 'Core SE/NiTi mean', 'Th', 'T0', 'Tc'}, 'Location', 'best');
    path = fullfile(plots_dir, 'temperature_means_10cycle.png');
    save_figure(fig, path);
end

function path = plot_cold_end(traces, result, plots_dir)
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1100, 520]);
    plot(traces.stage_ordinal, traces.SE_cold_end_proxy_K, '-o', 'LineWidth', 1.5, 'MarkerSize', 4);
    hold on;
    plot(traces.stage_ordinal, traces.SE_cold_inlet_proxy_K, '-s', 'LineWidth', 1.5, 'MarkerSize', 4);
    plot(traces.stage_ordinal, traces.SE_node1_T_K, '--', 'LineWidth', 1.0);
    plot(traces.stage_ordinal, traces.SE_node51_T_K, '--', 'LineWidth', 1.0);
    yline(result.options.system.T_c_K, ':', 'Tc', 'LabelHorizontalAlignment', 'left');
    yline(result.options.system.T0_K, ':', 'T0', 'LabelHorizontalAlignment', 'left');
    decorate_stage_axis(traces, 'Cold-side temperature proxies');
    ylabel('Temperature (K)');
    legend({'Cold-end proxy min(SE.T)', 'Cold-inlet proxy SE node 51', ...
        'SE node 1', 'SE node 51', 'Tc', 'T0'}, 'Location', 'best');
    path = fullfile(plots_dir, 'cold_end_temperatures_10cycle.png');
    save_figure(fig, path);
end

function path = plot_phase_fraction(traces, plots_dir)
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1100, 520]);
    plot(traces.stage_ordinal, traces.SMA_xM_mean, '-o', 'LineWidth', 1.5, 'MarkerSize', 4);
    hold on;
    plot(traces.stage_ordinal, traces.SE_xM_mean, '-s', 'LineWidth', 1.5, 'MarkerSize', 4);
    ylim([-0.05, 1.05]);
    decorate_stage_axis(traces, 'Mean martensite fraction');
    ylabel('xM');
    legend({'Actuator SMA mean xM', 'Core SE/NiTi mean xM'}, 'Location', 'best');
    path = fullfile(plots_dir, 'phase_fraction_10cycle.png');
    save_figure(fig, path);
end

function path = plot_performance(result, plots_dir)
    n = numel(result.cycle_results);
    cycles = (1:n).';
    PPSC = zeros(n, 1);
    PECC = zeros(n, 1);
    PH = zeros(n, 1);
    etaPSC = zeros(n, 1);
    etaECC = zeros(n, 1);
    etaH = zeros(n, 1);
    Qh = zeros(n, 1);
    Qr = zeros(n, 1);
    nu = zeros(n, 1);
    for idx = 1:n
        m = result.cycle_results(idx).metrics;
        PPSC(idx) = m.PPSC;
        PECC(idx) = m.PECC;
        PH(idx) = m.PH;
        etaPSC(idx) = m.etaPSC;
        etaECC(idx) = m.etaECC;
        etaH(idx) = m.etaH;
        Qh(idx) = m.Qh;
        Qr(idx) = m.Qr;
        nu(idx) = m.nu;
    end

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1100, 760]);
    tiledlayout(3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    nexttile;
    plot(cycles, PPSC, '-o', cycles, PECC, '-s', cycles, PH, '-^', 'LineWidth', 1.5);
    grid on;
    ylabel('Power (W)');
    title('10-cycle PSC/ECC/hybrid performance');
    legend({'PPSC', 'PECC', 'PH'}, 'Location', 'best');

    nexttile;
    plot(cycles, 100 * etaPSC, '-o', cycles, 100 * etaECC, '-s', cycles, 100 * etaH, '-^', 'LineWidth', 1.5);
    grid on;
    ylabel('Efficiency (%)');
    legend({'etaPSC', 'etaECC', 'etaH'}, 'Location', 'best');

    nexttile;
    yyaxis left;
    plot(cycles, Qh, '-o', cycles, Qr, '-s', 'LineWidth', 1.5);
    ylabel('Heat / cooling rate (W)');
    yyaxis right;
    plot(cycles, nu, '-^', 'LineWidth', 1.5);
    ylabel('Cycle frequency (Hz)');
    xlabel('Cycle index');
    grid on;
    legend({'Qh=Qa', 'Qr', 'nu'}, 'Location', 'best');
    path = fullfile(plots_dir, 'performance_10cycle.png');
    save_figure(fig, path);
end

function path = plot_temperature_heatmap(traces, plots_dir)
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1120, 720]);
    tiledlayout(2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    nexttile;
    imagesc(traces.stage_ordinal, 1:size(traces.SMA_T_matrix_K, 1), traces.SMA_T_matrix_K);
    axis tight;
    colorbar;
    ylabel('SMA node index');
    title('Actuator SMA T_{51} heatmap (K)');
    nexttile;
    imagesc(traces.stage_ordinal, 1:size(traces.SE_T_matrix_K, 1), traces.SE_T_matrix_K);
    axis tight;
    colorbar;
    ylabel('Core SE/NiTi node index');
    xlabel('Stage endpoint ordinal');
    title('Core SE/NiTi T_{51} heatmap (K)');
    path = fullfile(plots_dir, 'temperature_heatmap_10cycle.png');
    save_figure(fig, path);
end

function path = plot_latent_and_rate(traces, plots_dir)
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 1100, 720]);
    tiledlayout(2, 1, 'Padding', 'compact', 'TileSpacing', 'compact');
    nexttile;
    plot(traces.stage_ordinal, traces.SMA_r_xi_mean_1_per_s, '-o', ...
        traces.stage_ordinal, traces.SE_r_xi_mean_1_per_s, '-s', 'LineWidth', 1.5);
    grid on;
    ylabel('Mean r\_xi (1/s)');
    title('Stage-mean transformation rate');
    legend({'Actuator SMA', 'Core SE/NiTi'}, 'Location', 'best');
    nexttile;
    plot(traces.stage_ordinal, traces.SMA_q_latent_mean_W_per_m3, '-o', ...
        traces.stage_ordinal, traces.SE_q_latent_mean_W_per_m3, '-s', 'LineWidth', 1.5);
    grid on;
    xlabel('Stage endpoint ordinal');
    ylabel('Mean q\_latent (W/m^3)');
    title('Stage-mean latent heat source');
    legend({'Actuator SMA', 'Core SE/NiTi'}, 'Location', 'best');
    path = fullfile(plots_dir, 'latent_and_rate_10cycle.png');
    save_figure(fig, path);
end

function decorate_stage_axis(traces, title_text)
    grid on;
    xlabel('Stage endpoint ordinal (4 stages per cycle)');
    title(title_text);
    xlim([1, max(traces.stage_ordinal)]);
    xticks(1:4:max(traces.stage_ordinal));
    for idx = 4.5:4:max(traces.stage_ordinal)
        xline(idx, ':', 'Color', [0.7, 0.7, 0.7], 'HandleVisibility', 'off');
    end
end

function save_figure(fig, path)
    normalize_figure_style(fig);
    try
        exportgraphics(fig, path, 'Resolution', 180);
    catch
        saveas(fig, path);
    end
    close(fig);
end

function normalize_figure_style(fig)
    set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
    axes_handles = findall(fig, 'Type', 'axes');
    for idx = 1:numel(axes_handles)
        set(axes_handles(idx), 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
            'GridColor', [0.75, 0.75, 0.75], 'MinorGridColor', [0.85, 0.85, 0.85]);
        title_handle = get(axes_handles(idx), 'Title');
        xlabel_handle = get(axes_handles(idx), 'XLabel');
        ylabel_handle = get(axes_handles(idx), 'YLabel');
        set([title_handle, xlabel_handle, ylabel_handle], 'Color', 'k');
    end
    legends = findall(fig, 'Type', 'Legend');
    for idx = 1:numel(legends)
        set(legends(idx), 'Color', 'w', 'TextColor', 'k', 'EdgeColor', [0.3, 0.3, 0.3]);
    end
end
