[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$auditRoot = Join-Path $repo 'outputs_storage_audit\rejected_cold_fullcycle_raw_retirement_20260916'
$targetRoots = @(
    'cold_chamber_flux_compensated_fullcycle_0p85_20260913_v8',
    'cold_chamber_flux_compensated_fullcycle_kp126_225_0p85_20260914_v9',
    'cold_chamber_mass_offset_fullcycle_kp126_225_0p85_20260914_v12'
)

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-ContainedPath([string]$RelativePath) {
    $absolute = [IO.Path]::GetFullPath((Join-Path $outputs $RelativePath))
    Require $absolute.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) "Path escaped outputs: $absolute"
    return $absolute
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
    ($_.CommandLine -match [regex]::Escape($outputs) -or $_.CommandLine -match 'HeatDriveECC')
})
if ($Apply -and $running.Count -gt 0) {
    throw 'A HeatDriveECC MATLAB process is active.'
}

$targets = [Collections.Generic.List[object]]::new()
foreach ($rootName in $targetRoots) {
    $root = Get-ContainedPath $rootName
    Require (Test-Path -LiteralPath $root -PathType Container) "Missing target root: $root"
    $marker = Join-Path $root 'REJECTED_DO_NOT_RESUME.txt'
    $execution = Join-Path $root 'cold_chamber_execution.json'
    Require (Test-Path -LiteralPath $marker -PathType Leaf) "Missing rejection marker: $root"
    Require (Test-Path -LiteralPath $execution -PathType Leaf) "Missing execution contract: $root"
    $executionRecord = Get-Content -LiteralPath $execution -Raw | ConvertFrom-Json
    Require (-not [bool]$executionRecord.production_recovery_allowed -and
        -not [bool]$executionRecord.periodic_steady_state -and
        -not [bool]$executionRecord.checkpoint_saved) "Target is not a rejected raw-only package: $root"
    $checkpoints = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force |
        Where-Object { $_.Name -in @('final_operating_point.mat','operating_point.mat','checkpoint.mat') })
    Require ($checkpoints.Count -eq 0) "Checkpoint found in rejected target: $root"

    foreach ($relative in @('native\observations.mat','conservative\observations.mat')) {
        $path = Get-ContainedPath (Join-Path $rootName $relative)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $file = Get-Item -LiteralPath $path
        $targets.Add([pscustomobject]@{
            root = $rootName
            relative_path = Join-Path $rootName $relative
            bytes = [int64]$file.Length
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            reason = 'rejected full-cycle cold diagnostic; preserve contracts and scalar audits, remove dense native/conservative observations'
            production_recovery_allowed = $false
        })
    }
}
Require ($targets.Count -gt 0) 'No rejected cold full-cycle raw observations remain.'

New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
$planPath = Join-Path $auditRoot 'retirement_plan.json'
$plan = [ordered]@{
    schema = 'heatdrive_ecc_rejected_cold_fullcycle_raw_retirement_plan_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    target_roots = $targetRoots
    targets = @($targets)
    preserved = @('REJECTED_DO_NOT_RESUME.txt', 'cold_chamber_execution.json', 'configuration',
        'connectivity and inventory metadata', 'MATLAB diary', 'scalar audit evidence')
    production_recovery_allowed = $false
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $targets) {
        $path = Get-ContainedPath $target.relative_path
        Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $target.sha256) "Raw file changed: $path"
        if ($PSCmdlet.ShouldProcess($path, 'Remove rejected cold full-cycle raw observation')) {
            Remove-Item -LiteralPath $path -Force
            Require (-not (Test-Path -LiteralPath $path)) "Deletion failed: $path"
            $deleted.Add($target)
        }
    }
    foreach ($rootName in $targetRoots) {
        $marker = Join-Path (Get-ContainedPath $rootName) 'SUPERSEDED_RAW_COMPACTED.txt'
        @(
            'status=rejected_raw_compacted'
            'production_recovery_allowed=false'
            'preserved_execution_contract=true'
            'preserved_rejection_marker=true'
            'preserved_scalar_audit=true'
            'receipt=outputs_storage_audit/rejected_cold_fullcycle_raw_retirement_20260916/retirement_receipt.json'
        ) | Set-Content -LiteralPath $marker -Encoding utf8
    }
}

$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'
$receipt = [ordered]@{
    schema = 'heatdrive_ecc_rejected_cold_fullcycle_raw_retirement_receipt_v1'
    completed_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    plan_path = $planPath
    targets = @($targets)
    deleted = @($deleted)
    deleted_bytes = [int64]$(if ($deleted.Count -gt 0) { ($deleted | Measure-Object bytes -Sum).Sum } else { 0 })
    production_recovery_allowed = $false
}
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 8
