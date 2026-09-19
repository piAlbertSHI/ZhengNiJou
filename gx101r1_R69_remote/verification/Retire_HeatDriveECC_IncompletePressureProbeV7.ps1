[CmdletBinding()]
param(
    [string]$TargetRoot = '',
    [string]$AuditRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($TargetRoot)) {
    $TargetRoot = Join-Path $repo 'outputs\cold_chamber_pressure_probe_seed_20260919_v7'
}
if ([string]::IsNullOrWhiteSpace($AuditRoot)) {
    $AuditRoot = Join-Path $repo 'outputs_storage_audit\incomplete_pressure_probe_v7_retirement_20260919'
}
$target = [IO.Path]::GetFullPath($TargetRoot)
$audit = [IO.Path]::GetFullPath($AuditRoot)
$expectedTarget = [IO.Path]::GetFullPath((Join-Path $repo 'outputs\cold_chamber_pressure_probe_seed_20260919_v7'))
$expectedRaw = [IO.Path]::GetFullPath((Join-Path $expectedTarget 'native\observations.mat'))
if ($target -ne $expectedTarget) { throw 'Refusing an unexpected retirement target.' }
if (-not $target.StartsWith(([IO.Path]::GetFullPath((Join-Path $repo 'outputs')) + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Retirement target must remain inside outputs.'
}
if (-not (Test-Path -LiteralPath (Join-Path $target 'cold_chamber_execution.json') -PathType Leaf)) {
    throw 'Missing v7 execution contract.'
}
$execution = Get-Content -LiteralPath (Join-Path $target 'cold_chamber_execution.json') -Raw | ConvertFrom-Json
if ($execution.collection_pass -or $execution.error_message -ne 'Missing prerequisite.' -or $execution.production_recovery_allowed -or $execution.checkpoint_saved) {
    throw 'v7 is not the expected incomplete, non-recovery run.'
}
$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and $_.CommandLine -match [regex]::Escape($target)
})
if ($running.Count -gt 0) { throw 'A MATLAB process still references the v7 target.' }
if (-not (Test-Path -LiteralPath $expectedRaw -PathType Leaf)) { throw 'Expected raw observation is missing.' }
$item = Get-Item -LiteralPath $expectedRaw
$hash = (Get-FileHash -LiteralPath $expectedRaw -Algorithm SHA256).Hash
if ($item.Length -ne 166129040 -or $hash -ne '4E4F2D3D0105CE39169A91530B1506A0CACDC78EFE45568533EB1EB8DBBAA61B') {
    throw 'v7 raw observation hash/size does not match the reviewed file.'
}
New-Item -ItemType Directory -Path $audit -Force | Out-Null
$receiptPath = Join-Path $audit 'retirement_receipt.json'
if (Test-Path -LiteralPath $receiptPath) { throw 'Refusing to overwrite a retirement receipt.' }
$receipt = [ordered]@{
    schema = 'heatdrive_ecc_incomplete_pressure_probe_retirement_v1'
    created_at = (Get-Date).ToString('o')
    target_root = $target
    reason = 'v7 stopped before collection because a prerequisite was missing; it is not a recovery or seed source.'
    preserved_contract = (Join-Path $target 'cold_chamber_execution.json')
    retired_files = @([ordered]@{ path = $expectedRaw; bytes = $item.Length; sha256 = $hash })
    expected_after = 'native observations raw removed; execution contract and compact metadata retained'
    recovery_allowed = $false
    seed_eligible = $false
}
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding utf8
Remove-Item -LiteralPath $expectedRaw -Force
if (Test-Path -LiteralPath $expectedRaw) { throw 'Raw observation was not removed.' }
$receipt | ConvertTo-Json -Depth 6
