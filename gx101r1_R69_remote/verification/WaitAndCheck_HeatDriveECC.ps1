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
    [string]$OutputRoot = '',
    [int]$WaitMinutes = 30,
    [int]$LauncherPid = 0,
    [int]$WorkerPid = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($WaitMinutes -lt 1) {
    throw 'WaitMinutes must be at least 1.'
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputsRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'outputs'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $matlabProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '(?i)^matlab(?:\.exe)?$' })
    $outputDirectories = @(Get-ChildItem -LiteralPath $outputsRoot -Directory)
    $matches = foreach ($process in $matlabProcesses) {
        foreach ($directory in $outputDirectories) {
            if ($process.CommandLine -like "*$($directory.FullName)*") {
                [pscustomobject]@{
                    ProcessId = $process.ProcessId
                    CreationDate = $process.CreationDate
                    WorkingSetSize = $process.WorkingSetSize
                    OutputRoot = $directory.FullName
                }
            }
        }
    }
    $selected = $matches | Sort-Object `
        @{ Expression = { $_.CreationDate }; Descending = $true }, `
        @{ Expression = { $_.WorkingSetSize }; Descending = $true } |
        Select-Object -First 1
    if ($null -eq $selected) {
        throw 'Cannot discover an active HeatDriveECC output root; pass -OutputRoot explicitly.'
    }
    $OutputRoot = $selected.OutputRoot
}
$resolvedRoot = [System.IO.Path]::GetFullPath($OutputRoot)
if (-not $resolvedRoot.StartsWith(
        $outputsRoot + [System.IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must remain inside repository outputs: $resolvedRoot"
}
Start-Sleep -Seconds ($WaitMinutes * 60)

$launcher = if ($LauncherPid -gt 0) {
    Get-Process -Id $LauncherPid -ErrorAction SilentlyContinue
} else {
    $null
}
$rootLeaf = Split-Path -Leaf $resolvedRoot
$workerCim = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
    $_.ProcessId -ne $LauncherPid -and
    (($WorkerPid -gt 0 -and ($_.ProcessId -eq $WorkerPid -or
        $_.ParentProcessId -eq $WorkerPid)) -or
     $_.ParentProcessId -eq $LauncherPid -or
     $_.CommandLine -match [regex]::Escape($rootLeaf))
})
$workerPids = @($workerCim.ProcessId)
$workerCim = @($workerCim | Sort-Object `
    @{ Expression = { if ($_.ParentProcessId -eq $WorkerPid) { 0 } `
        elseif ($_.ParentProcessId -in $workerPids) { 1 } `
        elseif ($_.ProcessId -eq $WorkerPid) { 2 } else { 3 } } }, `
    @{ Expression = { $_.WorkingSetSize }; Descending = $true }, `
    @{ Expression = { $_.CreationDate } })
$worker = $null
foreach ($candidate in $workerCim) {
    $worker = Get-Process -Id $candidate.ProcessId -ErrorAction SilentlyContinue
    if ($worker) { break }
}
$stdoutPath = Join-Path $resolvedRoot 'matlab_stdout.log'
$stderrPath = Join-Path $resolvedRoot 'matlab_stderr.log'
$latestStdout = Get-ChildItem -LiteralPath $resolvedRoot -File `
    -Filter 'matlab_stdout*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$latestStderr = Get-ChildItem -LiteralPath $resolvedRoot -File `
    -Filter 'matlab_stderr*.log' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($latestStdout) { $stdoutPath = $latestStdout.FullName }
if ($latestStderr) { $stderrPath = $latestStderr.FullName }
$progressPath = Join-Path $resolvedRoot 'steady_continuation_progress.csv'
$statePath = Join-Path $resolvedRoot 'steady_continuation_state.mat'
if (-not (Test-Path -LiteralPath $progressPath)) {
    $latestProgress = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File `
        -Filter 'steady_continuation_progress.csv' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestProgress) {
        $progressPath = $latestProgress.FullName
        $statePath = Join-Path $latestProgress.DirectoryName `
            'steady_continuation_state.mat'
    }
}
if (-not (Test-Path -LiteralPath $statePath)) {
    $latestState = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File `
        -Filter 'steady_continuation_state.mat' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latestState) {
        $statePath = $latestState.FullName
    }
}

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
        progress_path = $progressPath
        state_path = $statePath
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
