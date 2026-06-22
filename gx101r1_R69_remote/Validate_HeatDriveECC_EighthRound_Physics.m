function result = Validate_HeatDriveECC_EighthRound_Physics()
% Independent hard-check validation for the eighth-round Simulink ECC model.

    r3 = Run_HeatDriveECC_EighthRound_Simulink_Cycles(struct('cycle_count', 3));
    r10 = Run_HeatDriveECC_EighthRound_Simulink_Cycles(struct('cycle_count', 10));

    checks3 = hard_checks(r3, false);
    checks10 = hard_checks(r10, true);
    figures = write_figures(r3, r10);
    audit_outputs = write_audit_tables(r3, r10);

    result = struct();
    result.r3 = r3;
    result.r10 = r10;
    result.checks3 = checks3;
    result.checks10 = checks10;
    result.passed = all_checks_pass(checks3) && all_checks_pass(checks10);
    result.figures = figures;
    result.audit_outputs = audit_outputs;
    result.report_path = write_report(result);

    fprintf('Ninth-round raw-loop validation passed: %d\n', result.passed);
    fprintf('Report: %s\n', result.report_path);
    if ~result.passed
        error('Validate:NinthRound:HardCheckFailed', ...
            'Ninth-round Simulink raw-loop hard checks failed. See report for details.');
    end
end

function checks = hard_checks(result, use_last3_average)
    s = result.summary;
    v = result.options.validation;
    map = result.options.output;
    Y = result.Y;
    cycles = s.cycle;
    if use_last3_average && numel(cycles) >= 3
        heat = average_cycle(cycles(end-2:end));
    else
        heat = cycles(end);
    end

    checks = struct();
    checks.used_simulink_sim = isfield(result, 'used_simulink_sim') && result.used_simulink_sim;
    checks.all_finite = s.all_finite;
    checks.max_abs_output = max(abs(Y(:))) <= v.max_abs_output;
    checks.samples_per_stage = s.stage_sample_min >= v.min_samples_per_stage;
    checks.eq6 = s.max_abs_eq6_scaled <= v.max_eq6_scaled;
    checks.eq7 = s.max_abs_eq7_scaled <= v.max_eq7_scaled;
    checks.Ta_spatial_gradient = s.max_Ta_spread_K > v.min_node_spread_K;
    checks.Tr_spatial_gradient = s.max_Tr_spread_K > v.min_node_spread_K;
    checks.Ta_node_traces_distinct = ...
        max(abs(Y(:, map.Ta_51(1)) - Y(:, map.Ta_51(end)))) > v.min_node_spread_K;
    checks.Tr_node_traces_distinct = ...
        max(abs(Y(:, map.Tr_51(1)) - Y(:, map.Tr_51(end)))) > v.min_node_spread_K;
    checks.Qh = relerr(heat.Qh_boundary_J, s.article_Qh_cycle_J) <= v.max_qh_rel_error;
    checks.Qr = relerr(heat.Qr_boundary_J, s.article_Qr_cycle_J) <= v.max_qr_rel_error;
    checks.QrQh = relerr(heat.Qr_boundary_J / max(heat.Qh_boundary_J, eps), ...
        s.article_Qr_over_Qh) <= v.max_qr_qh_rel_error;
    checks.delta_xM_a = s.err_delta_xM_a_rel <= v.max_delta_xM_a_rel_error;
    checks.delta_xM_r = s.err_delta_xM_r_rel <= v.max_delta_xM_r_rel_error && ...
        s.last_delta_xM_r >= v.min_delta_xM_r;
    checks.sigma_r_load = s.err_sigma_r_rel <= v.max_sigma_r_rel_error;
    checks.Th = s.err_Th_abs_K <= v.max_Th_abs_error_K;
    checks.energy_residual = max([cycles.energy_residual_fraction]) <= ...
        v.max_energy_residual_fraction;
    checks.raw_loop_audited = all(isfinite([cycles.Qh_raw_loop_J])) && ...
        all(isfinite([cycles.Qr_raw_loop_J])) && ...
        max(abs([cycles.Qh_boundary_J] - [cycles.Qh_raw_loop_J])) < 1.0e-9 && ...
        max(abs([cycles.Qr_boundary_J] - [cycles.Qr_raw_loop_J])) < 1.0e-9;
