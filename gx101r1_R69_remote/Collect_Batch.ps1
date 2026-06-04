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

$summaryRows = Get-ChildItem -LiteralPath $batchRoot -Recurse -Filter summary.json | ForEach-Object {
    $j = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    [pscustomobject]@{
        tag = $j.tag
        V_star = $j.V_star
        nCycles = $j.nCycles
        all_ok = $j.all_ok
        wall_s = [math]::Round([double]$j.total_walltime_s, 1)
        max_stage_s = [math]::Round([double]$j.max_stage_walltime_s, 1)
        max_sim_s = [math]::Round([double]$j.max_simulink_walltime_s, 1)
        cold_final_K = [math]::Round([double]$j.cold_sink_final_K, 4)
        cold_delta_K = [math]::Round([double]$j.cold_sink_delta_K, 4)
        hot_final_K = [math]::Round([double]$j.hot_sink_final_K, 4)
        retry = $j.retry_count
        comp = $j.compensation_count
        reused = $j.reused_count
        min_step = $j.min_step_warning
        out_dir = $j.out_dir
    }
} | Sort-Object V_star

$csvPath = Join-Path $batchRoot "batch_summary.csv"
$mdPath = Join-Path $batchRoot "batch_summary.md"
$summaryRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$lines = @()
$lines += "# R69 remote 8x50 batch summary"
$lines += ""
$lines += "- batch: $batchRoot"
$lines += "- generated_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "| tag | V* | ok | wall_s | cold_final_K | cold_delta_K | hot_final_K | retry/comp/reused | min_step |"
$lines += "|---|---:|---:|---:|---:|---:|---:|---|---:|"
foreach ($r in $summaryRows) {
    $lines += ("| {0} | {1} | {2} | {3:N1} | {4:N4} | {5:N4} | {6:N4} | {7}/{8}/{9} | {10} |" -f `
        $r.tag, $r.V_star, $r.all_ok, $r.wall_s, $r.cold_final_K, $r.cold_delta_K, `
        $r.hot_final_K, $r.retry, $r.comp, $r.reused, $r.min_step)
}
$lines -join "`r`n" | Set-Content -LiteralPath $mdPath -Encoding UTF8

Write-Host "Wrote $csvPath"
Write-Host "Wrote $mdPath"
$summaryRows | Format-Table -AutoSize
