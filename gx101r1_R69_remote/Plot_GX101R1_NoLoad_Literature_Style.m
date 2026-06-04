function plot_info = Plot_GX101R1_NoLoad_Literature_Style(run_result_or_path, figures_dir, plot_info)
% Publication-style no-load plots using formal cold-sink/CHEX naming.

    if nargin < 1 || isempty(run_result_or_path)
        error('Plot_GX101R1_NoLoad_Literature_Style:MissingInput', ...
            'run_result or run_result.mat path is required.');
    end
    if ischar(run_result_or_path) || isstring(run_result_or_path)
        data = load(char(run_result_or_path), 'run_result');
        run_result = data.run_result;
    else
        run_result = run_result_or_path;
    end

    if nargin < 2 || isempty(figures_dir)
        figures_dir = fullfile(get_field(run_result, 'outputs_dir', pwd), 'figures');
    end
    if nargin < 3 || isempty(plot_info)
        plot_info = struct('figures_dir', figures_dir, 'generated_files', {{}});
    end
    plot_zhou_style_sink_outlet = isfield(plot_info, 'plot_zhou_style_sink_outlet') && ...
        logical(plot_info.plot_zhou_style_sink_outlet);
    if ~exist(figures_dir, 'dir')
        mkdir(figures_dir);
    end

    cycle_results = reshape(get_field(run_result, 'cycle_results', struct([])), 1, []);
    if isempty(cycle_results)
        return;
    end

    series = build_continuous_sink_series(run_result, cycle_results);
    if numel(series.time_s) >= 2
        plot_info = plot_sink_envelope(plot_info, series, figures_dir);
        plot_info = plot_sink_span(plot_info, series, figures_dir);
    end
    active_outlets = build_zhou_active_outlet_series(run_result, cycle_results);
    if numel(active_outlets.time_s) >= 2
        plot_info = plot_zhou_active_outlets(plot_info, active_outlets, figures_dir);
    end
    if plot_zhou_style_sink_outlet
        sink_outlets = build_zhou_sink_outlet_series(run_result, cycle_results);
        if numel(sink_outlets.time_s) >= 2
            plot_info = plot_zhou_sink_outlets(plot_info, sink_outlets, figures_dir);
        end
    end

    [hold_report, cooldown_report] = representative_exchange_reports(cycle_results);
    if ~isempty(fieldnames(hold_report)) && ~isempty(fieldnames(cooldown_report))
        plot_info = plot_ordered_paths(plot_info, hold_report, cooldown_report, figures_dir);
    end
end