end

function avg = average_cycle(cycles)
    avg = cycles(end);
    avg.Qh_boundary_J = mean([cycles.Qh_boundary_J]);
    avg.Qr_boundary_J = mean([cycles.Qr_boundary_J]);
    avg.Qh_raw_loop_J = mean([cycles.Qh_raw_loop_J]);
    avg.Qr_raw_loop_J = mean([cycles.Qr_raw_loop_J]);
    avg.Qh_article_formula_J = mean([cycles.Qh_article_formula_J]);
    avg.Qr_article_formula_J = mean([cycles.Qr_article_formula_J]);
    avg.Qh_formula_minus_raw_J = mean([cycles.Qh_formula_minus_raw_J]);
    avg.Qr_formula_minus_raw_J = mean([cycles.Qr_formula_minus_raw_J]);
    avg.THE_reject_J = mean([cycles.THE_reject_J]);
end

function tf = all_checks_pass(checks)
    values = struct2cell(checks);
    tf = all(cellfun(@(x) islogical(x) && isscalar(x) && x, values));
end

function e = relerr(value, target)
    e = abs(value - target) / max(abs(target), eps);
end

function value = integrate_power(x, dt, idx)
    if ~any(idx)
        value = 0.0;
        return;
    end
    value = sum(x(idx) .* dt(idx));
end

function nodes = representative_nodes(N)
    nodes = unique(min(max([1 13 26 39 51], 1), N), 'stable');
end

function figures = write_figures(r3, r10)
    out_dir = r3.options.outputs_dir;
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    figures = {};
    figures{end + 1} = write_node_heatmap(r3, '3cycle');
    figures{end + 1} = write_representative_node_plot(r3, 'SMA', '3cycle');
    figures{end + 1} = write_representative_node_plot(r3, 'SE', '3cycle');
    figures{end + 1} = write_phase_fraction_plot(r3, '3cycle');
    figures{end + 1} = write_branch_temperature_plot(r3, '3cycle');
    figures{end + 1} = write_branch_internal_plot(r3, '3cycle');
    figures{end + 1} = write_cycle_energy_plot(r3, r10);
    figures{end + 1} = write_residual_plot(r3, '3cycle');
end

