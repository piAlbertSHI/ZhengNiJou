function plot_info = Plot_GlobalXi_Simulink_Cycle_Results(run_result)
% Generate publication-oriented plots for GlobalXi + Simulink101 cycle runs.

    plot_info = struct('figures_dir', '', 'generated_files', {{}});
    if ~isstruct(run_result) || ~isfield(run_result, 'config')
        return;
    end
    if numel(run_result) > 1
        plot_info = plot_multi_case_comparison(run_result);
        return;
    end

    config = run_result.config;
    if isfield(config, 'save_plots') && ~config.save_plots
        return;
    end

    figures_dir = get_field(config, 'figures_dir', fullfile(get_field(run_result, 'outputs_dir', pwd), 'figures'));
    if ~exist(figures_dir, 'dir')
        mkdir(figures_dir);
    end
    cleanup_known_plot_outputs(figures_dir);
    plot_info.figures_dir = figures_dir;

    cycle_results = reshape(get_field(run_result, 'cycle_results', struct([])), 1, []);
    diagnostics = reshape(get_field(run_result, 'cycle_diagnostics', struct([])), 1, []);
    stage_series = build_stage_end_series(run_result);
    representative_cycle_results = select_representative_cycle_results(cycle_results, config);

    if ~isempty(stage_series.time_s)
        plot_info = plot_stage_end_sma_temperature_time(plot_info, stage_series, figures_dir);
        plot_info = plot_stage_end_thermal_objects_time(plot_info, stage_series, figures_dir);
        plot_info = plot_stage_end_xi_time(plot_info, stage_series, figures_dir);
        plot_info = plot_stage_end_deflection_pressure_time(plot_info, stage_series, figures_dir);
    end

    if ~isempty(diagnostics)
        plot_info = plot_cycle_level_summary(plot_info, diagnostics, figures_dir, run_result);
        plot_info = plot_exchange_controls(plot_info, diagnostics, figures_dir);
    end

    if ~isempty(cycle_results)
        plot_info = plot_first_cycle_profiles(plot_info, cycle_results(1), figures_dir, config);
        plot_info = plot_first_load_stress_strain(plot_info, cycle_results(1), figures_dir);
        plot_info = plot_cycle_stage_heatmaps(plot_info, representative_cycle_results, figures_dir, config);
        plot_info = plot_final_cycle_profiles(plot_info, representative_cycle_results, figures_dir, config);
        plot_info = plot_exchange_101_profiles(plot_info, representative_cycle_results, figures_dir);
        plot_info = plot_exchange_fluid_probes(plot_info, cycle_results, figures_dir);
        plot_info = plot_exchange_probe_timeseries(plot_info, cycle_results, figures_dir);
        plot_info = plot_exchange_path_order_probes(plot_info, cycle_results, figures_dir);
        plot_info = plot_energy_audit_summary(plot_info, cycle_results, figures_dir);
        try
            plot_info = Plot_GX101R1_NoLoad_Literature_Style(run_result, figures_dir, plot_info);
        catch ME
            warning('Plot_GlobalXi:NoLoadStylePlotFailed', ...
                'No-load literature-style plots failed: %s', ME.message);
        end
        try
            plot_info = Plot_GX101R1_Fixed_Probe_Trajectories(run_result, figures_dir, plot_info);
        catch ME
            warning('Plot_GlobalXi:ProbeIndividualPlotFailed', ...
                'Fixed probe trajectory plots failed: %s', ME.message);
        end
    end
end

function plot_info = plot_multi_case_comparison(run_results)
    run_results = reshape(run_results, 1, []);
    plot_info = struct('figures_dir', '', 'generated_files', {{}});
    first_output = get_field(run_results(1), 'outputs_dir', pwd);
    if isempty(first_output)
        first_output = pwd;
    end
    figures_dir = fullfile(fileparts(first_output), 'figures_sweep_comparison');
    if ~exist(figures_dir, 'dir')
        mkdir(figures_dir);
    end
    cleanup_sweep_plot_outputs(figures_dir);
    plot_info.figures_dir = figures_dir;

    cases = collect_multi_case_metrics(run_results);
    if isempty(cases)
        return;
    end
    [x, order] = sort([cases.chip_heat_W]);
    cases = cases(order);
    x_label = 'Cold-load heat input (W)';

    fig = make_figure();
    hold on;
    plot(x, [cases.chip_temp_initial_K], '--', 'LineWidth', 1.2, 'DisplayName', 'Initial');
    plot(x, [cases.stage2_chip_out_K], marker_style('-o', x), 'LineWidth', 1.7, 'DisplayName', 'After stage 2');
    plot(x, [cases.stage4_chip_out_K], marker_style('-s', x), 'LineWidth', 1.7, 'DisplayName', 'After stage 4');
    hold off;
    xlabel(x_label);
    ylabel('Cold-load temperature (K)');
    title('1-cycle cold-load temperature versus heat input');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'sweep_load_power_cold_load_temperature_points.png');

    fig = make_figure();
    hold on;
    plot(x, [cases.stage2_chip_delta_K], marker_style('-o', x), 'LineWidth', 1.7, 'DisplayName', 'Stage 2 cold-load \DeltaT');
    plot(x, [cases.stage4_chip_delta_K], marker_style('-s', x), 'LineWidth', 1.7, 'DisplayName', 'Stage 4 cold-load \DeltaT');
    plot(x, [cases.net_chip_delta_K], marker_style('-^', x), 'LineWidth', 1.7, 'DisplayName', 'Net cycle cold-load \DeltaT');
    yline(0, ':', 'Color', [0.45 0.45 0.45], 'HandleVisibility', 'off');
    hold off;
    xlabel(x_label);
    ylabel('Temperature change (K)');
    title('Cold-load temperature changes and cooling threshold');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'sweep_load_power_cold_load_temperature_deltas.png');

    fig = make_figure();
    hold on;
    plot(x, [cases.sma_cooldown_port3_v4_K], marker_style('-o', x), 'LineWidth', 1.5, 'DisplayName', 'SMA S4 port3 / V4');
    plot(x, [cases.sma_cooldown_port4_v6_K], marker_style('-s', x), 'LineWidth', 1.5, 'DisplayName', 'SMA S4 port4 / V6');
    plot(x, [cases.chip_conn2_v6_K], marker_style('-^', x), 'LineWidth', 1.5, 'DisplayName', 'CHEX inlet / V6 side');
    plot(x, [cases.chip_cold_junction_K], marker_style('-d', x), 'LineWidth', 1.5, 'DisplayName', 'CHEX outlet boundary');
    plot(x, [cases.cold_conn1_v5_K], marker_style('-v', x), 'LineWidth', 1.5, 'DisplayName', 'Cold Conn1 / V5 return');
    hold off;
    xlabel(x_label);
    ylabel('Fluid temperature (K)');
    title('Stage 4 fixed-port fluid probes versus heat input');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'sweep_load_power_stage4_fluid_probe_temperatures.png');

    fig = make_figure();
    hold on;
    plot(x, [cases.stage2_hot_sink_delta_K], marker_style('-o', x), 'LineWidth', 1.5, 'DisplayName', 'Stage 2 hot sink \DeltaT');
    plot(x, [cases.stage4_hot_sink_delta_K], marker_style('-s', x), 'LineWidth', 1.5, 'DisplayName', 'Stage 4 hot sink \DeltaT');
    plot(x, [cases.stage2_cold_sink_delta_K], marker_style('-^', x), 'LineWidth', 1.5, 'DisplayName', 'Stage 2 cold sink \DeltaT');
    plot(x, [cases.stage4_cold_sink_delta_K], marker_style('-d', x), 'LineWidth', 1.5, 'DisplayName', 'Stage 4 cold sink \DeltaT');
    yline(0, ':', 'Color', [0.45 0.45 0.45], 'HandleVisibility', 'off');
    hold off;
    xlabel(x_label);
    ylabel('Internal sink temperature change (K)');
    title('Hot/cold sink internal response versus heat input');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'sweep_load_power_sink_internal_temperature_deltas.png');

    fig = make_figure();
    hold on;
    plot(x, [cases.stage4_chip_fluid_gain_K], marker_style('-o', x), 'LineWidth', 1.7, ...
        'DisplayName', 'CHEX endpoint \DeltaT (same time)');
    plot(x, [cases.stage4_chip_drop_K], marker_style('-s', x), 'LineWidth', 1.7, 'DisplayName', 'Cold-load internal drop');
    plot(x, [cases.stage4_chip_heat_source_J], marker_style('-^', x), 'LineWidth', 1.7, 'DisplayName', 'Cold-load heat input (J)');
    hold off;
    xlabel(x_label);
    ylabel('K or J');
    title('Stage 4 cold-load and CHEX response versus heat input');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'sweep_load_power_stage4_cold_load_response.png');
end