function series = build_continuous_sink_series(run_result, cycle_results)
    config = get_field(run_result, 'config', struct());
    solver_options = get_field(config, 'solver_options', struct());
    exchange_options = get_field(config, 'exchange_options', struct());
    hot_T = get_field(exchange_options, 'hot_sink_T_init', 293.0);
    cold_T = get_field(exchange_options, 'cold_sink_T_init', 293.0);
    cold_load_T = get_field(exchange_options, 'cold_load_T_init', 293.0);
    time_now = 0.0;
    series = struct('time_s', time_now, 'hot_sink_K', hot_T, ...
        'cold_sink_K', cold_T, 'cold_load_K', cold_load_T);

    for cidx = 1:numel(cycle_results)
        reports = reshape(get_field(cycle_results(cidx), 'stage_reports', struct([])), 1, []);
        stage_order = {'load_adiabatic', 'hold_exchange', 'unload_adiabatic', 'cooldown_exchange'};
        for sidx = 1:numel(stage_order)
            report = get_stage_report(reports, stage_order{sidx});
            if isempty(fieldnames(report))
                continue;
            end
            duration = stage_duration_s(report, stage_order{sidx}, solver_options, exchange_options);
            if has_probe_series(report)
                t_local = column(get_field(report, 'probe_time_local_s', []));
                mask = isfinite(t_local);
                t_local = t_local(mask);
                hot_raw = get_field(report, 'T_hot_sink_K_t', []);
                hot_v = vector_or_constant(hot_raw, hot_T, numel(mask));
                if isempty(hot_raw) || all(~isfinite(hot_v))
                    hot_v = linear_official_series(report, 'hot_sink_temp_in', 'hot_sink_temp_out', hot_T, numel(mask));
                end
                cold_raw = get_field(report, 'T_cold_sink_K_t', []);
                cold_v = vector_or_constant(cold_raw, cold_T, numel(mask));
                if isempty(cold_raw) || all(~isfinite(cold_v))
                    cold_v = linear_official_series(report, 'cold_sink_temp_in', 'cold_sink_temp_out', cold_T, numel(mask));
                end
                load_v = column(get_field(report, 'T_cold_load_K_t', get_field(report, 'T_chip_K_t', [])));
                load_v = vector_or_constant(load_v, cold_load_T, numel(mask));
                hot_v = hot_v(mask);
                cold_v = cold_v(mask);
                load_v = load_v(mask);
                if ~isempty(t_local)
                    [t_local, unique_idx] = unique(t_local, 'stable');
                    hot_v = hot_v(unique_idx);
                    cold_v = cold_v(unique_idx);
                    load_v = load_v(unique_idx);
                    append_points(time_now + t_local, hot_v, cold_v, load_v);
                end
            else
                hot_T = get_field(report, 'hot_sink_temp_out', get_field(report, 'hot_end_temp_out', hot_T));
                cold_T = get_field(report, 'cold_sink_temp_out', get_field(report, 'cold_end_temp_out', cold_T));
                cold_load_T = get_field(report, 'cold_load_temp_out', cold_load_T);
                append_points(time_now + duration, hot_T, cold_T, cold_load_T);
            end
            time_now = time_now + duration;
            hot_T = series.hot_sink_K(end);
            cold_T = series.cold_sink_K(end);
            cold_load_T = series.cold_load_K(end);
        end
    end

    function append_points(t, hot_values, cold_values, load_values)
        t = column(t);
        hot_values = column(hot_values);
        cold_values = column(cold_values);
        load_values = column(load_values);
        n = min([numel(t), numel(hot_values), numel(cold_values), numel(load_values)]);
        if n == 0
            return;
        end
        t = t(1:n); hot_values = hot_values(1:n); cold_values = cold_values(1:n); load_values = load_values(1:n);
        if ~isempty(series.time_s) && ~isempty(t) && abs(t(1) - series.time_s(end)) < 1.0e-12
            t = t(2:end); hot_values = hot_values(2:end); cold_values = cold_values(2:end); load_values = load_values(2:end);
        end
        series.time_s = [series.time_s; t]; %#ok<AGROW>
        series.hot_sink_K = [series.hot_sink_K; hot_values]; %#ok<AGROW>
        series.cold_sink_K = [series.cold_sink_K; cold_values]; %#ok<AGROW>
        series.cold_load_K = [series.cold_load_K; load_values]; %#ok<AGROW>
    end
end