function path = write_node_heatmap(result, tag)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(result.options.outputs_dir, [tag '_51node_temperature_heatmap.png']);
    fig = figure('Visible', 'off', 'Color', 'w');
    tiledlayout(2, 1);
    nexttile;
    imagesc(t, 1:result.options.node_count, Y(:, map.Ta_51).');
    set(gca, 'YDir', 'normal');
    colorbar;
    xlabel('time (s)');
    ylabel('SMA node');
    title('SMA Ta\_51 (K)');
    nexttile;
    imagesc(t, 1:result.options.node_count, Y(:, map.Tr_51).');
    set(gca, 'YDir', 'normal');
    colorbar;
    xlabel('time (s)');
    ylabel('SE node');
    title('SE Tr\_51 (K)');
    exportgraphics(fig, path, 'Resolution', 160);
    close(fig);
end

function path = write_representative_node_plot(result, solid_name, tag)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    nodes = representative_nodes(result.options.node_count);
    if strcmpi(solid_name, 'SMA')
        arr = map.Ta_51;
        title_text = 'SMA representative node temperatures';
        prefix = 'sma';
    else
        arr = map.Tr_51;
        title_text = 'SE representative node temperatures';
        prefix = 'se';
    end
    path = fullfile(result.options.outputs_dir, ...
        sprintf('%s_%s_representative_node_temperatures.png', tag, prefix));
    fig = figure('Visible', 'off', 'Color', 'w');
    plot(t, Y(:, arr(nodes)), 'LineWidth', 1.0);
    grid on;
    xlabel('time (s)');
    ylabel('temperature (K)');
    legend(compose('node %d', nodes), 'Location', 'best');
    title(title_text);
    exportgraphics(fig, path, 'Resolution', 160);
    close(fig);
end

function path = write_phase_fraction_plot(result, tag)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    nodes = representative_nodes(result.options.node_count);
    path = fullfile(result.options.outputs_dir, [tag '_phase_fraction_nodes.png']);
    fig = figure('Visible', 'off', 'Color', 'w');
    tiledlayout(2, 1);
    nexttile;
    plot(t, Y(:, map.xM_a_51(nodes)), 'LineWidth', 1.0);
    grid on;
    xlabel('time (s)');
    ylabel('xM SMA');
    legend(compose('node %d', nodes), 'Location', 'bestoutside');
    title('SMA martensite fraction nodes');
    nexttile;
    plot(t, Y(:, map.xM_r_51(nodes)), 'LineWidth', 1.0);
    grid on;
    xlabel('time (s)');
    ylabel('xM SE');
    legend(compose('node %d', nodes), 'Location', 'bestoutside');
    title('SE martensite fraction nodes');
    exportgraphics(fig, path, 'Resolution', 160);
    close(fig);
end

function path = write_branch_temperature_plot(result, tag)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(result.options.outputs_dir, [tag '_branch_inlet_outlet_temperatures.png']);
    fig = figure('Visible', 'off', 'Color', 'w');
    plot(t, Y(:, map.SMA_SHEX_Tin_K), '-', t, Y(:, map.SMA_SHEX_Tout_K), '--', ...
        t, Y(:, map.SMA_THE_Tin_K), '-', t, Y(:, map.SMA_THE_Tout_K), '--', ...
        t, Y(:, map.SE_THE_Tin_K), '-', t, Y(:, map.SE_THE_Tout_K), '--', ...
        t, Y(:, map.SE_CHEX_Tin_K), '-', t, Y(:, map.SE_CHEX_Tout_K), '--');
    grid on;
    xlabel('time (s)');
    ylabel('fluid temperature (K)');
    legend({'SMA-SHEX in','SMA-SHEX out','SMA-THE in','SMA-THE out', ...
        'SE-THE in','SE-THE out','SE-CHEX in','SE-CHEX out'}, ...
        'Location', 'bestoutside');
    title('Four-branch inlet/outlet fluid temperatures');
    exportgraphics(fig, path, 'Resolution', 160);
    close(fig);
end

function path = write_branch_internal_plot(result, tag)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(result.options.outputs_dir, ...
        [tag '_four_branch_internal_fluid_heatmaps.png']);
    fig = figure('Visible', 'off', 'Color', 'w');
    tiledlayout(2, 2);
    branch_arrays = {'SMA_SHEX_Tfluid_51','SMA_THE_Tfluid_51', ...
        'SE_THE_Tfluid_51','SE_CHEX_Tfluid_51'};
    titles = {'SMA-SHEX fluid','SMA-THE fluid','SE-THE fluid','SE-CHEX fluid'};
    for idx = 1:numel(branch_arrays)
        nexttile;
        imagesc(t, 1:result.options.node_count, Y(:, map.(branch_arrays{idx})).');
        set(gca, 'YDir', 'normal');
        colorbar;
        xlabel('time (s)');
        ylabel('node');
        title(titles{idx});
    end
    exportgraphics(fig, path, 'Resolution', 160);
    close(fig);
end

function path = write_residual_plot(result, tag)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(result.options.outputs_dir, [tag '_energy_residual_timeseries.png']);
    fig = figure('Visible', 'off', 'Color', 'w');
    plot(t, Y(:, map.energy_residual_W), 'LineWidth', 1.0);
    grid on;
    xlabel('time (s)');
    ylabel('residual (W)');
    title('Total branch/solid energy residual');
    exportgraphics(fig, path, 'Resolution', 160);
    close(fig);
end

function path = write_cycle_energy_plot(r3, r10)
    path = fullfile(r3.options.outputs_dir, 'eighth_round_cycle_energy_audit.png');
    c3 = r3.summary.cycle(end);
    c10 = average_cycle(r10.summary.cycle(end-2:end));
    labels = categorical({'raw Qh','raw Qr','formula Qh','formula Qr','THE reject'});
    labels = reordercats(labels, cellstr(labels));
    data = [c3.Qh_raw_loop_J, c3.Qr_raw_loop_J, ...
            c3.Qh_article_formula_J, c3.Qr_article_formula_J, c3.THE_reject_J; ...
            c10.Qh_raw_loop_J, c10.Qr_raw_loop_J, ...
            c10.Qh_article_formula_J, c10.Qr_article_formula_J, c10.THE_reject_J].';
    fig = figure('Visible', 'off', 'Color', 'w');
    bar(labels, data);
    grid on;
    ylabel('energy per cycle (J)');
    legend({'3-cycle last','10-cycle last-3 avg'}, 'Location', 'best');
    title('Eighth-round energy audit');
    exportgraphics(fig, path, 'Resolution', 160);
    close(fig);
end

function outputs = write_audit_tables(r3, r10)
    out_dir = r3.options.outputs_dir;
    outputs = struct();
    outputs.cycle_energy_csv = fullfile(out_dir, 'cycle_energy.csv');
    outputs.stage_energy_csv = fullfile(out_dir, 'stage_energy.csv');
    outputs.probe_timeseries_csv = fullfile(out_dir, 'probe_timeseries.csv');
    writetable([cycle_energy_table(r3, "3cycle"); ...
        cycle_energy_table(r10, "10cycle")], outputs.cycle_energy_csv);
    writetable(stage_energy_table(r3), outputs.stage_energy_csv);
    writetable(probe_timeseries_table(r3), outputs.probe_timeseries_csv);
end

function T = cycle_energy_table(result, run_label)
    cycles = result.summary.cycle(:);
    n = numel(cycles);
    run = repmat(string(run_label), n, 1);
    cycle_index = [cycles.cycle_index].';
    Qh_boundary_J = [cycles.Qh_boundary_J].';
    Qr_boundary_J = [cycles.Qr_boundary_J].';
    Qr_over_Qh = Qr_boundary_J ./ max(Qh_boundary_J, eps);
    Qh_article_formula_J = [cycles.Qh_article_formula_J].';
    Qr_article_formula_J = [cycles.Qr_article_formula_J].';
    Qh_formula_minus_raw_J = [cycles.Qh_formula_minus_raw_J].';
    Qr_formula_minus_raw_J = [cycles.Qr_formula_minus_raw_J].';
    THE_reject_J = [cycles.THE_reject_J].';
    SMA_sensible_J = [cycles.SMA_sensible_J].';
    SE_sensible_J = [cycles.SE_sensible_J].';
    latentA_J = [cycles.latentA_J].';
    latentR_J = [cycles.latentR_J].';
    mechanicalA_J = [cycles.mechanicalA_J].';
    mechanicalR_J = [cycles.mechanicalR_J].';
    branch_storage_J = [cycles.branch_storage_J].';
    energy_residual_J = [cycles.energy_residual_J].';
    energy_residual_fraction = [cycles.energy_residual_fraction].';
    delta_xM_a = [cycles.xM_a_max].' - [cycles.xM_a_min].';
    delta_xM_r = [cycles.xM_r_max].' - [cycles.xM_r_min].';
    sigma_r_load_MPa = [cycles.sigma_r_load_Pa].' ./ 1.0e6;
    max_Ta_spread_K = [cycles.max_Ta_spread_K].';
    max_Tr_spread_K = [cycles.max_Tr_spread_K].';
    Qh_rel_error = abs(Qh_boundary_J - result.summary.article_Qh_cycle_J) ./ ...
        result.summary.article_Qh_cycle_J;
    Qr_rel_error = abs(Qr_boundary_J - result.summary.article_Qr_cycle_J) ./ ...
        result.summary.article_Qr_cycle_J;
    QrQh_rel_error = abs(Qr_over_Qh - result.summary.article_Qr_over_Qh) ./ ...
        result.summary.article_Qr_over_Qh;
    T = table(run, cycle_index, Qh_boundary_J, Qr_boundary_J, Qr_over_Qh, ...
        Qh_article_formula_J, Qr_article_formula_J, ...
        Qh_formula_minus_raw_J, Qr_formula_minus_raw_J, ...
        Qh_rel_error, Qr_rel_error, QrQh_rel_error, THE_reject_J, ...
        SMA_sensible_J, SE_sensible_J, latentA_J, latentR_J, ...
        mechanicalA_J, mechanicalR_J, branch_storage_J, ...
        energy_residual_J, energy_residual_fraction, delta_xM_a, ...
        delta_xM_r, sigma_r_load_MPa, max_Ta_spread_K, max_Tr_spread_K);
end

function T = stage_energy_table(result)
    map = result.options.output;
    Y = result.Y;
    t = Y(:, map.time_s);
    dt = [0; diff(t)];
    stage = round(Y(:, map.stage_id));
    cycle = round(Y(:, map.cycle_index));
    rows = {};
    for c = unique(cycle(:)).'
        for st = 1:4
            idx = cycle == c & stage == st;
            if ~any(idx)
                continue;
            end
            first_idx = find(idx, 1, 'first');
            last_idx = find(idx, 1, 'last');
            rows(end + 1, :) = {c, st, active_branch_name(st), nnz(idx), ...
                t(first_idx), t(last_idx), ...
                integrate_power(Y(:, map.Q_shex_boundary_W), dt, idx), ...
                integrate_power(Y(:, map.Q_the_sma_boundary_W), dt, idx), ...
                integrate_power(Y(:, map.Q_the_se_boundary_W), dt, idx), ...
                integrate_power(Y(:, map.Q_chex_boundary_W), dt, idx), ...
                integrate_power(Y(:, map.Q_sma_shex_W), dt, idx), ...
                integrate_power(Y(:, map.Q_sma_the_W), dt, idx), ...
                integrate_power(Y(:, map.Q_se_the_W), dt, idx), ...
                integrate_power(Y(:, map.Q_se_chex_W), dt, idx), ...
                integrate_power(Y(:, map.SMA_sensible_W), dt, idx), ...
                integrate_power(Y(:, map.SE_sensible_W), dt, idx), ...
                integrate_power(Y(:, map.latentA_W), dt, idx), ...
                integrate_power(Y(:, map.latentR_W), dt, idx), ...
                integrate_power(Y(:, map.mechanicalA_W), dt, idx), ...
                integrate_power(Y(:, map.mechanicalR_W), dt, idx), ...
                integrate_power(Y(:, map.branch_storage_W), dt, idx), ...
                integrate_power(Y(:, map.energy_residual_W), dt, idx), ...
                Y(first_idx, map.Ta_mean_K), Y(last_idx, map.Ta_mean_K), ...
                Y(first_idx, map.Tr_mean_K), Y(last_idx, map.Tr_mean_K), ...
                Y(first_idx, map.xM_a_mean), Y(last_idx, map.xM_a_mean), ...
                Y(first_idx, map.xM_r_mean), Y(last_idx, map.xM_r_mean), ...
                Y(first_idx, map.SMA_SHEX_Tin_K), Y(last_idx, map.SMA_SHEX_Tout_K), ...
                Y(first_idx, map.SE_CHEX_Tin_K), Y(last_idx, map.SE_CHEX_Tout_K)};
        end
    end
    names = {'cycle_index','stage_id','active_branch','samples', ...
        'time_start_s','time_end_s','Q_shex_boundary_J', ...
        'Q_the_sma_boundary_J','Q_the_se_boundary_J','Q_chex_boundary_J', ...
        'Q_sma_shex_to_solid_J','Q_sma_the_to_solid_J', ...
        'Q_se_the_to_solid_J','Q_se_chex_to_solid_J', ...
        'SMA_sensible_J','SE_sensible_J','latentA_J','latentR_J', ...
        'mechanicalA_J','mechanicalR_J','branch_storage_J', ...
        'energy_residual_J','Ta_start_K','Ta_end_K','Tr_start_K', ...
        'Tr_end_K','xM_a_start','xM_a_end','xM_r_start','xM_r_end', ...
        'SMA_SHEX_Tin_start_K','SMA_SHEX_Tout_end_K', ...
        'SE_CHEX_Tin_start_K','SE_CHEX_Tout_end_K'};
    T = cell2table(rows, 'VariableNames', names);
end

function T = probe_timeseries_table(result)
    map = result.options.output;
    Y = result.Y;
    nodes = representative_nodes(result.options.node_count);
    T = table(Y(:, map.time_s), round(Y(:, map.cycle_index)), ...
        round(Y(:, map.stage_id)), Y(:, map.Ta_mean_K), Y(:, map.Tr_mean_K), ...
        Y(:, map.xM_a_mean), Y(:, map.xM_r_mean), ...
        Y(:, map.sigma_r_Pa) ./ 1.0e6, ...
        Y(:, map.Q_shex_boundary_W), Y(:, map.Q_chex_boundary_W), ...
        Y(:, map.SMA_SHEX_Tin_K), Y(:, map.SMA_SHEX_Tout_K), ...
        Y(:, map.SMA_THE_Tin_K), Y(:, map.SMA_THE_Tout_K), ...
        Y(:, map.SE_THE_Tin_K), Y(:, map.SE_THE_Tout_K), ...
        Y(:, map.SE_CHEX_Tin_K), Y(:, map.SE_CHEX_Tout_K), ...
        'VariableNames', {'time_s','cycle_index','stage_id','Ta_mean_K', ...
        'Tr_mean_K','xM_a_mean','xM_r_mean','sigma_r_MPa', ...
        'Q_shex_boundary_W','Q_chex_boundary_W','SMA_SHEX_Tin_K', ...
        'SMA_SHEX_Tout_K','SMA_THE_Tin_K','SMA_THE_Tout_K', ...
        'SE_THE_Tin_K','SE_THE_Tout_K','SE_CHEX_Tin_K','SE_CHEX_Tout_K'});
    for idx = 1:numel(nodes)
        node = nodes(idx);
        T.(sprintf('Ta_node_%02d_K', node)) = Y(:, map.Ta_51(node));
        T.(sprintf('Tr_node_%02d_K', node)) = Y(:, map.Tr_51(node));
    end
end

function name = active_branch_name(stage_id)
    names = {'SMA_SHEX','SE_THE','SMA_THE','SE_CHEX'};
    name = string(names{stage_id});
end

function report_path = write_report(result)
    options = result.r3.options;
    report_path = options.report_path;
    report_dir = fileparts(report_path);
    if ~exist(report_dir, 'dir')
        mkdir(report_dir);
    end
    [git_status, git_log] = git_snapshot(fileparts(fileparts(mfilename('fullpath'))));

    fid = fopen(report_path, 'w', 'n', 'UTF-8');
    cleaner = onCleanup(@() fclose(fid));
    if result.passed
        conclusion = '通过';
    else
        conclusion = '未通过';
    end
    inventory_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
        '项目文档', '当前主线文件清单.md');
    fprintf(fid, 'Current mainline physical validation report\n');
    fprintf(fid, 'Generated at: %s\n\n', datestr(now, 31));
    fprintf(fid, 'Conclusion: %s\n', conclusion);
    fprintf(fid, 'Mainline inventory: %s\n\n', inventory_path);
    fprintf(fid, 'Run command:\n');
    fprintf(fid, '  cd(''%s''); result = Validate_HeatDriveECC_EighthRound_Physics();\n\n', ...
        fileparts(mfilename('fullpath')));
    fprintf(fid, 'Active mainline:\n');
    fprintf(fid, '  model_name: %s\n  model_path: %s\n  outputs_dir: %s\n', ...
        result.r3.model_name, result.r3.model_path, options.outputs_dir);
    fprintf(fid, '  entrypoints: Run_HeatDriveECC_EighthRound_Simulink_Cycles / Validate_HeatDriveECC_EighthRound_Physics\n');
    fprintf(fid, '  note: no parallel model is created by this validation path.\n\n');
    fprintf(fid, 'Core implementation and energy convention:\n');
    fprintf(fid, '  Simulink uses FixedStepDiscrete and an Interpreted MATLAB Function block to call HeatDriveECC_EighthRound_CoreStep.\n');
    fprintf(fid, '  MATLAB configures parameters, launches sim(), collects outputs, recomputes hard checks, and writes reports.\n');
    fprintf(fid, '  Qh_boundary_J and Qr_boundary_J are raw-loop external boundary heat integrals only.\n');
    fprintf(fid, '  Qh_article_formula_J and Qr_article_formula_J are paper-formula audit fields and are not used as raw-loop hard checks.\n');
    fprintf(fid, '  Branch control volume: m_i cp dTf_i/dt = mdot cp (Tup - Tf_i) + Qboundary - Qsolid.\n\n');
    fprintf(fid, 'Four-stage route table:\n');
    fprintf(fid, '  Stage 1: SMA_SHEX active, PSC/SHEX boundary -> fluid -> SMA; SE mechanical loading.\n');
    fprintf(fid, '  Stage 2: SE_THE active, SE -> THE/HHEX hot side; SMA side isolated.\n');
    fprintf(fid, '  Stage 3: SMA_THE active, SMA -> THE/HHEX hot side; SE unload/pre-cools through coupling.\n');
    fprintf(fid, '  Stage 4: SE_CHEX active, cold-load inlet boundary -> CHEX fluid -> SE; raw Q_chex_boundary is cooling heat.\n\n');
    fprintf(fid, 'Final parameters and bounds:\n');
    fprintf(fid, '  m_dot_sma_shex=%.4g kg/s, m_dot_se_chex=%.4g kg/s\n', ...
        options.branch.m_dot_sma_shex_kg_per_s, options.branch.m_dot_se_chex_kg_per_s);
    fprintf(fid, '  UA_sma_shex=%.3g W/K, UA_sma_the=%.3g W/K, UA_se_chex=%.3g W/K\n', ...
        options.branch.UA_sma_shex_W_per_K, options.branch.UA_sma_the_W_per_K, ...
        options.branch.UA_se_chex_W_per_K);
    fprintf(fid, '  boundary_UA_shex=%.3g W/K, boundary_UA_chex=%.3g W/K, CHEX boundary T=%.3f K\n', ...
        options.branch.boundary_UA_shex_W_per_K, ...
        options.branch.boundary_UA_chex_W_per_K, options.branch.boundary_T_se_chex_K);
    fprintf(fid, '  rate_a_to_A=%.3g 1/s, rate_a_to_M=%.3g 1/s, rate_r_load=%.3g 1/s\n', ...
        options.constitutive.rate_a_to_A_1_per_s, ...
        options.constitutive.rate_a_to_M_1_per_s, ...
        options.constitutive.rate_r_load_1_per_s);
    fprintf(fid, '  rate_r_stage3=%.3g 1/s, rate_r_stage4=%.3g 1/s, unload_assist=%.3g MPa\n', ...
        options.constitutive.rate_r_stage3_unload_1_per_s, ...
        options.constitutive.rate_r_stage4_unload_1_per_s, ...
        options.constitutive.se_unload_assist_Pa / 1.0e6);
    fprintf(fid, '  bounds: m_dot [%.3g %.3g], UA_sma_shex [%.3g %.3g], UA_se_chex [%.3g %.3g], boundary_UA_chex [%.3g %.3g]\n\n', ...
        options.branch.calibration_bounds.m_dot_kg_per_s, ...
        options.branch.calibration_bounds.UA_sma_shex_W_per_K, ...
        options.branch.calibration_bounds.UA_se_chex_W_per_K, ...
        options.branch.calibration_bounds.boundary_UA_chex_W_per_K);
    fprintf(fid, 'Parameter search notes:\n');
    fprintf(fid, '  Initial eighth-round raw loop was outside target: Qh about 131.7 J/cycle, Qr about 0.61 J/cycle.\n');
    fprintf(fid, '  The FV branch and raw Qh/Qr calibration were corrected around SHEX boundary_UA, CHEX UA, and SE loading/unloading rate.\n');
    fprintf(fid, '  CHEX boundary at Tc limited Qr to about 1.6 J; CHEX cold-load inlet at T0 moved Qr into the 4-7 J range.\n');
    fprintf(fid, '  Final target is to keep 3-cycle and 10-cycle raw-loop metrics within the 30%% article window.\n\n');
    fprintf(fid, 'Known eighth-round repair status:\n');
    fprintf(fid, '  1. Formula audit values no longer replace boundary heat values.\n');
    fprintf(fid, '  2. The fluid branch uses an upwind control-volume update instead of a downstream-state-free plug-flow shortcut.\n');
    fprintf(fid, '  3. Raw Qh/Qr calibration is checked against paper targets.\n');
    fprintf(fid, '  4. Parameter bounds are aligned with defaults.\n');
    fprintf(fid, '  5. This report validates the current single mainline model and does not create another parallel model.\n\n');
    write_summary(fid, '3-cycle last cycle', result.r3.summary, result.r3.summary.cycle(end));
    c10avg = average_cycle(result.r10.summary.cycle(end-2:end));
    write_summary(fid, '10-cycle last-3 average heat / last state metrics', ...
        result.r10.summary, c10avg);
    fprintf(fid, 'Hard checks 3-cycle:\n');
    write_checks(fid, result.checks3);
    fprintf(fid, '\nHard checks 10-cycle:\n');
    write_checks(fid, result.checks10);
    fprintf(fid, '\nFigure files:\n');
    for idx = 1:numel(result.figures)
        fprintf(fid, '  %s\n', result.figures{idx});
    end
    fprintf(fid, '\nCSV/MAT outputs:\n');
    fprintf(fid, '  %s\n', result.audit_outputs.cycle_energy_csv);
    fprintf(fid, '  %s\n', result.audit_outputs.stage_energy_csv);
    fprintf(fid, '  %s\n', result.audit_outputs.probe_timeseries_csv);
    fprintf(fid, '  3-cycle MAT: %s\n', result.r3.output_mat);
    fprintf(fid, '  10-cycle MAT: %s\n', result.r10.output_mat);
    fprintf(fid, '\nSelf-check notes:\n');
    fprintf(fid, '  1. Forced assignment of validation results: no.\n');
    fprintf(fid, '  2. Post-processing overwrite of physical outputs: no.\n');
    fprintf(fid, '  3. Formula values used as boundary heat values: no; formula fields are audit-only.\n');
    fprintf(fid, '  4. New invalid parallel model created: no.\n');
    fprintf(fid, '  5. sim() called by the validation path: yes, through Run_HeatDriveECC_EighthRound_Simulink_Cycles.\n\n');
    fprintf(fid, 'Git status:\n%s\n', git_status);
    fprintf(fid, 'Recent commits:\n%s\n', git_log);
end

function write_summary(fid, label, summary, cycle_metrics)
    fprintf(fid, '%s:\n', label);
    fprintf(fid, '  Qh_boundary_J=%.4f, target=%.4f, relerr=%.3f\n', ...
        cycle_metrics.Qh_boundary_J, summary.article_Qh_cycle_J, ...
        relerr(cycle_metrics.Qh_boundary_J, summary.article_Qh_cycle_J));
    fprintf(fid, '  Qr_boundary_J=%.4f, target=%.4f, relerr=%.3f\n', ...
        cycle_metrics.Qr_boundary_J, summary.article_Qr_cycle_J, ...
        relerr(cycle_metrics.Qr_boundary_J, summary.article_Qr_cycle_J));
    fprintf(fid, '  Qr/Qh=%.4f, target=%.4f\n', ...
        cycle_metrics.Qr_boundary_J / max(cycle_metrics.Qh_boundary_J, eps), ...
        summary.article_Qr_over_Qh);
    fprintf(fid, '  delta_xM_a=%.4f, delta_xM_r=%.4f, sigma_r_load=%.3f MPa, Th=%.3f K\n', ...
        summary.last_delta_xM_a, summary.last_delta_xM_r, ...
        summary.last_sigma_r_load_Pa / 1.0e6, summary.max_Ta_mean_K);
    fprintf(fid, '  max Ta spread=%.4f K, max Tr spread=%.4f K, Eq7 max=%.3g\n', ...
        summary.max_Ta_spread_K, summary.max_Tr_spread_K, summary.max_abs_eq7_scaled);
    fprintf(fid, '  raw loop Qh=%.4f J, raw loop Qr=%.4f J\n', ...
        cycle_metrics.Qh_raw_loop_J, cycle_metrics.Qr_raw_loop_J);
    fprintf(fid, '  formula Qh=%.4f J, formula Qr=%.4f J, formula-raw=[%.4f, %.4f] J\n', ...
        cycle_metrics.Qh_article_formula_J, cycle_metrics.Qr_article_formula_J, ...
        cycle_metrics.Qh_formula_minus_raw_J, cycle_metrics.Qr_formula_minus_raw_J);
    fprintf(fid, '  energy residual fraction=%.3g\n\n', ...
        cycle_metrics.energy_residual_fraction);
end

function write_checks(fid, checks)
    names = fieldnames(checks);
    for idx = 1:numel(names)
        fprintf(fid, '  %-28s %d\n', names{idx}, checks.(names{idx}));
    end
end

function [status_text, log_text] = git_snapshot(repo_dir)
    [~, status_text] = system(sprintf('git -C "%s" status --short --branch', repo_dir));
    [~, log_text] = system(sprintf('git -C "%s" log --oneline -n 12', repo_dir));
end
