function outputs = Plot_HeatDriveECC_SCI_FigureSet(result_input, output_dir)
% Create a compact, publication-oriented figure set from one validated run.

    result = load_result(result_input);
    result.summary = Summarize_HeatDriveECC_EighthRound_Output( ...
        result.physical, result.options);
    if nargin < 2 || isempty(output_dir)
        output_dir = fullfile(result.output_dir, 'figures_sci');
    end
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end

    outputs = struct();
    outputs.schema = 'heatdrive_ecc_sci_figure_set_v1';
    outputs.source_result = result.output_mat;
    outputs.output_dir = output_dir;
    outputs.files = cell(5, 2);
    outputs.files(1, :) = export_pair( ...
        figure_cycle_mechanism(result), output_dir, ...
        'Fig01_last_cycle_mechanism');
    outputs.files(2, :) = export_pair( ...
        figure_axial_fields(result), output_dir, ...
        'Fig02_last_cycle_axial_fields');
    outputs.files(3, :) = export_pair( ...
        figure_convergence(result), output_dir, ...
        'Fig03_periodic_convergence');
    outputs.files(4, :) = export_pair( ...
        figure_control_energy(result), output_dir, ...
        'Fig04_control_and_energy');
    outputs.files(5, :) = export_pair( ...
        figure_literature_boundary(result), output_dir, ...
        'Fig05_table4_boundary_audit');
    outputs.manifest = fullfile(output_dir, 'figure_manifest.txt');
    write_manifest(outputs, result);
end

function result = load_result(value)
    if isstruct(value) && isfield(value, 'physical')
        result = value;
        return;
    end
    path = char(string(value));
    loaded = load(path, 'physical', 'options', 'summary', 'provenance');
    required = {'physical','options','provenance'};
    if ~all(isfield(loaded, required))
        error('HeatDriveECC:SCIFigureInvalidResult', ...
            'Result MAT is missing physical/options/provenance.');
    end
    result = loaded;
    result.output_mat = path;
    result.output_dir = fileparts(path);
end

function fig = figure_cycle_mechanism(result)
    p = result.physical;
    o = result.options;
    [idx, phase_s] = last_cycle_index(p, o);
    c = palette();
    fig = sci_figure(7.2, 6.1);
    tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', ...
        'Padding', 'compact');

    ax = nexttile(tl);
    plot(ax, phase_s, mean(p.SMA_T_21_K(idx, :), 2), ...
        'Color', c.sma, 'LineWidth', 1.35);
    hold(ax, 'on');
    plot(ax, phase_s, mean(p.SE_T_21_K(idx, :), 2), ...
        'Color', c.se, 'LineWidth', 1.35);
    plot(ax, phase_s, p.HHEX_T_K(idx), '--', ...
        'Color', c.hot, 'LineWidth', 1.1);
    plot(ax, phase_s, p.CHEX_T_K(idx), '--', ...
        'Color', c.cold, 'LineWidth', 1.1);
    stage_guides(ax, o);
    ylabel(ax, 'Temperature (K)');
    legend(ax, {'SMA mean','SE mean','HHEX','CHEX'}, ...
        'Location', 'eastoutside', 'Box', 'off');
    panel_label(ax, 'a');

    ax = nexttile(tl);
    plot(ax, phase_s, mean(p.xM_SMA_21(idx, :), 2), ...
        'Color', c.sma, 'LineWidth', 1.35);
    hold(ax, 'on');
    plot(ax, phase_s, mean(p.xM_SE_21(idx, :), 2), ...
        'Color', c.se, 'LineWidth', 1.35);
    stage_guides(ax, o);
    ylim(ax, [-0.03 1.03]);
    ylabel(ax, 'Martensite fraction');
    legend(ax, {'SMA','SE'}, 'Location', 'eastoutside', 'Box', 'off');
    panel_label(ax, 'b');

    ax = nexttile(tl);
    yyaxis(ax, 'left');
    h_sma = plot(ax, phase_s, abs(p.mdot_SMA_kgps(idx)) * 1e3, ...
        'Color', c.sma, 'LineWidth', 1.1);
    hold(ax, 'on');
    ylabel(ax, 'SMA mass flow (g s^{-1})');
    ylim(ax, [0 60]);
    ax.YAxis(1).Color = c.sma;
    yyaxis(ax, 'right');
    h_s2 = plot(ax, phase_s, p.mdot_SE_stage2_in_kgps(idx) * 1e3, ...
        'Color', c.se, 'LineWidth', 1.1);
    hold(ax, 'on');
    h_s4 = plot(ax, phase_s, p.mdot_SE_stage4_in_kgps(idx) * 1e3, '--', ...
        'Color', c.cold, 'LineWidth', 1.1);
    yline(ax, 3.2, ':', 'Color', [0.35 0.35 0.35], ...
        'HandleVisibility', 'off');
    ylabel(ax, 'SE route mass flow (g s^{-1})');
    ylim(ax, [0 4.2]);
    ax.YAxis(2).Color = c.neutral;
    stage_guides(ax, o);
    xlabel(ax, 'Cycle phase (s)');
    legend(ax, [h_sma h_s2 h_s4], {'SMA','SE rejection','SE cooling'}, ...
        'Location', 'eastoutside', 'Box', 'off');
    panel_label(ax, 'c');
    title(tl, sprintf('Cycle %d: coupled thermal, phase, and flow response', ...
        o.cycle_count), 'FontWeight', 'normal', 'Color', 'k');
