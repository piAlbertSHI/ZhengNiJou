function plot_info = Plot_GX101R1_Fixed_Probe_Trajectories(run_result, figures_dir, plot_info)
% Plot fixed physical probes as single continuous global-time trajectories.

    if nargin < 2 || isempty(figures_dir)
        figures_dir = fullfile(get_field(run_result, 'outputs_dir', pwd), 'figures');
    end
    if nargin < 3 || ~isstruct(plot_info)
        plot_info = struct('figures_dir', figures_dir, 'generated_files', {{}}); 
    end

    fixed_dir = fullfile(figures_dir, 'probe_timeseries_individual');
    alias_dir = fullfile(figures_dir, 'probe_timeseries_active_path_aliases');
    ensure_dir(fixed_dir);
    ensure_dir(alias_dir);

    fixed_probes = fixed_probe_definitions();
    alias_probes = active_alias_probe_definitions();
    mapping_rows = {};

    for idx = 1:numel(fixed_probes)
        [plot_info, generated] = plot_one_timeline(run_result, fixed_probes(idx), fixed_dir, plot_info);
        mapping_rows(end + 1, :) = probe_mapping_row(fixed_probes(idx), generated, 'fixed_physical_probe'); %#ok<AGROW>
    end
    for idx = 1:numel(alias_probes)
        [plot_info, generated] = plot_one_timeline(run_result, alias_probes(idx), alias_dir, plot_info);
        mapping_rows(end + 1, :) = probe_mapping_row(alias_probes(idx), generated, 'active_path_alias'); %#ok<AGROW>
    end

    mapping_path = fullfile(fixed_dir, 'fixed_probe_field_mapping.csv');
    write_mapping_csv(mapping_path, mapping_rows);
    plot_info.generated_files{end + 1} = mapping_path;
    plot_info.probe_timeseries_individual_dir = fixed_dir;
    plot_info.probe_timeseries_active_path_aliases_dir = alias_dir;
end

function [plot_info, generated] = plot_one_timeline(run_result, probe, output_dir, plot_info)
    timeline = Build_GX101R1_Continuous_Probe_Timeline(run_result, probe);
    generated = false;
    if ~timeline.ok
        return;
    end

    fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 920 430]);
    ax = axes(fig);
    plot(ax, timeline.time_s, timeline.value, '-', 'LineWidth', 1.45, 'Color', [0.10 0.31 0.58]);
    hold(ax, 'on');
    mark_stage_boundaries(ax, timeline);
    hold(ax, 'off');
    box(ax, 'on');
    grid(ax, 'on');
    xlabel(ax, 'Global time (s)');
    ylabel(ax, probe.ylabel);
    title(ax, probe.display_name, 'Interpreter', 'none');
    if ~isempty(probe.semantics)
        subtitle(ax, probe.semantics, 'Interpreter', 'none');
    end

    png_path = fullfile(output_dir, [probe.file_stub, '.png']);
    pdf_path = fullfile(output_dir, [probe.file_stub, '.pdf']);
    apply_white_theme(fig);
    exportgraphics(fig, png_path, 'Resolution', 300);
    exportgraphics(fig, pdf_path, 'ContentType', 'vector');
    close(fig);
    plot_info.generated_files{end + 1} = png_path;
    plot_info.generated_files{end + 1} = pdf_path;
    generated = true;
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

