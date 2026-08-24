[CmdletBinding()]
param(
    [string]$OutputRoot = '',
    [ValidateSet('l8', 'local_oat')]
    [string]$DesignKind = 'l8',
    [int[]]$RunIndices = @(),
    [int]$SegmentCycles = 20,
    [int]$MaximumAdditionalCycles = 40,
    [double[]]$FactorFraction = @(0.05, 0.05, 0.10, 0.10, 0.03, 0.05),
    [switch]$Resume
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($DesignKind -eq 'local_oat' -and
        -not $PSBoundParameters.ContainsKey('FactorFraction')) {
    $FactorFraction = @(0.005, 0.005, 0.01, 0.01, 0.005, 0.005)
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $defaultName = if ($DesignKind -eq 'local_oat') {
        'outputs\qian_table4_local_oat_sensitivity_20260824'
    } else {
        'outputs\qian_table4_L8_sensitivity_20260822'
    }
    $OutputRoot = Join-Path $repoRoot $defaultName
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$expectedOutputs = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'outputs'))
if (-not $OutputRoot.StartsWith($expectedOutputs + `
        [System.IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Sensitivity output must remain inside repository outputs: $OutputRoot"
}
$runLimit = if ($DesignKind -eq 'local_oat') { 12 } else { 8 }
if ($RunIndices.Count -eq 0) {
    $RunIndices = 1..$runLimit
}
if (@($RunIndices | Where-Object { $_ -lt 1 -or $_ -gt $runLimit }).Count -gt 0) {
    throw "RunIndices must be a subset of 1..$runLimit."
}
if ($SegmentCycles -lt 1 -or $MaximumAdditionalCycles -lt $SegmentCycles) {
    throw 'Cycle limits must be positive and maximum must cover one segment.'
}
if ($FactorFraction.Count -ne 6 -or
        @($FactorFraction | Where-Object { $_ -le 0 -or $_ -ge 0.5 }).Count -gt 0) {
    throw 'FactorFraction must contain six values strictly inside (0, 0.5).'
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$active = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
        $_.CommandLine -like "*$OutputRoot*"
    })
if ($active.Count -gt 0) {
    throw "A MATLAB process already references this output root: $OutputRoot"
}
$baseStdout = Join-Path $OutputRoot 'matlab_stdout.log'
$baseStderr = Join-Path $OutputRoot 'matlab_stderr.log'
if (-not $Resume -and ((Test-Path -LiteralPath $baseStdout) -or
        (Test-Path -LiteralPath $baseStderr))) {
    throw "Output log already exists. Refusing to overwrite: $OutputRoot"
}
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stdoutPath = if ($Resume) {
    Join-Path $OutputRoot "matlab_stdout_resume_$stamp.log"
} else {
    $baseStdout
}
$stderrPath = if ($Resume) {
    Join-Path $OutputRoot "matlab_stderr_resume_$stamp.log"
} else {
    $baseStderr
}

function ConvertTo-MatlabString([string]$Value) {
    return $Value.Replace("'", "''")
}
$repoForMatlab = ConvertTo-MatlabString $repoRoot
$outputForMatlab = ConvertTo-MatlabString $OutputRoot
$runText = ($RunIndices | Sort-Object -Unique | ForEach-Object {
    $_.ToString([Globalization.CultureInfo]::InvariantCulture)
}) -join ' '
$fractionText = ($FactorFraction | ForEach-Object {
    $_.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
}) -join ' '
$batch = @"
cd('$repoForMatlab'); addpath('$repoForMatlab'); addpath(fullfile('$repoForMatlab','verification')); settings=struct('output_root','$outputForMatlab','design_kind','$DesignKind','run_indices',[$runText],'factor_fraction',[$fractionText],'segment_cycles',$SegmentCycles,'maximum_additional_cycles',$MaximumAdditionalCycles,'run_candidates',true,'compact_raw_after_extraction',true); Run_HeatDriveECC_Table4_Sensitivity(settings);
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
    design_kind = $DesignKind
    segment_cycles = $SegmentCycles
    maximum_additional_cycles = $MaximumAdditionalCycles
    factor_fraction = $FactorFraction
    resume = [bool]$Resume
    initial_state_policy = 'frozen_c200_only'
    compaction_policy = 'delete candidate raw after scalar/report extraction'
} | ConvertTo-Json -Depth 4