function cases = collect_multi_case_metrics(run_results)
    cases = struct([]);
    for idx = 1:numel(run_results)
        r = run_results(idx);
        cycle_results = reshape(get_field(r, 'cycle_results', struct([])), 1, []);
        if isempty(cycle_results)
            continue;
        end
        reports = reshape(get_field(cycle_results(1), 'stage_reports', struct([])), 1, []);
        hold_report = get_stage_report(reports, 'hold_exchange');
        cooldown_report = get_stage_report(reports, 'cooldown_exchange');
        if isempty(fieldnames(hold_report)) || isempty(fieldnames(cooldown_report))
            continue;
        end
        config = get_field(r, 'config', struct());
        exchange_options = get_field(config, 'exchange_options', struct());
        item = struct();
        item.output_dir = string(get_field(r, 'outputs_dir', ''));
        item.run_label = string(get_field(config, 'run_label', sprintf('case_%d', idx)));
        item.chip_heat_W = get_field(exchange_options, 'chip_heat_W', get_field(cooldown_report, 'chip_heat_W', NaN));
        item.chip_temp_initial_K = get_field(exchange_options, 'cold_load_T_init', ...
            get_field(exchange_options, 'chip_T_init', get_field(hold_report, 'chip_temp_in', NaN)));
        item.stage2_chip_out_K = get_field(hold_report, 'chip_temp_out', NaN);
        item.stage4_chip_out_K = get_field(cooldown_report, 'chip_temp_out', NaN);
        item.stage2_chip_delta_K = get_field(hold_report, 'chip_temp_out', NaN) - get_field(hold_report, 'chip_temp_in', NaN);
        item.stage4_chip_delta_K = get_field(cooldown_report, 'chip_temp_out', NaN) - get_field(cooldown_report, 'chip_temp_in', NaN);
        item.net_chip_delta_K = item.stage4_chip_out_K - item.chip_temp_initial_K;
        item.sma_cooldown_port3_v4_K = get_field(cooldown_report, 'probe_sma_stage4_port3_v4_side_T_K', ...
            get_field(cooldown_report, 'sma_cooldown_inlet_fluid_temp_out', NaN));
        item.sma_cooldown_port4_v6_K = get_field(cooldown_report, 'probe_sma_stage4_port4_v6_side_T_K', ...
            get_field(cooldown_report, 'sma_cooldown_outlet_fluid_temp_out', NaN));
        item.chip_conn2_v6_K = get_field(cooldown_report, 'probe_chip_pipe_port_conn2_v6_sma_side_T_K', ...
            get_field(cooldown_report, 'chip_inlet_fluid_temp_out', NaN));
        item.chip_cold_junction_K = get_field(cooldown_report, 'probe_chip_to_cold_junction_T_K', ...
            get_field(cooldown_report, 'chip_outlet_fluid_temp_out', NaN));
        item.cold_conn1_v5_K = get_field(cooldown_report, 'probe_cold_hx_port_conn1_v5_return_side_T_K', ...
            get_field(cooldown_report, 'cold_hx_outlet_fluid_temp_out', NaN));
        item.stage2_hot_sink_delta_K = get_field(hold_report, 'hot_sink_temp_out', NaN) - get_field(hold_report, 'hot_sink_temp_in', NaN);
        item.stage4_hot_sink_delta_K = get_field(cooldown_report, 'hot_sink_temp_out', NaN) - get_field(cooldown_report, 'hot_sink_temp_in', NaN);
        item.stage2_cold_sink_delta_K = get_field(hold_report, 'cold_sink_temp_out', NaN) - get_field(hold_report, 'cold_sink_temp_in', NaN);
        item.stage4_cold_sink_delta_K = get_field(cooldown_report, 'cold_sink_temp_out', NaN) - get_field(cooldown_report, 'cold_sink_temp_in', NaN);
        item.stage4_chip_fluid_gain_K = get_field(cooldown_report, 'chip_fluid_endpoint_delta_K', ...
            get_field(cooldown_report, 'chip_fluid_temperature_gain_K', NaN));
        item.stage4_chip_drop_K = get_field(cooldown_report, 'chip_temp_in', NaN) - get_field(cooldown_report, 'chip_temp_out', NaN);
        item.stage4_chip_heat_source_J = get_field(cooldown_report, 'chip_heat_source_input_J', NaN);
        if isempty(cases)
            cases = item;
        else
            cases(end + 1) = item; %#ok<AGROW>
        end
    end
end

function stage_series = build_stage_end_series(run_result)
    cycle_results = reshape(get_field(run_result, 'cycle_results', struct([])), 1, []);
    config = get_field(run_result, 'config', struct());
    solver_options = get_field(config, 'solver_options', struct());
    exchange_options = get_field(config, 'exchange_options', struct());

    load_dt = get_field(solver_options, 'T_load', 0.1);
    hold_dt = get_field(exchange_options, 'hotflush_stop_time_s', 0.4);
    unload_dt = get_field(solver_options, 'T_unload', 0.1);
    cooldown_dt = get_field(exchange_options, 'coldflush_stop_time_s', 0.4);
    stage_dt = [load_dt, hold_dt, unload_dt, cooldown_dt];
    cycle_dt = sum(stage_dt);
    stage_names = {'load_adiabatic', 'hold_exchange', 'unload_adiabatic', 'cooldown_exchange'};

    initial_hot = get_field(exchange_options, 'hot_sink_T_init', get_field(exchange_options, 'ambient_T_init', 293));
    initial_cold = get_field(exchange_options, 'cold_sink_T_init', get_field(exchange_options, 'ambient_T_init', 293));
    initial_chip = get_field(exchange_options, 'cold_load_T_init', get_field(exchange_options, 'chip_T_init', 293));
    last_hot = initial_hot;
    last_cold = initial_cold;
    last_chip = initial_chip;
    initial_sma_T = get_field(solver_options, 'Tr', get_field(exchange_options, 'ambient_T_init', 293));

    stage_series = struct( ...
        'time_s', [], ...
        'cycle_index', [], ...
        'stage_index', [], ...
        'stage_name', {{}}, ...
        'avg_T_K', [], ...
        'center_T_K', [], ...
        'edge_T_K', [], ...
        'min_T_K', [], ...
        'max_T_K', [], ...
        'avg_xi', [], ...
        'max_xi', [], ...
        'center_deflection_mm', [], ...
        'peak_abs_deflection_mm', [], ...
        'pressure_MPa', [], ...
        'hot_sink_T_K', [], ...
        'cold_sink_T_K', [], ...
        'chip_T_K', [], ...
        'side_thermal_state_mode', {{}}, ...
        'frozen_side_state', [], ...
        'flush_volume_ratio', [], ...
        'h_water', []);
    stage_series.time_s = 0;
    stage_series.cycle_index = 0;
    stage_series.stage_index = 0;
    stage_series.stage_name = {'initial_state'};
    stage_series.avg_T_K = initial_sma_T;
    stage_series.center_T_K = initial_sma_T;
    stage_series.edge_T_K = initial_sma_T;
    stage_series.min_T_K = initial_sma_T;
    stage_series.max_T_K = initial_sma_T;
    stage_series.avg_xi = 0.0;
    stage_series.max_xi = 0.0;
    stage_series.center_deflection_mm = 0.0;
    stage_series.peak_abs_deflection_mm = 0.0;
    stage_series.pressure_MPa = 0.0;
    stage_series.hot_sink_T_K = initial_hot;
    stage_series.cold_sink_T_K = initial_cold;
    stage_series.chip_T_K = initial_chip;
    stage_series.side_thermal_state_mode = {'initial_state'};
    stage_series.frozen_side_state = true;
    stage_series.flush_volume_ratio = NaN;
    stage_series.h_water = NaN;

    for c = 1:numel(cycle_results)
        reports = reshape(get_field(cycle_results(c), 'stage_reports', struct([])), 1, []);
        cycle_index_value = get_field(cycle_results(c), 'cycle_index', c);
        elapsed = (cycle_index_value - 1) * cycle_dt;
        for s = 1:4
            elapsed = elapsed + stage_dt(s);
            report = get_stage_report(reports, stage_names{s});
            if isempty(fieldnames(report))
                continue;
            end

            last_hot = get_field(report, 'hot_sink_temp_out', last_hot);
            last_cold = get_field(report, 'cold_sink_temp_out', last_cold);
            last_chip = get_field(report, 'chip_temp_out', last_chip);

            summary = get_field(report, 'profile_summary', struct());
            stage_series.time_s(end + 1) = elapsed;
            stage_series.cycle_index(end + 1) = cycle_index_value;
            stage_series.stage_index(end + 1) = s;
            stage_series.stage_name{end + 1} = stage_names{s};
            stage_series.avg_T_K(end + 1) = get_field(report, 'avg_T_K', get_field(summary, 'avg_T_K', NaN));
            stage_series.center_T_K(end + 1) = get_field(report, 'center_T_K', get_field(summary, 'center_T_K', NaN));
            stage_series.edge_T_K(end + 1) = get_field(report, 'edge_T_K', get_field(summary, 'edge_T_K', NaN));
            stage_series.min_T_K(end + 1) = get_field(summary, 'min_T_K', NaN);
            stage_series.max_T_K(end + 1) = get_field(summary, 'max_T_K', NaN);
            stage_series.avg_xi(end + 1) = get_field(report, 'avg_xi', get_field(summary, 'avg_xi', NaN));
            stage_series.max_xi(end + 1) = get_field(report, 'max_xi', get_field(summary, 'max_xi', NaN));
            stage_series.center_deflection_mm(end + 1) = get_field(report, 'center_deflection_mm', get_field(summary, 'center_deflection_mm', NaN));
            stage_series.peak_abs_deflection_mm(end + 1) = get_field(report, 'peak_abs_deflection_mm', get_field(summary, 'peak_abs_deflection_mm', NaN));
            stage_series.pressure_MPa(end + 1) = get_field(report, 'final_pressure_MPa', get_field(summary, 'pressure_MPa', NaN));
            stage_series.hot_sink_T_K(end + 1) = last_hot;
            stage_series.cold_sink_T_K(end + 1) = last_cold;
            stage_series.chip_T_K(end + 1) = last_chip;
            stage_series.side_thermal_state_mode{end + 1} = get_field(report, 'side_thermal_state_mode', '');
            stage_series.frozen_side_state(end + 1) = logical(get_field(report, 'frozen_side_state', false));
            stage_series.flush_volume_ratio(end + 1) = get_field(report, 'flush_volume_ratio', NaN);
            stage_series.h_water(end + 1) = get_field(report, 'h_water', NaN);
        end
    end
end

