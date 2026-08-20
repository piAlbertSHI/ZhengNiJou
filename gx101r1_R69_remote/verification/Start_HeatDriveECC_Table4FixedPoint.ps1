[CmdletBinding()]
param(
    [double]$TchexK = 276.95,
    [string]$OutputRoot = '',
    [int]$SegmentCycles = 20,
    [int]$MaximumCycles = 200,
    [string]$InitialPriorResultPath = '',
    [string]$InitialCheckpointPath = '',
    [double]$Stage2InitialKp = -130.0,
    [double]$Stage2FinalKp = -130.0,
    [double]$Stage2TransitionStartS = 0.0,
    [double]$Stage2TransitionDurationS = 0.0,
    [double]$Stage4InitialKp = -225.0,
    [double]$Stage4FinalKp = -245.0,
    [double]$Stage4TransitionStartS = 50.0,
    [double]$Stage4TransitionDurationS = 50.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $temperatureTag = ('{0:F3}' -f $TchexK).Replace('.', 'p')
    $dateTag = Get-Date -Format 'yyyyMMdd'
    $OutputRoot = Join-Path $repoRoot "outputs\qian_table4_fixed_Tc_${temperatureTag}K_$dateTag"
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$stdoutPath = Join-Path $OutputRoot 'matlab_stdout.log'
$stderrPath = Join-Path $OutputRoot 'matlab_stderr.log'
if ((Test-Path -LiteralPath $stdoutPath) -or (Test-Path -LiteralPath $stderrPath)) {
    throw "Output log already exists. Refusing to overwrite: $OutputRoot"
}

function ConvertTo-MatlabString([string]$Value) {
    return $Value.Replace("'", "''")
}

$repoForMatlab = ConvertTo-MatlabString $repoRoot
$outputForMatlab = ConvertTo-MatlabString $OutputRoot
$priorForMatlab = ConvertTo-MatlabString $InitialPriorResultPath
$checkpointForMatlab = ConvertTo-MatlabString $InitialCheckpointPath
$stage2InitialKpText = $Stage2InitialKp.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$stage2FinalKpText = $Stage2FinalKp.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$stage2TransitionStartText = $Stage2TransitionStartS.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$stage2TransitionDurationText = $Stage2TransitionDurationS.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$stage4InitialKpText = $Stage4InitialKp.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$stage4FinalKpText = $Stage4FinalKp.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$stage4TransitionStartText = $Stage4TransitionStartS.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$stage4TransitionDurationText = $Stage4TransitionDurationS.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
$batch = @"
addpath('$repoForMatlab'); addpath(fullfile('$repoForMatlab','verification')); branch=struct('se_stage2_pressure_pi_kp_MPa_per_kgps',$stage2FinalKpText,'se_stage2_pressure_pi_initial_kp_MPa_per_kgps',$stage2InitialKpText,'se_stage2_pressure_pi_transition_start_s',$stage2TransitionStartText,'se_stage2_pressure_pi_transition_duration_s',$stage2TransitionDurationText,'se_stage4_pressure_pi_kp_MPa_per_kgps',$stage4FinalKpText,'se_stage4_pressure_pi_initial_kp_MPa_per_kgps',$stage4InitialKpText,'se_stage4_pressure_pi_transition_start_s',$stage4TransitionStartText,'se_stage4_pressure_pi_transition_duration_s',$stage4TransitionDurationText); settings=struct('Tchex_K',$($TchexK.ToString('R',[Globalization.CultureInfo]::InvariantCulture)),'output_root','$outputForMatlab','segment_cycles',$SegmentCycles,'maximum_cycles',$MaximumCycles,'required_consecutive_near_segments',1000,'resume_existing_state',true,'initial_prior_result_path','$priorForMatlab','initial_checkpoint_path','$checkpointForMatlab','branch_overrides',branch); Run_HeatDriveECC_Table4_FixedReservoirPoint(settings);
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
    Tchex_K = $TchexK
    segment_cycles = $SegmentCycles
    maximum_cycles = $MaximumCycles
    initial_prior_result_path = $InitialPriorResultPath
    initial_checkpoint_path = $InitialCheckpointPath
    stage2_initial_Kp_MPa_per_kgps = $Stage2InitialKp
    stage2_final_Kp_MPa_per_kgps = $Stage2FinalKp
    stage2_transition_start_s = $Stage2TransitionStartS
    stage2_transition_duration_s = $Stage2TransitionDurationS
    stage4_initial_Kp_MPa_per_kgps = $Stage4InitialKp
    stage4_final_Kp_MPa_per_kgps = $Stage4FinalKp
    stage4_transition_start_s = $Stage4TransitionStartS
    stage4_transition_duration_s = $Stage4TransitionDurationS
} | ConvertTo-Json -Depth 4
