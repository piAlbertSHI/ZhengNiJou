param(
    [string]$RepoRoot = "E:\gx101r1_R69_remote",
    [string]$OutputRoot = "",
    [int]$MinCycles = 30
)

$ErrorActionPreference = "Stop"

function New-Dir([string]$PathValue) {
    New-Item -ItemType Directory -Force -Path $PathValue | Out-Null
}

function Write-Utf8NoBom([string]$PathValue, [string]$TextValue) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, $TextValue, $encoding)
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $RepoRoot "Output"
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path

$stamp = Get-Date -Format "yyyyMMdd_HHmm"
$outDir = Join-Path $OutputRoot ("cop_summary_" + $stamp)
New-Dir $outDir

$repoM = $RepoRoot -replace "\\", "/"
$outputM = $OutputRoot -replace "\\", "/"
$outM = $outDir -replace "\\", "/"

$matlabPath = Join-Path $outDir "compute_cop_summary.m"
$matlabPathM = $matlabPath -replace "\\", "/"

$matlabCode = @"
try
    restoredefaultpath;
    repoRoot = '$repoM';
    outputRoot = '$outputM';
    outDir = '$outM';
    minCycles = $MinCycles;
    addpath(repoRoot, '-begin');
    addpath(fullfile(repoRoot, 'Tools', 'validation'), '-begin');

    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    resultFiles = dir(fullfile(outputRoot, '**', 'result.mat'));
    rows = struct([]);
    skipped = struct([]);
    for idx = 1:numel(resultFiles)
        resultPath = fullfile(resultFiles(idx).folder, resultFiles(idx).name);
        try
            S = load(resultPath, 'run_result', 'run_options', 'runner_error');
            if ~isfield(S, 'run_result') || ~isstruct(S.run_result)
                skipped = append_struct(skipped, skip_row(resultPath, 'missing_run_result'));
                continue;
            end
            rr = S.run_result;
            cycles = reshape(get_field(rr, 'cycle_results', struct([])), 1, []);
            cycleCount = numel(cycles);
            if cycleCount < minCycles
                skipped = append_struct(skipped, skip_row(resultPath, sprintf('cycle_count_%d_lt_%d', cycleCount, minCycles)));
                continue;
            end
            row = summarize_one_result(resultPath, S, rr, cycles);
            rows = append_struct(rows, row);
        catch ME
            skipped = append_struct(skipped, skip_row(resultPath, ['load_error:', ME.message]));
        end
    end

    if isempty(rows)
        T = table();
    else
        T = struct2table(rows);
        T = sortrows(T, {'V_star', 'stage_time_s', 'case_label'});
    end
    csvPath = fullfile(outDir, 'cop_summary.csv');
    writetable(T, csvPath);

    if isempty(skipped)
        STable = table();
    else
        STable = struct2table(skipped);
    end
    writetable(STable, fullfile(outDir, 'cop_summary_skipped.csv'));
    write_markdown(fullfile(outDir, 'cop_summary.md'), T, STable, minCycles);

    fprintf('COP summary written to:\n%s\n', outDir);
    fprintf('Rows included: %d\n', height(T));
    if height(T) > 0
        disp(T(:, {'case_label','V_star','stage_time_s','cycle_count','COP_no_pump','COP_lower_bound','COP_eq14_measured','SCP_W_per_kg','cold_sink_final_K','cold_sink_delta_K'}));
    end
