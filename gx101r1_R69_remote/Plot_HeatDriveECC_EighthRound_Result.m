function figures = Plot_HeatDriveECC_EighthRound_Result(result, tag)
% Write standalone white-background plots for one eighth-round ECC run.

    if nargin < 2 || isempty(tag)
        tag = sprintf('%dcycle', result.options.cycle_count);
    end
    out_dir = fullfile(result.options.outputs_dir, 'figures');
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    figures = {};
    figures{end + 1} = plot_mean_solid_temperatures(result, tag, out_dir);
    figures{end + 1} = plot_boundary_temperatures(result, tag, out_dir);
    figures{end + 1} = plot_representative_nodes(result, 'SMA', tag, out_dir);
    figures{end + 1} = plot_representative_nodes(result, 'SE', tag, out_dir);
    figures{end + 1} = plot_branch_inlet_outlet_temperatures(result, tag, out_dir);
    figures{end + 1} = plot_branch_internal_mean_temperatures(result, tag, out_dir);
    figures{end + 1} = plot_heat_rates(result, tag, out_dir);
    figures{end + 1} = plot_phase_and_stress(result, tag, out_dir);
end

function path = plot_mean_solid_temperatures(result, tag, out_dir)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(out_dir, [tag '_SMA_SE_mean_temperature.png']);
    fig = new_figure();
    plot(t, Y(:, map.Ta_mean_K), 'LineWidth', 1.4);
    hold on;
    plot(t, Y(:, map.Tr_mean_K), 'LineWidth', 1.4);
    yline(result.options.system.Th_K, ':', 'Th');
    yline(result.options.system.T0_K, ':', 'T0');
    yline(result.options.system.Tc_K, ':', 'Tc');
    grid on;
    xlabel('time (s)');
    ylabel('temperature (K)');
    legend({'SMA mean','SE mean','Th','T0','Tc'}, 'Location', 'best');
    title('SMA and SE mean temperatures');
    export_and_close(fig, path);
end

function path = plot_boundary_temperatures(result, tag, out_dir)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(out_dir, [tag '_SHEX_HHEX_CHEX_boundary_temperature.png']);
    fig = new_figure();
    plot(t, Y(:, map.SHEX_boundary_T_K), 'LineWidth', 1.4);
    hold on;
    plot(t, Y(:, map.HHEX_boundary_T_K), 'LineWidth', 1.4);
    plot(t, Y(:, map.CHEX_boundary_T_K), 'LineWidth', 1.4);
    yline(result.options.system.Tshex_source_K, ':', 'TPSC');
    yline(result.options.system.Thhex_K, ':', 'T0/HHEX ref');
    yline(result.options.system.Tchex_K, ':', 'Tc/CHEX ref');
    grid on;
    xlabel('time (s)');
    ylabel('temperature (K)');
    legend({'SHEX boundary','HHEX boundary','CHEX boundary', ...
        'TPSC','T0','Tc'}, 'Location', 'best');
    title('Heat exchanger boundary temperatures');
    export_and_close(fig, path);
end

function path = plot_representative_nodes(result, solid_name, tag, out_dir)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    nodes = representative_nodes(result.options.node_count);
    if strcmpi(solid_name, 'SMA')
        arr = map.Ta_21;
        path = fullfile(out_dir, [tag '_SMA_node_temperatures.png']);
        title_text = 'SMA node temperatures';
    else
        arr = map.Tr_21;
        path = fullfile(out_dir, [tag '_SE_node_temperatures.png']);
        title_text = 'SE node temperatures';
    end
    fig = new_figure();
    plot(t, Y(:, arr(nodes)), 'LineWidth', 1.1);
    grid on;
    xlabel('time (s)');
    ylabel('temperature (K)');
    legend(compose('node %d', nodes), 'Location', 'best');
    title(title_text);
    export_and_close(fig, path);
end

function path = plot_branch_inlet_outlet_temperatures(result, tag, out_dir)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(out_dir, [tag '_branch_inlet_outlet_temperature.png']);
    fig = new_figure();
    plot(t, Y(:, map.SMA_SHEX_Tin_K), '-', t, Y(:, map.SMA_SHEX_Tout_K), '--', ...
        t, Y(:, map.SMA_THE_Tin_K), '-', t, Y(:, map.SMA_THE_Tout_K), '--', ...
        t, Y(:, map.SE_THE_Tin_K), '-', t, Y(:, map.SE_THE_Tout_K), '--', ...
        t, Y(:, map.SE_CHEX_Tin_K), '-', t, Y(:, map.SE_CHEX_Tout_K), '--', ...
        'LineWidth', 1.0);
    grid on;
    xlabel('time (s)');
    ylabel('fluid temperature (K)');
    legend({'SMA-SHEX in','SMA-SHEX out','SMA-HHEX in','SMA-HHEX out', ...
        'SE-HHEX in','SE-HHEX out','SE-CHEX in','SE-CHEX out'}, ...
        'Location', 'bestoutside');
    title('Branch inlet and outlet temperatures');
    export_and_close(fig, path);
