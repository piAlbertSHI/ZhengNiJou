[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$rootName = 'cold_chamber_fullcycle_tuned120_225_10s_0p85_20260912'
$replacementName = 'cold_chamber_fullcycle_tuned125_225_10s_0p85_20260912'
$root = [IO.Path]::GetFullPath((Join-Path $outputs $rootName))
$replacement = [IO.Path]::GetFullPath((Join-Path $outputs $replacementName))
$auditRoot = Join-Path $repo 'outputs_storage_audit\superseded_cold120_raw_retirement_20260919'
$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'
$expectedCommit = '6c3d325cb45cc473a3a380d21044674bea5e6bc1'
$expectedHashes = [ordered]@{
    native = 'E2118B5980C9105799DE6962B869B66A53F5D5701431755612257B214A4EE81A'
    conservative = 'E6E278B173A8DDF1907BE8C155EEC5627300B52D14A193F7C081F8B83C37AF1B'
}

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Relative([string]$Path) {
    $base = [IO.Path]::GetFullPath($repo).TrimEnd('\') + '\'
    $uri = [Uri]$base
    return [Uri]::UnescapeDataString($uri.MakeRelativeUri([Uri][IO.Path]::GetFullPath($Path)).ToString()).Replace('/', '\')
}

Require (Test-Path -LiteralPath $root -PathType Container) "Missing 120/225 root: $root"
Require (Test-Path -LiteralPath $replacement -PathType Container) "Missing retained 125/225 replacement: $replacement"

$executionPath = Join-Path $root 'cold_chamber_execution.json'
Require (Test-Path -LiteralPath $executionPath -PathType Leaf) "Missing execution contract: $executionPath"
$execution = Get-Content -LiteralPath $executionPath -Raw | ConvertFrom-Json
Require ($execution.schema -eq 'heatdrive_ecc_independent_cold_chamber_v1') 'Unexpected execution schema.'
Require ([bool]$execution.collection_pass) '120/225 collection did not complete.'
Require ([string]$execution.execution_commit -eq $expectedCommit) '120/225 producer commit mismatch.'
Require (-not [bool]$execution.production_recovery_allowed) '120/225 permits recovery.'
Require (-not [bool]$execution.checkpoint_saved) '120/225 contains a checkpoint claim.'
Require (-not [bool]$execution.periodic_steady_state) '120/225 claims periodic steady state.'
Require (-not [bool]$execution.table4_reproduction_claim) '120/225 claims Table 4 reproduction.'
Require (-not [bool]$execution.full_device_first_law_verified) '120/225 claims full-device first-law closure.'

$replacementExecutionPath = Join-Path $replacement 'cold_chamber_execution.json'
Require (Test-Path -LiteralPath $replacementExecutionPath -PathType Leaf) 'Retained 125/225 execution contract is missing.'
$replacementExecution = Get-Content -LiteralPath $replacementExecutionPath -Raw | ConvertFrom-Json
Require ([bool]$replacementExecution.collection_pass) 'Retained 125/225 collection is incomplete.'
Require (-not [bool]$replacementExecution.production_recovery_allowed) 'Retained 125/225 permits recovery.'
Require (-not [bool]$replacementExecution.checkpoint_saved) 'Retained 125/225 contains a checkpoint claim.'

$checkpoints = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force |
    Where-Object { $_.Name -in @('final_operating_point.mat','operating_point.mat','checkpoint.mat') })
Require ($checkpoints.Count -eq 0) '120/225 unexpectedly contains a checkpoint file.'

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
    ($_.CommandLine -match [regex]::Escape($outputs) -or $_.CommandLine -match 'HeatDriveECC')
})
Require (-not $Apply -or $running.Count -eq 0) 'A HeatDriveECC MATLAB process is active.'

$targets = [Collections.Generic.List[object]]::new()
foreach ($arm in $expectedHashes.Keys) {
    $path = Join-Path (Join-Path $root $arm) 'observations.mat'
    Require (Test-Path -LiteralPath $path -PathType Leaf) "Missing 120/225 observation: $path"
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $case = @($execution.cases | Where-Object { $_.arm -eq $arm })
    Require ($case.Count -eq 1) "Missing 120/225 case: $arm"
    Require ([string]$case[0].observation_sha256 -eq $expectedHashes[$arm]) "Execution hash mismatch: $arm"
    Require ($actual -eq $expectedHashes[$arm]) "File hash mismatch: $arm"
    $file = Get-Item -LiteralPath $path
    $targets.Add([pscustomobject]@{
        kind = 'superseded_cold_tuning_timeseries'
        arm = $arm
        path = Relative $path
        bytes = [int64]$file.Length
        sha256 = $actual
    })
}

New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
$planPath = Join-Path $auditRoot 'retirement_plan.json'
$plan = [ordered]@{
    schema = 'heatdrive_ecc_superseded_cold120_raw_retirement_plan_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    superseded_root = $rootName
    replacement_root = $replacementName
    reason = '120/225 is an earlier non-recoverable diagnostic comparison; retain the later 125/225 comparison and all scalar/audit evidence.'
    execution_commit = $expectedCommit
    targets = @($targets)
    production_recovery_allowed = $false
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $targets) {
        $path = [IO.Path]::GetFullPath((Join-Path $repo $target.path))
        Require ($path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) 'Target escaped 120/225 root.'
        Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $target.sha256) "Hash changed after plan creation: $path"
        if ($PSCmdlet.ShouldProcess($path, 'Remove superseded 120/225 raw observation')) {
            Remove-Item -LiteralPath $path -Force
            Require (-not (Test-Path -LiteralPath $path)) "Deletion failed: $path"
            $deleted.Add($target)
        }
    }
    $marker = Join-Path $root 'SUPERSEDED_RAW_COMPACTED.txt'
    @(
        'status=superseded_raw_compacted'
        'production_recovery_allowed=false'
        'preserved_execution_contract=true'
        'preserved_summary_and_audit=true'
        'replacement=outputs/cold_chamber_fullcycle_tuned125_225_10s_0p85_20260912'
        'receipt=outputs_storage_audit/superseded_cold120_raw_retirement_20260919/retirement_receipt.json'
    ) | Set-Content -LiteralPath $marker -Encoding utf8
}

$receipt = [ordered]@{
    schema = 'heatdrive_ecc_superseded_cold120_raw_retirement_receipt_v1'
    completed_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    plan_path = $planPath
    superseded_root = $rootName
    replacement_root = $replacementName
    targets = @($targets)
    deleted = @($deleted)
    deleted_bytes = [int64]$(if ($deleted.Count -gt 0) { ($deleted | Measure-Object bytes -Sum).Sum } else { 0 })
    production_recovery_allowed = $false
}
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 8