function plot_info = plot_stage_end_sma_temperature_time(plot_info, s, figures_dir)
    fig = make_figure();
    hold on;
    plot(s.time_s, s.max_T_K, marker_style('-^', s.time_s), 'Color', [0.86 0.22 0.14], ...
        'LineWidth', 1.5, 'DisplayName', 'Maximum');
    plot(s.time_s, s.avg_T_K, marker_style('-o', s.time_s), 'Color', [0.12 0.12 0.12], ...
        'LineWidth', 1.8, 'DisplayName', 'Average');
    plot(s.time_s, s.min_T_K, marker_style('-v', s.time_s), 'Color', [0.12 0.46 0.82], ...
        'LineWidth', 1.5, 'DisplayName', 'Minimum');
    decorate_stage_axis(s);
    hold off;
    xlabel('Time t (s)');
    ylabel('SMA temperature (K)');
    title('SMA stage-end temperature evolution');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'time_stage_end_sma_temperature.png');
end

function plot_info = plot_stage_end_thermal_objects_time(plot_info, s, figures_dir)
    fig = make_figure();
    hold on;
    plot(s.time_s, s.hot_sink_T_K, marker_style('-o', s.time_s), 'Color', [0.86 0.22 0.14], ...
        'LineWidth', 1.8, 'DisplayName', 'Hot sink');
    plot(s.time_s, s.cold_sink_T_K, marker_style('-s', s.time_s), 'Color', [0.12 0.46 0.82], ...
        'LineWidth', 1.8, 'DisplayName', 'Cold sink');
    plot(s.time_s, s.chip_T_K, marker_style('-^', s.time_s), 'Color', [0.36 0.36 0.36], ...
        'LineWidth', 1.5, 'DisplayName', 'Cold load');
    decorate_stage_axis(s);
    hold off;
    xlabel('Time t (s)');
    ylabel('Internal thermal-mass temperature (K)');
    title('Hot sink, cold sink, and cold-load internal temperatures at stage ends');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'time_stage_end_hot_cold_cold_load_temperature_overview.png');

    fig = make_figure();
    hold on;
    plot(s.time_s, s.hot_sink_T_K - s.hot_sink_T_K(1), marker_style('-o', s.time_s), 'Color', [0.86 0.22 0.14], ...
        'LineWidth', 1.8, 'DisplayName', 'Hot sink');
    plot(s.time_s, s.cold_sink_T_K - s.cold_sink_T_K(1), marker_style('-s', s.time_s), 'Color', [0.12 0.46 0.82], ...
        'LineWidth', 1.8, 'DisplayName', 'Cold sink');
    plot(s.time_s, s.chip_T_K - s.chip_T_K(1), marker_style('-^', s.time_s), 'Color', [0.36 0.36 0.36], ...
        'LineWidth', 1.5, 'DisplayName', 'Cold load');
    yline(0, ':', 'Color', [0.45 0.45 0.45], 'HandleVisibility', 'off');
    decorate_stage_axis(s);
    hold off;
    xlabel('Time t (s)');
    ylabel('Temperature change from initial state (K)');
    title('Internal thermal-object temperature changes at stage ends');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'time_stage_end_hot_cold_cold_load_temperature_change.png');

    fig = make_figure();
    hold on;
    plot(s.time_s, s.hot_sink_T_K, marker_style('-o', s.time_s), 'Color', [0.86 0.22 0.14], ...
        'LineWidth', 1.8, 'DisplayName', 'Hot sink');
    plot(s.time_s, s.cold_sink_T_K, marker_style('-s', s.time_s), 'Color', [0.12 0.46 0.82], ...
        'LineWidth', 1.8, 'DisplayName', 'Cold sink');
    decorate_stage_axis(s);
    hold off;
    xlabel('Time t (s)');
    ylabel('Internal sink temperature (K)');
    title('Hot/cold sink internal temperatures at stage ends, zoomed');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'time_hot_cold_sink_temperature_zoom.png');

    chip_track_mask = (s.stage_index == 0) | (s.stage_index == 2) | (s.stage_index == 4);
    if any(chip_track_mask)
        sx = subset_stage_series(s, chip_track_mask);
        fig = make_figure();
        hold on;
        plot(sx.time_s, sx.chip_T_K, marker_style('-o', sx.time_s), ...
            'LineWidth', 1.8, 'DisplayName', 'Cold-load temperature');
        decorate_stage_axis(sx);
        label_cold_load_exchange_points(sx, sx.chip_T_K);
        hold off;
        xlabel('Time t (s)');
        ylabel('Cold-load temperature (K)');
        title('Cold-load temperature from initial state through active exchange stages');
        legend('Location', 'best');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'time_cold_load_temperature_absolute.png');

        fig = make_figure();
        chip_reference = sx.chip_T_K(1);
        hold on;
        chip_delta = sx.chip_T_K - chip_reference;
        plot(sx.time_s, chip_delta, marker_style('-o', sx.time_s), ...
            'LineWidth', 1.8, 'DisplayName', 'Cold-load temperature change');
        decorate_stage_axis(sx);
        label_cold_load_exchange_points(sx, chip_delta);
        hold off;
        xlabel('Time t (s)');
        ylabel('Cold-load temperature change from initial state (K)');
        title('Cold-load cumulative change from initial state');
        legend('Location', 'best');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'time_cold_load_temperature_change.png');
    end
end

function plot_info = plot_stage_end_xi_time(plot_info, s, figures_dir)
    fig = make_figure();
    hold on;
    plot(s.time_s, s.avg_xi, marker_style('-o', s.time_s), 'LineWidth', 1.8, 'DisplayName', 'Average xi');
    plot(s.time_s, s.max_xi, marker_style('-s', s.time_s), 'LineWidth', 1.5, 'DisplayName', 'Max xi');
    decorate_stage_axis(s);
    hold off;
    xlabel('Time t (s)');
    ylabel('Martensite volume fraction');
    title('SMA martensite fraction at stage ends');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'time_stage_end_martensite_fraction.png');
end

function plot_info = plot_stage_end_deflection_pressure_time(plot_info, s, figures_dir)
    fig = make_figure();
    yyaxis left
    plot(s.time_s, s.center_deflection_mm, marker_style('-o', s.time_s), 'LineWidth', 1.7);
    ylabel('Center deflection w(0) (mm)');
    yyaxis right
    plot(s.time_s, s.pressure_MPa, marker_style('-s', s.time_s), 'LineWidth', 1.5);
    ylabel('Pressure (MPa)');
    decorate_stage_axis(s);
    xlabel('Time t (s)');
    title('Stage-end center deflection and pressure');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'time_stage_end_deflection_pressure.png');
end

function plot_info = plot_cycle_level_summary(plot_info, diagnostics, figures_dir, run_result)
    c = [diagnostics.cycle_index];
    config = get_field(run_result, 'config', struct());
    solver_options = get_field(config, 'solver_options', struct());
    exchange_options = get_field(config, 'exchange_options', struct());
    initial_sma_T = get_field(solver_options, 'Tr', get_field(exchange_options, 'ambient_T_init', 293));
    initial_hot = get_field(exchange_options, 'hot_sink_T_init', get_field(exchange_options, 'ambient_T_init', 293));
    initial_cold = get_field(exchange_options, 'cold_sink_T_init', get_field(exchange_options, 'ambient_T_init', 293));
    initial_chip = get_field(exchange_options, 'cold_load_T_init', get_field(exchange_options, 'chip_T_init', 293));
    c0 = [0, c];
    fig = make_figure();
    hold on;
    plot(c0, [initial_sma_T, [diagnostics.load_end_avg_T_K]], marker_style('-o', c0), 'LineWidth', 1.5, 'DisplayName', 'Initial + load end');
    plot(c0, [initial_sma_T, [diagnostics.hold_end_avg_T_K]], marker_style('-s', c0), 'LineWidth', 1.5, 'DisplayName', 'Initial + hold end');
    plot(c0, [initial_sma_T, [diagnostics.unload_end_avg_T_K]], marker_style('-^', c0), 'LineWidth', 1.5, 'DisplayName', 'Initial + unload end');
    plot(c0, [initial_sma_T, [diagnostics.cold_end_avg_T_K]], marker_style('-d', c0), 'LineWidth', 1.5, 'DisplayName', 'Initial + cooldown end');
    hold off;
    xlabel('Cycle');
    ylabel('Average SMA temperature (K)');
    title('Cycle-resolved stage-end average SMA temperature, including initial state');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_stage_end_avg_sma_temperature.png');

    fig = make_figure();
    hold on;
    plot(c0, [initial_hot, [diagnostics.hot_sink_temp_after_coldflush]], marker_style('-o', c0), 'LineWidth', 1.5, 'DisplayName', 'Hot sink');
    plot(c0, [initial_cold, [diagnostics.cold_sink_temp_after_coldflush]], marker_style('-s', c0), 'LineWidth', 1.5, 'DisplayName', 'Cold sink');
    plot(c0, [initial_chip, report_vector(diagnostics, 'cold_load_temp_after_coldflush', 'chip_temp_after_coldflush')], ...
        marker_style('-^', c0), 'LineWidth', 1.5, 'DisplayName', 'Cold load');
    hold off;
    xlabel('Cycle');
    ylabel('Temperature (K)');
    title('Thermal object temperatures from initial state to each cooldown end');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_cooldown_end_thermal_objects.png');

    [chip_x, chip_y, chip_labels] = build_cycle_cold_load_track(diagnostics, initial_chip);
    fig = make_figure();
    plot(chip_x, chip_y, marker_style('-o', chip_x), 'LineWidth', 1.8, 'DisplayName', 'Cold-load temperature');
    set_sparse_xticks(gca, chip_x, chip_labels, 28);
    xlabel('Global active-exchange point');
    ylabel('Cold-load temperature (K)');
    title('Continuous cold-load temperature track from initial state');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_cold_load_temperature_exchange_end_trend.png');

    fig = make_figure();
    yyaxis left
    plot(c0, [0, [diagnostics.avg_xi_final]], marker_style('-o', c0), 'LineWidth', 1.5);
    ylabel('Final average xi');
    yyaxis right
    plot(c0, [0, [diagnostics.center_deflection_peak_mm]], marker_style('-s', c0), 'LineWidth', 1.5);
    ylabel('Peak |w| (mm)');
    xlabel('Cycle');
    title('Final martensite fraction and peak deflection by cycle, including initial state');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_final_xi_peak_deflection.png');
