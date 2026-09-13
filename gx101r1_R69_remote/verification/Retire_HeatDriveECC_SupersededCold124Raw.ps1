[CmdletBinding()]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$rootName = 'cold_chamber_fullcycle_tuned124_225_10s_0p85_20260913'
$root = [IO.Path]::GetFullPath((Join-Path $outputs $rootName))
$auditRoot = Join-Path $repo 'outputs_storage_audit\superseded_cold124_raw_retirement_20260913'
$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'
$expectedCommit = '56c21bb74016458b8e85861aaba15e8e77633faa'
$expectedHashes = [ordered]@{
    native = '33595F8BE38391C2AE18A9DB0AFCAE20108CC2F74E6B5458B89D15042A98815D'
    conservative = 'C37CD4B85E2D24BAE7B86906CF3CAE1E7FDD64EB624FDE96F152F3C25054BB0B'
}
$preservedRoots = @(
    'cold_chamber_fullcycle_tuned120_225_10s_0p85_20260912',
    'cold_chamber_fullcycle_tuned125_225_10s_0p85_20260912'
)

if (-not $root.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Unexpected cold diagnostic root: $root"
}

$executionPath = Join-Path $root 'cold_chamber_execution.json'
if (-not (Test-Path -LiteralPath $executionPath -PathType Leaf)) {
    throw "Missing execution contract: $executionPath"
}
$execution = Get-Content -LiteralPath $executionPath -Raw | ConvertFrom-Json
if ($execution.schema -ne 'heatdrive_ecc_independent_cold_chamber_v1' -or
        -not $execution.collection_pass -or
        $execution.execution_commit -ne $expectedCommit -or
        $execution.production_recovery_allowed -or
        $execution.checkpoint_saved -or
        $execution.periodic_steady_state -or
        $execution.table4_reproduction_claim) {
    throw 'The 124/225 execution contract is not the expected rejected diagnostic package.'
}

$checkpoint = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force |
    Where-Object { $_.Name -in @('final_operating_point.mat','operating_point.mat','checkpoint.mat') })
if ($checkpoint.Count -gt 0) { throw 'The rejected 124/225 package unexpectedly contains a checkpoint.' }

foreach ($name in $preservedRoots) {
    $preserved = [IO.Path]::GetFullPath((Join-Path $outputs $name))
    if (-not (Test-Path -LiteralPath $preserved -PathType Container)) {
        throw "Required preserved comparison root is missing: $preserved"
    }
    $observations = @(Get-ChildItem -LiteralPath $preserved -File -Recurse -Force |
        Where-Object { $_.Name -eq 'observations.mat' })
    if ($observations.Count -ne 2) {
        throw "Expected two retained observation files in: $preserved"
    }
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
    ($_.CommandLine -match [regex]::Escape($outputs) -or $_.CommandLine -match 'HeatDriveECC')
})
if ($Apply -and $running.Count -gt 0) { throw 'A HeatDriveECC MATLAB process is active.' }

if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.schema -ne 'heatdrive_ecc_superseded_cold124_raw_retirement_receipt_v1' -or
            $receipt.production_recovery_allowed -or $receipt.targets.Count -ne 2) {
        throw 'Existing 124/225 retirement receipt is invalid.'
    }
    $remaining = @($receipt.targets | Where-Object { Test-Path -LiteralPath $_.path })
    if ($remaining.Count -gt 0) { throw 'Existing 124/225 retirement is incomplete.' }
    $retiredBytes = ($receipt.targets | Measure-Object -Property bytes -Sum).Sum
    [ordered]@{
        applied = $false
        already_retired = $true
        retired_items = $receipt.targets.Count
        retired_bytes = [long]$retiredBytes
        retired_GiB = [math]::Round($retiredBytes / 1GB, 6)
        production_recovery_allowed = $false
        receipt_path = $receiptPath
    } | ConvertTo-Json -Depth 5
    return
}

$targets = [Collections.Generic.List[object]]::new()
foreach ($arm in $expectedHashes.Keys) {
    $path = Join-Path (Join-Path $root $arm) 'observations.mat'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing 124/225 observation file: $path"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $case = @($execution.cases | Where-Object { $_.arm -eq $arm })
    if ($case.Count -ne 1 -or $case[0].observation_sha256 -ne $expectedHashes[$arm] -or
            $actualHash -ne $expectedHashes[$arm]) {
        throw "Observation hash contract failed for arm: $arm"
    }
    $file = Get-Item -LiteralPath $path
    $targets.Add([pscustomobject]@{
        kind = 'superseded_cold_tuning_timeseries'
        arm = $arm
        path = $file.FullName
        bytes = $file.Length
        sha256 = $actualHash
    })
}

New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
$plan = [ordered]@{
    schema = 'heatdrive_ecc_superseded_cold124_raw_retirement_plan_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    superseded_root = $rootName
    reason = '124/225 worsened stage-2 RMS versus retained 125/225 and has no recovery eligibility'
    preserved_roots = $preservedRoots
    execution_commit = $expectedCommit
    targets = @($targets)
    production_recovery_allowed = $false
}
$planPath = Join-Path $auditRoot 'retirement_plan.json'
$plan | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $targets) {
        $path = [IO.Path]::GetFullPath($target.path)
        if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) { throw 'Target escaped the exact 124/225 root.' }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $target.sha256) {
            throw "124/225 raw changed after plan creation: $path"
        }
        Remove-Item -LiteralPath $path -Force
        if (Test-Path -LiteralPath $path) { throw "124/225 raw retirement did not complete: $path" }
        $deleted.Add($target)
    }

    $marker = Join-Path $root 'SUPERSEDED_RAW_COMPACTED.txt'
    @(
        'status=superseded_raw_compacted'
        'production_recovery_allowed=false'
        'preserved_execution_contract=true'
        'preserved_summary_and_audit=true'
        'replacement=outputs/cold_chamber_fullcycle_tuned125_225_10s_0p85_20260912'
        'receipt=outputs_storage_audit/superseded_cold124_raw_retirement_20260913/retirement_receipt.json'
    ) | Set-Content -LiteralPath $marker -Encoding utf8

    [ordered]@{
        schema = 'heatdrive_ecc_superseded_cold124_raw_retirement_receipt_v1'
        completed_at = (Get-Date).ToString('o')
        execution_commit = $expectedCommit
        targets = @($deleted)
        preserved_roots = $preservedRoots
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
    preserved_roots = $preservedRoots
    plan_path = $planPath
    receipt_path = $receiptPath
} | ConvertTo-Json -Depth 5
