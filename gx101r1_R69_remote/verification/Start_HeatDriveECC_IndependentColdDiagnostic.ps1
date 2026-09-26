[CmdletBinding()]
param(
    [string]$OutputRoot = '',
    [string]$InitialObservationRoot = '',
    [double]$Stage4Kp = -245,
    [double]$Stage4InitialKp = -225,
    [double]$Stage4Ki = -255,
    [double]$Stage4TransitionDurationS = 10,
    [double]$Stage4BlendInitial = 1.0,
    [double]$Stage4BlendFinal = 1.0,
    [ValidateSet('arithmetic_blend','logarithmic_endpoint')]
    [string]$Stage4ViscosityClosure = 'arithmetic_blend'
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
if ($Stage4BlendInitial -lt 0.0 -or $Stage4BlendInitial -gt 1.0 -or
    $Stage4BlendFinal -lt 0.0 -or $Stage4BlendFinal -gt 1.0) {
    throw 'Stage4 endpoint-viscosity blend weights must be within [0,1].'
}
if ($Stage4Ki -ge 0.0) {
    throw 'Stage4 Ki must be negative for the signed pressure-error convention.'
}
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
$outputParent = Split-Path -Parent $OutputRoot
New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
$stdoutTemp = "$OutputRoot.matlab_stdout.tmp"
$stderrTemp = "$OutputRoot.matlab_stderr.tmp"
if ((Test-Path -LiteralPath $stdoutTemp) -or (Test-Path -LiteralPath $stderrTemp)) {
    throw "Refusing to overwrite temporary diagnostic logs for: $OutputRoot"
}
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
    stage4_ki = $Stage4Ki
    stage4_transition_duration_s = $Stage4TransitionDurationS
    stage4_endpoint_viscosity_blend_initial = $Stage4BlendInitial
    stage4_endpoint_viscosity_blend_final = $Stage4BlendFinal
    stage4_endpoint_viscosity_closure_mode = $Stage4ViscosityClosure
}
function MatlabQuote([string]$Value) { return $Value.Replace("'", "''") }
$repoM = MatlabQuote $repoRoot
$outputM = MatlabQuote $OutputRoot
$sourceM = MatlabQuote $InitialObservationRoot
$kp = $Stage4Kp.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$initialKp = $Stage4InitialKp.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$ki = $Stage4Ki.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$transition = $Stage4TransitionDurationS.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$blendInitial = $Stage4BlendInitial.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$blendFinal = $Stage4BlendFinal.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$closureMode = MatlabQuote $Stage4ViscosityClosure
$batch = @"
cd('$repoM'); addpath(genpath(pwd)); overrides=struct(); overrides.se_stage2_pressure_pi_kp_MPa_per_kgps=-126; overrides.se_stage2_pressure_pi_initial_kp_MPa_per_kgps=-126; overrides.se_stage2_pressure_pi_transition_start_s=0; overrides.se_stage2_pressure_pi_transition_duration_s=0; overrides.se_stage4_pressure_pi_kp_MPa_per_kgps=$kp; overrides.se_stage4_pressure_pi_initial_kp_MPa_per_kgps=$initialKp; overrides.se_stage4_pressure_pi_ki_MPa_per_kgps_s=$ki; overrides.se_stage4_pressure_pi_transition_start_s=0; overrides.se_stage4_pressure_pi_transition_duration_s=$transition; overrides.se_stage4_endpoint_viscosity_blend_initial=$blendInitial; overrides.se_stage4_endpoint_viscosity_blend_final=$blendFinal; overrides.se_stage4_endpoint_viscosity_blend_start_s=0; overrides.se_stage4_endpoint_viscosity_blend_duration_s=0; overrides.se_stage4_endpoint_viscosity_closure_mode='$closureMode'; record=Run_HeatDriveECC_ColdChamberDiagnostic('$repoM','$outputM',10,true,true,true,true,true,'specific_inventory',0.85,overrides,false,true,'zero_based_offset',1,'$sourceM','normal',true,true); disp(jsonencode(struct('collection_pass',record.collection_pass,'completed_arms',numel(record.cases),'output_root','$outputM')));
"@.Trim()
$matlab = 'C:\Program Files\MATLAB\R2025b\bin\matlab.exe'
if (-not (Test-Path -LiteralPath $matlab -PathType Leaf)) { throw "MATLAB executable not found: $matlab" }
$started = Get-Date
& $matlab '-batch' $batch 1> $stdoutTemp 2> $stderrTemp
$exitCode = $LASTEXITCODE
$outputExists = Test-Path -LiteralPath $OutputRoot -PathType Container
if (-not $outputExists) { New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null }
Move-Item -LiteralPath $stdoutTemp -Destination (Join-Path $OutputRoot 'matlab_stdout.log') -Force
Move-Item -LiteralPath $stderrTemp -Destination (Join-Path $OutputRoot 'matlab_stderr.log') -Force
$contract.completed_at = (Get-Date).ToString('o')
$contract.exit_code = $exitCode
$contract.wall_seconds = ((Get-Date) - $started).TotalSeconds
$contract | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputRoot 'launcher_contract.json') -Encoding utf8
if ($exitCode -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $OutputRoot 'REJECTED_DO_NOT_RESUME.txt'))) {
    @(
        'status=rejected_launcher_or_model_failure'
        'production_recovery_allowed=false'
        'c200_state_imported=false'
        'checkpoint_saved=false'
        "exit_code=$exitCode"
        'do_not_use_as_initialization_source=true'
    ) | Set-Content -LiteralPath (Join-Path $OutputRoot 'REJECTED_DO_NOT_RESUME.txt') -Encoding utf8
}
Write-Output ($contract | ConvertTo-Json -Depth 8)
exit $exitCode