end

function [x, y, labels] = build_cycle_cold_load_track(diagnostics, initial_chip)
    diagnostics = reshape(diagnostics, 1, []);
    x = 0;
    y = initial_chip;
    labels = {'C0 Initial'};
    point_index = 0;
    for idx = 1:numel(diagnostics)
        cycle_index = get_field(diagnostics(idx), 'cycle_index', idx);
        point_index = point_index + 1;
        x(end + 1) = point_index; %#ok<AGROW>
        y(end + 1) = get_field(diagnostics(idx), 'cold_load_temp_after_hotflush', ...
            get_field(diagnostics(idx), 'chip_temp_after_hotflush', NaN)); %#ok<AGROW>
        labels{end + 1} = sprintf('C%d-S2', cycle_index); %#ok<AGROW>
        point_index = point_index + 1;
        x(end + 1) = point_index; %#ok<AGROW>
        y(end + 1) = get_field(diagnostics(idx), 'cold_load_temp_after_coldflush', ...
            get_field(diagnostics(idx), 'chip_temp_after_coldflush', NaN)); %#ok<AGROW>
        labels{end + 1} = sprintf('C%d-S4', cycle_index); %#ok<AGROW>
    end
end

function plot_info = plot_exchange_controls(plot_info, diagnostics, figures_dir)
    c = [diagnostics.cycle_index];
    fig = make_figure();
    tiledlayout(3, 1, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    hold on;
    plot(c, [diagnostics.hold_h_water], marker_style('-o', c), 'LineWidth', 1.5, 'DisplayName', 'Hold');
    plot(c, [diagnostics.cooldown_h_water], marker_style('-s', c), 'LineWidth', 1.5, 'DisplayName', 'Cooldown');
    hold off;
    ylabel('h (W/m^2/K)');
    title('Exchange heat-transfer coefficient');
    legend('Location', 'best');
    grid on;

    nexttile;
    hold on;
    plot(c, [diagnostics.hold_flush_volume_ratio], marker_style('-o', c), 'LineWidth', 1.5, 'DisplayName', 'Hold');
    plot(c, [diagnostics.cooldown_flush_volume_ratio], marker_style('-s', c), 'LineWidth', 1.5, 'DisplayName', 'Cooldown');
    hold off;
    ylabel('Flush ratio');
    title('Flush volume ratio');
    grid on;

    nexttile;
    plot(c, report_vector(diagnostics, 'cold_load_drop_cooldown_K', 'chip_drop_cooldown_K'), ...
        marker_style('-^', c), 'LineWidth', 1.5);
    xlabel('Cycle');
    ylabel('Cold-load drop (K)');
    title('Cold-load temperature drop during cooldown exchange');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_exchange_controls_and_cold_load_drop.png');
end

function plot_info = plot_first_cycle_profiles(plot_info, cycle_result, figures_dir, config)
    reports = cycle_result.stage_reports;
    labels = {'load_adiabatic', 'hold_exchange', 'unload_adiabatic', 'cooldown_exchange'};
    display_labels = {'Load end', 'Hold exchange end', 'Unload end', 'Cooldown end'};
    initial_sma_T = get_initial_sma_temperature(config);

    fig = make_figure();
    hold on;
    initial_r_mm = [];
    for idx = 1:numel(labels)
        profile = get_field(get_stage_report(reports, labels{idx}), 'profile', struct());
        if has_profile(profile, 'T_K')
            if isempty(initial_r_mm)
                initial_r_mm = profile.r_mm(:);
                plot(initial_r_mm, initial_sma_T * ones(size(initial_r_mm)), '--', ...
                    'LineWidth', 1.2, 'DisplayName', 'Initial');
            end
            plot(profile.r_mm, profile.T_K, 'LineWidth', 1.5, 'DisplayName', display_labels{idx});
        end
    end
    hold off;
    xlabel('Radius (mm)');
    ylabel('SMA temperature (K)');
    title('Cycle 1 radial SMA temperature profiles, including initial state');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'cycle1_radial_temperature_profiles.png');

    load_profile = get_field(get_stage_report(reports, 'load_adiabatic'), 'profile', struct());
    if has_profile(load_profile, 'w_mm')
        fig = make_figure();
        plot(load_profile.r_mm, load_profile.w_mm, '-o', 'LineWidth', 1.5);
        xlabel('Radius (mm)');
        ylabel('Deflection w (mm)');
        title('Cycle 1 load-end deflection profile');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'cycle1_load_end_deflection.png');

        fig = make_figure();
        plot(load_profile.r_mm, load_profile.xi, '-o', 'LineWidth', 1.5);
        xlabel('Radius (mm)');
        ylabel('Martensite fraction xi');
        title('Cycle 1 load-end martensite profile');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'cycle1_load_end_xi.png');
    end
end

function plot_info = plot_first_load_stress_strain(plot_info, cycle_result, figures_dir)
    load_report = get_stage_report(cycle_result.stage_reports, 'load_adiabatic');
    checkpoint_path = get_field(load_report, 'checkpoint_path', '');
    if isempty(checkpoint_path) || ~exist(checkpoint_path, 'file')
        return;
    end

    mechanics = reconstruct_checkpoint_mechanics(checkpoint_path);
    if isempty(fieldnames(mechanics))
        return;
    end

    fig = make_figure();
    hold on;
    plot(mechanics.r_mm, mechanics.eps_r * 1e3, '-o', 'LineWidth', 1.5, 'DisplayName', '\epsilon_r');
    plot(mechanics.r_mm, mechanics.eps_theta * 1e3, '-s', 'LineWidth', 1.5, 'DisplayName', '\epsilon_\theta');
    plot(mechanics.r_mm, mechanics.eps_eq * 1e3, '-^', 'LineWidth', 1.5, 'DisplayName', '\epsilon_{eq}');
    hold off;
    xlabel('Radius (mm)');
    ylabel('Strain (10^{-3})');
    title('Cycle 1 load-end strain profile');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'cycle1_load_end_strain_profile.png');

    fig = make_figure();
    hold on;
    plot(mechanics.r_mm, mechanics.sigma_r_MPa, '-o', 'LineWidth', 1.5, 'DisplayName', '\sigma_r');
    plot(mechanics.r_mm, mechanics.sigma_theta_MPa, '-s', 'LineWidth', 1.5, 'DisplayName', '\sigma_\theta');
    plot(mechanics.r_mm, mechanics.sigma_eq_MPa, '-^', 'LineWidth', 1.5, 'DisplayName', '\sigma_{eq}');
    hold off;
    xlabel('Radius (mm)');
    ylabel('Stress (MPa)');
    title('Cycle 1 load-end stress profile');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'cycle1_load_end_stress_profile.png');

    fig = make_figure();
    scatter(mechanics.eps_eq * 1e3, mechanics.sigma_eq_MPa, 36, mechanics.r_mm, 'filled');
    xlabel('Equivalent strain (10^{-3})');
    ylabel('Equivalent stress (MPa)');
    title('Cycle 1 load-end stress-strain map colored by radius');
    cb = colorbar;
    cb.Label.String = 'Radius (mm)';
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'cycle1_load_end_stress_strain_map.png');
end

function plot_info = plot_cycle_stage_heatmaps(plot_info, cycle_results, figures_dir, config)
    [T_matrix, xi_matrix, r_mm, row_labels] = build_profile_matrices(cycle_results);
    if isempty(T_matrix)
        return;
    end
    initial_sma_T = get_initial_sma_temperature(config);
    T_matrix = [initial_sma_T * ones(1, numel(r_mm)); T_matrix];
    xi_matrix = [zeros(1, numel(r_mm)); xi_matrix];
    row_labels = [{'C0-Initial'}, row_labels];
    y_ticks = sparse_tick_indices(size(T_matrix, 1), 32);

    fig = make_figure();
    imagesc(r_mm, 1:size(T_matrix, 1), T_matrix);
    set(gca, 'YTick', y_ticks, 'YTickLabel', row_labels(y_ticks));
    xlabel('Radius (mm)');
    ylabel('Cycle-stage');
    title('Representative stage-end radial SMA temperature heatmap, including initial state');
    cb = colorbar;
    cb.Label.String = 'Temperature (K)';
    plot_info = save_plot(plot_info, fig, figures_dir, 'heatmap_stage_end_radial_temperature.png');

    fig = make_figure();
    imagesc(r_mm, 1:size(xi_matrix, 1), xi_matrix);
    set(gca, 'YTick', y_ticks, 'YTickLabel', row_labels(y_ticks));
    xlabel('Radius (mm)');
    ylabel('Cycle-stage');
    title('Representative stage-end radial martensite fraction heatmap, including initial state');
    cb = colorbar;
    cb.Label.String = 'xi';
    plot_info = save_plot(plot_info, fig, figures_dir, 'heatmap_stage_end_radial_xi.png');
end

function plot_info = plot_final_cycle_profiles(plot_info, cycle_results, figures_dir, config)
    fig = make_figure();
    hold on;
    initial_sma_T = get_initial_sma_temperature(config);
    plotted_initial = false;
    for c = 1:numel(cycle_results)
        cycle_index = get_field(cycle_results(c), 'cycle_index', c);
        report = get_stage_report(cycle_results(c).stage_reports, 'cooldown_exchange');
        profile = get_field(report, 'profile', struct());
        if has_profile(profile, 'T_K')
            if ~plotted_initial
                r0 = profile.r_mm(:);
                plot(r0, initial_sma_T * ones(size(r0)), '--', ...
                    'LineWidth', 1.2, 'DisplayName', 'Initial');
                plotted_initial = true;
            end
            plot(profile.r_mm, profile.T_K, 'LineWidth', 1.5, ...
                'DisplayName', sprintf('Cycle %d', cycle_index));
        end
    end
    hold off;
    xlabel('Radius (mm)');
    ylabel('Cooldown-end SMA temperature (K)');
    title('Representative cooldown-end radial temperature profiles, including initial state');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'cooldown_end_temperature_profiles_by_cycle.png');