end

function path = plot_branch_internal_mean_temperatures(result, tag, out_dir)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(out_dir, [tag '_branch_internal_mean_temperature.png']);
    fig = new_figure();
    plot(t, mean(Y(:, map.SMA_SHEX_Tfluid_21), 2), 'LineWidth', 1.2);
    hold on;
    plot(t, mean(Y(:, map.SMA_THE_Tfluid_21), 2), 'LineWidth', 1.2);
    plot(t, mean(Y(:, map.SE_THE_Tfluid_21), 2), 'LineWidth', 1.2);
    plot(t, mean(Y(:, map.SE_CHEX_Tfluid_21), 2), 'LineWidth', 1.2);
    grid on;
    xlabel('time (s)');
    ylabel('mean fluid temperature (K)');
    legend({'SMA-SHEX','SMA-HHEX','SE-HHEX','SE-CHEX'}, 'Location', 'best');
    title('Internal branch mean fluid temperatures');
    export_and_close(fig, path);
end

function path = plot_heat_rates(result, tag, out_dir)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(out_dir, [tag '_heat_rate_timeseries.png']);
    fig = new_figure();
    plot(t, Y(:, map.Q_shex_boundary_W), 'LineWidth', 1.1);
    hold on;
    plot(t, Y(:, map.Q_the_sma_boundary_W), 'LineWidth', 1.1);
    plot(t, Y(:, map.Q_the_se_boundary_W), 'LineWidth', 1.1);
    plot(t, Y(:, map.Q_chex_boundary_W), 'LineWidth', 1.1);
    plot(t, Y(:, map.Q_psc_to_shex_W), '--', 'LineWidth', 1.0);
    plot(t, Y(:, map.Q_ambient_to_hhex_W), '--', 'LineWidth', 1.0);
    plot(t, Y(:, map.Q_cold_load_to_chex_W), ':', 'LineWidth', 1.0);
    grid on;
    xlabel('time (s)');
    ylabel('heat rate (W)');
    legend({'SHEX to SMA branch','HHEX to SMA branch', ...
        'HHEX to SE branch','CHEX to SE branch','PSC to SHEX', ...
        'ambient to HHEX','cold load to CHEX'}, 'Location', 'bestoutside');
    title('Boundary heat rates');
    export_and_close(fig, path);
end

function path = plot_phase_and_stress(result, tag, out_dir)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(out_dir, [tag '_phase_fraction_and_stress.png']);
    fig = new_figure();
    tiledlayout(2, 1);
    nexttile;
    plot(t, Y(:, map.xM_a_mean), 'LineWidth', 1.2);
    hold on;
    plot(t, Y(:, map.xM_r_mean), 'LineWidth', 1.2);
    grid on;
    xlabel('time (s)');
    ylabel('mean martensite fraction');
    legend({'SMA','SE'}, 'Location', 'best');
    title('Mean martensite fraction');
    nexttile;
    plot(t, Y(:, map.sigma_a_Pa) ./ 1.0e6, 'LineWidth', 1.2);
    hold on;
    plot(t, Y(:, map.sigma_r_Pa) ./ 1.0e6, 'LineWidth', 1.2);
    grid on;
    xlabel('time (s)');
    ylabel('stress (MPa)');
    legend({'SMA','SE'}, 'Location', 'best');
    title('Coupled stress');
    export_and_close(fig, path);
end

function nodes = representative_nodes(N)
    nodes = unique(round(linspace(1, N, min(5, N))), 'stable');
end

function fig = new_figure()
    fig = figure('Visible', 'off', 'Color', 'w', ...
        'InvertHardcopy', 'off', 'Position', [100 100 1100 680]);
end

function export_and_close(fig, path)
    force_white_theme(fig);
    exportgraphics(fig, path, 'Resolution', 180);
    close(fig);
end

function force_white_theme(fig)
    set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
    axes_handles = findall(fig, 'Type', 'axes');
    for idx = 1:numel(axes_handles)
        ax = axes_handles(idx);
        set(ax, 'Color', 'w', ...
            'XColor', 'k', 'YColor', 'k', 'ZColor', 'k', ...
            'GridColor', [0.78 0.78 0.78], ...
            'MinorGridColor', [0.88 0.88 0.88]);
        set(get(ax, 'Title'), 'Color', 'k');
        set(get(ax, 'XLabel'), 'Color', 'k');
        set(get(ax, 'YLabel'), 'Color', 'k');
        set(get(ax, 'ZLabel'), 'Color', 'k');
    end
    legend_handles = findall(fig, 'Type', 'legend');
    for idx = 1:numel(legend_handles)
        set(legend_handles(idx), 'Color', 'w', ...
            'TextColor', 'k', 'EdgeColor', [0.65 0.65 0.65]);
    end
    text_handles = findall(fig, 'Type', 'text');
    for idx = 1:numel(text_handles)
        set(text_handles(idx), 'Color', 'k');
    end
end
