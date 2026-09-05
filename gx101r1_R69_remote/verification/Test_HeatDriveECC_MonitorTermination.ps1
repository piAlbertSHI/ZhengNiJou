[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$outputs = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\outputs'))
$fixture = Join-Path $outputs ('monitor_test_' + [guid]::NewGuid().ToString('N'))
$monitor = Join-Path $PSScriptRoot 'WaitAndCheck_HeatDriveECC.ps1'
# Only the test process bypasses the timer; production waits are unchanged.
function Start-Sleep { param([int]$Seconds) }
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture 'old_result') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $fixture 'matlab_stdout.log') | Out-Null
    New-Item -ItemType File -Path (Join-Path $fixture 'matlab_stderr.log') | Out-Null
    $snapshot = (& $monitor -OutputRoot $fixture -WaitMinutes 1) | ConvertFrom-Json
    if ($LASTEXITCODE -ne 2 -or $snapshot.state -ne 'worker_exited_without_stop') {
        throw 'A stale result directory concealed interrupted execution.'
    }
    Set-Content -LiteralPath (Join-Path $fixture 'matlab_stdout.log') -Value `
        'STEADY_CONTINUATION_STOP status=mechanism_failure cycles=40 reason=test'
    $snapshot = (& $monitor -OutputRoot $fixture -WaitMinutes 1) | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $snapshot.state -ne 'continuation_stopped' -or
            -not $snapshot.normal_stop_marker_present -or
            $snapshot.stop_marker -notmatch 'mechanism_failure') {
        throw 'Explicit mechanism failure was not reported with its stop reason.'
    }
    'MONITOR_TERMINATION_REGRESSION_PASS=1'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    if (-not $resolved.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $resolved) -notmatch '^monitor_test_[a-f0-9]{32}$') {
        throw 'Test cleanup escaped its unique fixture directory.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
