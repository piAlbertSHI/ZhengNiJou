[CmdletBinding()]
param(
    [string]$OutputRoot = '',
    [int[]]$RunIndices = @(1, 2, 3, 4, 5, 6, 7, 8),
    [int]$SegmentCycles = 20,
    [int]$MaximumAdditionalCycles = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot `
        'outputs\qian_table4_L8_sensitivity_20260822'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$expectedOutputs = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'outputs'))
if (-not $OutputRoot.StartsWith($expectedOutputs + `
        [System.IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Sensitivity output must remain inside repository outputs: $OutputRoot"
}
if ($RunIndices.Count -lt 1 -or
        @($RunIndices | Where-Object { $_ -lt 1 -or $_ -gt 8 }).Count -gt 0) {
    throw 'RunIndices must be a nonempty subset of 1..8.'
}
if ($SegmentCycles -lt 1 -or $MaximumAdditionalCycles -lt $SegmentCycles) {
    throw 'Cycle limits must be positive and maximum must cover one segment.'
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$stdoutPath = Join-Path $OutputRoot 'matlab_stdout.log'
$stderrPath = Join-Path $OutputRoot 'matlab_stderr.log'
if ((Test-Path -LiteralPath $stdoutPath) -or
        (Test-Path -LiteralPath $stderrPath)) {
    throw "Output log already exists. Refusing to overwrite: $OutputRoot"
}

function ConvertTo-MatlabString([string]$Value) {
    return $Value.Replace("'", "''")
}
$repoForMatlab = ConvertTo-MatlabString $repoRoot
$outputForMatlab = ConvertTo-MatlabString $OutputRoot
$runText = ($RunIndices | Sort-Object -Unique | ForEach-Object {
    $_.ToString([Globalization.CultureInfo]::InvariantCulture)
}) -join ' '
$batch = @"
cd('$repoForMatlab'); addpath('$repoForMatlab'); addpath(fullfile('$repoForMatlab','verification')); settings=struct('output_root','$outputForMatlab','run_indices',[$runText],'segment_cycles',$SegmentCycles,'maximum_additional_cycles',$MaximumAdditionalCycles,'run_candidates',true,'compact_raw_after_extraction',true); Run_HeatDriveECC_Table4_Sensitivity(settings);
"@.Trim()
$quotedBatch = '"' + $batch.Replace('"', '\"') + '"'

$matlab = 'C:\Program Files\MATLAB\R2025b\bin\matlab.exe'
$process = Start-Process -FilePath $matlab -ArgumentList @('-batch', $quotedBatch) `
    -WorkingDirectory $repoRoot -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru

[ordered]@{
    started_at = (Get-Date).ToString('o')
    worker_pid = $process.Id
    output_root = $OutputRoot
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    run_indices = $RunIndices
    segment_cycles = $SegmentCycles
    maximum_additional_cycles = $MaximumAdditionalCycles
    initial_state_policy = 'frozen_c200_only'
    compaction_policy = 'delete candidate raw after scalar/report extraction'
} | ConvertTo-Json -Depth 4
