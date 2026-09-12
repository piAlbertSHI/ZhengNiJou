[CmdletBinding()]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = Join-Path $repo 'outputs'
$auditRoot = Join-Path $repo 'outputs_storage_audit\runtime_observation_c200_retirement_20260912'
$contractPath = Join-Path $PSScriptRoot 'runtime_observation_c200_diagnostic_contract.json'
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
if ($contract.schema -ne 'heatdrive_ecc_runtime_state_observation_diagnostic_v1' -or
        -not $contract.raw_retirement.approved -or
        $contract.recovery_policy.state_recovery_allowed) {
    throw 'Runtime observation retirement is not authorized by its diagnostic contract.'
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
    ($_.CommandLine -match [regex]::Escape('qian_runtime_state_observation_from180_20260906') -or
        $_.CommandLine -match 'HeatDriveECC')
})
if ($Apply -and $running.Count -gt 0) {
    throw 'A HeatDriveECC MATLAB process is active; retirement is disabled.'
}

function Resolve-ManagedLeaf([string]$RelativePath) {
    $path = [IO.Path]::GetFullPath((Join-Path $repo $RelativePath))
    if (-not $path.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Retirement target escaped outputs: $path"
    }
    return $path
}

$targets = @(
    [pscustomobject]@{
        kind = 'non_authoritative_full_physical_timeseries'
        path = Resolve-ManagedLeaf $contract.result_relative_path
        bytes = [long]$contract.result_bytes
        sha256 = $contract.result_sha256
    },
    [pscustomobject]@{
        kind = 'recovery_prohibited_diagnostic_operating_point'
        path = Resolve-ManagedLeaf $contract.checkpoint_relative_path
        bytes = [long]$contract.checkpoint_bytes
        sha256 = $contract.checkpoint_sha256
    }
)
$observation = Resolve-ManagedLeaf $contract.observation_relative_path
if ((Get-Item -LiteralPath $observation).Length -ne [long]$contract.observation_bytes -or
        (Get-FileHash -LiteralPath $observation -Algorithm SHA256).Hash -ne $contract.observation_sha256) {
    throw 'Retained internal-state observation identity changed.'
}

$existing = @($targets | Where-Object { Test-Path -LiteralPath $_.path -PathType Leaf })
foreach ($target in $existing) {
    $file = Get-Item -LiteralPath $target.path
    if ($file.Length -ne $target.bytes -or
            (Get-FileHash -LiteralPath $target.path -Algorithm SHA256).Hash -ne $target.sha256) {
        throw "Retirement target identity changed: $($target.path)"
    }
}
$missingWithoutReceipt = @($targets | Where-Object { -not (Test-Path -LiteralPath $_.path -PathType Leaf) }).Count -gt 0 -and
    -not (Test-Path -LiteralPath (Join-Path $auditRoot 'retirement_receipt.json') -PathType Leaf)
if ($missingWithoutReceipt) { throw 'A target is missing without a retirement receipt.' }
$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'
if ($existing.Count -eq 0 -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)) {
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.schema -ne 'heatdrive_ecc_runtime_observation_raw_retirement_receipt_v1' -or
            $receipt.production_recovery_allowed -or $receipt.targets.Count -ne 2) {
        throw 'Existing runtime observation retirement receipt is invalid.'
    }
    foreach ($target in $targets) {
        $match = @($receipt.targets | Where-Object {
            [IO.Path]::GetFullPath($_.path) -eq $target.path -and
            [long]$_.bytes -eq $target.bytes -and $_.sha256 -eq $target.sha256
        })
        if ($match.Count -ne 1 -or (Test-Path -LiteralPath $target.path)) {
            throw 'Existing runtime observation retirement no longer matches the contract.'
        }
    }
    [ordered]@{
        applied = $false; already_retired = $true; planned_files = 2; deleted_files = 0
        retired_bytes = [long]$contract.result_bytes + [long]$contract.checkpoint_bytes
        retained_observation_bytes = (Get-Item -LiteralPath $observation).Length
        plan_path = Join-Path $auditRoot 'retirement_plan.json'; receipt_path = $receiptPath
    } | ConvertTo-Json -Depth 4
    return
}

New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
$plan = [ordered]@{
    schema = 'heatdrive_ecc_runtime_observation_raw_retirement_plan_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    reason = 'Retain unique internal-state observation and scalar audits; retire non-authoritative duplicated physical time series and recovery-prohibited OP.'
    retained_observation = [ordered]@{ path=$observation; bytes=[long]$contract.observation_bytes; sha256=$contract.observation_sha256 }
    targets = @($targets)
    deleted_bytes_planned = [long](($targets | Measure-Object bytes -Sum).Sum)
    production_recovery_allowed = $false
    table4_reproduction_claim = $false
}
$planPath = Join-Path $auditRoot 'retirement_plan.json'
$plan | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target.path -PathType Leaf) {
            if ((Get-FileHash -LiteralPath $target.path -Algorithm SHA256).Hash -ne $target.sha256) {
                throw 'Target changed after retirement plan creation.'
            }
            Remove-Item -LiteralPath $target.path -Force
        }
        if (Test-Path -LiteralPath $target.path) { throw 'Retirement deletion did not complete.' }
        $deleted.Add($target)
        [ordered]@{
            schema = 'heatdrive_ecc_runtime_observation_raw_retirement_receipt_v1'
            completed_at = (Get-Date).ToString('o')
            targets = @($deleted)
            retained_observation = $plan.retained_observation
            production_recovery_allowed = $false
        } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $auditRoot 'retirement_receipt.json') -Encoding utf8
    }
}

$deletedBytes = 0L
foreach ($target in $deleted) { $deletedBytes += [long]$target.bytes }
[ordered]@{
    applied = [bool]$Apply
    planned_files = $targets.Count
    deleted_files = $deleted.Count
    deleted_bytes = $deletedBytes
    deleted_GiB = [math]::Round($deletedBytes / 1GB, 6)
    retained_observation_bytes = (Get-Item -LiteralPath $observation).Length
    plan_path = $planPath
    receipt_path = $receiptPath
} | ConvertTo-Json -Depth 4
