function plot_paths = Plot_HeatDriveECC_Temperature_Trends(result)
% Write white-background temperature trend plots for heat-drive ECC results.

    options = result.options;
    map = options.output_map;
    time_s = result.time_s;
    values = result.values;
    output_dir = result.output_dir;
    prefix = sprintf('heatdrive_ecc_%dcycle', options.cycle_count);

    if ~isfolder(output_dir)
        mkdir(output_dir);
    end

    plot_paths = struct();
    plot_paths.sma_se_temperature_png = fullfile(output_dir, [prefix, '_sma_se_temperature.png']);
    plot_paths.sma_temperature_nodes_png = fullfile(output_dir, [prefix, '_sma_temperature_nodes.png']);
    plot_paths.se_temperature_nodes_png = fullfile(output_dir, [prefix, '_se_temperature_nodes.png']);
    plot_paths.all_probe_temperatures_png = fullfile(output_dir, [prefix, '_all_probe_temperatures.png']);
    plot_paths.shex_probe_temperatures_png = fullfile(output_dir, [prefix, '_shex_probe_temperatures.png']);
    plot_paths.hhex_probe_temperatures_png = fullfile(output_dir, [prefix, '_hhex_probe_temperatures.png']);
    plot_paths.chex_probe_temperatures_png = fullfile(output_dir, [prefix, '_chex_probe_temperatures.png']);
    plot_paths.probe_plot_dir = fullfile(output_dir, 'probe_temperature_plots');
    plot_paths.probe_plot_index_csv = fullfile(output_dir, [prefix, '_probe_plot_index.csv']);

    if ~isfolder(plot_paths.probe_plot_dir)
        mkdir(plot_paths.probe_plot_dir);
    end

    plot_sma_se_summary(time_s, values, map, result, plot_paths.sma_se_temperature_png);
    plot_nodes(time_s, values(:, map.T_a_51), [1 13 26 39 51], ...
        'SMA node temperature trends', result, plot_paths.sma_temperature_nodes_png);
    plot_nodes(time_s, values(:, map.T_r_51), [1 13 26 39 51], ...
        'SE node temperature trends', result, plot_paths.se_temperature_nodes_png);

    probe_table = result.probe_table;
    plot_probe_set(probe_table, get_probe_names(probe_table), ...
        'All temperature probes', result, plot_paths.all_probe_temperatures_png);
    plot_probe_set(probe_table, select_probe_names(probe_table, {'SHEX'}), ...
        'SHEX internal and inlet/outlet probes', result, plot_paths.shex_probe_temperatures_png);
    plot_probe_set(probe_table, select_probe_names(probe_table, {'HHEX', 'THE'}), ...
        'HHEX/THE internal and inlet/outlet probes', result, plot_paths.hhex_probe_temperatures_png);
    plot_probe_set(probe_table, select_probe_names(probe_table, {'CHEX', 'RHE'}), ...
        'CHEX/RHE internal and inlet/outlet probes', result, plot_paths.chex_probe_temperatures_png);

    write_individual_probe_plots(probe_table, result, plot_paths.probe_plot_dir, ...
        plot_paths.probe_plot_index_csv);
end

function plot_sma_se_summary(time_s, values, map, result, output_png)
    fig = make_fig([1200 720]);
    ax = axes(fig);
    hold(ax, 'on');
    plot(ax, time_s, values(:, map.T_a_mean_K), 'Color', [0.80 0.10 0.10], 'LineWidth', 1.8);
    plot(ax, time_s, values(:, map.T_a_min_K), '--', 'Color', [0.95 0.45 0.45], 'LineWidth', 1.0);
    plot(ax, time_s, values(:, map.T_a_max_K), '--', 'Color', [0.55 0.00 0.00], 'LineWidth', 1.0);
    plot(ax, time_s, values(:, map.T_r_mean_K), 'Color', [0.10 0.25 0.85], 'LineWidth', 1.8);
    plot(ax, time_s, values(:, map.T_r_min_K), '--', 'Color', [0.45 0.60 0.95], 'LineWidth', 1.0);
    plot(ax, time_s, values(:, map.T_r_max_K), '--', 'Color', [0.00 0.10 0.55], 'LineWidth', 1.0);
    format_temperature_axes(ax, 'SMA and SE mean/min/max temperature trends');
    add_stage_lines(ax, result);
    lgd = legend(ax, {'SMA mean','SMA min','SMA max','SE mean','SE min','SE max'}, ...
        'Location', 'eastoutside', 'Interpreter', 'none');
    format_legend(lgd);
    save_figure(fig, output_png);
end

function plot_nodes(time_s, node_values, node_indices, title_text, result, output_png)
    fig = make_fig([1200 720]);
    ax = axes(fig);
    hold(ax, 'on');
    colors = lines(numel(node_indices));
    for idx = 1:numel(node_indices)
        node = node_indices(idx);
        plot(ax, time_s, node_values(:, node), 'LineWidth', 1.4, 'Color', colors(idx, :));
    end
    format_temperature_axes(ax, title_text);
    add_stage_lines(ax, result);
    labels = arrayfun(@(n) sprintf('node %02d', n), node_indices, 'UniformOutput', false);
    lgd = legend(ax, labels, 'Location', 'eastoutside', 'Interpreter', 'none');
    format_legend(lgd);
    save_figure(fig, output_png);
