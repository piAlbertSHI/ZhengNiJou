[CmdletBinding()]
param(
    [string]$OutputRoot = '',
    [int]$SegmentCycles = 20,
    [int]$MaximumCycles = 220,
    [string]$RecoveryContractPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($SegmentCycles -lt 1) {
    throw 'SegmentCycles must be positive.'
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'outputs'))
$contractPath = if ([string]::IsNullOrWhiteSpace($RecoveryContractPath)) {
    Join-Path $repoRoot 'verification\c200_mainline_freeze_contract.json'
} else {
    [IO.Path]::GetFullPath($RecoveryContractPath)
}
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$initialCycles = [int]$contract.completed_cycles
if ($MaximumCycles -le $initialCycles) {
    throw "MaximumCycles must exceed recovery cycle C$initialCycles."
}
if ($contract.PSObject.Properties.Name -contains 'mechanism_pass' -and
        -not [bool]$contract.mechanism_pass) {
    throw 'Recovery contract is not mechanism-valid.'
}

function Resolve-RepoPath([string]$RelativePath) {
    $path = [IO.Path]::GetFullPath((Join-Path $repoRoot ($RelativePath -replace '/', '\')))
    $prefix = $repoRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Freeze-contract path escaped repository: $path"
    }
    return $path
}

$priorResultPath = Resolve-RepoPath $contract.result_relative_path
$checkpointPath = Resolve-RepoPath $contract.checkpoint_relative_path
$expectedCheckpointHash = [string]$contract.checkpoint_sha256
$actualCheckpointHash = (Get-FileHash -LiteralPath $checkpointPath -Algorithm SHA256).Hash
if ($actualCheckpointHash -ne $expectedCheckpointHash) {
    throw "Frozen C200 checkpoint hash mismatch: $actualCheckpointHash"
}
$expectedResultHash = [string]$contract.result_sha256
$actualResultHash = (Get-FileHash -LiteralPath $priorResultPath -Algorithm SHA256).Hash
if ($actualResultHash -ne $expectedResultHash) {
    throw "Recovery result hash mismatch: $actualResultHash"
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $outputsRoot `
        "qian_coupled_source_heatflow_steady_from_c${initialCycles}_20260831"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$outputPrefix = $outputsRoot + [IO.Path]::DirectorySeparatorChar
if (-not $OutputRoot.StartsWith($outputPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must remain inside repository outputs: $OutputRoot"
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$stdoutPath = Join-Path $OutputRoot 'matlab_stdout.log'
$stderrPath = Join-Path $OutputRoot 'matlab_stderr.log'
if ((Test-Path -LiteralPath $stdoutPath) -or (Test-Path -LiteralPath $stderrPath)) {
    throw "Output logs already exist. Refusing to overwrite: $OutputRoot"
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
    $_.CommandLine -match [regex]::Escape($OutputRoot)
})
if ($running.Count -gt 0) {
    throw "A MATLAB process already references the output root: $OutputRoot"
}

function ConvertTo-MatlabString([string]$Value) {
    return $Value.Replace("'", "''")
}

$repoForMatlab = ConvertTo-MatlabString $repoRoot
$outputForMatlab = ConvertTo-MatlabString $OutputRoot
$priorForMatlab = ConvertTo-MatlabString $priorResultPath
$checkpointForMatlab = ConvertTo-MatlabString $checkpointPath
$contractForMatlab = ConvertTo-MatlabString $contractPath
$batch = @"
cd('$repoForMatlab'); addpath(pwd); addpath(fullfile(pwd,'verification')); settings=struct('Tchex_K',276.95,'output_root','$outputForMatlab','segment_cycles',$SegmentCycles,'maximum_cycles',$MaximumCycles,'required_consecutive_near_segments',1000,'resume_existing_state',true,'initial_prior_result_path','$priorForMatlab','initial_checkpoint_path','$checkpointForMatlab','initial_state_policy','validated_recovery_contract_only','mainline_contract_path','$contractForMatlab','checkpoint_transition_fields',{{}},'checkpoint_append_signal_fields',{{'Q_SHEX_source_to_sink_W','Q_SHEX_sink_to_fluid_W'}},'branch_overrides',struct('se_stage2_pressure_pi_kp_MPa_per_kgps',-136.0,'se_stage2_pressure_pi_initial_kp_MPa_per_kgps',-135.0,'se_stage2_pressure_pi_transition_start_s',1070.0,'se_stage2_pressure_pi_transition_duration_s',20.0,'se_stage4_pressure_pi_kp_MPa_per_kgps',-255.0,'se_stage4_pressure_pi_initial_kp_MPa_per_kgps',-255.0,'se_stage4_pressure_pi_transition_start_s',0.0,'se_stage4_pressure_pi_transition_duration_s',0.0)); Run_HeatDriveECC_Table4_FixedReservoirPoint(settings);
"@.Trim()

$runContract = [ordered]@{
    schema = 'heatdrive_ecc_source_heat_flow_validation_v1'
    created_at = (Get-Date).ToString('o')
    output_root = $OutputRoot
    initial_prior_result_path = $priorResultPath
    initial_checkpoint_path = $checkpointPath
    initial_checkpoint_sha256 = $actualCheckpointHash
    initial_result_sha256 = $actualResultHash
    initial_state_policy = 'validated_recovery_contract_only'
    initial_cycles = $initialCycles
    preserve_state_classes = @('thermal_capacity','buffer','constitutive','temperature','phase_fraction','independent_route_PI_memory')
    Tchex_K = 276.95
    segment_cycles = $SegmentCycles
    maximum_cycles = $MaximumCycles
    new_signal = 'shex_source_heat_flow_W; simlog/SHEX/HotSinkFluidLink/Q'
    topology_change_for_sink_to_fluid_signal = $false
    system_COP_status_before_production_audit = 'withheld'
}
$runContract | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot 'source_heat_flow_run_contract.json') -Encoding UTF8

$matlab = 'C:\Program Files\MATLAB\R2025b\bin\matlab.exe'
$process = Start-Process -FilePath $matlab -ArgumentList @('-batch', ('"' + $batch.Replace('"', '\"') + '"')) `
    -WorkingDirectory $repoRoot -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru

[ordered]@{
    started_at = (Get-Date).ToString('o')
    worker_pid = $process.Id
    output_root = $OutputRoot
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    initial_checkpoint_sha256 = $actualCheckpointHash
    segment_cycles = $SegmentCycles
    maximum_cycles = $MaximumCycles
    state_reset = $false
    source_heat_flow_signal = 'shex_source_heat_flow_W; simlog/SHEX/HotSinkFluidLink/Q'
} | ConvertTo-Json -Depth 6