function series = build_zhou_active_outlet_series(run_result, cycle_results)
    config = get_field(run_result, 'config', struct());
    solver_options = get_field(config, 'solver_options', struct());
    exchange_options = get_field(config, 'exchange_options', struct());
    baseline_T = get_field(exchange_options, 'ambient_T_init', 293.0);
    time_now = 0.0;
    series = struct('time_s', 0.0, 'Th_out_K', baseline_T, 'Tc_out_K', baseline_T);

    for cidx = 1:numel(cycle_results)
        reports = reshape(get_field(cycle_results(cidx), 'stage_reports', struct([])), 1, []);
        stage_order = {'load_adiabatic', 'hold_exchange', 'unload_adiabatic', 'cooldown_exchange'};
        for sidx = 1:numel(stage_order)
            stage_name = stage_order{sidx};
            report = get_stage_report(reports, stage_name);
            if isempty(fieldnames(report))
                continue;
            end
            duration = stage_duration_s(report, stage_name, solver_options, exchange_options);
            if strcmp(stage_name, 'hold_exchange')
                [t_local, values] = active_stage_series(report, { ...
                    'T_probe_v3_sma_to_hot_hot_hx_side_K_t', ...
                    'T_probe_sma_stage2_port2_v3_side_K_t', ...
                    'T_hot_hx_inlet_fluid_K_t'}, ...
                    'hot_hx_inlet_fluid_temp_out', baseline_T);
                append_active(time_now + t_local, values, baseline_T + zeros(size(values)));
            elseif strcmp(stage_name, 'cooldown_exchange')
                [t_local, values] = active_stage_series(report, { ...
                    'T_probe_v6_sma_to_cold_hx_cold_hx_side_K_t', ...
                    'T_probe_sma_stage4_port4_v6_side_K_t', ...
                    'T_cold_hx_inlet_fluid_K_t'}, ...
                    'cold_hx_inlet_fluid_temp_out', baseline_T);
                append_active(time_now + t_local, baseline_T + zeros(size(values)), values);
            else
                append_active([time_now; time_now + duration], [baseline_T; baseline_T], [baseline_T; baseline_T]);
            end
            time_now = time_now + duration;
        end
    end

    function append_active(t, th_values, tc_values)
        t = column(t);
        th_values = column(th_values);
        tc_values = column(tc_values);
        n = min([numel(t), numel(th_values), numel(tc_values)]);
        if n == 0
            return;
        end
        t = t(1:n); th_values = th_values(1:n); tc_values = tc_values(1:n);
        same_time = ~isempty(series.time_s) && abs(t(1) - series.time_s(end)) < 1.0e-12;
        same_value = same_time && abs(th_values(1) - series.Th_out_K(end)) < 1.0e-12 && ...
            abs(tc_values(1) - series.Tc_out_K(end)) < 1.0e-12;
        if same_value
            t = t(2:end); th_values = th_values(2:end); tc_values = tc_values(2:end);
        end
        series.time_s = [series.time_s; t]; %#ok<AGROW>
        series.Th_out_K = [series.Th_out_K; th_values]; %#ok<AGROW>
        series.Tc_out_K = [series.Tc_out_K; tc_values]; %#ok<AGROW>
    end
end

function series = build_zhou_sink_outlet_series(run_result, cycle_results)
    config = get_field(run_result, 'config', struct());
    solver_options = get_field(config, 'solver_options', struct());
    exchange_options = get_field(config, 'exchange_options', struct());
    baseline_T = get_field(exchange_options, 'ambient_T_init', 293.0);
    time_now = 0.0;
    series = struct('time_s', 0.0, 'Th_out_K', baseline_T, 'Tc_out_K', baseline_T);

    for cidx = 1:numel(cycle_results)
        reports = reshape(get_field(cycle_results(cidx), 'stage_reports', struct([])), 1, []);
        stage_order = {'load_adiabatic', 'hold_exchange', 'unload_adiabatic', 'cooldown_exchange'};
        for sidx = 1:numel(stage_order)
            stage_name = stage_order{sidx};
            report = get_stage_report(reports, stage_name);
            if isempty(fieldnames(report))
                continue;
            end
            duration = stage_duration_s(report, stage_name, solver_options, exchange_options);
            if strcmp(stage_name, 'hold_exchange')
                [t_local, values] = active_stage_series(report, ...
                    {'T_hot_hx_inlet_fluid_K_t'}, ...
                    'hot_hx_inlet_fluid_temp_out', baseline_T);
                append_sink_outlet(time_now + t_local, values, baseline_T + zeros(size(values)));
            elseif strcmp(stage_name, 'cooldown_exchange')
                [t_local, values] = active_stage_series(report, ...
                    {'T_cold_hx_inlet_fluid_K_t'}, ...
                    'cold_hx_inlet_fluid_temp_out', baseline_T);
                append_sink_outlet(time_now + t_local, baseline_T + zeros(size(values)), values);
            else
                append_sink_outlet([time_now; time_now + duration], ...
                    [baseline_T; baseline_T], [baseline_T; baseline_T]);
            end
            time_now = time_now + duration;
        end
    end

    function append_sink_outlet(t, th_values, tc_values)
        t = column(t);
        th_values = column(th_values);
        tc_values = column(tc_values);
        n = min([numel(t), numel(th_values), numel(tc_values)]);
        if n == 0
            return;
        end
        t = t(1:n); th_values = th_values(1:n); tc_values = tc_values(1:n);
        same_time = ~isempty(series.time_s) && abs(t(1) - series.time_s(end)) < 1.0e-12;
        same_value = same_time && abs(th_values(1) - series.Th_out_K(end)) < 1.0e-12 && ...
            abs(tc_values(1) - series.Tc_out_K(end)) < 1.0e-12;
        if same_value
            t = t(2:end); th_values = th_values(2:end); tc_values = tc_values(2:end);
        end
        series.time_s = [series.time_s; t]; %#ok<AGROW>
        series.Th_out_K = [series.Th_out_K; th_values]; %#ok<AGROW>
        series.Tc_out_K = [series.Tc_out_K; tc_values]; %#ok<AGROW>
    end