end

function fig = figure_axial_fields(result)
    p = result.physical;
    o = result.options;
    [idx, phase_s] = last_cycle_index(p, o);
    axial = linspace(0, 1, o.node_count);
    fig = sci_figure(7.2, 5.6);
    tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', ...
        'Padding', 'compact');
    field_panel(nexttile(tl), axial, phase_s, p.SMA_T_21_K(idx, :), ...
        'SMA temperature (K)', 'turbo', 'a');
    field_panel(nexttile(tl), axial, phase_s, p.SE_T_21_K(idx, :), ...
        'SE temperature (K)', 'turbo', 'b');
    field_panel(nexttile(tl), axial, phase_s, p.xM_SMA_21(idx, :), ...
        'SMA martensite fraction', 'parula', 'c');
    field_panel(nexttile(tl), axial, phase_s, p.xM_SE_21(idx, :), ...
        'SE martensite fraction', 'parula', 'd');
    title(tl, sprintf('Cycle %d axial fields (21-node physical model)', ...
        o.cycle_count), 'FontWeight', 'normal', 'Color', 'k');
end

function fig = figure_convergence(result)
    p = result.physical;
    o = result.options;
    s = result.summary;
    cycles = s.cycle(:);
    n = numel(cycles);
    cycle_id = (1:n).';
    endpoint = [[cycles.SMA_end_K].', [cycles.SE_end_K].', ...
        [cycles.HHEX_end_K].', [cycles.CHEX_end_K].'];
    endpoint_drift = [NaN; max(abs(diff(endpoint, 1, 1)), [], 2)];
    [eq9_K, scp_Wpg] = cycle_performance(p, o);
    c = palette();

    fig = sci_figure(7.2, 5.9);
    tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', ...
        'Padding', 'compact');
    ax = nexttile(tl);
    plot(ax, cycle_id, endpoint(:, 1), 'Color', c.sma, 'LineWidth', 1.1);
    hold(ax, 'on');
    plot(ax, cycle_id, endpoint(:, 2), 'Color', c.se, 'LineWidth', 1.1);
    plot(ax, cycle_id, endpoint(:, 3), '--', 'Color', c.hot, 'LineWidth', 1.0);
    plot(ax, cycle_id, endpoint(:, 4), '--', 'Color', c.cold, 'LineWidth', 1.0);
    ylabel(ax, 'Cycle-end temperature (K)');
    legend(ax, {'SMA','SE','HHEX','CHEX'}, 'Location', 'best', 'Box', 'off');
    panel_label(ax, 'a');

    ax = nexttile(tl);
    semilogy(ax, cycle_id, max(endpoint_drift, eps), ...
        'Color', c.neutral, 'LineWidth', 1.2);
    hold(ax, 'on');
    yline(ax, s.performance.periodic_endpoint_limit_K, '--', ...
        'Color', c.limit, 'LineWidth', 1.0);
    ylabel(ax, 'Endpoint L_{\infty} drift (K)');
    panel_label(ax, 'b');

    ax = nexttile(tl);
    plot(ax, cycle_id, eq9_K, 'Color', c.hot, 'LineWidth', 1.2);
    hold(ax, 'on');
    yline(ax, 26.2, '--', 'Color', c.limit, 'LineWidth', 1.0);
    xlabel(ax, 'Cycle');
    ylabel(ax, 'Eq. 9 lift (K)');
    legend(ax, {'Model','Qian Table 4 maximum lift'}, ...
        'Location', 'best', 'Box', 'off');
    panel_label(ax, 'c');

    ax = nexttile(tl);
    plot(ax, cycle_id, scp_Wpg, 'Color', c.cold, 'LineWidth', 1.2);
    hold(ax, 'on');
    yline(ax, 0, ':', 'Color', c.neutral, 'HandleVisibility', 'off');
    xlabel(ax, 'Cycle');
    ylabel(ax, 'Eq. 10 SCP (W g^{-1})');
    panel_label(ax, 'd');
    title(tl, 'Cold-start to periodic-state convergence', ...
        'FontWeight', 'normal', 'Color', 'k');
