[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$auditRoot = [IO.Path]::GetFullPath((Join-Path $repo 'outputs_storage_audit'))
$roots = @(
    'nonlinear_ramp_joint_delay_20260911',
    'nonlinear_ramp_staggered_delay_20260911',
    'nonlinear_ramp_pressure_delay_20260911',
    'nonlinear_ramp_hold_gate_delay_20260911'
)

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-ContainedPath([string]$RelativePath) {
    $absolute = [IO.Path]::GetFullPath((Join-Path $auditRoot $RelativePath))
    Require $absolute.StartsWith($auditRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) "Path escaped outputs_storage_audit: $absolute"
    return $absolute
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and $_.CommandLine -match [regex]::Escape($repo)
})
Require ($running.Count -eq 0) 'A repository MATLAB process is still running.'

$targets = foreach ($rootName in $roots) {
    $audit = Get-ContainedPath ("${rootName}_rejected_audit.json")
    Require (Test-Path -LiteralPath $audit -PathType Leaf) "Missing rejected audit: $audit"
    $record = Get-Content -LiteralPath $audit -Raw | ConvertFrom-Json
    Require ($record.schema -eq 'heatdrive_ecc_rejected_diagnostic_package_v1') "Unexpected audit schema: $audit"
    Require ([bool]$record.required_rejection_fields_verified -and
        [int]$record.checkpoint_files_found -eq 0 -and
        -not [bool]$record.states_promoted -and
        -not [bool]$record.c200_imported -and
        -not [bool]$record.production_recovery_allowed) "Audit is not an eligible rejected package: $audit"

    $rawRelative = Join-Path $rootName 'failed_public_observations.mat'
    $raw = Get-ContainedPath $rawRelative
    Require (Test-Path -LiteralPath $raw -PathType Leaf) "Missing rejected raw file: $raw"
    $file = Get-Item -LiteralPath $raw
    [pscustomobject]@{
        package = $rootName
        relative_path = $rawRelative
        bytes = [int64]$file.Length
        sha256 = (Get-FileHash -LiteralPath $raw -Algorithm SHA256).Hash
        reason = 'rejected diagnostic package; no checkpoint, promotion, C200 import, recovery or interpolation eligibility'
        production_recovery_allowed = $false
    }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$package = Join-Path $auditRoot "rejected_audit_raw_retirement_$stamp"
New-Item -ItemType Directory -Path $package -Force | Out-Null
$planPath = Join-Path $package 'retirement_plan.json'
$plan = [ordered]@{
    schema = 'heatdrive_ecc_rejected_audit_raw_retirement_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    targets = @($targets)
    preserved = @('rejected audit JSON', 'pre-simulation inspection', 'compiled-state inspection', 'MATLAB diary', 'component build metadata')
    production_recovery_allowed = $false
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $targets) {
        $path = Get-ContainedPath $target.relative_path
        Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $target.sha256) "Hash changed: $path"
        if ($PSCmdlet.ShouldProcess($path, 'Remove rejected audit raw observation')) {
            Remove-Item -LiteralPath $path -Force
            Require (-not (Test-Path -LiteralPath $path)) "Deletion failed: $path"
            $deleted.Add($target)
        }
    }
}

$deletedBytes = if ($deleted.Count -gt 0) { ($deleted | Measure-Object bytes -Sum).Sum } else { 0 }
$receipt = [ordered]@{
    schema = 'heatdrive_ecc_rejected_audit_raw_retirement_receipt_v1'
    completed_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    plan_path = $planPath
    targets = @($targets)
    deleted = @($deleted)
    deleted_bytes = [int64]$deletedBytes
    production_recovery_allowed = $false
}
$receiptPath = Join-Path $package 'retirement_receipt.json'
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 8