end

function [t_local, values] = active_stage_series(report, field_candidates, scalar_fallback_field, baseline_T)
    t_local = column(get_field(report, 'probe_time_local_s', []));
    mask = isfinite(t_local);
    t_local = t_local(mask);
    values = [];
    for idx = 1:numel(field_candidates)
        raw = column(get_field(report, field_candidates{idx}, []));
        if numel(raw) == numel(mask)
            raw = raw(mask);
        end
        if numel(raw) == numel(t_local) && any(isfinite(raw))
            values = raw;
            break;
        end
    end
    if isempty(values)
        scalar_value = get_field(report, scalar_fallback_field, baseline_T);
        if isempty(t_local)
            duration = get_field(report, 'stop_time_s', 0.0);
            t_local = [0.0; duration];
            values = [baseline_T; scalar_value];
        else
            values = repmat(scalar_value, numel(t_local), 1);
        end
    end
end

function plot_info = plot_sink_envelope(plot_info, series, figures_dir)
    fig = make_pub_figure();
    hold on;
    plot(series.time_s, series.hot_sink_K, '-', 'Color', [0.86 0.22 0.14], ...
        'LineWidth', 1.8, 'DisplayName', 'Hot sink');
    plot(series.time_s, series.cold_sink_K, '-', 'Color', [0.12 0.46 0.82], ...
        'LineWidth', 1.8, 'DisplayName', 'Cold sink');
    hold off;
    xlabel('Time (s)');
    ylabel('Temperature (K)');
    title('Hot and cold sink temperature envelope');
    legend('Location', 'best', 'Box', 'off');
    set_axes_style();
    plot_info = save_pub_plot(plot_info, fig, figures_dir, 'hot_cold_sink_temperature_envelope');
end

function plot_info = plot_sink_span(plot_info, series, figures_dir)
    fig = make_pub_figure();
    plot(series.time_s, series.hot_sink_K - series.cold_sink_K, '-', ...
        'Color', [0.18 0.18 0.18], 'LineWidth', 1.8);
    xlabel('Time (s)');
    ylabel('Hot--cold sink temperature span (K)');
    set_axes_style();
    plot_info = save_pub_plot(plot_info, fig, figures_dir, 'hot_cold_temperature_span');
end

function plot_info = plot_zhou_active_outlets(plot_info, series, figures_dir)
    fig = make_pub_figure();
    hold on;
    plot(series.time_s, series.Th_out_K, '-', 'Color', [0.86 0.22 0.14], ...
        'LineWidth', 1.8, 'Marker', 'o', 'MarkerSize', 2.2, ...
        'MarkerIndices', sparse_marker_indices(series.time_s), ...
        'DisplayName', 'T_{h,in} HHEX inlet');
    plot(series.time_s, series.Tc_out_K, '-', 'Color', [0.12 0.46 0.82], ...
        'LineWidth', 1.8, 'Marker', 'o', 'MarkerSize', 2.2, ...
        'MarkerIndices', sparse_marker_indices(series.time_s), ...
        'DisplayName', 'T_{c,in} CHEX inlet');
    hold off;
    xlabel('Time (s)');
    ylabel('Inlet fluid temperature (K)');
    title('Alternating hot/cold HX inlet fluid temperatures');
    legend('Location', 'best', 'Box', 'off');
    set_axes_style();
    plot_info = save_pub_plot(plot_info, fig, figures_dir, 'zhou_style_active_inlet_fluid_temperature');
end

