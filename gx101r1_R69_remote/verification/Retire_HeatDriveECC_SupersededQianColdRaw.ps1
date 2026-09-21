[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$auditRoot = Join-Path $repo 'outputs_storage_audit\superseded_qian_cold_raw_retirement_20260922'
$targetRoots = @(
    'qian_coupled_retuned_cold_seed_20260919_v7'
    'qian_coupled_retuned_cold_20cycle_20260920_v9'
    'qian_coupled_retuned_cold_seed_20260920_v12'
    'qian_coupled_retuned_cold_20cycle_20260920_v13'
    'qian_coupled_retuned_cold_seed_20260920_v14'
)
$preservedRoots = @(
    'qian_coupled_retuned_cold_seed_20260920_v17'
    'qian_coupled_retuned_cold_20cycle_20260921_v19'
    'qian_coupled_retuned_cold_seed_20260921_v20'
    'qian_coupled_retuned_cold_preflight_20260922_v21'
    'qian_coupled_retuned_cold_seed_20260922_v22'
)

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-ContainedPath([string]$RelativePath) {
    $path = [IO.Path]::GetFullPath((Join-Path $outputs $RelativePath))
    Require $path.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) "Path escaped outputs: $path"
    return $path
}

function Get-RelativePath([string]$Path) {
    $base = [IO.Path]::GetFullPath($outputs).TrimEnd('\') + '\'
    return [Uri]::UnescapeDataString(([Uri]$base).MakeRelativeUri([Uri][IO.Path]::GetFullPath($Path)).ToString()).Replace('/', '\')
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $command = [string]$_.CommandLine
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and $command -and
    (@($targetRoots | Where-Object { $command -match [regex]::Escape($_) }).Count -gt 0)
})
if ($Apply -and $running.Count -gt 0) {
    throw 'A MATLAB process references a superseded qian cold package.'
}

$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'
if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
    $existing = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($existing.schema -eq 'heatdrive_ecc_superseded_qian_cold_raw_retirement_receipt_v1' -and
        [bool]$existing.applied) {
        foreach ($rootName in $targetRoots) {
            $root = Get-ContainedPath $rootName
            Require (Test-Path -LiteralPath $root -PathType Container) "Retired root is missing: $root"
            Require (-not (Get-ChildItem -LiteralPath $root -File -Recurse -Force |
                Where-Object { $_.Name -eq 'observations.mat' })) "Retired raw still exists: $rootName"
            Require (Test-Path -LiteralPath (Join-Path $root 'SUPERSEDED_RAW_COMPACTED.txt') -PathType Leaf) `
                "Retirement marker is missing: $rootName"
        }
        $existing | ConvertTo-Json -Depth 8
        return
    }
}

$targets = [Collections.Generic.List[object]]::new()
foreach ($rootName in $targetRoots) {
    $root = Get-ContainedPath $rootName
    Require (Test-Path -LiteralPath $root -PathType Container) "Missing target root: $root"
    $executionPath = Join-Path $root 'cold_chamber_execution.json'
    Require (Test-Path -LiteralPath $executionPath -PathType Leaf) "Missing execution contract: $executionPath"
    $execution = Get-Content -LiteralPath $executionPath -Raw | ConvertFrom-Json
    Require (-not [bool]$execution.production_recovery_allowed -and
        -not [bool]$execution.periodic_steady_state -and
        -not [bool]$execution.checkpoint_saved) "Target is not diagnostic-only: $rootName"
    $marker = @(
        (Join-Path $root 'REJECTED_DO_NOT_RESUME.txt')
        (Join-Path $root 'QUALIFIED_10S_PRESEED_ONLY.txt')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    $marker = @($marker)
    Require ($marker.Count -eq 1) "Target has no unique diagnostic marker: $rootName"
    foreach ($arm in @('native', 'conservative')) {
        $path = Join-Path (Join-Path $root $arm) 'observations.mat'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $file = Get-Item -LiteralPath $path
        $targets.Add([pscustomobject]@{
            root = $rootName
            arm = $arm
            relative_path = Get-RelativePath $path
            bytes = [int64]$file.Length
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            reason = 'superseded diagnostic trajectory; preserve execution contract, marker, scalar audits and hashes'
        })
    }
}
Require ($targets.Count -eq 10) "Expected ten dense observation files, found $($targets.Count)."

New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$planPath = Join-Path $auditRoot "retirement_plan_$stamp.json"
$plan = [ordered]@{
    schema = 'heatdrive_ecc_superseded_qian_cold_raw_retirement_plan_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    target_roots = $targetRoots
    preserved_roots = $preservedRoots
    targets = @($targets)
    production_recovery_allowed = $false
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $targets) {
        $path = Get-ContainedPath ([string]$target.relative_path)
        Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $target.sha256) "Hash changed after plan creation: $path"
        if ($PSCmdlet.ShouldProcess($path, 'Remove superseded qian cold observation')) {
            Remove-Item -LiteralPath $path -Force
            Require (-not (Test-Path -LiteralPath $path)) "Deletion failed: $path"
            $deleted.Add($target)
        }
    }
    foreach ($rootName in $targetRoots) {
        $markerPath = Join-Path (Get-ContainedPath $rootName) 'SUPERSEDED_RAW_COMPACTED.txt'
        @(
            'status=superseded_raw_compacted'
            'production_recovery_allowed=false'
            'preserved_execution_contract=true'
            'preserved_diagnostic_marker=true'
            'preserved_scalar_audit=true'
            'receipt=outputs_storage_audit/superseded_qian_cold_raw_retirement_20260922/retirement_receipt.json'
        ) | Set-Content -LiteralPath $markerPath -Encoding utf8
    }
}

$receipt = [ordered]@{
    schema = 'heatdrive_ecc_superseded_qian_cold_raw_retirement_receipt_v1'
    completed_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    plan_path = $planPath
    target_roots = $targetRoots
    preserved_roots = $preservedRoots
    targets = @($targets)
    deleted = @($deleted)
    deleted_bytes = [int64]$(if ($deleted.Count -gt 0) { ($deleted | Measure-Object bytes -Sum).Sum } else { 0 })
    production_recovery_allowed = $false
}
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 8
