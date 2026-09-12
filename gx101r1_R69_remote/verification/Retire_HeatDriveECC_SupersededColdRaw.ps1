[CmdletBinding()]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$auditRoot = Join-Path $repo 'outputs_storage_audit\superseded_cold_raw_retirement_20260912'
$passingAuditPath = Join-Path $repo 'outputs_storage_audit\cold_onset_probe_audit_20260911.json'
$passingAudit = Get-Content -LiteralPath $passingAuditPath -Raw | ConvertFrom-Json
if (-not $passingAudit.cold_onset_probe_pass -or $passingAudit.production_recovery_allowed) {
    throw 'The replacement cold onset evidence is not qualified.'
}

$supersededRoots = @(
    'cold_chamber_diagnostic_0p5_20260911',
    'cold_chamber_diagnostic_0p75_20260911',
    'cold_chamber_diagnostic_normal_20260911',
    'cold_chamber_onset_0p75_20260911',
    'cold_chamber_smoke_20260911',
    'cold_chamber_smoke_normal_20260911'
)
$currentRoot = Join-Path $outputs 'cold_chamber_onset_specific_0p75_20260911'
$allRoots = @($supersededRoots | ForEach-Object { Join-Path $outputs $_ }) + @($currentRoot)
foreach ($root in $allRoots) {
    $resolved = [IO.Path]::GetFullPath($root)
    if (-not $resolved.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "Unexpected cold diagnostic root: $resolved"
    }
    $checkpoint = @(Get-ChildItem -LiteralPath $resolved -File -Recurse -Force |
        Where-Object { $_.Name -in @('final_operating_point.mat','operating_point.mat','checkpoint.mat') })
    if ($checkpoint.Count -gt 0) { throw "Cold diagnostic unexpectedly contains a checkpoint: $resolved" }
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
    ($_.CommandLine -match [regex]::Escape($outputs) -or $_.CommandLine -match 'HeatDriveECC')
})
if ($Apply -and $running.Count -gt 0) { throw 'A HeatDriveECC MATLAB process is active.' }

$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'
if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.schema -ne 'heatdrive_ecc_superseded_cold_raw_retirement_receipt_v1' -or
            $receipt.production_recovery_allowed -or $receipt.targets.Count -lt 7) {
        throw 'Existing superseded cold retirement receipt is invalid.'
    }
    $retiredBytes = 0L
    foreach ($target in $receipt.targets) {
        $path = [IO.Path]::GetFullPath($target.path)
        if (-not $path.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $path)) {
            throw 'Existing superseded cold retirement is incomplete or out of scope.'
        }
        $retiredBytes += [long]$target.bytes
    }
    [ordered]@{
        applied = $false; already_retired = $true; retired_items = $receipt.targets.Count
        retired_bytes = $retiredBytes; retired_GiB = [math]::Round($retiredBytes / 1GB, 6)
        replacement_pass = [bool]$passingAudit.cold_onset_probe_pass
        plan_path = Join-Path $auditRoot 'retirement_plan.json'; receipt_path = $receiptPath
    } | ConvertTo-Json -Depth 4
    return
}

$rawNames = @('observations.mat','failed_public_observations.mat')
$targets = [Collections.Generic.List[object]]::new()
foreach ($name in $supersededRoots) {
    $root = Join-Path $outputs $name
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force |
            Where-Object { $_.Name -in $rawNames }) {
        $targets.Add([pscustomobject]@{
            kind = 'superseded_cold_timeseries'
            path = $file.FullName
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        })
    }
}
$buildNames = @('cache','codegen')
foreach ($root in $allRoots) {
    $directories = @(Get-ChildItem -LiteralPath $root -Directory -Recurse -Force |
        Where-Object { $_.Name -in $buildNames } |
        Sort-Object { $_.FullName.Length })
    foreach ($directory in $directories) {
        $alreadyCovered = @($targets | Where-Object {
            $_.kind -eq 'regenerable_build_directory' -and
            $directory.FullName.StartsWith($_.path + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
        if ($alreadyCovered) { continue }
        $directoryBytes = 0L
        foreach ($file in Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Force) {
            $directoryBytes += $file.Length
        }
        $targets.Add([pscustomobject]@{
            kind = 'regenerable_build_directory'
            path = $directory.FullName
            bytes = $directoryBytes
            sha256 = ''
        })
    }
}

New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
$plan = [ordered]@{
    schema = 'heatdrive_ecc_superseded_cold_raw_retirement_plan_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    replacement_package = [IO.Path]::GetRelativePath($repo, $currentRoot)
    replacement_audit = [IO.Path]::GetRelativePath($repo, $passingAuditPath)
    targets = @($targets)
    production_recovery_allowed = $false
}
$planPath = Join-Path $auditRoot 'retirement_plan.json'
$plan | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in @($targets | Sort-Object { $_.path.Length } -Descending)) {
        $path = [IO.Path]::GetFullPath($target.path)
        if (-not $path.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) { throw 'Target escaped outputs.' }
        if (Test-Path -LiteralPath $path) {
            if ($target.kind -eq 'superseded_cold_timeseries' -and
                    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $target.sha256) {
                throw 'Cold raw changed after plan creation.'
            }
            Remove-Item -LiteralPath $path -Recurse -Force
        }
        if (Test-Path -LiteralPath $path) { throw 'Cold raw retirement did not complete.' }
        $deleted.Add($target)
    }
    foreach ($name in $supersededRoots) {
        $marker = Join-Path (Join-Path $outputs $name) 'SUPERSEDED_RAW_COMPACTED.txt'
        @(
            'status=superseded_raw_compacted'
            'production_recovery_allowed=false'
            'replacement=outputs/cold_chamber_onset_specific_0p75_20260911'
            'receipt=outputs_storage_audit/superseded_cold_raw_retirement_20260912/retirement_receipt.json'
        ) | Set-Content -LiteralPath $marker -Encoding utf8
    }
    [ordered]@{
        schema = 'heatdrive_ecc_superseded_cold_raw_retirement_receipt_v1'
        completed_at = (Get-Date).ToString('o')
        targets = @($deleted)
        replacement_audit_sha256 = (Get-FileHash -LiteralPath $passingAuditPath -Algorithm SHA256).Hash
        production_recovery_allowed = $false
    } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $auditRoot 'retirement_receipt.json') -Encoding utf8
}

$deletedBytes = 0L
foreach ($target in $deleted) { $deletedBytes += [long]$target.bytes }
[ordered]@{
    applied = [bool]$Apply
    deleted_items = $deleted.Count
    deleted_bytes = $deletedBytes
    deleted_GiB = [math]::Round($deletedBytes / 1GB, 6)
    replacement_pass = [bool]$passingAudit.cold_onset_probe_pass
    plan_path = $planPath
    receipt_path = $receiptPath
} | ConvertTo-Json -Depth 4