function plot_info = plot_zhou_sink_outlets(plot_info, series, figures_dir)
    fig = make_pub_figure();
    hold on;
    plot(series.time_s, series.Th_out_K, '-', 'Color', [0.86 0.22 0.14], ...
        'LineWidth', 1.8, 'DisplayName', 'T_{h,out} sink-side');
    plot(series.time_s, series.Tc_out_K, '-', 'Color', [0.12 0.46 0.82], ...
        'LineWidth', 1.8, 'DisplayName', 'T_{c,out} sink-side');
    hold off;
    xlabel('Time (s)');
    ylabel('Outlet temperature (K)');
    legend('Location', 'best', 'Box', 'off');
    set_axes_style();
    plot_info = save_pub_plot(plot_info, fig, figures_dir, 'zhou_style_sink_outlet_temperature');
end

function plot_info = plot_ordered_paths(plot_info, hold_report, cooldown_report, figures_dir)
    hold_labels = {'Cold buffer', 'SMA inlet', 'SMA outlet', 'Hot HX inlet', 'Hot HX outlet'};
    hold_values = [ ...
        get_field(hold_report, 'probe_root_cold_buffer_fluid_T_K', NaN), ...
        get_field(hold_report, 'stage2_sma_in_from_cold_T_K', get_field(hold_report, 'probe_sma_stage2_port1_v1_side_T_K', NaN)), ...
        get_field(hold_report, 'stage2_sma_out_to_hot_T_K', get_field(hold_report, 'probe_sma_stage2_port2_v3_side_T_K', NaN)), ...
        get_field(hold_report, 'probe_v3_sma_to_hot_hot_hx_side_T_K', NaN), ...
        get_field(hold_report, 'hot_hx_outlet_fluid_temp_out', get_field(hold_report, 'hot_sink_temp_out', NaN))];

    cooldown_labels = {'Hot buffer', 'SMA inlet', 'SMA outlet', 'CHEX inlet', 'CHEX outlet', 'Cold buffer'};
    cooldown_values = [ ...
        get_field(cooldown_report, 'probe_root_hot_buffer_fluid_T_K', NaN), ...
        get_field(cooldown_report, 'stage4_sma_in_from_hot_T_K', get_field(cooldown_report, 'probe_sma_stage4_port3_v4_side_T_K', NaN)), ...
        get_field(cooldown_report, 'stage4_sma_out_to_chip_T_K', get_field(cooldown_report, 'probe_sma_stage4_port4_v6_side_T_K', NaN)), ...
        get_field(cooldown_report, 'cold_hx_inlet_fluid_temp_out', get_field(cooldown_report, 'probe_chip_pipe_port_conn2_v6_sma_side_T_K', NaN)), ...
        get_field(cooldown_report, 'cold_hx_outlet_fluid_temp_out', get_field(cooldown_report, 'probe_chip_to_cold_junction_T_K', NaN)), ...
        get_field(cooldown_report, 'probe_root_cold_buffer_fluid_T_K', NaN)];

    fig = make_pub_figure();
    tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
    nexttile;
    plot(1:numel(hold_values), hold_values, '-o', 'Color', [0.10 0.30 0.68], ...
        'LineWidth', 1.6, 'MarkerSize', 4);
    set(gca, 'XTick', 1:numel(hold_labels), 'XTickLabel', hold_labels);
    xtickangle(25);
    ylabel('Fluid temperature (K)');
    xlabel('Stage 2 ordered path');
    set_axes_style();

    nexttile;
    plot(1:numel(cooldown_values), cooldown_values, '-o', 'Color', [0.74 0.18 0.12], ...
        'LineWidth', 1.6, 'MarkerSize', 4);
    set(gca, 'XTick', 1:numel(cooldown_labels), 'XTickLabel', cooldown_labels);
    xtickangle(25);
    ylabel('Fluid temperature (K)');
    xlabel('Stage 4 ordered path');
    set_axes_style();
    plot_info = save_pub_plot(plot_info, fig, figures_dir, 'stage2_stage4_ordered_flow_path_temperature');
end

function [hold_report, cooldown_report] = representative_exchange_reports(cycle_results)
    hold_report = struct();
    cooldown_report = struct();
    for idx = 1:numel(cycle_results)
        reports = reshape(get_field(cycle_results(idx), 'stage_reports', struct([])), 1, []);
        h = get_stage_report(reports, 'hold_exchange');
        c = get_stage_report(reports, 'cooldown_exchange');
        if ~isempty(fieldnames(h)) && ~isempty(fieldnames(c))
            hold_report = h;
            cooldown_report = c;
        end
    end