end

function plot_info = plot_exchange_101_profiles(plot_info, cycle_results, figures_dir)
    exchange_names = {'hold_exchange', 'cooldown_exchange'};
    display_names = {'Stage 2 hold exchange: cold -> SMA -> hot', ...
        'Stage 4 cooldown exchange: hot -> SMA -> CHEX/cold return'};
    for c = 1:numel(cycle_results)
        cycle_index = get_field(cycle_results(c), 'cycle_index', c);
        for s = 1:numel(exchange_names)
            report = get_stage_report(cycle_results(c).stage_reports, exchange_names{s});
            cp = load_exchange_checkpoint(report);
            if isempty(fieldnames(cp)) || ~isfield(cp, 'T_x_in_101') || ~isfield(cp, 'T_x_out_101')
                continue;
            end
            x_mm = 1:numel(cp.T_x_out_101);
            if isfield(cp, 'strip_geometry') && isfield(cp.strip_geometry, 'x_strip_m')
                x_mm = 1.0e3 * cp.strip_geometry.x_strip_m(:);
            end
            fig = make_figure();
            hold on;
            plot(x_mm, cp.T_x_in_101(:), '--', 'LineWidth', 1.4, 'DisplayName', 'T_x in');
            plot(x_mm, cp.T_x_out_101(:), '-', 'LineWidth', 1.8, 'DisplayName', 'T_x out');
            hold off;
            xlabel('Diameter coordinate x (mm), cold side -R to hot side +R');
            ylabel('SMA strip temperature (K)');
            title(sprintf('Representative cycle %d %s', cycle_index, display_names{s}));
            subtitle(sprintf('Endpoint \\DeltaT = %.4g K, nonmirror max = %.4g K', ...
                cp.T_x_out_101(end) - cp.T_x_out_101(1), max(abs(cp.T_x_out_101(:) - flipud(cp.T_x_out_101(:))))));
            legend('Location', 'best');
            grid on;
            plot_info = save_plot(plot_info, fig, figures_dir, ...
                sprintf('cycle%d_%s_Tx101_directional_profile.png', cycle_index, exchange_names{s}));
        end
    end
end

function plot_info = plot_exchange_fluid_probes(plot_info, cycle_results, figures_dir)
    hold_reports = collect_stage_reports(cycle_results, 'hold_exchange');
    cooldown_reports = collect_stage_reports(cycle_results, 'cooldown_exchange');
    if ~isempty(hold_reports)
        c = [hold_reports.cycle_index];
        fig = make_figure();
        hold on;
        plot(c, report_vector(hold_reports, 'probe_sma_stage2_port1_v1_side_T_K', 'sma_hold_inlet_fluid_temp_out'), marker_style('-o', c), 'LineWidth', 1.5, 'DisplayName', 'SMA S2 port1 / V1 side');
        plot(c, report_vector(hold_reports, 'probe_sma_stage2_port2_v3_side_T_K', 'sma_hold_outlet_fluid_temp_out'), marker_style('-s', c), 'LineWidth', 1.5, 'DisplayName', 'SMA S2 port2 / V3 side');
        plot(c, report_vector(hold_reports, 'probe_hot_hx_port1_v3_side_T_K', 'hot_hx_inlet_fluid_temp_out'), marker_style('-^', c), 'LineWidth', 1.5, 'DisplayName', 'Hot HX port1 / V3 side');
        plot(c, report_vector(hold_reports, 'probe_hot_hx_port2_v2_return_side_T_K', 'hot_hx_outlet_fluid_temp_out'), marker_style('-d', c), 'LineWidth', 1.5, 'DisplayName', 'Hot HX port2 / V2 return');
        hold off;
        xlabel('Cycle');
        ylabel('Fluid probe temperature (K)');
        title('Stage 2 fixed-port fluid probe temperatures');
        legend('Location', 'best');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_hold_exchange_fluid_probe_temperatures.png');
    end

    if ~isempty(cooldown_reports)
        c = [cooldown_reports.cycle_index];
        fig = make_figure();
        hold on;
        plot(c, report_vector(cooldown_reports, 'probe_sma_stage4_port3_v4_side_T_K', 'sma_cooldown_inlet_fluid_temp_out'), marker_style('-o', c), 'LineWidth', 1.5, 'DisplayName', 'SMA S4 port3 / V4 side');
        plot(c, report_vector(cooldown_reports, 'probe_sma_stage4_port4_v6_side_T_K', 'sma_cooldown_outlet_fluid_temp_out'), marker_style('-s', c), 'LineWidth', 1.5, 'DisplayName', 'SMA S4 port4 / V6 side');
        plot(c, report_vector(cooldown_reports, 'cold_hx_inlet_fluid_temp_out', 'probe_chip_pipe_port_conn2_v6_sma_side_T_K'), marker_style('-^', c), 'LineWidth', 1.5, 'DisplayName', 'CHEX inlet / V6 side');
        plot(c, report_vector(cooldown_reports, 'cold_hx_outlet_fluid_temp_out', 'probe_chip_to_cold_junction_T_K'), marker_style('-d', c), 'LineWidth', 1.5, 'DisplayName', 'CHEX outlet boundary');
        plot(c, report_vector(cooldown_reports, 'probe_cold_hx_port_conn1_v5_return_side_T_K', 'cold_hx_outlet_fluid_temp_out'), marker_style('-v', c), 'LineWidth', 1.5, 'DisplayName', 'Cold HX Conn1 / V5 return');
        hold off;
        xlabel('Cycle');
        ylabel('Fluid probe temperature (K)');
        title('Stage 4 fixed-port fluid probe temperatures');
        legend('Location', 'best');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_cooldown_exchange_fluid_probe_temperatures.png');

        fig = make_figure();
        hold on;
        plot(c, report_vector(cooldown_reports, 'probe_stage4_sma_port4_minus_port3_K', ''), marker_style('-o', c), ...
            'LineWidth', 1.5, 'DisplayName', 'SMA port4 - port3');
        plot(c, report_vector(cooldown_reports, 'probe_stage4_v4_sma_side_minus_hot_side_K', ''), marker_style('-s', c), ...
            'LineWidth', 1.5, 'DisplayName', 'V4 SMA side - hot side');
        plot(c, report_vector(cooldown_reports, 'probe_stage4_sma_port3_minus_v4_sma_side_K', ''), marker_style('-^', c), ...
            'LineWidth', 1.5, 'DisplayName', 'SMA port3 - V4 SMA side');
        plot(c, report_vector(cooldown_reports, 'probe_stage4_v6_chip_side_minus_sma_side_K', ''), marker_style('-d', c), ...
            'LineWidth', 1.5, 'DisplayName', 'V6 CHEX side - SMA side');
        plot(c, report_vector(cooldown_reports, 'probe_stage4_chip_conn2_minus_v6_chip_side_K', ''), marker_style('-v', c), ...
            'LineWidth', 1.5, 'DisplayName', 'CHEX inlet - V6 CHEX side');
        plot(c, report_vector(cooldown_reports, 'probe_stage4_chip_junction_minus_chip_conn2_K', 'chip_fluid_endpoint_delta_K'), marker_style('-p', c), ...
            'LineWidth', 1.5, 'DisplayName', 'CHEX endpoint out - in (same time)');
        plot(c, report_vector(cooldown_reports, 'probe_stage4_cold_port_conn1_minus_chip_junction_K', ''), marker_style('-h', c), ...
            'LineWidth', 1.5, 'DisplayName', 'Cold return - CHEX outlet boundary');
        yline(0, ':', 'LineWidth', 1.0, 'DisplayName', 'zero');
        hold off;
        xlabel('Cycle');
        ylabel('Probe temperature jump (K)');
        title('Stage 4 fixed-port temperature jumps for anomaly localization');
        legend('Location', 'best');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_stage4_probe_temperature_jumps.png');
    end
end

