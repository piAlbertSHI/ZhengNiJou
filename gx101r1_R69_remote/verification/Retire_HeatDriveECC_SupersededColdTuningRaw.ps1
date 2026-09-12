[CmdletBinding()]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$auditRoot = Join-Path $repo 'outputs_storage_audit\superseded_cold_tuning_raw_retirement_20260913'
$replacementRoots = @(
    'cold_chamber_fullcycle_tuned120_225_10s_0p85_20260912',
    'cold_chamber_fullcycle_tuned125_225_10s_0p85_20260912'
)
$supersededRoots = @(
    'cold_chamber_fullcycle_10s_0p85_20260912',
    'cold_chamber_fullcycle_tuned_10s_0p85_20260912',
    'cold_chamber_fullcycle_tuned100_220_10s_0p85_20260912',
    'cold_chamber_fullcycle_tuned110_255_10s_0p85_20260912'
)
$allRoots = @($supersededRoots + $replacementRoots)

foreach ($name in $allRoots) {
    $root = [IO.Path]::GetFullPath((Join-Path $outputs $name))
    if (-not $root.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Unexpected cold tuning root: $root"
    }
    $execution = Join-Path $root 'cold_chamber_execution.json'
    if (-not (Test-Path -LiteralPath $execution -PathType Leaf)) {
        throw "Missing execution contract: $execution"
    }
    $checkpoint = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force |
        Where-Object { $_.Name -in @('final_operating_point.mat','operating_point.mat','checkpoint.mat') })
    if ($checkpoint.Count -gt 0) { throw "Cold tuning unexpectedly contains a checkpoint: $root" }
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
    ($_.CommandLine -match [regex]::Escape($outputs) -or $_.CommandLine -match 'HeatDriveECC')
})
if ($Apply -and $running.Count -gt 0) { throw 'A HeatDriveECC MATLAB process is active.' }

$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'
if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.schema -ne 'heatdrive_ecc_superseded_cold_tuning_raw_retirement_receipt_v1' -or
            $receipt.production_recovery_allowed -or $receipt.targets.Count -ne 8) {
        throw 'Existing cold tuning retirement receipt is invalid.'
    }
    $remaining = @($receipt.targets | Where-Object { Test-Path -LiteralPath $_.path })
    if ($remaining.Count -gt 0) { throw 'Existing cold tuning retirement is incomplete.' }
    $retiredBytes = ($receipt.targets | Measure-Object -Property bytes -Sum).Sum
    [ordered]@{
        applied = $false; already_retired = $true; retired_items = $receipt.targets.Count
        retired_bytes = [long]$retiredBytes; retired_GiB = [math]::Round($retiredBytes / 1GB, 6)
        production_recovery_allowed = $false; receipt_path = $receiptPath
    } | ConvertTo-Json -Depth 5
    return
}

$targets = [Collections.Generic.List[object]]::new()
foreach ($name in $supersededRoots) {
    $root = Join-Path $outputs $name
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force |
            Where-Object { $_.Name -eq 'observations.mat' }) {
        $targets.Add([pscustomobject]@{
            kind = 'superseded_cold_tuning_timeseries'
            path = $file.FullName
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        })
    }
}
if ($targets.Count -ne 8) { throw "Expected 8 superseded observation files, found $($targets.Count)." }

New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
$plan = [ordered]@{
    schema = 'heatdrive_ecc_superseded_cold_tuning_raw_retirement_plan_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    superseded_roots = $supersededRoots
    preserved_roots = $replacementRoots
    targets = @($targets)
    production_recovery_allowed = $false
}
$planPath = Join-Path $auditRoot 'retirement_plan.json'
$plan | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $targets) {
        $path = [IO.Path]::GetFullPath($target.path)
        if (-not $path.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) { throw 'Target escaped outputs.' }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $target.sha256) {
            throw "Cold tuning raw changed after plan creation: $path"
        }
        Remove-Item -LiteralPath $path -Force
        if (Test-Path -LiteralPath $path) { throw "Cold tuning raw retirement did not complete: $path" }
        $deleted.Add($target)
    }
    foreach ($name in $supersededRoots) {
        $marker = Join-Path (Join-Path $outputs $name) 'SUPERSEDED_RAW_COMPACTED.txt'
        @(
            'status=superseded_raw_compacted'
            'production_recovery_allowed=false'
            'preserved_execution_contract=true'
            'preserved_summary_and_audit=true'
            'replacement=outputs/cold_chamber_fullcycle_tuned125_225_10s_0p85_20260912'
            'receipt=outputs_storage_audit/superseded_cold_tuning_raw_retirement_20260913/retirement_receipt.json'
        ) | Set-Content -LiteralPath $marker -Encoding utf8
    }
    [ordered]@{
        schema = 'heatdrive_ecc_superseded_cold_tuning_raw_retirement_receipt_v1'
        completed_at = (Get-Date).ToString('o')
        targets = @($deleted)
        production_recovery_allowed = $false
    } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $receiptPath -Encoding utf8
}

$deletedBytes = 0L
foreach ($target in $deleted) { $deletedBytes += [long]$target.bytes }
[ordered]@{
    applied = [bool]$Apply
    deleted_items = $deleted.Count
    deleted_bytes = $deletedBytes
    deleted_GiB = [math]::Round($deletedBytes / 1GB, 6)
    preserved_roots = $replacementRoots
    plan_path = $planPath
    receipt_path = $receiptPath
} | ConvertTo-Json -Depth 5
