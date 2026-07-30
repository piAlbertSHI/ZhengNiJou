function figures = Plot_HeatDriveECC_EighthRound_Result(result, tag)
% Write standalone white-background plots from physical Simscape logs.

    if nargin < 2 || isempty(tag)
        tag = sprintf('%dcycle', result.options.cycle_count);
    end
    if ~isfield(result, 'physical') || ...
            ~strcmp(result.authority, 'physical_simscape_to_workspace_logs')
        error('Plot:EighthRound:NonPhysicalAuthority', ...
            'Plots require the physical Simscape result structure.');
    end
    out_dir = fullfile(result.output_dir, 'figures');
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    figures = {};
    figures{end + 1} = plot_mean_solid_temperatures(result, tag, out_dir);
    figures{end + 1} = plot_all_solid_nodes(result, 'SMA', tag, out_dir);
    figures{end + 1} = plot_all_solid_nodes(result, 'SE', tag, out_dir);
    figures{end + 1} = plot_heat_exchanger_temperatures(result, tag, out_dir);
    figures{end + 1} = plot_branch_temperatures(result, tag, out_dir);
    figures{end + 1} = plot_all_temperature_probes(result, tag, out_dir);
    figures{end + 1} = plot_phase_fraction(result, tag, out_dir);
    figures{end + 1} = plot_stress(result, tag, out_dir);
    figures{end + 1} = plot_mass_flows(result, tag, out_dir);
    figures{end + 1} = plot_constitutive_heat(result, tag, out_dir);
    figures{end + 1} = plot_pump_commands_and_power(result, tag, out_dir);
end

function path = plot_mean_solid_temperatures(result, tag, out_dir)
    p = result.physical;
    t = p.time_s;
    path = fullfile(out_dir, [tag '_01_SMA_SE_mean_temperature.png']);
    fig = new_figure();
    plot(t, mean(p.SMA_T_21_K, 2), 'LineWidth', 1.5);
    hold on;
    plot(t, mean(p.SE_T_21_K, 2), 'LineWidth', 1.5);
    yline(result.options.equilibrium.T_transform_complete_K, ...
        ':', 'SMA shifted Af');
    yline(result.options.system.T0_K, ':', 'HHEX');
    yline(result.options.system.Tc_K, ':', 'CHEX');
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('temperature (K)');
    legend({'SMA mean','SE mean','SMA shifted Af','HHEX','CHEX'}, ...
        'Location', 'best');
    title('Physical SMA and SE mean temperatures');
    export_and_close(fig, path);
end

function path = plot_all_solid_nodes(result, solid_name, tag, out_dir)
    p = result.physical;
    if strcmpi(solid_name, 'SMA')
        values = p.SMA_T_21_K;
        path = fullfile(out_dir, [tag '_02_SMA_all_21_node_temperatures.png']);
        title_text = 'Physical SMA temperatures: all 21 axial nodes';
    else
        values = p.SE_T_21_K;
        path = fullfile(out_dir, [tag '_03_SE_all_21_node_temperatures.png']);
        title_text = 'Physical SE temperatures: all 21 axial nodes';
    end
    fig = new_figure();
    plot(p.time_s, values, 'LineWidth', 0.9);
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('temperature (K)');
    title(title_text);
    export_and_close(fig, path);
end

function path = plot_heat_exchanger_temperatures(result, tag, out_dir)
    p = result.physical;
    path = fullfile(out_dir, [tag '_04_SHEX_HHEX_CHEX_temperature.png']);
    fig = new_figure();
    plot(p.time_s, p.SHEX_T_K, 'LineWidth', 1.5);
    hold on;
    plot(p.time_s, p.HHEX_T_K, 'LineWidth', 1.5);
    plot(p.time_s, p.CHEX_T_K, 'LineWidth', 1.5);
    plot(p.time_s, p.SHEX_buffer_T_K, '--', 'LineWidth', 1.0);
    plot(p.time_s, p.HHEX_buffer_T_K, '--', 'LineWidth', 1.0);
    plot(p.time_s, p.CHEX_buffer_T_K, '--', 'LineWidth', 1.0);
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('temperature (K)');
    legend({'SHEX mass','HHEX mass','CHEX mass', ...
        'SHEX buffer','HHEX buffer','CHEX buffer'}, 'Location', 'bestoutside');
    title('Physical exchanger and buffer temperatures');
    export_and_close(fig, path);
end

function path = plot_branch_temperatures(result, tag, out_dir)
    p = result.physical;
    path = fullfile(out_dir, [tag '_05_branch_inlet_outlet_temperature.png']);
    fig = new_figure();
    plot(p.time_s, p.SMA_stage1_Tin_K, '-', ...
        p.time_s, p.SMA_stage1_Tout_K, '--', ...
        p.time_s, p.SMA_stage3_Tin_K, '-', ...
        p.time_s, p.SMA_stage3_Tout_K, '--', ...
        p.time_s, p.SE_stage2_Tin_K, '-', ...
        p.time_s, p.SE_stage2_Tout_K, '--', ...
        p.time_s, p.SE_stage4_Tin_K, '-', ...
        p.time_s, p.SE_stage4_Tout_K, '--', 'LineWidth', 1.0);
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('fluid temperature (K)');
    legend({'S1 SMA in','S1 SMA out','S3 SMA in','S3 SMA out', ...
        'S2 SE in','S2 SE out','S4 SE in','S4 SE out'}, ...
        'Location', 'bestoutside');
    title('Physical branch inlet and outlet temperatures');
    export_and_close(fig, path);
end

