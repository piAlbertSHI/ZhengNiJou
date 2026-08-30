function outputs = Plot_HeatDriveECC_LocalSensitivityAudit(settings)
% Plot the six mechanism-gated local OAT pairs without imputing failures.

% Filled markers are admissible periodic points. Crosses are rejected
% candidates. A response line is drawn only when both points form a strict
% local pair, so the figure cannot visually imply a derivative from a
% rejected state.

    if nargin < 1
        settings = struct();
    end
    repo_root = fileparts(mfilename('fullpath'));
    defaults = struct( ...
        'initial_results_csv', fullfile(repo_root, 'outputs', ...
            'qian_table4_local_oat_sensitivity_20260824', ...
            'sensitivity_results.csv'), ...
        'initial_effects_csv', fullfile(repo_root, 'outputs', ...
            'qian_table4_local_oat_sensitivity_20260824', ...
            'sensitivity_effects.csv'), ...
        'refined_results_csv', fullfile(repo_root, 'outputs', ...
            'qian_table4_local_oat_refined_sensitivity_20260826', ...
            'sensitivity_results.csv'), ...
        'refined_effects_csv', fullfile(repo_root, 'outputs', ...
            'qian_table4_local_oat_refined_sensitivity_20260826', ...
            'sensitivity_effects.csv'), ...
        'output_dir', fullfile(repo_root, 'outputs_storage_audit', ...
            'local_sensitivity_figure'));
    settings = merge_structs(defaults, settings);
    source_paths = {settings.initial_results_csv, ...
        settings.initial_effects_csv, settings.refined_results_csv, ...
        settings.refined_effects_csv};
    for idx = 1:numel(source_paths)
        assert(isfile(source_paths{idx}), ...
            'HeatDriveECC:LocalSensitivitySourceMissing', ...
            'Missing local sensitivity source: %s', source_paths{idx});
    end
    if ~exist(settings.output_dir, 'dir')
        mkdir(settings.output_dir);
    end

    initial_results = readtable(settings.initial_results_csv, ...
        'VariableNamingRule', 'preserve', 'TextType', 'string');
    initial_effects = readtable(settings.initial_effects_csv, ...
        'VariableNamingRule', 'preserve', 'TextType', 'string');
    refined_results = readtable(settings.refined_results_csv, ...
        'VariableNamingRule', 'preserve', 'TextType', 'string');
    refined_effects = readtable(settings.refined_effects_csv, ...
        'VariableNamingRule', 'preserve', 'TextType', 'string');
    assert(height(initial_results) == 12 && ...
            height(refined_results) == 12 && ...
            height(initial_effects) == 6 && ...
            height(refined_effects) == 6, ...
        'HeatDriveECC:LocalSensitivityShapeMismatch', ...
        'Each OAT source must contain 12 candidates and 6 factors.');
    [results, effects] = consolidate_evidence(initial_results, ...
        initial_effects, refined_results, refined_effects);
    writetable(results, fullfile(settings.output_dir, ...
        'local_sensitivity_results.csv'));
    writetable(effects, fullfile(settings.output_dir, ...
        'local_sensitivity_effects.csv'));

    factor_fields = {'UA_level', 'endpoint_capacity_level', ...
        'SE_buffer_level', 'fluid_inventory_level', ...
        'regenerator_utilization_level', 'latent_heat_level'};
    factor_titles = {'Heat-exchanger UA', 'Endpoint heat capacity', ...
        'SE buffer volume', 'SMA fluid inventory', ...
        'SE regeneration flow', 'Transformation latent heat'};
    steps = effects.fractional_step;
    eq9_limits = padded_limits(results.eq9_lift_K, 0.12);
    scp_limits = padded_limits(results.eq10_SCP_W_per_g, 0.12);

    fig = figure('Color', 'w', 'Units', 'inches', ...
        'Position', [1 1 7.2 6.8], 'Visible', 'off');
    set(fig, 'DefaultAxesFontName', 'Arial', ...
        'DefaultAxesFontSize', 8, 'DefaultTextFontName', 'Arial', ...
        'DefaultTextFontSize', 8);
    tl = tiledlayout(fig, 3, 2, 'TileSpacing', 'compact', ...
        'Padding', 'compact');
    for idx = 1:6
        ax = nexttile(tl);
        plot_factor(ax, results, effects(idx, :), factor_fields{idx}, ...
            factor_titles{idx}, steps(idx), eq9_limits, scp_limits, idx);
    end
    title(tl, {'Mechanism-gated local sensitivity audit', ...
        'Filled = admissible; x = rejected; lines require a strict pair'}, ...
        'FontWeight', 'normal', 'Color', 'k');

    png_path = fullfile(settings.output_dir, ...
        'Fig07_local_sensitivity_audit.png');
    pdf_path = fullfile(settings.output_dir, ...
        'Fig07_local_sensitivity_audit.pdf');
    exportgraphics(fig, png_path, 'Resolution', 600, ...
        'BackgroundColor', 'white');
    exportgraphics(fig, pdf_path, 'ContentType', 'vector', ...
        'BackgroundColor', 'white');
    close(fig);

    manifest_path = fullfile(settings.output_dir, ...
        'local_sensitivity_manifest.txt');
    write_manifest(manifest_path, settings, results, effects);
    outputs = struct( ...
        'schema', 'heatdrive_ecc_local_sensitivity_figure_v2', ...
        'png', png_path, 'pdf', pdf_path, 'manifest', manifest_path, ...
        'completed_points', height(results), ...
        'admissible_points', nnz(logical(results.admissible)), ...
        'strict_local_pairs', ...
            nnz(logical(effects.strict_local_pair_available)));
