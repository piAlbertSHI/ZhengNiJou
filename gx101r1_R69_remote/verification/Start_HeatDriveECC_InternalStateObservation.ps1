[CmdletBinding()]
param([string]$OutputRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = Join-Path $repo 'outputs'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $outputs 'qian_runtime_state_observation_from180_20260906'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (-not $OutputRoot.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Observation output must stay inside repository outputs.'
}
$dirty = @(git -C $repo status --porcelain)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) {
    throw 'Commit and review observation code before starting the production segment.'
}
$active = @(Get-CimInstance Win32_Process -Filter "Name='MATLAB.exe'" |
    Where-Object { $_.CommandLine -like "*$repo*" })
if ($active.Count -gt 0) {
    throw 'A MATLAB process already references this repository; do not compete with it.'
}
$drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($OutputRoot).TrimEnd('\').TrimEnd(':'))
if ($drive.Free -lt 12GB) { throw 'Keep at least 12 GiB free before collecting this segment.' }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
# CreateNew is the single-launch guard; a failed attempt requires explicit review.
$lockPath = Join-Path $OutputRoot 'observation_launch.json'
$stream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
try {
    $intent = [ordered]@{
        schema = 'heatdrive_ecc_state_observation_launch_v1'
        started_at = (Get-Date).ToString('o')
        code_commit = (git -C $repo rev-parse HEAD).Trim()
        source_contract = 'verification/runtime_c180_recovery_contract.json'
        source_cycles = 180
        target_cycles = 200
        name_scope = 'runtime observation C200; not the frozen paper C200 authority'
        strict_restore_required = $true
        capture_internal_states = $true
        native_simscape_history_cycles = 1
        state_reset = $false
        steady_parameter_study_allowed = $false
        complete_internal_state_periodicity_verified = $false
        preserve_c180_and_frozen_c200 = $true
    }
    $payload = [Text.Encoding]::UTF8.GetBytes(($intent | ConvertTo-Json -Depth 4))
    $stream.Write($payload, 0, $payload.Length)
} finally { $stream.Dispose() }
$stdout = Join-Path $OutputRoot 'matlab_stdout.log'
$stderr = Join-Path $OutputRoot 'matlab_stderr.log'
if ((Test-Path -LiteralPath $stdout) -or (Test-Path -LiteralPath $stderr)) {
    throw 'Existing logs must not be overwritten.'
}
$r = $repo.Replace("'", "''")
$o = $OutputRoot.Replace("'", "''")
$batch = "cd('$r'); addpath('verification'); Run_HeatDriveECC_InternalStateObservation('$o');"
$process = Start-Process -FilePath 'C:\Program Files\MATLAB\R2025b\bin\matlab.exe' `
    -ArgumentList @('-batch', ('"' + $batch + '"')) -WorkingDirectory $repo `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
    -WindowStyle Hidden -PassThru
$started = [ordered]@{worker_pid=$process.Id; output_root=$OutputRoot; launch_contract=$lockPath}
$started | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputRoot 'launch_process.json') -Encoding utf8
$started | ConvertTo-Json