function path = plot_all_temperature_probes(result, tag, out_dir)
    p = result.physical;
    path = fullfile(out_dir, [tag '_06_all_scalar_temperature_probes.png']);
    fig = new_figure();
    hold on;
    names = p.probe_names;
    for idx = 1:numel(names)
        plot(p.time_s, p.probes.(names{idx}), 'LineWidth', 0.55);
    end
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('temperature (K)');
    title(sprintf('All physical scalar temperature probes (%d channels)', ...
        numel(names)));
    export_and_close(fig, path);
end

function path = plot_phase_fraction(result, tag, out_dir)
    p = result.physical;
    path = fullfile(out_dir, [tag '_07_phase_fraction.png']);
    fig = new_figure();
    plot(p.time_s, mean(p.xM_SMA_21, 2), 'LineWidth', 1.5);
    hold on;
    plot(p.time_s, mean(p.xM_SE_21, 2), 'LineWidth', 1.5);
    add_stage_lines(gca, result.options);
    grid on;
    ylim([-0.02 1.02]);
    xlabel('time (s)');
    ylabel('mean martensite fraction');
    legend({'SMA','SE'}, 'Location', 'best');
    title('Physical coupled constitutive phase state');
    export_and_close(fig, path);
end

function path = plot_stress(result, tag, out_dir)
    p = result.physical;
    path = fullfile(out_dir, [tag '_08_coupled_stress.png']);
    fig = new_figure();
    plot(p.time_s, mean(p.sigma_SMA_21_Pa, 2) / 1.0e6, 'LineWidth', 1.5);
    hold on;
    plot(p.time_s, mean(p.sigma_SE_21_Pa, 2) / 1.0e6, 'LineWidth', 1.5);
    yline(result.options.material.SMA.nominal_stress_Pa / 1.0e6, ...
        ':', 'Xu nominal SMA stress');
    yline(result.options.geometry.sigma_se_design_Pa / 1.0e6, ...
        ':', 'SE design stress');
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('stress (MPa)');
    legend({'SMA mean','SE mean','SMA target','SE target'}, ...
        'Location', 'best');
    title('Physical SMA-SE compatibility stress');
    export_and_close(fig, path);
end

function path = plot_mass_flows(result, tag, out_dir)
    p = result.physical;
    path = fullfile(out_dir, [tag '_09_mass_flow_routes.png']);
    fig = new_figure();
    plot(p.time_s, p.mdot_SMA_kgps, 'LineWidth', 1.1);
    hold on;
    plot(p.time_s, p.mdot_SE_stage2_in_kgps, 'LineWidth', 1.1);
    plot(p.time_s, p.mdot_SE_stage2_out_kgps, '--', 'LineWidth', 1.1);
    plot(p.time_s, p.mdot_SE_stage4_in_kgps, 'LineWidth', 1.1);
    plot(p.time_s, p.mdot_SE_stage4_out_kgps, '--', 'LineWidth', 1.1);
    yline(result.options.branch.m_dot_kg_per_s, ':', 'scaled target');
    yline(-result.options.branch.m_dot_kg_per_s, ':');
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('mass flow rate (kg/s)');
    legend({'SMA S1/S3 loop','SE S2 inlet','SE S2 outlet', ...
        'SE S4 inlet','SE S4 outlet','target'}, 'Location', 'bestoutside');
    title('Physical route mass flow rates');
    export_and_close(fig, path);
end

function path = plot_constitutive_heat(result, tag, out_dir)
    p = result.physical;
    path = fullfile(out_dir, [tag '_10_constitutive_heat_source.png']);
    fig = new_figure();
    plot(p.time_s, sum(p.Q_SMA_constitutive_21_W, 2), 'LineWidth', 1.2);
    hold on;
    plot(p.time_s, sum(p.Q_SE_constitutive_21_W, 2), 'LineWidth', 1.2);
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('heat injected into solid (W)');
    legend({'SMA constitutive source','SE constitutive source'}, ...
        'Location', 'best');
    title('Physical 21-node constitutive heat-source totals');
    export_and_close(fig, path);
end

function path = plot_pump_commands_and_power(result, tag, out_dir)
    p = result.physical;
    path = fullfile(out_dir, [tag '_11_pump_command_and_power.png']);
    fig = new_figure();
    tiledlayout(2, 1);
    nexttile;
    plot(p.time_s, p.pressure_command_SMA_MPa, 'LineWidth', 1.2);
    hold on;
    plot(p.time_s, p.pressure_command_SE_MPa, 'LineWidth', 1.2);
    add_stage_lines(gca, result.options);
    grid on;
    ylabel('pressure command (MPa)');
    legend({'SMA pump','SE pump'}, 'Location', 'best');
    title('Physical pump pressure commands');
    nexttile;
    plot(p.time_s, p.pump_power_SMA_W, 'LineWidth', 1.2);
    hold on;
    plot(p.time_s, p.pump_power_SE_W, 'LineWidth', 1.2);
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('hydraulic power (W)');
    legend({'SMA pump','SE pump'}, 'Location', 'best');
    title('Hydraulic power from command and measured mass flow');
    export_and_close(fig, path);
end

function add_stage_lines(ax, options)
    hold(ax, 'on');
    tau = options.schedule.tau_cycle_s;
    for c = 0:(options.cycle_count - 1)
        base = c * tau;
        for s = 1:4
            xline(ax, base + options.schedule.stage_end_s(s), ...
                ':', 'Color', [0.72 0.72 0.72], 'HandleVisibility', 'off');
        end
    end
end

function fig = new_figure()
    fig = figure('Visible', 'off', 'Color', 'w', ...
        'InvertHardcopy', 'off', 'Position', [100 100 1180 720]);
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