function plot_info = plot_exchange_probe_timeseries(plot_info, cycle_results, figures_dir)
    if isempty(cycle_results)
        return;
    end
    reports = reshape(get_field(cycle_results(1), 'stage_reports', struct([])), 1, []);
    hold_report = get_stage_report(reports, 'hold_exchange');
    cooldown_report = get_stage_report(reports, 'cooldown_exchange');
    if ~has_probe_timeseries(hold_report) && ~has_probe_timeseries(cooldown_report)
        return;
    end

    fig = make_figure();
    hold on;
    plot_probe_line(hold_report, 'T_hot_sink_K_t', '-', [0.78 0.22 0.12], 'Hot sink, stage 2');
    plot_probe_line(cooldown_report, 'T_hot_sink_K_t', '-', [0.78 0.22 0.12], 'Hot sink, stage 4');
    plot_probe_line(hold_report, 'T_cold_sink_K_t', '-', [0.18 0.36 0.72], 'Cold sink, stage 2');
    plot_probe_line(cooldown_report, 'T_cold_sink_K_t', '-', [0.18 0.36 0.72], 'Cold sink, stage 4');
    plot_probe_line(hold_report, 'T_cold_load_K_t', '-', [0.28 0.50 0.24], 'Cold load, stage 2');
    plot_probe_line(cooldown_report, 'T_cold_load_K_t', '-', [0.28 0.50 0.24], 'Cold load, stage 4');
    plot_probe_line(cooldown_report, 'T_cold_supply_K_t', '--', [0.20 0.65 0.85], 'CHEX inlet / cold supply');
    plot_probe_line(cooldown_report, 'T_cold_return_K_t', '--', [0.45 0.20 0.72], 'CHEX outlet / cold return');
    add_probe_stage_boundaries(hold_report, cooldown_report);
    hold off;
    xlabel('Time (s)');
    ylabel('Temperature (K)');
    title('Exchange-stage 50-point temperature probes');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'time_exchange_probe_temperature_timeseries.png');

    fig = make_figure();
    hold on;
    plot_probe_line(hold_report, 'T_sma_fluid_in_K_t', '-', [0.10 0.45 0.75], 'Stage 2 SMA fluid inlet');
    plot_probe_line(hold_report, 'T_sma_fluid_out_K_t', '--', [0.10 0.45 0.75], 'Stage 2 SMA fluid outlet');
    plot_probe_line(cooldown_report, 'T_sma_fluid_in_K_t', '-', [0.85 0.33 0.10], 'Stage 4 SMA fluid inlet');
    plot_probe_line(cooldown_report, 'T_sma_fluid_out_K_t', '--', [0.85 0.33 0.10], 'Stage 4 SMA fluid outlet');
    plot_probe_line(cooldown_report, 'T_cold_hx_inlet_fluid_K_t', '-.', [0.20 0.65 0.85], 'Stage 4 CHEX inlet');
    plot_probe_line(cooldown_report, 'T_cold_hx_outlet_fluid_K_t', ':', [0.45 0.20 0.72], 'Stage 4 CHEX outlet');
    add_probe_stage_boundaries(hold_report, cooldown_report);
    hold off;
    xlabel('Time (s)');
    ylabel('Fluid temperature (K)');
    title('SMA and CHEX inlet/outlet fluid probes');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'time_exchange_probe_fluid_inlet_outlet.png');

    fig = make_figure();
    hold on;
    plot_probe_line(hold_report, 'T_sma_101_mean_K_t', '-', [0.10 0.45 0.75], 'Stage 2 SMA mean');
    plot_probe_line(hold_report, 'T_sma_101_center_K_t', '--', [0.10 0.45 0.75], 'Stage 2 SMA center');
    plot_probe_line(hold_report, 'T_sma_101_edge_K_t', ':', [0.10 0.45 0.75], 'Stage 2 SMA edge');
    plot_probe_line(cooldown_report, 'T_sma_101_mean_K_t', '-', [0.85 0.33 0.10], 'Stage 4 SMA mean');
    plot_probe_line(cooldown_report, 'T_sma_101_center_K_t', '--', [0.85 0.33 0.10], 'Stage 4 SMA center');
    plot_probe_line(cooldown_report, 'T_sma_101_edge_K_t', ':', [0.85 0.33 0.10], 'Stage 4 SMA edge');
    add_probe_stage_boundaries(hold_report, cooldown_report);
    hold off;
    xlabel('Time (s)');
    ylabel('SMA temperature (K)');
    title('SMA 101-node mean/center/edge during exchange stages');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'time_exchange_probe_sma_101_timeseries.png');
end

function tf = has_probe_timeseries(report)
    tf = isstruct(report) && isfield(report, 'probe_time_global_s') && ...
        isnumeric(report.probe_time_global_s) && numel(report.probe_time_global_s) >= 2;
end

function plot_probe_line(report, field_name, line_style, color_value, label_text)
    if ~has_probe_timeseries(report) || ~isfield(report, field_name)
        return;
    end
    t = report.probe_time_global_s(:);
    y = report.(field_name);
    if ~isnumeric(y)
        return;
    end
    y = y(:);
    if numel(y) ~= numel(t) || ~any(isfinite(y))
        return;
    end
    plot(t, y, line_style, 'LineWidth', 1.5, 'Color', color_value, 'DisplayName', label_text);
end

function add_probe_stage_boundaries(hold_report, cooldown_report)
    add_one_probe_boundary(hold_report, 'Stage 2');
    add_one_probe_boundary(cooldown_report, 'Stage 4');
end

function add_one_probe_boundary(report, label_text)
    if ~has_probe_timeseries(report)
        return;
    end
    t = report.probe_time_global_s(:);
    xline(t(1), ':', label_text, 'Color', [0.45 0.45 0.45], ...
        'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
    xline(t(end), ':', 'Color', [0.75 0.75 0.75], 'HandleVisibility', 'off');
end

function plot_info = plot_exchange_path_order_probes(plot_info, cycle_results, figures_dir)
    hold_reports = collect_stage_reports(cycle_results, 'hold_exchange');
    cooldown_reports = collect_stage_reports(cycle_results, 'cooldown_exchange');

    if ~isempty(hold_reports)
        reports = select_representative_stage_reports(hold_reports, 10);
        labels = {'Cold buffer', 'V1 cold side', 'V1 SMA side', 'SMA S2 port1', ...
            'SMA S2 port2', 'V3 SMA side', 'V3 hot side', 'Hot HX port1', 'Hot HX port2'};
        fig = make_figure();
        hold on;
        for idx = 1:numel(reports)
            values = [ ...
                get_field(reports(idx), 'probe_root_cold_buffer_fluid_T_K', NaN), ...
                get_field(reports(idx), 'probe_v1_cold_inlet_cold_buffer_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_v1_cold_inlet_sma_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_sma_stage2_port1_v1_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_sma_stage2_port2_v3_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_v3_sma_to_hot_sma_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_v3_sma_to_hot_hot_hx_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_hot_hx_port1_v3_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_hot_hx_port2_v2_return_side_T_K', NaN)];
            plot(1:numel(values), values, marker_style('-o', values), 'LineWidth', 1.5, ...
                'DisplayName', sprintf('Cycle %d', get_field(reports(idx), 'cycle_index', idx)));
        end
        hold off;
        set(gca, 'XTick', 1:numel(labels), 'XTickLabel', labels);
        xtickangle(25);
        ylabel('Fluid temperature (K)');
        title('Stage 2 fixed-port sequence with valve-side probes');
        legend('Location', 'best');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'stage2_ordered_fluid_path_temperatures.png');

        c = [hold_reports.cycle_index];
        fig = make_figure();
        hold on;
        plot(c, [hold_reports.hot_sink_temp_in], marker_style('-o', c), 'LineWidth', 1.5, 'DisplayName', 'Hot sink internal in');
        plot(c, [hold_reports.hot_sink_temp_out], marker_style('-s', c), 'LineWidth', 1.5, 'DisplayName', 'Hot sink internal out');
        plot(c, [hold_reports.hot_sink_temp_out] - [hold_reports.hot_sink_temp_in], marker_style('-^', c), ...
            'LineWidth', 1.5, 'DisplayName', 'Hot sink internal \DeltaT');
        hold off;
        xlabel('Cycle');
        ylabel('Temperature or \DeltaT (K)');
        title('Stage 2 hot-sink internal response');
        legend('Location', 'best');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_stage2_hot_sink_internal_response.png');
    end

    if ~isempty(cooldown_reports)
        reports = select_representative_stage_reports(cooldown_reports, 10);
        labels = {'Hot buffer', 'V4 hot side', 'V4 SMA side', 'SMA S4 port3', ...
            'SMA S4 port4', 'V6 SMA side', 'V6 CHEX side', 'CHEX inlet', ...
            'CHEX outlet', 'Cold return', 'Cold buffer'};
        fig = make_figure();
        hold on;
        for idx = 1:numel(reports)
            values = [ ...
                get_field(reports(idx), 'probe_root_hot_buffer_fluid_T_K', NaN), ...
                get_field(reports(idx), 'probe_v4_hot_inlet_hot_buffer_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_v4_hot_inlet_sma_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_sma_stage4_port3_v4_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_sma_stage4_port4_v6_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_v6_sma_to_chip_sma_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_v6_sma_to_chip_chip_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_chip_pipe_port_conn2_v6_sma_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_chip_to_cold_junction_T_K', NaN), ...
                get_field(reports(idx), 'probe_cold_hx_port_conn1_v5_return_side_T_K', NaN), ...
                get_field(reports(idx), 'probe_root_cold_buffer_fluid_T_K', NaN)];
            plot(1:numel(values), values, marker_style('-o', values), 'LineWidth', 1.5, ...
                'DisplayName', sprintf('Cycle %d', get_field(reports(idx), 'cycle_index', idx)));
        end
        hold off;
        set(gca, 'XTick', 1:numel(labels), 'XTickLabel', labels);
        xtickangle(25);
        ylabel('Fluid temperature (K)');
        title('Stage 4 fixed-port sequence with valve-side and CHEX probes');
        legend('Location', 'best');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'stage4_ordered_fluid_path_temperatures.png');

        c = [cooldown_reports.cycle_index];
        fig = make_figure();
        hold on;
        plot(c, report_vector(cooldown_reports, 'cold_hx_inlet_fluid_temp_out', 'probe_chip_pipe_port_conn2_v6_sma_side_T_K'), marker_style('-o', c), ...
            'LineWidth', 1.5, 'DisplayName', 'CHEX inlet / V6 side');
        plot(c, report_vector(cooldown_reports, 'cold_hx_outlet_fluid_temp_out', 'probe_chip_to_cold_junction_T_K'), marker_style('-s', c), ...
            'LineWidth', 1.5, 'DisplayName', 'CHEX outlet / cold-return boundary');
        plot(c, report_vector(cooldown_reports, 'chip_fluid_endpoint_delta_K', 'chip_fluid_temperature_gain_K'), marker_style('-^', c), ...
            'LineWidth', 1.5, 'DisplayName', 'Endpoint out - in (same time)');
        hold off;
        xlabel('Cycle');
        ylabel('Temperature or endpoint \DeltaT (K)');
        title('Stage 4 CHEX-side fluid endpoint probes');
        legend('Location', 'best');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_stage4_chex_fluid_inlet_outlet_gain.png');

        fig = make_figure();
        hold on;
        plot(c, [cooldown_reports.cold_sink_temp_in], marker_style('-o', c), 'LineWidth', 1.5, 'DisplayName', 'Cold sink internal in');
        plot(c, [cooldown_reports.cold_sink_temp_out], marker_style('-s', c), 'LineWidth', 1.5, 'DisplayName', 'Cold sink internal out');
        plot(c, [cooldown_reports.cold_sink_temp_out] - [cooldown_reports.cold_sink_temp_in], marker_style('-^', c), ...
            'LineWidth', 1.5, 'DisplayName', 'Cold sink internal \DeltaT');
        hold off;
        xlabel('Cycle');
        ylabel('Temperature or \DeltaT (K)');
        title('Stage 4 cold-sink internal response');
        legend('Location', 'best');
        grid on;
        plot_info = save_plot(plot_info, fig, figures_dir, 'cycle_stage4_cold_sink_internal_response.png');
    end
