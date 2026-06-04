param(
    [string]$RepoRoot = "",
    [string]$RunId = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$outputRoot = Join-Path $RepoRoot "Output"
if ([string]::IsNullOrWhiteSpace($RunId)) {
    $latest = Get-ChildItem -LiteralPath $outputRoot -Directory |
        Where-Object { $_.Name -like "r69_8v_50c_*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $latest) {
        throw "No r69_8v_50c_* batch found under $outputRoot"
    }
    $batchRoot = $latest.FullName
} else {
    $batchRoot = Join-Path $outputRoot $RunId
}

$launchPath = Join-Path $batchRoot "launch_status.csv"
if (-not (Test-Path -LiteralPath $launchPath)) {
    throw "Missing launch_status.csv: $launchPath"
}

$rows = Import-Csv -LiteralPath $launchPath | ForEach-Object {
    $summaryExists = Test-Path -LiteralPath $_.summary_json
    $summary = $null
    if ($summaryExists) {
        $summary = Get-Content -LiteralPath $_.summary_json -Raw | ConvertFrom-Json
    }
    $caseDir = $_.case_dir
    $stageCsv = Join-Path $caseDir "stages.csv"
    $cycleCount = 0
    $lastStage = ""
    if (Test-Path -LiteralPath $stageCsv) {
        $stageRows = Import-Csv -LiteralPath $stageCsv
        if ($stageRows.Count -gt 0) {
            $cycleCount = ($stageRows | ForEach-Object { [int]$_.cycle_index } | Measure-Object -Maximum).Maximum
            $lastStage = ($stageRows | Select-Object -Last 1).stage_name
        }
    }
    $stderrLen = if (Test-Path -LiteralPath $_.stderr) { (Get-Item -LiteralPath $_.stderr).Length } else { -1 }
    $proc = Get-Process -Id ([int]$_.process_id) -ErrorAction SilentlyContinue
    [pscustomobject]@{
        tag = $_.tag
        V_star = $_.V_star
        pid = $_.process_id
        running = ($null -ne $proc)
        summary = $summaryExists
        cycles_seen = $cycleCount
        last_stage = $lastStage
        stderr_bytes = $stderrLen
        all_ok = if ($summary) { $summary.all_ok } else { "" }
        wall_s = if ($summary) { [math]::Round([double]$summary.total_walltime_s, 1) } else { "" }
        cold_final_K = if ($summary) { [math]::Round([double]$summary.cold_sink_final_K, 3) } else { "" }
        cold_delta_K = if ($summary) { [math]::Round([double]$summary.cold_sink_delta_K, 3) } else { "" }
        retry = if ($summary) { $summary.retry_count } else { "" }
        comp = if ($summary) { $summary.compensation_count } else { "" }
        reused = if ($summary) { $summary.reused_count } else { "" }
    }
}

Write-Host "Batch: $batchRoot"
$rows | Format-Table -AutoSize