end

function duration = stage_duration_s(report, stage_name, solver_options, exchange_options)
    duration = get_field(report, 'stop_time_s', NaN);
    if isfinite(duration)
        return;
    end
    switch stage_name
        case 'load_adiabatic'
            duration = get_field(solver_options, 'T_load', 0.1);
        case 'unload_adiabatic'
            duration = get_field(solver_options, 'T_unload', 0.1);
        case 'hold_exchange'
            duration = get_field(exchange_options, 'hotflush_stop_time_s', 0.4);
        case 'cooldown_exchange'
            duration = get_field(exchange_options, 'coldflush_stop_time_s', 0.4);
        otherwise
            duration = 0.0;
    end
end

function tf = has_probe_series(report)
    tf = isstruct(report) && isfield(report, 'probe_time_local_s') && ...
        isfield(report, 'T_hot_sink_K_t') && isfield(report, 'T_cold_sink_K_t');
end

function fig = make_pub_figure()
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 780, 520]);
end

function set_axes_style()
    ax = gca;
    ax.Color = 'w';
    ax.XColor = 'k';
    ax.YColor = 'k';
    ax.Box = 'on';
    ax.LineWidth = 0.8;
    ax.FontName = 'Times New Roman';
    ax.FontSize = 10;
    grid(ax, 'off');
end

function plot_info = save_pub_plot(plot_info, fig, figures_dir, base_name)
    png_path = fullfile(figures_dir, [base_name, '.png']);
    pdf_path = fullfile(figures_dir, [base_name, '.pdf']);
    apply_white_theme(fig);
    exportgraphics(fig, png_path, 'Resolution', 300);
    exportgraphics(fig, pdf_path, 'ContentType', 'vector');
    close(fig);
    plot_info.generated_files{end + 1} = png_path;
    plot_info.generated_files{end + 1} = pdf_path;
end

function idx = sparse_marker_indices(x)
    n = numel(x);
    if n <= 80
        idx = 1:n;
    else
        idx = unique(round(linspace(1, n, 80)));
    end
end

function apply_white_theme(fig)
    set(fig, 'Color', 'w', 'InvertHardcopy', 'off');
    axes_list = findall(fig, 'Type', 'axes');
    for idx = 1:numel(axes_list)
        ax = axes_list(idx);
        set(ax, 'Color', 'w', 'XColor', 'k', 'YColor', 'k', 'ZColor', 'k');
        title_obj = get(ax, 'Title');
        xlabel_obj = get(ax, 'XLabel');
        ylabel_obj = get(ax, 'YLabel');
        zlabel_obj = get(ax, 'ZLabel');
        set([title_obj, xlabel_obj, ylabel_obj, zlabel_obj], 'Color', 'k');
    end
    legends = findall(fig, 'Type', 'legend');
    for idx = 1:numel(legends)
        set(legends(idx), 'Color', 'w', 'TextColor', 'k', 'EdgeColor', [0.85 0.85 0.85]);
    end
end

function report = get_stage_report(reports, stage_name)
    report = struct();
    for idx = 1:numel(reports)
        if strcmp(get_field(reports(idx), 'stage_name', ''), stage_name)
            report = reports(idx);
            return;
        end
    end
end

function out = column(value)
    if ~isnumeric(value)
        out = [];
    else
        out = value(:);
    end
end

function out = vector_or_constant(value, fallback_value, n)
    out = column(value);
    if numel(out) ~= n
        out = repmat(fallback_value, n, 1);
    end
end

function out = linear_official_series(report, in_field, out_field, fallback_value, n)
    value_in = get_field(report, in_field, fallback_value);
    value_out = get_field(report, out_field, value_in);
    if ~(isfinite(value_in) && isfinite(value_out)) || n <= 0
        out = repmat(fallback_value, max(n, 0), 1);
        return;
    end
    if n == 1
        out = value_out;
    else
        out = linspace(value_in, value_out, n).';
    end
end

function value = get_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