end

function fig = figure_control_energy(result)
    p = result.physical;
    o = result.options;
    s = result.summary;
    [idx, phase_s] = last_cycle_index(p, o);
    c = palette();
    fig = sci_figure(7.2, 5.9);
    tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', ...
        'Padding', 'compact');

    ax = nexttile(tl);
    plot(ax, phase_s, p.pressure_command_SMA_MPa(idx), ...
        'Color', c.sma, 'LineWidth', 1.1);
    hold(ax, 'on');
    plot(ax, phase_s, p.pressure_command_SE_MPa(idx), ...
        'Color', c.se, 'LineWidth', 1.1);
    stage_guides(ax, o);
    ylabel(ax, 'Pressure command (MPa)');
    legend(ax, {'SMA','SE'}, 'Location', 'best', 'Box', 'off');
    panel_label(ax, 'a');

    ax = nexttile(tl);
    plot(ax, phase_s, p.pump_power_SMA_W(idx), ...
        'Color', c.sma, 'LineWidth', 1.1);
    hold(ax, 'on');
    plot(ax, phase_s, p.pump_power_SE_W(idx), ...
        'Color', c.se, 'LineWidth', 1.1);
    stage_guides(ax, o);
    ylabel(ax, 'Hydraulic power (W)');
    legend(ax, {'SMA','SE'}, 'Location', 'best', 'Box', 'off');
    panel_label(ax, 'b');

    ax = nexttile(tl);
    sample_window = max(1, round(0.02 / o.simulation.fixed_step_s));
    q_sma = smoothdata(sum(p.Q_SMA_constitutive_21_W(idx, :), 2), ...
        'movmean', sample_window);
    q_se = smoothdata(sum(p.Q_SE_constitutive_21_W(idx, :), 2), ...
        'movmean', sample_window);
    plot(ax, phase_s, q_sma, ...
        'Color', c.sma, 'LineWidth', 1.0);
    hold(ax, 'on');
    plot(ax, phase_s, q_se, ...
        'Color', c.se, 'LineWidth', 1.0);
    stage_guides(ax, o);
    xlabel(ax, 'Cycle phase (s)');
    ylabel(ax, 'Constitutive heat rate (W)');
    legend(ax, {'SMA','SE'}, 'Location', 'best', 'Box', 'off');
    panel_label(ax, 'c');

    last = s.cycle(end);
    values = [last.Q_pipe_to_SMA_J, last.Q_constitutive_SMA_J, ...
        last.delta_U_sensible_SMA_J, last.energy_residual_SMA_J; ...
        last.Q_pipe_to_SE_J, last.Q_constitutive_SE_J, ...
        last.delta_U_sensible_SE_J, last.energy_residual_SE_J];
    ax = nexttile(tl);
    bar(ax, values, 'grouped');
    xticks(ax, 1:2);
    xticklabels(ax, {'SMA','SE'});
    ylabel(ax, 'Cycle energy (J)');
    legend(ax, {'Pipe heat','Constitutive','\DeltaU','Residual'}, ...
        'Location', 'southoutside', 'Orientation', 'horizontal', ...
        'NumColumns', 2, 'Box', 'off');
    panel_label(ax, 'd');
    title(tl, sprintf('Cycle %d control effort and energy closure', ...
        o.cycle_count), 'FontWeight', 'normal', 'Color', 'k');
end