catch ME
    fid = fopen(fullfile('$outM', 'compute_cop_summary_error.txt'), 'w');
    fprintf(fid, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
    fclose(fid);
    rethrow(ME);
end

function row = summarize_one_result(resultPath, S, rr, cycles)
    [vStar, stageTime, label] = infer_case_metadata(resultPath, S, rr);
    cycleDiag = reshape(get_field(rr, 'cycle_diagnostics', struct([])), 1, []);
    q = NaN(1, numel(cycles));
    w1 = NaN(1, numel(cycles));
    wpump = NaN(1, numel(cycles));
    wpumpUpper = NaN(1, numel(cycles));
    scpTime = NaN(1, numel(cycles));
    stage2Flush = NaN(1, numel(cycles));
    stage4Flush = NaN(1, numel(cycles));
    stageWall = NaN(1, 4 * numel(cycles));
    mSMA = NaN;
    for cidx = 1:numel(cycles)
        reports = reshape(get_field(cycles(cidx), 'stage_reports', struct([])), 1, []);
        if numel(reports) >= 4
            loadR = reports(1);
            holdR = reports(2);
            coldR = reports(4);
            q(cidx) = first_finite([ ...
                get_field(coldR, 'Q_cool_for_COP_J', NaN), ...
                get_field(coldR, 'Q_sma_htf_stage4_J', NaN), ...
                abs(get_field(coldR, 'Q_stage4_SMA_to_HTF_J', NaN))]);
            w1(cidx) = first_finite([ ...
                get_field(loadR, 'W_load_input_J', NaN), ...
                abs(get_field(loadR, 'work_signed_J', NaN))]);
            wpump(cidx) = finite_sum([ ...
                abs(get_field(holdR, 'Wpump_estimated_J', NaN)), ...
                abs(get_field(coldR, 'Wpump_estimated_J', NaN))]);
            wpumpUpper(cidx) = pump_upper_bound(holdR) + pump_upper_bound(coldR);
            scpTime(cidx) = stage_duration(loadR) + stage_duration(holdR) + ...
                stage_duration(get_report_or_empty(reports, 3)) + stage_duration(coldR);
            stage2Flush(cidx) = first_finite([ ...
                get_field(holdR, 'actual_active_flush_volume_ratio_full_stage', NaN), ...
                get_field(holdR, 'actual_active_flush_volume_ratio', NaN)]);
            stage4Flush(cidx) = first_finite([ ...
                get_field(coldR, 'actual_active_flush_volume_ratio_full_stage', NaN), ...
                get_field(coldR, 'actual_active_flush_volume_ratio', NaN)]);
            base = (cidx - 1) * 4;
            for sidx = 1:min(4, numel(reports))
                stageWall(base + sidx) = get_field(reports(sidx), 'stage_walltime_s', NaN);
            end
            mSMA = first_finite([mSMA, get_field(coldR, 'sma_physical_mass_kg', NaN), ...
                get_field(loadR, 'sma_physical_mass_kg', NaN)]);
        elseif numel(cycleDiag) >= cidx
            d = cycleDiag(cidx);
            q(cidx) = get_field(d, 'Q_cool_for_COP_J', NaN);
            w1(cidx) = get_field(d, 'load_W_input_J', NaN);
            wpump(cidx) = finite_sum([get_field(d, 'hold_Wpump_estimated_J', NaN), ...
                get_field(d, 'cooldown_Wpump_estimated_J', NaN)]);
            stage2Flush(cidx) = get_field(d, 'hold_actual_active_flush_volume_ratio_full_stage', NaN);
            stage4Flush(cidx) = get_field(d, 'cooldown_actual_active_flush_volume_ratio_full_stage', NaN);
        end
    end
    if ~isfinite(mSMA)
        mSMA = 0.00653451271946677;
    end
    if all(~isfinite(scpTime))
        scpTime(:) = 0.2 + 2.0 * stageTime;
    else
        bad = ~isfinite(scpTime) | scpTime <= 0;
        scpTime(bad) = 0.2 + 2.0 * stageTime;
    end
    valid = isfinite(q) & isfinite(w1) & q > 0 & w1 > 0;
    measuredPumpValid = valid & isfinite(wpump);
    upperPumpValid = valid & isfinite(wpumpUpper);
    sumQ = sum(q(valid));
    sumW1 = sum(w1(valid));
    if any(measuredPumpValid) && nnz(measuredPumpValid) == nnz(valid)
        sumWpump = sum(wpump(valid));
        copMeasured = sumQ / (sumW1 + sumWpump);
        pumpStatus = "measured";
    else
        sumWpump = NaN;
        copMeasured = NaN;
        if any(upperPumpValid) && nnz(upperPumpValid) == nnz(valid)
            pumpStatus = "bounded_from_saturation";
        else
            pumpStatus = "missing";
        end
    end
    if any(upperPumpValid) && nnz(upperPumpValid) == nnz(valid)
        sumWpumpUpper = sum(wpumpUpper(valid));
        copLower = sumQ / (sumW1 + sumWpumpUpper);
    else
        sumWpumpUpper = NaN;
        copLower = NaN;
    end
    copNoPump = sumQ / sumW1;
    scp = sumQ / (mSMA * sum(scpTime(valid)));
    lastValid = find(valid, 1, 'last');
    lastCOPNoPump = NaN;
    lastCOPLower = NaN;
    if ~isempty(lastValid)
        lastCOPNoPump = q(lastValid) / w1(lastValid);
        if isfinite(wpumpUpper(lastValid))
            lastCOPLower = q(lastValid) / (w1(lastValid) + wpumpUpper(lastValid));
        end
    end

    row = struct();
    row.case_label = string(label);
    row.V_star = vStar;
    row.stage_time_s = stageTime;
    row.cycle_count = numel(cycles);
    row.valid_cycle_count = nnz(valid);
    row.COP_eq14_measured = copMeasured;
    row.COP_no_pump = copNoPump;
    row.COP_lower_bound = copLower;
    row.last_cycle_COP_no_pump = lastCOPNoPump;
    row.last_cycle_COP_lower_bound = lastCOPLower;
    row.SCP_W_per_kg = scp;
    row.Qcool_sum_J = sumQ;
    row.Qcool_mean_J = mean(q(valid));
    row.W1_sum_J = sumW1;
    row.W1_mean_J = mean(w1(valid));
    row.Wpump_sum_J = sumWpump;
    row.Wpump_upper_bound_sum_J = sumWpumpUpper;
    row.pump_status = string(pumpStatus);
    row.stage2_flush_mean = mean(stage2Flush(isfinite(stage2Flush)));
    row.stage4_flush_mean = mean(stage4Flush(isfinite(stage4Flush)));
    row.stage2_flush_last = last_finite(stage2Flush);
    row.stage4_flush_last = last_finite(stage4Flush);
    row.max_stage_walltime_s = max(stageWall(isfinite(stageWall)));
    row.cold_sink_final_K = first_finite([get_field(rr, 'final_cold_sink_temp', NaN), ...
        last_cycle_diag_field(cycleDiag, 'cold_sink_temp_after_coldflush')]);
    row.hot_sink_final_K = first_finite([get_field(rr, 'final_hot_sink_temp', NaN), ...
        last_cycle_diag_field(cycleDiag, 'hot_sink_temp_after_coldflush')]);
    row.cold_sink_delta_K = 293.0 - row.cold_sink_final_K;
    row.runner_ok = logical(get_field(rr, 'ok', true));
    row.runner_error_empty = strlength(string(get_field(S, 'runner_error', ''))) == 0;
    row.result_path = string(resultPath);
end

function [vStar, stageTime, label] = infer_case_metadata(resultPath, S, rr)
    vStar = NaN;
    stageTime = NaN;
    label = erase(string(resultPath), string(filesep + "result.mat"));
    if isfield(S, 'run_options') && isstruct(S.run_options)
        opts = S.run_options;
        ex = get_field(opts, 'exchange_options', struct());
        vStar = first_finite([vStar, get_field(ex, 'flush_volume_target_ratio', NaN)]);
        stageTime = first_finite([stageTime, get_field(ex, 'hotflush_stop_time_s', NaN), ...
            get_field(ex, 'coldflush_stop_time_s', NaN)]);
        label = string(get_field(opts, 'run_label', label));
    end
    cfg = get_field(rr, 'config', struct());
    ex2 = get_field(cfg, 'exchange_options', struct());
    vStar = first_finite([vStar, get_field(ex2, 'flush_volume_target_ratio', NaN)]);
    stageTime = first_finite([stageTime, get_field(ex2, 'hotflush_stop_time_s', NaN), ...
        get_field(ex2, 'coldflush_stop_time_s', NaN)]);
    label = string(get_field(cfg, 'run_label', label));
end

function value = pump_upper_bound(report)
    value = NaN;
    vol = first_finite([get_field(report, 'actual_active_flush_volume_m3_full_stage', NaN), ...
        get_field(report, 'actual_active_flush_volume_m3', NaN)]);
    dpMax = max(abs([get_field(report, 'pressure_pi_min_MPa', NaN), ...
        get_field(report, 'pressure_pi_max_MPa', NaN)]), [], 'omitnan');
    if isfinite(vol) && isfinite(dpMax)
        value = dpMax * 1.0e6 * vol;
    end
end

function duration = stage_duration(report)
    duration = get_field(report, 'stop_time_s', NaN);
    if ~isfinite(duration)
        duration = get_field(report, 'stage_duration_s', NaN);
    end
    if ~isfinite(duration)
        name = lower(char(string(get_field(report, 'stage_name', ''))));
        if contains(name, 'load') || contains(name, 'unload')
            duration = 0.1;
        end
    end
end

function report = get_report_or_empty(reports, idx)
    if numel(reports) >= idx
        report = reports(idx);
    else
        report = struct();
    end
end

function v = finite_sum(values)
    values = values(isfinite(values));
    if isempty(values)
        v = NaN;
    else
        v = sum(values);
    end
end

function v = first_finite(values)
    v = NaN;
    for k = 1:numel(values)
        if isnumeric(values(k)) && isfinite(values(k))
            v = values(k);
            return;
        end
    end
end

function v = last_finite(values)
    values = values(isfinite(values));
    if isempty(values)
        v = NaN;
    else
        v = values(end);
    end
end

function value = last_cycle_diag_field(cycleDiag, fieldName)
    value = NaN;
    if isempty(cycleDiag)
        return;
    end
    d = cycleDiag(end);
    value = get_field(d, fieldName, NaN);
end

function row = skip_row(pathValue, reason)
    row = struct('result_path', string(pathValue), 'reason', string(reason));
end

function rows = append_struct(rows, row)
    if isempty(rows)
        rows = row;
    else
        rows(end + 1) = row;
    end
end

function value = get_field(s, fieldName, defaultValue)
    if isstruct(s) && isfield(s, fieldName)
        value = s.(fieldName);
    else
        value = defaultValue;
    end
end

function write_markdown(pathValue, T, STable, minCycles)
    fid = fopen(pathValue, 'w', 'n', 'UTF-8');
    assert(fid > 0, 'Failed to open %s', pathValue);
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '# COP summary\n\n');
    fprintf(fid, '- Included runs: cycle_count >= %d\n', minCycles);
    fprintf(fid, '- COP_eq14_measured = Qcool / (W1 + measured Wpump), only when measured Wpump exists.\n');
    fprintf(fid, '- COP_no_pump = Qcool / W1.\n');
    fprintf(fid, '- COP_lower_bound = Qcool / (W1 + saturation-bound Wpump), used when PI pressure output is not logged.\n\n');
    if isempty(T) || height(T) == 0
        fprintf(fid, 'No completed runs found.\n');
    else
        fprintf(fid, '| case | V* | t_s | cycles | COP_no_pump | COP_lower | SCP_W/kg | cold_delta_K | pump_status |\n');
        fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---|\n');
        for i = 1:height(T)
            fprintf(fid, '| %s | %.4g | %.4g | %d | %.6g | %.6g | %.6g | %.6g | %s |\n', ...
                char(T.case_label(i)), T.V_star(i), T.stage_time_s(i), T.cycle_count(i), ...
                T.COP_no_pump(i), T.COP_lower_bound(i), T.SCP_W_per_kg(i), ...
                T.cold_sink_delta_K(i), char(T.pump_status(i)));
        end
    end
    if ~isempty(STable) && height(STable) > 0
        fprintf(fid, '\n## Skipped\n\n');
        fprintf(fid, '| result | reason |\n|---|---|\n');
        for i = 1:height(STable)
            fprintf(fid, '| %s | %s |\n', char(STable.result_path(i)), char(STable.reason(i)));
        end
    end
end
"@

Write-Utf8NoBom $matlabPath $matlabCode

$logPath = Join-Path $outDir "matlab_stdout.log"
$errPath = Join-Path $outDir "matlab_stderr.log"

Set-Location -LiteralPath $RepoRoot
matlab -batch "run('$matlabPathM')" 1> $logPath 2> $errPath

Write-Host "COP summary directory:"
Write-Host $outDir
Write-Host ""
Write-Host "Main files:"
Write-Host (Join-Path $outDir "cop_summary.csv")
Write-Host (Join-Path $outDir "cop_summary.md")
