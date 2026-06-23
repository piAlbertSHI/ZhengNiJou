function figure_paths = Plot_HeatDriveECC_LongTask_Results(result_mat_path)
% Generate white-background diagnostic figures for long-task verification.

    if nargin < 1 || isempty(result_mat_path)
        root_dir = fileparts(fileparts(mfilename('fullpath')));
        result_mat_path = fullfile(root_dir, 'outputs', 'long_task', ...
            'threecycle_check.mat');
    end
    S = load(result_mat_path, 'simOut', 'options');
    outdir = fullfile(fileparts(result_mat_path), 'figures');
    if ~exist(outdir, 'dir')
        mkdir(outdir);
    end

    figure_paths = strings(0, 1);
    figure_paths(end + 1, 1) = plot_mean_temperature(S.simOut, outdir);
    figure_paths(end + 1, 1) = plot_node_temperature(S.simOut, S.options, outdir);
    figure_paths(end + 1, 1) = plot_phase_stress(S.simOut, S.options, outdir);
    figure_paths(end + 1, 1) = plot_probe_temperatures(S.simOut, outdir);

    fprintf('Generated %d figures in %s\n', numel(figure_paths), outdir);
    for idx = 1:numel(figure_paths)
        fprintf('%s\n', figure_paths(idx));
    end
end

function path = plot_mean_temperature(simOut, outdir)
    [tSma, sma] = signal_matrix(simOut.get('SMA_Tx21_internal'));
    [tSe, se] = signal_matrix(simOut.get('SE_Tx21_internal'));
    fig = new_figure();
    plot_band(tSma, sma, [0.0 0.30 0.75], 'SMA');
    plot_band(tSe, se, [0.85 0.25 0.10], 'SE');
    xlabel('Time (s)');
    ylabel('Temperature (K)');
    title('SMA and SE Mean/Range Temperature');
    legend('SMA mean', 'SMA range', 'SE mean', 'SE range', ...
        'Location', 'best');
    path = save_figure(fig, outdir, 'sma_se_mean_temperature.png');
end

function path = plot_node_temperature(simOut, options, outdir)
    [tSma, sma] = signal_matrix(simOut.get('SMA_Tx21_internal'));
    [tSe, se] = signal_matrix(simOut.get('SE_Tx21_internal'));
    nodes = unique(round(linspace(1, options.node_count, 5)));
    fig = new_figure();
    tiledlayout(2, 1, 'TileSpacing', 'compact');
    nexttile;
    plot(tSma, sma(:, nodes), 'LineWidth', 1.0);
    grid on;
    ylabel('SMA T (K)');
    title('SMA Node Temperatures');
    legend(node_labels(nodes), 'Location', 'bestoutside');
    nexttile;
    plot(tSe, se(:, nodes), 'LineWidth', 1.0);
    grid on;
    xlabel('Time (s)');
    ylabel('SE T (K)');
    title('SE Node Temperatures');
    legend(node_labels(nodes), 'Location', 'bestoutside');
    path = save_figure(fig, outdir, 'sma_se_node_temperatures.png');
end

function path = plot_phase_stress(simOut, options, outdir)
    [t, y] = signal_matrix(simOut.get('ECC_constitutive21_output'));
    N = options.node_count;
    state = y(:, (2 * N + 1):end);
    xA = mean(state(:, 1:N), 2);
    xR = mean(state(:, (N + 1):(2 * N)), 2);
    sigmaA = mean(state(:, (2 * N + 1):(3 * N)), 2) ./ 1.0e6;
    sigmaR = mean(state(:, (3 * N + 1):(4 * N)), 2) ./ 1.0e6;

    fig = new_figure();
    tiledlayout(2, 1, 'TileSpacing', 'compact');
    nexttile;
    plot(t, xA, 'LineWidth', 1.2);
    hold on;
    plot(t, xR, 'LineWidth', 1.2);
    grid on;
    ylabel('Martensite fraction');
    title('Constitutive State');
    legend('SMA x_M', 'SE x_M', 'Location', 'best');
    nexttile;
    plot(t, sigmaA, 'LineWidth', 1.2);
    hold on;
    plot(t, sigmaR, 'LineWidth', 1.2);
    grid on;
    xlabel('Time (s)');
    ylabel('Stress (MPa)');
    legend('SMA stress', 'SE stress', 'Location', 'best');
    path = save_figure(fig, outdir, 'phase_fraction_and_stress.png');