end

function [results, effects] = consolidate_evidence(initial_results, ...
        initial_effects, refined_results, refined_effects)
% Use one internally symmetric campaign for each factor. The initial buffer
% pair is retained because it already passed; all other factors use the
% smaller refined perturbation. No rejected point is used in a derivative.
    use_initial = 3;
    results = table();
    effects = table();
    for factor_idx = 1:6
        rows = (2 * factor_idx - 1):(2 * factor_idx);
        if factor_idx == use_initial
            current_results = initial_results(rows, :);
            current_effect = initial_effects(factor_idx, :);
            source = "initial_20260824";
        else
            current_results = refined_results(rows, :);
            current_effect = refined_effects(factor_idx, :);
            source = "refined_20260826";
        end
        current_results.evidence_source = repmat(source, 2, 1);
        current_effect.evidence_source = source;
        results = [results; current_results]; %#ok<AGROW>
        effects = [effects; current_effect]; %#ok<AGROW>
    end
end

function plot_factor(ax, results, effect, level_field, factor_title, ...
        step, eq9_limits, scp_limits, panel_index)
    levels = results.(level_field);
    selected = levels ~= 0;
    pair = results(selected, :);
    [~, order] = sort(pair.(level_field));
    pair = pair(order, :);
    x = 100 * step * pair.(level_field);
    strict_pair = logical(effect.strict_local_pair_available);

    hold(ax, 'on');
    yyaxis(ax, 'left');
    ax.YColor = [0.10 0.38 0.65];
    if strict_pair
        plot(ax, x, pair.eq9_lift_K, '-', 'Color', [0.10 0.38 0.65], ...
            'LineWidth', 1.0);
    end
    h_eq9 = plot_gated(ax, x, pair.eq9_lift_K, ...
        logical(pair.admissible), 'o', [0.10 0.38 0.65]);
    ylabel(ax, 'Eq. 9 lift (K)');
    ylim(ax, eq9_limits);

    yyaxis(ax, 'right');
    ax.YColor = [0.85 0.38 0.05];
    if strict_pair
        plot(ax, x, pair.eq10_SCP_W_per_g, '-', ...
            'Color', [0.85 0.38 0.05], 'LineWidth', 1.0);
    end
    h_scp = plot_gated(ax, x, pair.eq10_SCP_W_per_g, ...
        logical(pair.admissible), 's', [0.85 0.38 0.05]);
    ylabel(ax, 'SCP (W g^{-1})');
    ylim(ax, scp_limits);

    xlabel(ax, 'Parameter perturbation (%)');
    xlim(ax, 100 * step * [-1.55 1.55]);
    xticks(ax, 100 * step * [-1 1]);
    title(ax, factor_title, 'Color', 'k');
    grid(ax, 'on');
    box(ax, 'on');
    ax.Color = 'w';
    ax.XColor = 'k';
    status_color = [0.10 0.50 0.25];
    status_text = 'strict pair: PASS';
    if ~strict_pair
        status_color = [0.75 0.15 0.15];
        status_text = 'strict pair: unavailable';
    end
    text(ax, 0.98, 0.06, status_text, 'Units', 'normalized', ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
        'FontSize', 6.5, 'Color', status_color);
    text(ax, 0.01, 0.98, char('a' + panel_index - 1), ...
        'Units', 'normalized', 'VerticalAlignment', 'top', ...
        'FontWeight', 'bold', 'Color', 'k');
    if panel_index == 1
        lgd = legend(ax, [h_eq9, h_scp], {'Eq. 9', 'SCP'}, ...
            'Location', 'north', 'Box', 'off', 'Orientation', 'horizontal');
        lgd.TextColor = 'k';
    end
