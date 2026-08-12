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
    figures = [figures, plot_grouped_temperature_probes(result, tag, out_dir)];
    figures{end + 1} = plot_phase_fraction(result, tag, out_dir);
    figures{end + 1} = plot_stress(result, tag, out_dir);
    figures{end + 1} = plot_mass_flows(result, tag, out_dir);
    figures{end + 1} = plot_constitutive_heat(result, tag, out_dir);
    figures{end + 1} = plot_pump_commands_and_power(result, tag, out_dir);
    figures{end + 1} = plot_solid_energy_exchange(result, tag, out_dir);
end

function path = plot_mean_solid_temperatures(result, tag, out_dir)
    p = result.physical;
    t = p.time_s;
    path = fullfile(out_dir, [tag '_01_SMA_SE_mean_temperature.png']);
    fig = new_figure();
    plot(t, mean(p.SMA_T_21_K, 2), 'LineWidth', 1.5);
    hold on;
    plot(t, mean(p.SE_T_21_K, 2), 'LineWidth', 1.5);
    yline(result.options.equilibrium.T_transform_start_K, ...
        ':', 'SMA reverse start line');
    yline(result.options.system.T0_K, ':', 'HHEX');
    yline(result.options.system.Tc_K, ':', 'CHEX');
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('temperature (K)');
    legend({'SMA mean','SE mean','SMA reverse start','HHEX','CHEX'}, ...
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
    plot(p.time_s, p.SMA_HHEX_buffer_T_K, ':', 'LineWidth', 1.2);
    plot(p.time_s, p.CHEX_buffer_T_K, '--', 'LineWidth', 1.0);
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('temperature (K)');
    legend({'SHEX mass','HHEX mass','CHEX mass', ...
        'SHEX water buffer','HHEX glycol buffer', ...
        'HHEX SMA-water buffer','CHEX glycol buffer'}, ...
        'Location', 'bestoutside');
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

function paths = plot_grouped_temperature_probes(result, tag, out_dir)
    p = result.physical;
    groups = { ...
        '06a_SMA_stage1_SHEX_probes', 'SMA Stage 1 and SHEX probes', { ...
            'SHEX_hot_hx_', 'SHEX_probe_', 'shex_hot_pipe_', ...
            'probe_root_shex_', 'probe_sma_stage1_', ...
            'sma_stage1_', 'sma_hold_'}; ...
        '06b_SMA_stage3_HHEX_probes', 'SMA Stage 3 and HHEX-water probes', { ...
            'hhex_sma_branch_', 'probe_sma_stage3_', ...
            'sma_stage3_', 'sma_cooldown_', 'sma_hot_buffer_'}; ...
        '06c_SE_stage2_HHEX_probes', 'SE Stage 2 and HHEX-glycol probes', { ...
            'hot_buffer_', 'hot_hx_', 'hot_sink_', ...
            'probe_root_hot_', 'probe_hot_hx_', 'probe_v4_hot_', ...
            'probe_v3_sma_to_hot_'}; ...
        '06d_SE_stage4_CHEX_probes', 'SE Stage 4 and CHEX-glycol probes', { ...
            'chip_', 'cold_buffer_', 'cold_hx_', 'cold_load_', ...
            'cold_return_', 'cold_sink_', 'cold_subsystem_', ...
            'probe_chip_', 'probe_cold_', 'probe_root_cold_', ...
            'probe_v1_cold_', 'probe_v6_sma_to_chip_'}; ...
        '06e_exchanger_buffer_probes', 'Exchanger masses and buffer probes', { ...
            'SHEX_hot_sink_temp_out', 'hot_sink_temp_out', ...
            'cold_sink_temp_out', 'shex_buffer_temp_out', ...
            'hot_buffer_temp_out', 'cold_buffer_temp_out', ...
            'sma_hot_buffer_temp_out', 'probe_root_shex_buffer_', ...
            'probe_root_hot_buffer_', 'probe_root_cold_buffer_'} ...
        };
    paths = cell(1, size(groups, 1));
    for group_idx = 1:size(groups, 1)
        suffix = groups{group_idx, 1};
        title_text = groups{group_idx, 2};
        tokens = groups{group_idx, 3};
        names = select_probe_names(p.probe_names, tokens);
        paths{group_idx} = fullfile(out_dir, ...
            sprintf('%s_%s.png', tag, suffix));
        fig = new_figure();
        hold on;
        for probe_idx = 1:numel(names)
            plot(p.time_s, p.probes.(names{probe_idx}), 'LineWidth', 0.9);
        end
        add_stage_lines(gca, result.options);
        grid on;
        xlabel('time (s)');
        ylabel('temperature (K)');
        title(sprintf('%s (%d channels)', title_text, numel(names)));
        legend(strrep(names, '_', ' '), 'Location', 'bestoutside', ...
            'FontSize', 7);
        export_and_close(fig, paths{group_idx});
    end
end

function selected = select_probe_names(names, tokens)
    selected_mask = false(size(names));
    for token_idx = 1:numel(tokens)
        selected_mask = selected_mask | startsWith(names, tokens{token_idx}, ...
            'IgnoreCase', true);
    end
    selected = names(selected_mask);
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
    [sigma_sma_full_Pa, sigma_se_full_Pa] = ...
        full_transform_compatibility_stresses(result.options);
    yline(sigma_sma_full_Pa / 1.0e6, ':', ...
        'Table 4 full-transform SMA compatibility');
    yline(sigma_se_full_Pa / 1.0e6, ':', ...
        'Table 4 full-transform SE compatibility');
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('stress (MPa)');
    legend({'SMA mean','SE mean','SMA compatibility','SE compatibility'}, ...
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
    yline(result.options.branch.m_dot_sma_shex_kg_per_s, ...
        ':', 'SMA 50.8 g/s');
    yline(result.options.branch.m_dot_se_the_kg_per_s, ...
        ':', 'SE 3.2 g/s');
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('mass flow rate (kg/s)');
    legend({'SMA S1/S3 loop','SE S2 inlet','SE S2 outlet', ...
        'SE S4 inlet','SE S4 outlet','SMA target','SE target'}, ...
        'Location', 'bestoutside');
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

function path = plot_solid_energy_exchange(result, tag, out_dir)
    p = result.physical;
    path = fullfile(out_dir, [tag '_12_solid_energy_exchange.png']);
    fig = new_figure();
    tiledlayout(2, 1);
    nexttile;
    plot(p.time_s, sum(p.Q_SMA_hold_pipe_to_solid_21_W, 2), ...
        'LineWidth', 1.1);
    hold on;
    plot(p.time_s, sum(p.Q_SMA_cooldown_pipe_to_solid_21_W, 2), ...
        'LineWidth', 1.1);
    plot(p.time_s, sum(p.Q_SMA_constitutive_21_W, 2), ...
        'LineWidth', 1.1);
    add_stage_lines(gca, result.options);
    grid on;
    ylabel('heat into SMA (W)');
    legend({'Stage 1 pipe','Stage 3 pipe','Constitutive'}, ...
        'Location', 'best');
    title('Measured SMA solid energy exchange');
    nexttile;
    plot(p.time_s, sum(p.Q_SE_hold_pipe_to_solid_21_W, 2), ...
        'LineWidth', 1.1);
    hold on;
    plot(p.time_s, sum(p.Q_SE_cooldown_pipe_to_solid_21_W, 2), ...
        'LineWidth', 1.1);
    plot(p.time_s, sum(p.Q_SE_constitutive_21_W, 2), ...
        'LineWidth', 1.1);
    add_stage_lines(gca, result.options);
    grid on;
    xlabel('time (s)');
    ylabel('heat into SE (W)');
    legend({'Stage 2 pipe','Stage 4 pipe','Constitutive'}, ...
        'Location', 'best');
    title('Measured SE solid energy exchange');
    export_and_close(fig, path);
end

function [sigma_a_Pa, sigma_r_Pa] = ...
        full_transform_compatibility_stresses(options)
    g = options.geometry;
    sma = options.material.SMA;
    se = options.material.SE;
    force_ratio = g.S_r_m2 / g.S_a_m2;
    numerator_m = g.L_a_m * sma.epsilon_T - ...
        g.L_r_m * se.epsilon_T;
    denominator_m_per_Pa = ...
        g.L_a_m * force_ratio / sma.E_m_Pa + ...
        g.L_r_m / se.E_m_Pa;
    sigma_r_Pa = numerator_m / max(denominator_m_per_Pa, eps);
    sigma_a_Pa = force_ratio * sigma_r_Pa;
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
