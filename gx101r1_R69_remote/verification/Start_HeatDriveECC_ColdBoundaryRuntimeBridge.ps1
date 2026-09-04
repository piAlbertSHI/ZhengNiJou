[CmdletBinding()]
param(
    [string]$OutputRoot = '',
    [int]$SegmentCycles = 3,
    [int]$MaximumAdditionalCycles = 12
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot `
        'outputs\qian_cold_boundary_runtime_bridge_from_c243_20260904'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$expectedOutputs = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'outputs'))
if (-not $OutputRoot.StartsWith($expectedOutputs + `
        [System.IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Bridge output must remain inside repository outputs: $OutputRoot"
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
$batch = @"
cd('$repoForMatlab'); addpath('$repoForMatlab'); addpath(fullfile('$repoForMatlab','verification')); settings=struct('output_root','$outputForMatlab','segment_cycles',$SegmentCycles,'maximum_additional_cycles',$MaximumAdditionalCycles); Run_HeatDriveECC_ColdBoundaryRuntimeBridge(settings);
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
    segment_cycles = $SegmentCycles
    maximum_additional_cycles = $MaximumAdditionalCycles
    authority_contract = 'verification/system_energy_c243_recovery_contract.json'
    Tc_policy = 'unchanged_276.95_K'
    migration = 'compiletime_to_runtime_temperature_configurability_only'
    strict_operating_point_restore_required = $true
    state_reset_claim = 'not_assumed; accepted only after strict checksum gates pass'
} | ConvertTo-Json -Depth 4