end

function plot_probe_set(probe_table, probe_names, title_text, result, output_png)
    fig = make_fig([1500 850]);
    ax = axes(fig);
    hold(ax, 'on');
    names = cellstr(probe_names);
    if isempty(names)
        text(ax, 0.5, 0.5, 'No probes found', 'HorizontalAlignment', 'center');
        format_temperature_axes(ax, title_text);
        save_figure(fig, output_png);
        return;
    end

    colors = lines(max(numel(names), 1));
    for idx = 1:numel(names)
        rows = strcmp(cellstr(probe_table.probe_name), names{idx});
        t = probe_table.time_s(rows);
        T = probe_table.temperature_K(rows);
        [t, order] = sort(t);
        T = T(order);
        plot(ax, t, T, 'LineWidth', 1.1, 'Color', colors(idx, :));
    end
    format_temperature_axes(ax, title_text);
    add_stage_lines(ax, result);
    lgd = legend(ax, names, 'Location', 'eastoutside', 'Interpreter', 'none');
    format_legend(lgd);
    save_figure(fig, output_png);
end

function write_individual_probe_plots(probe_table, result, output_dir, index_csv)
    names = get_probe_names(probe_table);
    components = cell(size(names));
    png_paths = cell(size(names));
    for idx = 1:numel(names)
        rows = strcmp(cellstr(probe_table.probe_name), names{idx});
        component_values = cellstr(probe_table.component(rows));
        components{idx} = component_values{1};
        safe_name = regexprep(names{idx}, '[^A-Za-z0-9_]+', '_');
        png_path = fullfile(output_dir, sprintf('%02d_%s.png', idx, safe_name));
        png_paths{idx} = png_path;

        fig = make_fig([1100 680]);
        ax = axes(fig);
        hold(ax, 'on');
        t = probe_table.time_s(rows);
        T = probe_table.temperature_K(rows);
        [t, order] = sort(t);
        T = T(order);
        plot(ax, t, T, 'LineWidth', 1.5, 'Color', [0.10 0.25 0.75]);
        format_temperature_axes(ax, sprintf('%s temperature trend', names{idx}));
        add_stage_lines(ax, result);
        save_figure(fig, png_path);
    end

    index_table = table(names(:), components(:), png_paths(:), ...
        'VariableNames', {'probe_name','component','png_path'});
    writetable(index_table, index_csv);
end

function names = get_probe_names(probe_table)
    names = unique(cellstr(probe_table.probe_name), 'stable');
end

function names = select_probe_names(probe_table, tokens)
    all_names = get_probe_names(probe_table);
    components = cellstr(probe_table.component);
    probe_names = cellstr(probe_table.probe_name);
    keep = false(size(all_names));
    for idx = 1:numel(all_names)
        rows = strcmp(probe_names, all_names{idx});
        text_blob = upper(strjoin([{all_names{idx}}, unique(components(rows), 'stable').'], ' '));
        for token_idx = 1:numel(tokens)
            keep(idx) = keep(idx) || contains(text_blob, upper(tokens{token_idx}));
        end
    end
    names = all_names(keep);
end

function fig = make_fig(position_wh)
    fig = figure('Visible', 'off', 'Color', 'w', ...
        'InvertHardcopy', 'off', 'Position', [100 100 position_wh(1) position_wh(2)]);
end

function format_temperature_axes(ax, title_text)
    set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', ...
        'GridColor', [0.82 0.82 0.82], 'MinorGridColor', [0.90 0.90 0.90]);
    grid(ax, 'on');
    box(ax, 'on');
    xlabel(ax, 'Time (s)', 'Color', 'k');
    ylabel(ax, 'Temperature (K)', 'Color', 'k');
    title(ax, title_text, 'Color', 'k', 'Interpreter', 'none');
end

function format_legend(lgd)
    set(lgd, 'Color', 'w', 'TextColor', 'k', 'EdgeColor', [0.75 0.75 0.75]);
end

function add_stage_lines(ax, result)
    time_s = result.time_s;
    values = result.values;
    map = result.options.output_map;
    stage_change_idx = find(diff(round(values(:, map.stage_id))) ~= 0) + 1;
    cycle_change_idx = find(diff(round(values(:, map.cycle_index))) ~= 0) + 1;
    for idx = 1:numel(stage_change_idx)
        xline(ax, time_s(stage_change_idx(idx)), '-', 'Color', [0.86 0.86 0.86], ...
            'LineWidth', 0.6, 'HandleVisibility', 'off');
    end
    for idx = 1:numel(cycle_change_idx)
        xline(ax, time_s(cycle_change_idx(idx)), '-', 'Color', [0.25 0.25 0.25], ...
            'LineWidth', 0.9, 'HandleVisibility', 'off');
    end
end

function save_figure(fig, png_path)
    set(fig, 'Color', 'w');
    axes_handles = findall(fig, 'Type', 'axes');
    set(axes_handles, 'Color', 'w');
    exportgraphics(fig, png_path, 'Resolution', 180, 'BackgroundColor', 'white');
    savefig(fig, [png_path(1:end-4), '.fig']);
    close(fig);
end
