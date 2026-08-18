<#!
.SYNOPSIS
    Wait once, then inspect one HeatDriveECC long-task output root.

.DESCRIPTION
    This script deliberately produces no polling output while waiting. It does
    not send commands to MATLAB and never terminates a process. After the wait
    it prints one status snapshot containing process health, logs, progress, and
    result directories.
#>

[CmdletBinding()]
param(
    [string]$OutputRoot = 'C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs\qian_coupled_stage4_retuned_steady_from40_20260818',
    [int]$WaitMinutes = 30,
    [int]$LauncherPid = 22540,
    [int]$WorkerPid = 31108
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($WaitMinutes -lt 1) {
    throw 'WaitMinutes must be at least 1.'
}

$resolvedRoot = [System.IO.Path]::GetFullPath($OutputRoot)
Start-Sleep -Seconds ($WaitMinutes * 60)

$worker = Get-Process -Id $WorkerPid -ErrorAction SilentlyContinue
$launcher = Get-Process -Id $LauncherPid -ErrorAction SilentlyContinue
$stdoutPath = Join-Path $resolvedRoot 'matlab_stdout.log'
$stderrPath = Join-Path $resolvedRoot 'matlab_stderr.log'
$progressPath = Join-Path $resolvedRoot 'steady_continuation_progress.csv'
$statePath = Join-Path $resolvedRoot 'steady_continuation_state.mat'

$resultDirectories = @(Get-ChildItem -LiteralPath $resolvedRoot -Directory -ErrorAction SilentlyContinue)
$progressLines = @()
if (Test-Path -LiteralPath $progressPath) {
    $progressLines = @(Get-Content -LiteralPath $progressPath -ErrorAction SilentlyContinue)
}
$stdoutTail = @(Get-Content -LiteralPath $stdoutPath -Tail 12 -ErrorAction SilentlyContinue)
$stderrTail = @(Get-Content -LiteralPath $stderrPath -Tail 12 -ErrorAction SilentlyContinue)

$processState = if ($worker) {
    'worker_running'
} elseif ($resultDirectories.Count -gt 0 -or $progressLines.Count -gt 1) {
    'worker_finished_results_present'
} else {
    'worker_missing_without_results'
}

$report = [ordered]@{
    checked_at = (Get-Date).ToString('o')
    output_root = $resolvedRoot
    wait_minutes = $WaitMinutes
    state = $processState
    launcher = if ($launcher) {
        [ordered]@{ pid = $launcher.Id; responding = $launcher.Responding; cpu_seconds = $launcher.CPU }
    } else { $null }
    worker = if ($worker) {
        [ordered]@{
            pid = $worker.Id
            responding = $worker.Responding
            cpu_seconds = $worker.CPU
            working_set_gb = [math]::Round($worker.WorkingSet64 / 1GB, 3)
            private_memory_gb = [math]::Round($worker.PrivateMemorySize64 / 1GB, 3)
        }
    } else { $null }
    files = [ordered]@{
        stdout_exists = Test-Path -LiteralPath $stdoutPath
        stderr_exists = Test-Path -LiteralPath $stderrPath
        progress_exists = Test-Path -LiteralPath $progressPath
        state_exists = Test-Path -LiteralPath $statePath
    }
    result_directories = @($resultDirectories | ForEach-Object {
        [ordered]@{ name = $_.Name; last_write_time = $_.LastWriteTime.ToString('o') }
    })
    progress_tail = $progressLines | Select-Object -Last 3
    stdout_tail = $stdoutTail
    stderr_tail = $stderrTail
}

$report | ConvertTo-Json -Depth 8

if ($processState -eq 'worker_missing_without_results') {
    exit 2
}
exit 0
