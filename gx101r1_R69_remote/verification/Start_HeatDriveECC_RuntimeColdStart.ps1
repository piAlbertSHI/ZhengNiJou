[CmdletBinding()]
param(
    [string]$OutputRoot = '',
    [int]$SegmentCycles = 20,
    [int]$MaximumCycles = 260,
    [double]$TchexK = 276.95
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputsRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'outputs'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $outputsRoot `
        'qian_coupled_runtime_strict_coldstart_20260904'
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if (-not $OutputRoot.StartsWith($outputsRoot + `
        [System.IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Cold-start output must remain inside repository outputs: $OutputRoot"
}
if ($SegmentCycles -lt 1 -or $MaximumCycles -lt $SegmentCycles) {
    throw 'Cycle limits must be positive and maximum must cover one segment.'
}

$determinismPath = Join-Path $repoRoot `
    'outputs_storage_audit\runtime_builder_determinism_20260904\runtime_builder_determinism_audit.json'
$determinism = Get-Content -LiteralPath $determinismPath -Raw | ConvertFrom-Json
if (-not [bool]$determinism.production_runtime_cold_start_allowed -or
        -not [bool]$determinism.strict_restore_pass -or
        -not [bool]$determinism.model_checksum_equal) {
    throw 'Runtime builder determinism gate has not passed.'
}

$parameterContractPath = Join-Path $repoRoot `
    'verification\cold_boundary_runtime_c246_recovery_contract.json'
$parameterContract = Get-Content -LiteralPath $parameterContractPath -Raw |
    ConvertFrom-Json
if ([bool]$parameterContract.recovery_policy.state_recovery_allowed) {
    throw 'C246 must be recovery-disabled before it is used as parameter-only evidence.'
}
$parameterResult = Join-Path $repoRoot `
    ($parameterContract.result_relative_path.Replace('/', '\'))
$actualParameterHash = (Get-FileHash -LiteralPath $parameterResult `
    -Algorithm SHA256).Hash
if ($actualParameterHash -ne [string]$parameterContract.result_sha256) {
    throw 'C246 parameter-source result SHA-256 mismatch.'
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
$parameterForMatlab = ConvertTo-MatlabString $parameterResult
$tchexText = $TchexK.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$batch = @"
cd('$repoForMatlab'); addpath(genpath(pwd)); p=load('$parameterForMatlab','options'); base=p.options; base.system.cold_boundary_temperature_configurability='runtime'; base.system.cold_boundary_temperature_configurability_source='strict runtime cold start; no prior Operating Point'; base.simulation.checkpoint_restore_policy='strict'; settings=struct('Tchex_K',$tchexText,'output_root','$outputForMatlab','segment_cycles',$SegmentCycles,'maximum_cycles',$MaximumCycles,'required_consecutive_near_segments',1000,'generate_intermediate_figures',false,'compact_superseded_segments',true,'resume_existing_state',true,'initial_prior_result_path','','initial_checkpoint_path','','initial_state_policy','cold_start_no_checkpoint','mainline_contract_path','','model_overrides',base); Run_HeatDriveECC_Table4_FixedReservoirPoint(settings);
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
    maximum_cycles = $MaximumCycles
    Tchex_K = $TchexK
    state_initialization = 'independent_cold_start_no_checkpoint'
    old_operating_point_loaded = $false
    checkpoint_restore_policy = 'strict_after_first_segment'
    cold_boundary_temperature_configurability = 'runtime'
    compact_superseded_segments = $true
    parameter_source_result = $parameterResult
    parameter_source_sha256 = $actualParameterHash
    parameter_source_state_used = $false
} | ConvertTo-Json -Depth 4