function fig = figure_literature_boundary(result)
    perf = result.summary.performance;
    model_lift = [perf.temperature_lift_eq9_K, 34.2120534519357];
    model_scp = [perf.specific_cooling_eq10_W_per_g, 0.210892552652645];
    qian_lift = [0, 26.2];
    qian_scp = [0.64, 0];
    slope = diff(model_scp) / diff(model_lift);
    extrapolated_root = model_lift(1) - model_scp(1) / slope;
    c = palette();
    fig = sci_figure(7.2, 4.5);
    ax = axes(fig);
    plot(ax, qian_lift, qian_scp, '-', 'Color', c.neutral, ...
        'LineWidth', 1.4);
    hold(ax, 'on');
    scatter(ax, qian_lift, qian_scp, 55, 'o', ...
        'MarkerEdgeColor', c.neutral, 'MarkerFaceColor', 'w', ...
        'LineWidth', 1.2);
    plot(ax, [model_lift extrapolated_root], [model_scp 0], '--', ...
        'Color', c.model, 'LineWidth', 1.2);
    scatter(ax, model_lift(1), model_scp(1), 65, 'o', ...
        'MarkerEdgeColor', c.model, 'MarkerFaceColor', c.model, ...
        'LineWidth', 1.1);
    scatter(ax, model_lift(2), model_scp(2), 75, 'x', ...
        'MarkerEdgeColor', c.fail, 'LineWidth', 1.8);
    scatter(ax, extrapolated_root, 0, 55, '^', ...
        'MarkerEdgeColor', c.model, 'MarkerFaceColor', 'w', ...
        'LineWidth', 1.1);
    xlabel(ax, 'Temperature lift, Eq. 9 (K)');
    ylabel(ax, 'Specific cooling power, Eq. 10 (W g^{-1})');
    lgd = legend(ax, {'Qian Table 4 endpoint connection', ...
        'Qian Table 4 endpoints','Two-point model extrapolation', ...
        'Periodic model point, T_c = 276.95 K', ...
        'Rejected mechanism point, T_c = 270 K', ...
        'Extrapolated model zero'}, 'Location', 'northeast', 'Box', 'off');
    lgd.FontSize = 7.2;
    text(ax, model_lift(1) + 0.5, model_scp(1) + 0.025, ...
        sprintf('Periodic; SCP = %.3f', model_scp(1)), 'FontSize', 8);
    text(ax, model_lift(2) + 0.5, model_scp(2) - 0.035, ...
        'SE transformation incomplete', 'Color', c.fail, 'FontSize', 8);
    text(ax, extrapolated_root - 1.0, 0.045, ...
        sprintf('Linear diagnostic root: %.1f K', extrapolated_root), ...
        'Color', c.model, 'FontSize', 8, 'HorizontalAlignment', 'right');
    title(ax, 'Table 4 boundary audit: periodic point versus invalid root search', ...
        'FontWeight', 'normal');
    xlim(ax, [0 max(48, extrapolated_root + 2)]);
    ylim(ax, [-0.03 0.70]);
end

function [eq9_K, scp_Wpg] = cycle_performance(p, o)
    n = o.cycle_count;
    eq9_K = NaN(n, 1);
    scp_Wpg = NaN(n, 1);
    t = p.time_s(:);
    hot_out = p.probes.hot_hx_inlet_fluid_temp_out(:);
    cold_out = p.probes.cold_hx_inlet_fluid_temp_out(:);
    cold_in = p.probes.cold_hx_outlet_fluid_temp_out(:);
    route_flow = abs(p.mdot_SE_stage4_in_kgps(:)) .* ...
        double(p.stage_id(:) == 4);
    cooling_W = route_flow .* o.system.cp_fluid_J_per_kgK .* ...
        (cold_out - cold_in);
    mass_g = o.equilibrium.m_r_kg * 1e3;
    for cycle_idx = 1:n
        t0 = (cycle_idx - 1) * o.schedule.tau_cycle_s;
        t1 = cycle_idx * o.schedule.tau_cycle_s;
        idx = t >= t0 & t <= t1;
        eq9_K(cycle_idx) = trapz(t(idx), hot_out(idx) - cold_out(idx)) / ...
            o.schedule.tau_cycle_s;
        scp_Wpg(cycle_idx) = trapz(t(idx), cooling_W(idx)) / ...
            o.schedule.tau_cycle_s / mass_g;
    end
end

function field_panel(ax, axial, phase_s, values, label, map_name, letter)
    imagesc(ax, axial, phase_s, values);
    axis(ax, 'xy');
    colormap(ax, map_name);
    colorbar(ax);
    xlabel(ax, 'Normalized axial coordinate');
    ylabel(ax, 'Cycle phase (s)');
    title(ax, label, 'FontWeight', 'normal');
    panel_label(ax, letter);
end

function [idx, phase_s] = last_cycle_index(p, o)
    idx = p.cycle_index(:) == o.cycle_count;
    phase_s = p.time_s(idx) - ...
        (o.cycle_count - 1) * o.schedule.tau_cycle_s;
end