function mark_stage_boundaries(ax, timeline)
    stage_names = timeline.stage_name;
    if isempty(stage_names)
        return;
    end
    changed = [true, ~strcmp(stage_names(2:end), stage_names(1:end-1))];
    idxs = find(changed);
    max_marks = min(numel(idxs), 40);
    if numel(idxs) > max_marks
        idxs = idxs(unique(round(linspace(1, numel(idxs), max_marks))));
    end
    for k = 1:numel(idxs)
        idx = idxs(k);
        xline(ax, timeline.time_s(idx), ':', ...
            short_stage_label(timeline.cycle_index(idx), timeline.stage_index(idx)), ...
            'Color', [0.72 0.72 0.72], 'FontSize', 7, ...
            'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
    end
end

function label = short_stage_label(cycle_index, stage_index)
    if isfinite(cycle_index) && isfinite(stage_index)
        label = sprintf('C%d-S%d', cycle_index, stage_index);
    else
        label = '';
    end
end

function probes = fixed_probe_definitions()
    probes = [ ...
        make_probe('T_probe_v1_cold_inlet_cold_buffer_side_K_t', 'probe_v1_cold_inlet_cold_buffer_side_T_K', 'V1 cold-inlet cold-buffer side', 'Temperature (K)', 'fixed_v1_cold_inlet_cold_buffer_side', 'fixed port: cold-buffer side of V1'), ...
        make_probe('T_probe_v1_cold_inlet_sma_side_K_t', 'probe_v1_cold_inlet_sma_side_T_K', 'V1 cold-inlet SMA side', 'Temperature (K)', 'fixed_v1_cold_inlet_sma_side', 'fixed port: SMA side of V1'), ...
        make_probe('T_probe_sma_stage2_port1_v1_side_K_t', 'probe_sma_stage2_port1_v1_side_T_K', 'Stage 2 SMA port 1, V1 side', 'Temperature (K)', 'fixed_sma_stage2_port1_v1_side', 'fixed port: stage-2 SMA inlet boundary'), ...
        make_probe('T_probe_sma_stage2_port2_v3_side_K_t', 'probe_sma_stage2_port2_v3_side_T_K', 'Stage 2 SMA port 2, V3 side', 'Temperature (K)', 'fixed_sma_stage2_port2_v3_side', 'fixed port: stage-2 SMA outlet boundary'), ...
        make_probe('T_probe_v3_sma_to_hot_sma_side_K_t', 'probe_v3_sma_to_hot_sma_side_T_K', 'V3 SMA-to-HHEX SMA side', 'Temperature (K)', 'fixed_v3_sma_to_hot_sma_side', 'fixed port: SMA side of V3'), ...
        make_probe('T_probe_v3_sma_to_hot_hot_hx_side_K_t', 'probe_v3_sma_to_hot_hot_hx_side_T_K', 'V3 SMA-to-HHEX HHEX side', 'Temperature (K)', 'fixed_v3_sma_to_hot_hhex_side', 'fixed port: HHEX side of V3'), ...
        make_probe('T_hot_hx_inlet_fluid_K_t', 'hot_hx_inlet_fluid_temp_out', 'HHEX inlet fluid boundary', 'Temperature (K)', 'fixed_hhex_inlet_boundary', 'HHEX inlet boundary, not hot-sink lumped mass'), ...
        make_probe('T_hot_hx_outlet_fluid_K_t', 'hot_hx_outlet_fluid_temp_out', 'HHEX outlet fluid boundary', 'Temperature (K)', 'fixed_hhex_outlet_boundary', 'HHEX outlet boundary'), ...
        make_probe('T_probe_v4_hot_inlet_hot_buffer_side_K_t', 'probe_v4_hot_inlet_hot_buffer_side_T_K', 'V4 hot-inlet hot-buffer side', 'Temperature (K)', 'fixed_v4_hot_inlet_hot_buffer_side', 'fixed port: hot-buffer side of V4'), ...
        make_probe('T_probe_v4_hot_inlet_sma_side_K_t', 'probe_v4_hot_inlet_sma_side_T_K', 'V4 hot-inlet SMA side', 'Temperature (K)', 'fixed_v4_hot_inlet_sma_side', 'fixed port: SMA side of V4'), ...
        make_probe('T_probe_sma_stage4_port3_v4_side_K_t', 'probe_sma_stage4_port3_v4_side_T_K', 'Stage 4 SMA port 3, V4 side', 'Temperature (K)', 'fixed_sma_stage4_port3_v4_side', 'fixed port: stage-4 SMA inlet boundary'), ...
        make_probe('T_probe_sma_stage4_port4_v6_side_K_t', 'probe_sma_stage4_port4_v6_side_T_K', 'Stage 4 SMA port 4, V6 side', 'Temperature (K)', 'fixed_sma_stage4_port4_v6_side', 'fixed port: stage-4 SMA outlet boundary'), ...
        make_probe('T_probe_v6_sma_to_cold_hx_sma_side_K_t', 'probe_v6_sma_to_cold_hx_sma_side_T_K', 'V6 SMA-to-CHEX SMA side', 'Temperature (K)', 'fixed_v6_sma_to_chex_sma_side', 'fixed port: SMA side of V6'), ...
        make_probe('T_probe_v6_sma_to_cold_hx_cold_hx_side_K_t', 'probe_v6_sma_to_cold_hx_cold_hx_side_T_K', 'V6 SMA-to-CHEX CHEX side', 'Temperature (K)', 'fixed_v6_sma_to_chex_chex_side', 'fixed port: CHEX side of V6'), ...
        make_probe('T_cold_hx_inlet_fluid_K_t', 'cold_hx_inlet_fluid_temp_out', 'CHEX inlet fluid boundary', 'Temperature (K)', 'fixed_chex_inlet_boundary', 'CHEX pipe inlet / SMA-to-CHEX boundary, not a lumped mass'), ...
        make_probe('T_cold_hx_outlet_fluid_K_t', 'cold_hx_outlet_fluid_temp_out', 'CHEX outlet / cold-return boundary', 'Temperature (K)', 'fixed_chex_outlet_cold_return_boundary', 'CHEX pipe outlet / cold return boundary, not cold-sink lumped mass'), ...
        make_probe('T_hot_sink_K_t', 'hot_sink_temp_out', 'Hot-sink lumped mass', 'Temperature (K)', 'fixed_hot_sink_mass', 'lumped hot-side effective thermal mass'), ...
        make_probe('T_cold_sink_K_t', 'cold_sink_temp_out', 'Cold-sink lumped mass', 'Temperature (K)', 'fixed_cold_sink_mass', 'lumped CHEX/cold-side effective thermal mass'), ...
        make_probe('T_cold_load_K_t', 'cold_load_temp_out', 'Cold-load thermal mass', 'Temperature (K)', 'fixed_cold_load_mass', 'external cold-load thermal mass')];
end

function probes = active_alias_probe_definitions()
    probes = [ ...
        make_probe('T_sma_fluid_in_K_t', 'sma_inlet_fluid_temp_out', 'Active-path SMA fluid inlet alias', 'Temperature (K)', 'active_alias_sma_fluid_in', 'active-path alias; stage 2 and stage 4 refer to different physical ports'), ...
        make_probe('T_sma_fluid_out_K_t', 'sma_outlet_fluid_temp_out', 'Active-path SMA fluid outlet alias', 'Temperature (K)', 'active_alias_sma_fluid_out', 'active-path alias; stage 2 and stage 4 refer to different physical ports'), ...
        make_probe('T_cold_supply_K_t', 'cold_hx_inlet_fluid_temp_out', 'Active-path cold supply alias', 'Temperature (K)', 'active_alias_cold_supply', 'active-path alias for stage-4 SMA outlet to CHEX inlet'), ...
        make_probe('T_cold_return_K_t', 'cold_hx_outlet_fluid_temp_out', 'Active-path cold return alias', 'Temperature (K)', 'active_alias_cold_return', 'active-path alias for stage-4 CHEX outlet / cold return boundary'), ...
        make_probe('mdot_active_kgps_t', 'sma_inlet_branch_mass_flow_kgps', 'Active-path mass flow', 'Mass flow (kg/s)', 'active_alias_mdot', 'active-path hydraulic quantity'), ...
        make_probe('Q_active_m3ps_t', 'Q_target_m3ps', 'Active-path volume flow', 'Volume flow (m^3/s)', 'active_alias_Q', 'active-path hydraulic quantity'), ...
        make_probe('h_sma_W_m2K_t', 'h_water', 'SMA-side convective coefficient', 'h (W m^{-2} K^{-1})', 'active_alias_h_sma', 'active-path heat-transfer coefficient'), ...
        make_probe('Re_sma_t', 'Re', 'SMA-side Reynolds number', 'Re (-)', 'active_alias_Re_sma', 'active-path hydraulic quantity')];
end

function probe = make_probe(field, scalar_field, display_name, ylabel, file_stub, semantics)
    probe = struct( ...
        'field', field, ...
        'scalar_field', scalar_field, ...
        'display_name', display_name, ...
        'ylabel', ylabel, ...
        'file_stub', file_stub, ...
        'semantics', semantics);
end

function row = probe_mapping_row(probe, generated, category)
    row = {category, probe.field, probe.scalar_field, probe.display_name, probe.semantics, logical(generated)};
end

function write_mapping_csv(path_value, rows)
    fid = fopen(path_value, 'w');
    if fid < 0
        return;
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, 'category,timeseries_field,terminal_field,display_name,semantics,generated\n');
    for idx = 1:size(rows, 1)
        fprintf(fid, '%s,%s,%s,%s,%s,%d\n', ...
            csv_escape(rows{idx, 1}), csv_escape(rows{idx, 2}), csv_escape(rows{idx, 3}), ...
            csv_escape(rows{idx, 4}), csv_escape(rows{idx, 5}), rows{idx, 6});
    end
end

function text = csv_escape(value)
    text = char(string(value));
    text = strrep(text, '"', '""');
    text = ['"', text, '"'];
end

function ensure_dir(path_value)
    if ~exist(path_value, 'dir')
        mkdir(path_value);
    end
end

function value = get_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