end

function handle = plot_gated(ax, x, y, admissible, marker, color)
    accepted = find(admissible);
    rejected = find(~admissible);
    handle = plot(ax, NaN, NaN, marker, 'Color', color, ...
        'MarkerFaceColor', color, 'MarkerSize', 5, 'LineStyle', 'none');
    if ~isempty(accepted)
        plot(ax, x(accepted), y(accepted), marker, 'Color', color, ...
            'MarkerFaceColor', color, 'MarkerSize', 5, ...
            'LineStyle', 'none');
    end
    if ~isempty(rejected)
        plot(ax, x(rejected), y(rejected), 'x', 'Color', color, ...
            'MarkerSize', 6, 'LineWidth', 1.2, 'LineStyle', 'none');
    end
end

function limits = padded_limits(values, fraction)
    values = values(isfinite(values));
    span = max(values) - min(values);
    if span <= 0
        span = max(abs(values(1)), 1) * 0.02;
    end
    limits = [min(values) - fraction * span, ...
        max(values) + fraction * span];
end

function write_manifest(path, settings, results, effects)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'HeatDriveECC:LocalSensitivityManifestOpenFailed', ...
        'Cannot write %s.', path);
    cleaner = onCleanup(@() fclose(fid));
    strict = logical(effects.strict_local_pair_available);
    fprintf(fid, 'schema=heatdrive_ecc_local_sensitivity_figure_v2\n');
    fprintf(fid, 'completed_points=%d\n', height(results));
    fprintf(fid, 'admissible_points=%d\n', nnz(logical(results.admissible)));
    fprintf(fid, 'rejected_points=%d\n', nnz(~logical(results.admissible)));
    fprintf(fid, 'strict_local_pairs=%d\n', nnz(strict));
    fprintf(fid, 'strict_pair_factors=%s\n', ...
        strjoin(cellstr(effects.factor(strict)), ','));
    fprintf(fid, ['derivative_policy=reported only when both symmetric ', ...
        'candidates are mechanism-valid and periodic\n']);
    fprintf(fid, ['evidence_policy=initial symmetric buffer pair plus ', ...
        'refined symmetric pairs for all other factors\n']);
    fprintf(fid, 'initial_results_csv=%s\n', ...
        settings.initial_results_csv);
    fprintf(fid, 'initial_effects_csv=%s\n', ...
        settings.initial_effects_csv);
    fprintf(fid, 'refined_results_csv=%s\n', ...
        settings.refined_results_csv);
    fprintf(fid, 'refined_effects_csv=%s\n', ...
        settings.refined_effects_csv);
    clear cleaner
end

function out = merge_structs(out, overrides)
    names = fieldnames(overrides);
    for idx = 1:numel(names)
        out.(names{idx}) = overrides.(names{idx});
    end
end