end

function plot_info = plot_energy_audit_summary(plot_info, cycle_results, figures_dir)
    exchange_reports = [collect_stage_reports(cycle_results, 'hold_exchange'), ...
        collect_stage_reports(cycle_results, 'cooldown_exchange')];
    if isempty(exchange_reports)
        return;
    end
    labels = cell(1, numel(exchange_reports));
    values = nan(numel(exchange_reports), 5);
    for idx = 1:numel(exchange_reports)
        labels{idx} = sprintf('C%d-%s', exchange_reports(idx).cycle_index, short_stage_name(exchange_reports(idx).stage_name));
        values(idx, :) = [ ...
            get_field(exchange_reports(idx), 'sma_101_delta_energy_J', NaN), ...
            get_field(exchange_reports(idx), 'hot_sink_delta_energy_J', NaN), ...
            get_field(exchange_reports(idx), 'cold_sink_delta_energy_J', NaN), ...
            get_field(exchange_reports(idx), 'cold_load_delta_energy_J', ...
                get_field(exchange_reports(idx), 'chip_delta_energy_J', NaN)), ...
            get_field(exchange_reports(idx), 'energy_residual_J', NaN)];
    end
    if numel(exchange_reports) > 60
        plot_info = plot_energy_audit_long_summary(plot_info, exchange_reports, values, figures_dir);
        return;
    end
    fig = make_figure();
    bar(values);
    set(gca, 'XTick', 1:numel(labels), 'XTickLabel', labels);
    xtickangle(35);
    ylabel('Energy term (J)');
    title('Exchange-stage energy audit');
    legend({'SMA 101 \DeltaE', 'Hot sink \DeltaE', 'Cold sink \DeltaE', 'Cold load \DeltaE', 'Residual'}, ...
        'Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'exchange_energy_audit_bars.png');

    fig = make_figure();
    bar([exchange_reports.compression_delta_energy_J]);
    set(gca, 'XTick', 1:numel(labels), 'XTickLabel', labels);
    xtickangle(35);
    ylabel('E_{51 compressed} - E_{101 out} (J)');
    title('101-to-51 compression energy difference');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'exchange_compression_energy_difference.png');
end

function plot_info = plot_energy_audit_long_summary(plot_info, exchange_reports, values, figures_dir)
    cycle_index = [exchange_reports.cycle_index];
    is_hold = strcmp({exchange_reports.stage_name}, 'hold_exchange');
    is_cooldown = strcmp({exchange_reports.stage_name}, 'cooldown_exchange');

    fig = make_figure();
    hold on;
    plot(cycle_index(is_hold), values(is_hold, 5), marker_style('-o', cycle_index(is_hold)), ...
        'LineWidth', 1.5, 'DisplayName', 'Stage 2 residual');
    plot(cycle_index(is_cooldown), values(is_cooldown, 5), marker_style('-s', cycle_index(is_cooldown)), ...
        'LineWidth', 1.5, 'DisplayName', 'Stage 4 residual');
    hold off;
    xlabel('Cycle');
    ylabel('Energy residual (J)');
    title('Exchange energy residual trend for long cycle run');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'exchange_energy_residual_trend.png');

    compression_delta = [exchange_reports.compression_delta_energy_J];
    fig = make_figure();
    hold on;
    plot(cycle_index(is_hold), compression_delta(is_hold), marker_style('-o', cycle_index(is_hold)), ...
        'LineWidth', 1.5, 'DisplayName', 'Stage 2 compression');
    plot(cycle_index(is_cooldown), compression_delta(is_cooldown), marker_style('-s', cycle_index(is_cooldown)), ...
        'LineWidth', 1.5, 'DisplayName', 'Stage 4 compression');
    hold off;
    xlabel('Cycle');
    ylabel('E_{51 compressed} - E_{101 out} (J)');
    title('101-to-51 compression energy difference trend for long cycle run');
    legend('Location', 'best');
    grid on;
    plot_info = save_plot(plot_info, fig, figures_dir, 'exchange_compression_energy_difference_trend.png');
end

function mechanics = reconstruct_checkpoint_mechanics(checkpoint_path)
    try
        state_std = GlobalXi_Checkpoint_To_Simulink_State(checkpoint_path);
        Y = state_std.Y(:);
        grid = state_std.grid;
        params = state_std.params;
        N = state_std.N;
        u = Y(1:N);
        w = Y(N + (1:N));
        T = Y(2 * N + (1:N));
        xi = Y(3 * N + (1:N));
        [eps_r, eps_theta] = membrane_strains(u, w, grid);
        eps_eq = sqrt(max(eps_r .^ 2 - eps_r .* eps_theta + eps_theta .^ 2, 0));

        sigma = zeros(3, N);
        eps_tr = zeros(N, 3);
        if isfield(state_std.state, 'eps_tr') && ~isempty(state_std.state.eps_tr)
            eps_tr = state_std.state.eps_tr;
        end
        for i = 1:N
            props = SMA_LocalKinetics('update_properties', xi(i), params);
            eps_i = [eps_r(i); eps_theta(i); 0.0];
            eps_tr_i = eps_tr(i, :).';
            eps_e = eps_i - eps_tr_i - props.alpha_vec * (T(i) - params.Tr);
            sigma(:, i) = props.C_mat * eps_e;
        end
        sigma_eq = sqrt(max(sigma(1, :).^2 - sigma(1, :) .* sigma(2, :) + sigma(2, :).^2 + 3.0 * sigma(3, :).^2, 0.0));

        mechanics = struct( ...
            'r_mm', 1.0e3 * grid.r(:), ...
            'eps_r', eps_r(:), ...
            'eps_theta', eps_theta(:), ...
            'eps_eq', eps_eq(:), ...
            'sigma_r_MPa', sigma(1, :)' / 1.0e6, ...
            'sigma_theta_MPa', sigma(2, :)' / 1.0e6, ...
            'sigma_eq_MPa', sigma_eq(:) / 1.0e6);
    catch
        mechanics = struct();
    end
end

function [eps_r, eps_theta] = membrane_strains(u, w, grid)
    D1 = grid.D1;
    w_r = D1 * w;
    w_r(1) = 0.0;
    eps_r = D1 * u + 0.5 * w_r .^ 2;
    eps_theta = zeros(size(u));
    eps_theta(1) = eps_r(1);
    eps_theta(2:end) = u(2:end) ./ grid.r(2:end);
end

function [T_matrix, xi_matrix, r_mm, row_labels] = build_profile_matrices(cycle_results)
    stage_names = {'load_adiabatic', 'hold_exchange', 'unload_adiabatic', 'cooldown_exchange'};
    short_names = {'L', 'H', 'U', 'C'};
    T_matrix = [];
    xi_matrix = [];
    r_mm = [];
    row_labels = {};
    for c = 1:numel(cycle_results)
        cycle_index = get_field(cycle_results(c), 'cycle_index', c);
        for s = 1:numel(stage_names)
            report = get_stage_report(cycle_results(c).stage_reports, stage_names{s});
            profile = get_field(report, 'profile', struct());
            if has_profile(profile, 'T_K') && isfield(profile, 'xi')
                if isempty(r_mm)
                    r_mm = profile.r_mm(:).';
                end
                T_matrix(end + 1, :) = profile.T_K(:).'; %#ok<AGROW>
                xi_matrix(end + 1, :) = profile.xi(:).'; %#ok<AGROW>
                row_labels{end + 1} = sprintf('C%d-%s', cycle_index, short_names{s}); %#ok<AGROW>
            end
        end
    end
end

function decorate_stage_axis(s)
    y_limits = ylim;
    cooldown_times = s.time_s(s.stage_index == 4);
    line_indices = sparse_tick_indices(numel(cooldown_times), 40);
    for idx = line_indices
        xline(cooldown_times(idx), ':', 'Color', [0.65 0.65 0.65], 'HandleVisibility', 'off');
    end
    ylim(y_limits);
end

function label_cold_load_exchange_points(s, y_values)
    y_values = y_values(:).';
    if isempty(y_values) || all(~isfinite(y_values))
        return;
    end
    y_range = max(y_values) - min(y_values);
    if ~isfinite(y_range) || y_range == 0
        y_range = 1;
    end
    label_indices = 1:numel(s.time_s);
    if numel(label_indices) > 30
        label_indices = unique([1, sparse_tick_indices(numel(s.time_s), 18), numel(s.time_s)]);
    end
    for idx = label_indices
        if s.stage_index(idx) == 0
            label = 'C0 Initial';
        elseif s.stage_index(idx) == 2
            label = sprintf('C%d-S2', s.cycle_index(idx));
        elseif s.stage_index(idx) == 4
            label = sprintf('C%d-S4', s.cycle_index(idx));
        else
            continue;
        end
        text(s.time_s(idx), y_values(idx) + 0.025 * y_range, label, ...
            'FontSize', 8, 'HorizontalAlignment', 'center', 'HandleVisibility', 'off');
    end
end

