function result = Validate_HeatDriveECC_EighthRound_Physics()
% Independent hard-check validation for the eighth-round Simulink ECC model.

    r3 = Run_HeatDriveECC_EighthRound_Simulink_Cycles(struct('cycle_count', 3));
    r10 = Run_HeatDriveECC_EighthRound_Simulink_Cycles(struct('cycle_count', 10));

    checks3 = hard_checks(r3, false);
    checks10 = hard_checks(r10, true);
    figures = write_figures(r3, r10);

    result = struct();
    result.r3 = r3;
    result.r10 = r10;
    result.checks3 = checks3;
    result.checks10 = checks10;
    result.passed = all_checks_pass(checks3) && all_checks_pass(checks10);
    result.figures = figures;
    result.report_path = write_report(result);

    fprintf('Eighth-round validation passed: %d\n', result.passed);
    fprintf('Report: %s\n', result.report_path);
    if ~result.passed
        error('Validate:EighthRound:HardCheckFailed', ...
            'Eighth-round Simulink hard checks failed. See report for details.');
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

function figures = write_figures(r3, r10)
    out_dir = r3.options.outputs_dir;
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    figures = {};
    figures{end + 1} = write_node_heatmap(r3, '3cycle');
    figures{end + 1} = write_branch_temperature_plot(r3, '3cycle');
    figures{end + 1} = write_cycle_energy_plot(r3, r10);
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

function path = write_branch_temperature_plot(result, tag)
    map = result.options.output;
    t = result.time_s;
    Y = result.Y;
    path = fullfile(result.options.outputs_dir, [tag '_branch_inlet_outlet_temperatures.png']);
    fig = figure('Visible', 'off', 'Color', 'w');
    plot(t, Y(:, map.SMA_SHEX_Tin_K), '-', t, Y(:, map.SMA_SHEX_Tout_K), '--', ...
        t, Y(:, map.SMA_THE_Tin_K), '-', t, Y(:, map.SMA_THE_Tout_K), '--', ...
        t, Y(:, map.SE_THE_Tin_K), '-', t, Y(:, map.SE_THE_Tout_K), '--', ...
        t, Y(:, map.SE_RHE_Tin_K), '-', t, Y(:, map.SE_RHE_Tout_K), '--');
    grid on;
    xlabel('time (s)');
    ylabel('fluid temperature (K)');
    legend({'SMA-SHEX in','SMA-SHEX out','SMA-THE in','SMA-THE out', ...
        'SE-THE in','SE-THE out','SE-RHE in','SE-RHE out'}, ...
        'Location', 'bestoutside');
    title('Four-branch inlet/outlet fluid temperatures');
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
    fprintf(fid, 'Agent2 第八轮真实51节点Simulink仿真报告\n');
    fprintf(fid, '生成时间: %s\n\n', datestr(now, 31));
    fprintf(fid, '运行命令:\n');
    fprintf(fid, '  cd(''%s''); result = Validate_HeatDriveECC_EighthRound_Physics();\n\n', ...
        fileparts(mfilename('fullpath')));
    fprintf(fid, '模型名: %s\n模型路径: %s\n输出目录: %s\n\n', ...
        result.r3.model_name, result.r3.model_path, options.outputs_dir);
    fprintf(fid, '核心实现:\n');
    fprintf(fid, '  Simulink 使用 FixedStepDiscrete 和 Interpreted MATLAB Function 块推进 HeatDriveECC_EighthRound_CoreStep。\n');
    fprintf(fid, '  MATLAB 只负责参数、启动 sim()、收集输出、重算 hard checks 和写报告。\n');
    fprintf(fid, '  51 个 SMA 节点和 51 个 SE 节点分别输出 Ta/Tr/xM/sigma/epsilon/pai/r_xi。\n\n');
    fprintf(fid, '校准参数:\n');
    fprintf(fid, '  UA_sma_shex=%.3g W/K, UA_sma_the=%.3g W/K, UA_se_rhe=%.3g W/K\n', ...
        options.branch.UA_sma_shex_W_per_K, options.branch.UA_sma_the_W_per_K, ...
        options.branch.UA_se_rhe_W_per_K);
    fprintf(fid, '  rate_a_to_M=%.3g 1/s, rate_r_unload=%.3g 1/s, eta_hr=%.3f\n\n', ...
        options.constitutive.rate_a_to_M_1_per_s, ...
        options.constitutive.rate_r_stage3_unload_1_per_s, options.system.eta_hr);
    write_summary(fid, '3-cycle last cycle', result.r3.summary, result.r3.summary.cycle(end));
    c10avg = average_cycle(result.r10.summary.cycle(end-2:end));
    write_summary(fid, '10-cycle last-3 average heat / last state metrics', ...
        result.r10.summary, c10avg);
    fprintf(fid, 'Hard checks 3-cycle:\n');
    write_checks(fid, result.checks3);
    fprintf(fid, '\nHard checks 10-cycle:\n');
    write_checks(fid, result.checks10);
    fprintf(fid, '\n图文件:\n');
    for idx = 1:numel(result.figures)
        fprintf(fid, '  %s\n', result.figures{idx});
    end
    fprintf(fid, '\n自检返工记录:\n');
    fprintf(fid, '  1. 修正 SE 潜热符号，使加载放热、卸载吸热。\n');
    fprintf(fid, '  2. 将能量积分由 trapz 改为按 Simulink 步长 dt 矩形积分，避免阶段切换漏计。\n');
    fprintf(fid, '  3. 加入 Eq.24 热回收外部边界热量审计，同时保留 raw loop 边界热量。\n');
    fprintf(fid, '  4. 多周期漂移后重新校准统一参数集，并用 3-cycle/10-cycle Simulink 重验。\n\n');
    fprintf(fid, 'Git 状态:\n%s\n', git_status);
    fprintf(fid, '最近提交:\n%s\n', git_log);
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
    fprintf(fid, '  raw loop Qh=%.4f J, raw loop Qr=%.4f J, energy residual fraction=%.3g\n\n', ...
        cycle_metrics.Qh_raw_loop_J, cycle_metrics.Qr_raw_loop_J, ...
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
