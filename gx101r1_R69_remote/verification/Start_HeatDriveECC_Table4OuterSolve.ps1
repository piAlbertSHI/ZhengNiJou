[CmdletBinding()]
param(
    [double[]]$TcCandidatesK = @(275.5),
    [string]$OutputRoot = '',
    [int]$SegmentCycles = 11,
    [int]$MaximumAdditionalCycles = 80,
    [ValidateSet('eq10_SCP_W_per_g', 'eq9_lift_K')]
    [string]$TargetMetric = 'eq10_SCP_W_per_g'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot `
        'outputs\qian_table4_zero_load_outer_solve_20260822'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$expectedOutputs = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'outputs'))
if (-not $OutputRoot.StartsWith($expectedOutputs + `
        [System.IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Outer-solve output must remain inside repository outputs: $OutputRoot"
}
if ($TcCandidatesK.Count -lt 1 -or
        @($TcCandidatesK | Where-Object { $_ -lt 255.05 -or $_ -gt 303.15 }).Count -gt 0) {
    throw 'All Tc candidates must be inside [255.05, 303.15] K.'
}
if ($SegmentCycles -lt 1 -or $MaximumAdditionalCycles -lt 11) {
    throw 'SegmentCycles must be positive and MaximumAdditionalCycles must be at least 11.'
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
$candidateText = ($TcCandidatesK | ForEach-Object {
    $_.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
}) -join ' '
$batch = @"
cd('$repoForMatlab'); addpath('$repoForMatlab'); addpath(fullfile('$repoForMatlab','verification')); settings=struct('output_root','$outputForMatlab','Tc_candidates_K',[$candidateText],'target_metric','$TargetMetric','segment_cycles',$SegmentCycles,'maximum_additional_cycles',$MaximumAdditionalCycles,'run_candidates',true); Run_HeatDriveECC_Table4_OuterSolve(settings);
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
    Tc_candidates_K = $TcCandidatesK
    segment_cycles = $SegmentCycles
    maximum_additional_cycles = $MaximumAdditionalCycles
    effective_minimum_boundary_transition_cycles = [Math]::Max($SegmentCycles, 11)
    target_metric = $TargetMetric
    endpoint_name = if ($TargetMetric -eq 'eq9_lift_K') { 'zero_lift' } else { 'zero_load' }
    initial_state_policy = 'validated_C200_mainline_recovery_reference_only'
} | ConvertTo-Json -Depth 4