end

function path = plot_probe_temperatures(simOut, outdir)
    names = { ...
        'shex_buffer_temp_out', ...
        'hot_buffer_temp_out', ...
        'cold_buffer_temp_out', ...
        'sma_stage1_inlet_fluid_temp_out', ...
        'sma_stage1_outlet_fluid_temp_out', ...
        'sma_stage3_inlet_fluid_temp_out', ...
        'sma_stage3_outlet_fluid_temp_out', ...
        'hhex_sma_branch_inlet_fluid_temp_out', ...
        'hhex_sma_branch_outlet_fluid_temp_out'};
    fig = new_figure();
    hold on;
    plotted = strings(0, 1);
    for idx = 1:numel(names)
        if ~any(strcmp(simOut.who, names{idx}))
            continue;
        end
        [t, y] = signal_matrix(simOut.get(names{idx}));
        plot(t, y(:, 1), 'LineWidth', 1.0);
        plotted(end + 1, 1) = string(names{idx}); %#ok<AGROW>
    end
    grid on;
    xlabel('Time (s)');
    ylabel('Temperature (K)');
    title('Heat Exchanger and SMA Route Probes');
    legend(strrep(plotted, '_', '\_'), 'Location', 'bestoutside');
    path = save_figure(fig, outdir, 'probe_temperatures.png');
end

function fig = new_figure()
    fig = figure('Visible', 'off', 'Color', 'w', ...
        'Position', [100 100 1300 760]);
    set(fig, 'InvertHardcopy', 'off');
    set(fig, ...
        'DefaultAxesColor', 'w', ...
        'DefaultAxesXColor', 'k', ...
        'DefaultAxesYColor', 'k', ...
        'DefaultAxesZColor', 'k', ...
        'DefaultAxesGridColor', [0.75 0.75 0.75], ...
        'DefaultAxesMinorGridColor', [0.85 0.85 0.85], ...
        'DefaultTextColor', 'k', ...
        'DefaultLegendColor', 'w', ...
        'DefaultLegendTextColor', 'k');
end

function plot_band(t, values, color, label_text)
    mean_values = mean(values, 2);
    min_values = min(values, [], 2);
    max_values = max(values, [], 2);
    fill([t; flipud(t)], [min_values; flipud(max_values)], color, ...
        'FaceAlpha', 0.12, 'EdgeColor', 'none', ...
        'DisplayName', [label_text ' range']);
    hold on;
    plot(t, mean_values, 'Color', color, 'LineWidth', 1.4, ...
        'DisplayName', [label_text ' mean']);
    grid on;
end

function labels = node_labels(nodes)
    labels = strings(numel(nodes), 1);
    for idx = 1:numel(nodes)
        labels(idx) = "node " + nodes(idx);
    end
end

function [t, y] = signal_matrix(signal)
    if isa(signal, 'timeseries')
        t = signal.Time(:);
        y = squeeze(signal.Data);
    else
        t = signal.time(:);
        y = squeeze(signal.signals.values);
    end
    if isvector(y)
        y = y(:);
    elseif size(y, 1) ~= numel(t)
        y = y.';
    end
    t = double(t);
    y = double(y);
end

function path = save_figure(fig, outdir, file_name)
    path = string(fullfile(outdir, file_name));
    exportgraphics(fig, path, 'Resolution', 180, 'BackgroundColor', 'white');
    close(fig);
end