function stage_guides(ax, o)
    hold(ax, 'on');
    starts = cumsum(o.schedule.stage_durations_s(1:end-1));
    for value = starts(:).'
        xline(ax, value, ':', 'Color', [0.72 0.72 0.72], ...
            'HandleVisibility', 'off');
    end
    xlim(ax, [0 o.schedule.tau_cycle_s]);
end

function panel_label(ax, letter)
    text(ax, 0.015, 0.96, ['(' letter ')'], 'Units', 'normalized', ...
        'FontWeight', 'bold', 'VerticalAlignment', 'top', 'Color', 'k');
end

function fig = sci_figure(width_in, height_in)
    fig = figure('Visible', 'off', 'Color', 'w', ...
        'Units', 'inches', 'Position', [0.5 0.5 width_in height_in], ...
        'PaperPositionMode', 'auto');
    set(fig, 'DefaultAxesFontName', 'Arial', ...
        'DefaultAxesFontSize', 8.5, 'DefaultAxesLineWidth', 0.75, ...
        'DefaultAxesTickDir', 'out', 'DefaultAxesBox', 'on', ...
        'DefaultLineLineWidth', 1.1, 'DefaultTextFontName', 'Arial');
end

function files = export_pair(fig, output_dir, base_name)
    apply_axes_style(fig);
    png_path = fullfile(output_dir, [base_name '.png']);
    pdf_path = fullfile(output_dir, [base_name '.pdf']);
    exportgraphics(fig, png_path, 'Resolution', 600, ...
        'BackgroundColor', 'white');
    exportgraphics(fig, pdf_path, 'ContentType', 'vector', ...
        'BackgroundColor', 'white');
    close(fig);
    files = {png_path, pdf_path};
end

function apply_axes_style(fig)
    axes_handles = findall(fig, 'Type', 'axes');
    for idx = 1:numel(axes_handles)
        axes_handles(idx).Color = 'w';
        axes_handles(idx).XColor = 'k';
        axes_handles(idx).YColor = 'k';
        axes_handles(idx).ZColor = 'k';
        axes_handles(idx).GridColor = [0.72 0.72 0.72];
        axes_handles(idx).MinorGridColor = [0.86 0.86 0.86];
        grid(axes_handles(idx), 'on');
        axes_handles(idx).GridAlpha = 0.12;
        axes_handles(idx).MinorGridAlpha = 0.07;
        axes_handles(idx).Layer = 'top';
        axes_handles(idx).Title.Color = 'k';
        axes_handles(idx).XLabel.Color = 'k';
        axes_handles(idx).YLabel.Color = 'k';
    end
    legends = findall(fig, 'Type', 'legend');
    for idx = 1:numel(legends)
        legends(idx).Color = 'w';
        legends(idx).TextColor = 'k';
        legends(idx).EdgeColor = 'none';
    end
    colorbars = findall(fig, 'Type', 'ColorBar');
    for idx = 1:numel(colorbars)
        colorbars(idx).Color = 'k';
        colorbars(idx).FontName = 'Arial';
        colorbars(idx).FontSize = 8;
    end
end

function c = palette()
    c = struct( ...
        'sma', [0.00 0.45 0.70], ...
        'se', [0.84 0.37 0.00], ...
        'hot', [0.80 0.20 0.20], ...
        'cold', [0.20 0.55 0.75], ...
        'neutral', [0.25 0.25 0.25], ...
        'limit', [0.45 0.45 0.45], ...
        'model', [0.00 0.62 0.45], ...
        'fail', [0.80 0.20 0.20]);
end

function write_manifest(outputs, result)
    fid = fopen(outputs.manifest, 'w', 'n', 'UTF-8');
    if fid < 0
        error('HeatDriveECC:SCIFigureManifestOpenFailed', ...
            'Cannot write %s.', outputs.manifest);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, 'schema=%s\n', outputs.schema);
    fprintf(fid, 'source_result=%s\n', outputs.source_result);
    fprintf(fid, 'cycle_count=%d\n', result.options.cycle_count);
    fprintf(fid, 'mechanism_boundary=validated_physical_simscape\n');
    fprintf(fid, 'periodic_steady_state=%d\n', ...
        result.summary.performance.periodic_steady_state);
    fprintf(fid, 'strict_table4_reproduction=%d\n', ...
        result.summary.quantitative_literature_reproduction_pass);
    for idx = 1:size(outputs.files, 1)
        fprintf(fid, 'figure_%02d_png=%s\n', idx, outputs.files{idx, 1});
        fprintf(fid, 'figure_%02d_pdf=%s\n', idx, outputs.files{idx, 2});
    end
    clear cleaner
end
