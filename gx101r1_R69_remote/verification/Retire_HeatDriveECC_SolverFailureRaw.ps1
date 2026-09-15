[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$auditRoot = [IO.Path]::GetFullPath((Join-Path $repo 'outputs_storage_audit'))
$roots = @(
    'nonlinear_pre_feedback_ramp_20260910',
    'nonlinear_ramp_direct_bias_dynamic_20260910'
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
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
        $_.CommandLine -match [regex]::Escape($repo)
})
Require ($running.Count -eq 0) 'A repository MATLAB process is still running.'

$targets = foreach ($rootName in $roots) {
    $root = Get-ContainedPath $rootName
    $inspectionPath = Join-Path $root 'compiled_states_inspection.json'
    $preflightPath = Join-Path $root 'pre_simulation_inspection.json'
    $rawPath = Join-Path $root 'failed_public_observations.mat'
    Require (Test-Path -LiteralPath $inspectionPath -PathType Leaf) "Missing compiled-state inspection: $inspectionPath"
    Require (Test-Path -LiteralPath $preflightPath -PathType Leaf) "Missing pre-simulation inspection: $preflightPath"
    Require (Test-Path -LiteralPath $rawPath -PathType Leaf) "Missing failed raw observation: $rawPath"
    $inspection = Get-Content -LiteralPath $inspectionPath -Raw | ConvertFrom-Json
    $preflight = Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json
    Require ($inspection.schema -eq 'heatdrive_ecc_cold_compiled_states_v1') "Unexpected inspection schema: $inspectionPath"
    Require (-not [bool]$inspection.inspection_pass -and
        [bool]$inspection.simulation_run -and
        -not [bool]$inspection.failed_terminal_state_imported -and
        -not [bool]$inspection.c200_state_imported -and
        -not [bool]$inspection.production_recovery_allowed -and
        -not [bool]$inspection.checkpoint_saved) "Raw file is not a solver-failure rejection: $inspectionPath"
    Require (-not [bool]$preflight.inspection_pass -and
        -not [bool]$preflight.simulation_run -and
        -not [bool]$preflight.production_recovery_allowed -and
        -not [bool]$preflight.checkpoint_saved) "Preflight contract is not rejected: $preflightPath"
    $file = Get-Item -LiteralPath $rawPath
    [pscustomobject]@{
        package = $rootName
        relative_path = Join-Path $rootName 'failed_public_observations.mat'
        bytes = [int64]$file.Length
        sha256 = (Get-FileHash -LiteralPath $rawPath -Algorithm SHA256).Hash
        failure_stage = $inspection.stage
        reason = 'solver-failure diagnostic raw; no checkpoint, C200 import, promotion, recovery or interpolation eligibility'
        production_recovery_allowed = $false
    }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$package = Join-Path $auditRoot "solver_failure_raw_retirement_$stamp"
New-Item -ItemType Directory -Path $package -Force | Out-Null
$planPath = Join-Path $package 'retirement_plan.json'
$plan = [ordered]@{
    schema = 'heatdrive_ecc_solver_failure_raw_retirement_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    targets = @($targets)
    preserved = @('compiled-state inspection', 'pre-simulation inspection', 'MATLAB diary', 'component build metadata')
    production_recovery_allowed = $false
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $targets) {
        $path = Get-ContainedPath $target.relative_path
        Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $target.sha256) "Hash changed: $path"
        if ($PSCmdlet.ShouldProcess($path, 'Remove solver-failure diagnostic raw observation')) {
            Remove-Item -LiteralPath $path -Force
            Require (-not (Test-Path -LiteralPath $path)) "Deletion failed: $path"
            $deleted.Add($target)
        }
    }
}

$deletedBytes = if ($deleted.Count -gt 0) { ($deleted | Measure-Object bytes -Sum).Sum } else { 0 }
$receipt = [ordered]@{
    schema = 'heatdrive_ecc_solver_failure_raw_retirement_receipt_v1'
    completed_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    plan_path = $planPath
    targets = @($targets)
    deleted = @($deleted)
    deleted_bytes = [int64]$deletedBytes
    production_recovery_allowed = $false
}
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $package 'retirement_receipt.json') -Encoding utf8
$receipt | ConvertTo-Json -Depth 8
