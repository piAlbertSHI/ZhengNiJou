[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Apply,
    [string]$TargetRootName = 'qian_coupled_native_endpoint_chamber_diag_20260922_v26'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$auditRoot = [IO.Path]::GetFullPath((Join-Path $repo 'outputs_storage_audit'))
$targetRoot = [IO.Path]::GetFullPath((Join-Path $outputs $targetRootName))

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

Require ($targetRoot.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::OrdinalIgnoreCase)) 'Endpoint diagnostic root escaped outputs.'
Require (Test-Path -LiteralPath $targetRoot -PathType Container) "Missing target root: $targetRoot"
Require (Test-Path -LiteralPath (Join-Path $targetRoot 'REJECTED_DO_NOT_RESUME.txt') -PathType Leaf) 'Missing rejection marker.'
Require (Test-Path -LiteralPath (Join-Path $targetRoot 'cold_chamber_execution.json') -PathType Leaf) 'Missing execution contract.'

$execution = Get-Content -LiteralPath (Join-Path $targetRoot 'cold_chamber_execution.json') -Raw | ConvertFrom-Json
Require (-not [bool]$execution.production_recovery_allowed -and
    -not [bool]$execution.periodic_steady_state -and
    -not [bool]$execution.checkpoint_saved -and
    [bool]$execution.endpoint_chamber_diagnostic) 'Target is not a rejected endpoint-only package.'

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and $_.CommandLine -match [regex]::Escape($targetRoot)
})
Require ($running.Count -eq 0) 'A MATLAB process still references the endpoint diagnostic root.'

$targets = foreach ($arm in @('native', 'conservative')) {
    $relative = Join-Path $targetRootName (Join-Path $arm 'observations.mat')
    $path = [IO.Path]::GetFullPath((Join-Path $outputs $relative))
    Require (Test-Path -LiteralPath $path -PathType Leaf) "Missing raw observation: $path"
    $file = Get-Item -LiteralPath $path
    [pscustomobject]@{
        arm = $arm
        relative_path = $relative
        bytes = [int64]$file.Length
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        reason = 'rejected endpoint cold diagnostic; retain contracts and scalar audits, remove dense observations'
        production_recovery_allowed = $false
    }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$package = Join-Path $auditRoot "native_endpoint_diagnostic_raw_retirement_$stamp"
New-Item -ItemType Directory -Path $package -Force | Out-Null
$planPath = Join-Path $package 'retirement_plan.json'
$plan = [ordered]@{
    schema = 'heatdrive_ecc_native_endpoint_diagnostic_raw_retirement_plan_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    target_root = $targetRootName
    targets = @($targets)
    preserved = @('REJECTED_DO_NOT_RESUME.txt', 'cold_chamber_execution.json',
        'pressure probe audit', 'cold buffer audit', 'seed gate decision',
        'configuration', 'connectivity and inventory metadata',
        'compiled inventory tags', 'MATLAB diary', 'public targets')
    production_recovery_allowed = $false
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $targets) {
        $path = [IO.Path]::GetFullPath((Join-Path $outputs $target.relative_path))
        Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $target.sha256) "Hash changed: $path"
        if ($PSCmdlet.ShouldProcess($path, 'Remove rejected endpoint diagnostic raw observation')) {
            Remove-Item -LiteralPath $path -Force
            Require (-not (Test-Path -LiteralPath $path)) "Deletion failed: $path"
            $deleted.Add($target)
        }
    }
    $marker = Join-Path $targetRoot 'RAW_OBSERVATIONS_RETIRED.txt'
    @(
        'status=rejected_raw_compacted'
        'production_recovery_allowed=false'
        'preserved_execution_contract=true'
        'preserved_rejection_marker=true'
        'preserved_scalar_audit=true'
        "receipt=$((Join-Path $package 'retirement_receipt.json').Substring($repo.Length + 1))"
    ) | Set-Content -LiteralPath $marker -Encoding utf8
}

$receipt = [ordered]@{
    schema = 'heatdrive_ecc_native_endpoint_diagnostic_raw_retirement_receipt_v1'
    completed_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    plan_path = $planPath
    target_root = $targetRootName
    targets = @($targets)
    deleted = @($deleted)
    deleted_bytes = [int64]$(if ($deleted.Count -gt 0) { ($deleted | Measure-Object bytes -Sum).Sum } else { 0 })
    production_recovery_allowed = $false
}
$receiptPath = Join-Path $package 'retirement_receipt.json'
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 8