function selected = select_representative_cycle_results(cycle_results, config)
    cycle_results = reshape(cycle_results, 1, []);
    if isempty(cycle_results)
        selected = cycle_results;
        return;
    end
    max_cycles = get_field(config, 'max_profile_plot_cycles', 12);
    if numel(cycle_results) <= max_cycles
        selected = cycle_results;
        return;
    end

    cycle_indices = arrayfun(@(item, idx) get_field(item, 'cycle_index', idx), ...
        cycle_results, 1:numel(cycle_results));
    sample_positions = unique(round(linspace(1, numel(cycle_results), max_cycles)));
    selected = cycle_results(sample_positions);
    selected_indices = cycle_indices(sample_positions);
    fprintf('Plot_GlobalXi_Simulink_Cycle_Results: long run detected; profile and 101 plots use representative cycles: %s\n', ...
        mat2str(selected_indices));
end

function selected = select_representative_stage_reports(reports, max_reports)
    reports = reshape(reports, 1, []);
    if isempty(reports) || numel(reports) <= max_reports
        selected = reports;
        return;
    end
    sample_positions = unique(round(linspace(1, numel(reports), max_reports)));
    selected = reports(sample_positions);
end

function style_out = marker_style(style_in, x_values)
    if numel(x_values) <= 80
        style_out = style_in;
        return;
    end
    style_out = regexprep(style_in, '[\+\*\.xosd\^v<>ph]', '');
    if isempty(style_out)
        style_out = '-';
    end
end

function indices = sparse_tick_indices(n, max_ticks)
    if n <= 0
        indices = [];
    elseif n <= max_ticks
        indices = 1:n;
    else
        indices = unique(round(linspace(1, n, max_ticks)));
    end
end

function set_sparse_xticks(ax, x_values, labels, max_ticks)
    tick_indices = sparse_tick_indices(numel(x_values), max_ticks);
    set(ax, 'XTick', x_values(tick_indices), 'XTickLabel', labels(tick_indices));
    xtickangle(ax, 35);
end

function initial_sma_T = get_initial_sma_temperature(config)
    solver_options = get_field(config, 'solver_options', struct());
    exchange_options = get_field(config, 'exchange_options', struct());
    initial_sma_T = get_field(solver_options, 'Tr', get_field(exchange_options, 'ambient_T_init', 293));
end

function sx = subset_stage_series(s, mask)
    sx = s;
    fields = fieldnames(s);
    for idx = 1:numel(fields)
        name = fields{idx};
        value = s.(name);
        if iscell(value) && numel(value) == numel(mask)
            sx.(name) = value(mask);
        elseif isnumeric(value) && numel(value) == numel(mask)
            sx.(name) = value(mask);
        elseif islogical(value) && numel(value) == numel(mask)
            sx.(name) = value(mask);
        end
    end
end

function cleanup_known_plot_outputs(figures_dir)
    patterns = { ...
        'time_stage_end_sma_temperature.png', ...
        'time_stage_end_hot_cold_chip_temperature_frozen_overview.png', ...
        'time_stage_end_hot_cold_chip_internal_temperature_change.png', ...
        'time_stage_end_hot_cold_cold_load_temperature_overview.png', ...
        'time_stage_end_hot_cold_cold_load_temperature_change.png', ...
        'time_hot_cold_sink_temperature_zoom.png', ...
        'time_chip_temperature_absolute.png', ...
        'time_chip_temperature_change.png', ...
        'time_cold_load_temperature_absolute.png', ...
        'time_cold_load_temperature_change.png', ...
        'time_stage_end_martensite_fraction.png', ...
        'time_stage_end_deflection_pressure.png', ...
        'cycle_stage_end_avg_sma_temperature.png', ...
        'cycle_cooldown_end_thermal_objects.png', ...
        'cycle_chip_temperature_exchange_end_trend.png', ...
        'cycle_chip_temperature_stage2_stage4_auxiliary.png', ...
        'cycle_cold_load_temperature_exchange_end_trend.png', ...
        'cycle_final_xi_peak_deflection.png', ...
        'cycle_exchange_controls_and_chip_drop.png', ...
        'cycle_exchange_controls_and_cold_load_drop.png', ...
        'cycle1_radial_temperature_profiles.png', ...
        'cycle1_load_end_deflection.png', ...
        'cycle1_load_end_xi.png', ...
        'cycle1_load_end_strain_profile.png', ...
        'cycle1_load_end_stress_profile.png', ...
        'cycle1_load_end_stress_strain_map.png', ...
        'heatmap_stage_end_radial_temperature.png', ...
        'heatmap_stage_end_radial_xi.png', ...
        'cooldown_end_temperature_profiles_by_cycle.png', ...
        'cycle*_hold_exchange_Tx101_directional_profile.png', ...
        'cycle*_cooldown_exchange_Tx101_directional_profile.png', ...
        'cycle_hold_exchange_fluid_probe_temperatures.png', ...
        'cycle_cooldown_exchange_fluid_probe_temperatures.png', ...
        'cycle_stage4_probe_temperature_jumps.png', ...
        'stage2_ordered_fluid_path_temperatures.png', ...
        'stage4_ordered_fluid_path_temperatures.png', ...
        'cycle_stage2_hot_sink_internal_response.png', ...
        'cycle_stage4_cold_sink_internal_response.png', ...
        'cycle_stage4_chip_fluid_inlet_outlet_gain.png', ...
        'cycle_stage4_chex_fluid_inlet_outlet_gain.png', ...
        'exchange_energy_audit_bars.png', ...
        'exchange_compression_energy_difference.png', ...
        'exchange_energy_residual_trend.png', ...
        'exchange_compression_energy_difference_trend.png', ...
        'hot_cold_sink_temperature_envelope.png', ...
        'hot_cold_sink_temperature_envelope.pdf', ...
        'hot_cold_temperature_span.png', ...
        'hot_cold_temperature_span.pdf', ...
        'zhou_style_active_outlet_temperature.png', ...
        'zhou_style_active_outlet_temperature.pdf', ...
        'zhou_style_active_inlet_fluid_temperature.png', ...
        'zhou_style_active_inlet_fluid_temperature.pdf', ...
        'zhou_style_sink_outlet_temperature.png', ...
        'zhou_style_sink_outlet_temperature.pdf', ...
        'stage2_stage4_ordered_flow_path_temperature.png', ...
        'stage2_stage4_ordered_flow_path_temperature.pdf'};
    for idx = 1:numel(patterns)
        files = dir(fullfile(figures_dir, patterns{idx}));
        for file_idx = 1:numel(files)
            delete(fullfile(files(file_idx).folder, files(file_idx).name));
        end
    end
end

function cleanup_sweep_plot_outputs(figures_dir)
    patterns = { ...
        'sweep_chip_power_chip_temperature_points.png', ...
        'sweep_chip_power_chip_temperature_deltas.png', ...
        'sweep_chip_power_stage4_fluid_probe_temperatures.png', ...
        'sweep_chip_power_sink_internal_temperature_deltas.png', ...
        'sweep_chip_power_stage4_chip_response.png', ...
        'sweep_load_power_cold_load_temperature_points.png', ...
        'sweep_load_power_cold_load_temperature_deltas.png', ...
        'sweep_load_power_stage4_fluid_probe_temperatures.png', ...
        'sweep_load_power_sink_internal_temperature_deltas.png', ...
        'sweep_load_power_stage4_cold_load_response.png'};
    for idx = 1:numel(patterns)
        files = dir(fullfile(figures_dir, patterns{idx}));
        for file_idx = 1:numel(files)
            delete(fullfile(files(file_idx).folder, files(file_idx).name));
        end
    end
end

function fig = make_figure()
    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100, 100, 980, 640]);
end

function plot_info = save_plot(plot_info, fig, figures_dir, file_name)
    path_value = fullfile(figures_dir, file_name);
    apply_white_theme(fig);
    exportgraphics(fig, path_value, 'Resolution', 220);
    close(fig);
    plot_info.generated_files{end + 1} = path_value;
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

function reports_out = collect_stage_reports(cycle_results, stage_name)
    reports_out = struct([]);
    for c = 1:numel(cycle_results)
        report = get_stage_report(cycle_results(c).stage_reports, stage_name);
        if ~isempty(fieldnames(report))
            if isempty(reports_out)
                reports_out = report;
            else
                reports_out(end + 1) = report; %#ok<AGROW>
            end
        end
    end
end

function checkpoint = load_exchange_checkpoint(report)
    checkpoint = struct();
    checkpoint_path = get_field(report, 'simulink_checkpoint_path', '');
    if isempty(checkpoint_path) || ~exist(checkpoint_path, 'file')
        checkpoint_path = get_field(report, 'checkpoint_path', '');
    end
    if isempty(checkpoint_path) || ~exist(checkpoint_path, 'file')
        return;
    end
    try
        checkpoint = load(checkpoint_path);
    catch
        checkpoint = struct();
    end
end

function short_name = short_stage_name(stage_name)
    switch char(string(stage_name))
        case 'hold_exchange'
            short_name = 'H';
        case 'cooldown_exchange'
            short_name = 'C';
        otherwise
            short_name = char(string(stage_name));
    end
end

function tf = has_profile(profile, field_name)
    tf = isstruct(profile) && isfield(profile, 'r_mm') && isfield(profile, field_name) && ...
        ~isempty(profile.r_mm) && ~isempty(profile.(field_name));
end

function value = get_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end

function values = report_vector(reports, primary_field, fallback_field)
    values = nan(1, numel(reports));
    for idx = 1:numel(reports)
        value = get_field(reports(idx), primary_field, NaN);
        if ~isfinite_scalar(value) && nargin >= 3 && ~isempty(fallback_field)
            value = get_field(reports(idx), fallback_field, NaN);
        end
        values(idx) = scalar_or_nan(value);
    end
end

function tf = isfinite_scalar(value)
    tf = isnumeric(value) && isscalar(value) && isfinite(value);
end

function value_out = scalar_or_nan(value_in)
    if isnumeric(value_in) && isscalar(value_in)
        value_out = value_in;
    else
        value_out = NaN;
    end
end
