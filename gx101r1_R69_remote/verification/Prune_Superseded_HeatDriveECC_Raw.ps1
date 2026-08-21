<#
.SYNOPSIS
    Remove only raw arrays from explicitly superseded HeatDriveECC output roots.

.DESCRIPTION
    This script is intentionally narrow and non-resumable. It retains reports,
    summaries, contracts, progress/state files, markers and small Operating
    Points. The authoritative C200 output is not in the target list.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$outputRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\outputs'))
$targetNames = @(
    'qian_coupled_stage2_kp70_130_from_valid100_20260820',
    'qian_table4_fixed_Tc_276p950K_kp135_255_switch_smoke_from_valid102_20260821',
    'qian_table4_fixed_Tc_276p950K_kp225_235_steady_20260820',
    'qian_table4_fixed_Tc_276p950K_kp225_245_steady_20260821',
    'qian_table4_fixed_Tc_276p950K_steady_20260820',
    'qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821\qian2019_table2_table4_simscape_127cycle_20260821_081410',
    'qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821\qian2019_table2_table4_simscape_147cycle_20260821_090448',
    'qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821\qian2019_table2_table4_simscape_167cycle_20260821_100014',
    'qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821\qian2019_table2_table4_simscape_187cycle_20260821_111712'
)
$rawNames = @('physical_simscape_result.mat', 'stage_temperature_probes_50samples.csv')
$targets = [System.Collections.Generic.List[object]]::new()

foreach ($name in $targetNames) {
    $directory = Join-Path $outputRoot $name
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Cleanup root does not exist: $directory"
    }
    $markers = @(Get-ChildItem -LiteralPath $directory -File -Filter 'SUPERSEDED_BY_*.txt')
    if ($markers.Count -eq 0) {
        throw "Required superseded marker is missing: $directory"
    }
    foreach ($file in (Get-ChildItem -LiteralPath $directory -File -Recurse)) {
        if ($file.Name -in $rawNames) {
            $targets.Add($file)
        }
    }
}

$totalBytes = 0L
if ($targets.Count -gt 0) {
    $totalBytes = [int64](($targets | Measure-Object Length -Sum).Sum)
}
foreach ($file in $targets) {
    $resolved = [System.IO.Path]::GetFullPath($file.FullName)
    $allowedPrefix = $outputRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe cleanup path: $resolved"
    }
    if ($PSCmdlet.ShouldProcess($resolved, 'Remove superseded raw output')) {
        Remove-Item -LiteralPath $resolved -Force
    }
}

[pscustomobject]@{
    removed_files = $targets.Count
    released_gb = [math]::Round($totalBytes / 1GB, 3)
    output_root = $outputRoot
    targets = $targetNames -join ';'
} | ConvertTo-Json -Depth 4
