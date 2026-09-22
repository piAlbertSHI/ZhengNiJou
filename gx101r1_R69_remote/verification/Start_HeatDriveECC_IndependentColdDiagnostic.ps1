[CmdletBinding()]
param(
    [string]$OutputRoot = '',
    [string]$InitialObservationRoot = '',
    [double]$Stage4Kp = -245,
    [double]$Stage4InitialKp = -225,
    [double]$Stage4TransitionDurationS = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'outputs'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $outputsRoot 'qian_coupled_native_endpoint_chamber_diag_20260923_v34'
}
if ([string]::IsNullOrWhiteSpace($InitialObservationRoot)) {
    $InitialObservationRoot = Join-Path $outputsRoot 'qian_coupled_native_endpoint_chamber_diag_20260922_v32'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$InitialObservationRoot = [IO.Path]::GetFullPath($InitialObservationRoot)
if (-not $OutputRoot.StartsWith($outputsRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Diagnostic output escaped repository outputs: $OutputRoot"
}
if (Test-Path -LiteralPath $OutputRoot) {
    throw "Refusing to overwrite an existing diagnostic output: $OutputRoot"
}
$sourceExecution = Join-Path $InitialObservationRoot 'cold_chamber_execution.json'
$sourceObservations = Join-Path $InitialObservationRoot 'native\observations.mat'
if (-not (Test-Path -LiteralPath $sourceExecution -PathType Leaf) -or
    -not (Test-Path -LiteralPath $sourceObservations -PathType Leaf)) {
    throw "Qualified cold source is incomplete: $InitialObservationRoot"
}
$sourceRecord = Get-Content -LiteralPath $sourceExecution -Raw | ConvertFrom-Json
if (-not [bool]$sourceRecord.collection_pass -or
    [int]$sourceRecord.stop_time_s -ne 10 -or
    -not [bool]$sourceRecord.conservative_buffers -or
    [string]$sourceRecord.buffer_mass_formulation -ne 'zero_based_offset' -or
    -not [bool]$sourceRecord.initial_flux_compensation -or
    [bool]$sourceRecord.production_recovery_allowed) {
    throw 'Initialization source does not satisfy the qualified independent cold diagnostic contract.'
}
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
$stdoutPath = Join-Path $OutputRoot 'matlab_stdout.log'
$stderrPath = Join-Path $OutputRoot 'matlab_stderr.log'
$sourceSha = (Get-FileHash -LiteralPath $sourceObservations -Algorithm SHA256).Hash
$gitHead = (& git -C $repoRoot rev-parse HEAD).Trim()

$contract = [ordered]@{
    schema = 'heatdrive_ecc_independent_cold_diagnostic_launcher_v1'
    generated_at = (Get-Date).ToString('o')
    execution_commit = $gitHead
    output_root = $OutputRoot
    initialization_source_root = $InitialObservationRoot
    initialization_source_observations_sha256 = $sourceSha
    c200_state_imported = $false
    checkpoint_saved = $false
    production_recovery_allowed = $false
    duration_s = 10
    cycle_count = 1
    network_absolute_pressure_MPa = 0.85
    formulation = 'specific_inventory'
    scale_inventory = $true
    buffer_mass_guess = $true
    buffer_mass_targets = $true
    pipe_energy_targets = $true
    conservative_buffers = $true
    initial_flux_compensation = $true
    buffer_mass_formulation = 'zero_based_offset'
    endpoint_chamber_diagnostic = $true
    endpoint_all_arms = $true
    stage2_kp = -126
    stage2_initial_kp = -126
    stage4_kp = $Stage4Kp
    stage4_initial_kp = $Stage4InitialKp
    stage4_transition_duration_s = $Stage4TransitionDurationS
}
$contract | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'launcher_contract.json') -Encoding utf8

function MatlabQuote([string]$Value) { return $Value.Replace("'", "''") }
$repoM = MatlabQuote $repoRoot
$outputM = MatlabQuote $OutputRoot
$sourceM = MatlabQuote $InitialObservationRoot
$kp = $Stage4Kp.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$initialKp = $Stage4InitialKp.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$transition = $Stage4TransitionDurationS.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$batch = @"
cd('$repoM'); addpath(genpath(pwd)); overrides=struct(); overrides.se_stage2_pressure_pi_kp_MPa_per_kgps=-126; overrides.se_stage2_pressure_pi_initial_kp_MPa_per_kgps=-126; overrides.se_stage2_pressure_pi_transition_start_s=0; overrides.se_stage2_pressure_pi_transition_duration_s=0; overrides.se_stage4_pressure_pi_kp_MPa_per_kgps=$kp; overrides.se_stage4_pressure_pi_initial_kp_MPa_per_kgps=$initialKp; overrides.se_stage4_pressure_pi_transition_start_s=0; overrides.se_stage4_pressure_pi_transition_duration_s=$transition; record=Run_HeatDriveECC_ColdChamberDiagnostic('$repoM','$outputM',10,true,true,true,true,'specific_inventory',0.85,overrides,false,true,'zero_based_offset',1,'$sourceM','normal',true,true); disp(jsonencode(struct('collection_pass',record.collection_pass,'completed_arms',numel(record.cases),'output_root','$outputM')));
"@.Trim()
$matlab = 'C:\Program Files\MATLAB\R2025b\bin\matlab.exe'
if (-not (Test-Path -LiteralPath $matlab -PathType Leaf)) { throw "MATLAB executable not found: $matlab" }
$started = Get-Date
& $matlab '-batch' $batch 1> $stdoutPath 2> $stderrPath
$exitCode = $LASTEXITCODE
$contract.completed_at = (Get-Date).ToString('o')
$contract.exit_code = $exitCode
$contract.wall_seconds = ((Get-Date) - $started).TotalSeconds
$contract | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'launcher_contract.json') -Encoding utf8
Write-Output ($contract | ConvertTo-Json -Depth 8)
exit $exitCode
