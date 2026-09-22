[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$TargetRootName = @(
        'qian_coupled_retuned_cold_20cycle_20260921_v19',
        'qian_coupled_retuned_cold_seed_20260921_v20',
        'qian_coupled_retuned_cold_preflight_20260922_v21',
        'qian_coupled_retuned_cold_seed_20260922_v22'
    ),
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$auditRoot = [IO.Path]::GetFullPath((Join-Path $repo 'outputs_storage_audit'))
$allowed = @(
    'qian_coupled_retuned_cold_20cycle_20260921_v19',
    'qian_coupled_retuned_cold_seed_20260921_v20',
    'qian_coupled_retuned_cold_preflight_20260922_v21',
    'qian_coupled_retuned_cold_seed_20260922_v22'
)

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-RelativePath([string]$Base, [string]$Path) {
    $baseUri = [Uri]([IO.Path]::GetFullPath($Base).TrimEnd('\') + '\')
    $pathUri = [Uri]([IO.Path]::GetFullPath($Path))
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

function Get-Contained([string]$Base, [string]$Name) {
    Require ($allowed -contains $Name) "Target is not on the explicit retirement allowlist: $Name"
    $path = [IO.Path]::GetFullPath((Join-Path $Base $Name))
    Require $path.StartsWith($Base + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) "Target escaped outputs: $path"
    return $path
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$'
})
$records = [Collections.Generic.List[object]]::new()

foreach ($name in $TargetRootName) {
    $root = Get-Contained $outputs $name
    Require (Test-Path -LiteralPath $root -PathType Container) "Missing target root: $root"
    $marker = Join-Path $root 'REJECTED_DO_NOT_RESUME.txt'
    Require (Test-Path -LiteralPath $marker -PathType Leaf) "Missing rejection marker: $marker"
    $executionPath = Join-Path $root 'cold_chamber_execution.json'
    Require (Test-Path -LiteralPath $executionPath -PathType Leaf) "Missing execution contract: $executionPath"
    $execution = Get-Content -LiteralPath $executionPath -Raw | ConvertFrom-Json
    Require (-not [bool]$execution.production_recovery_allowed) "Recovery is allowed by contract: $name"
    Require (-not [bool]$execution.periodic_steady_state) "Target claims periodic state: $name"
    Require (-not [bool]$execution.checkpoint_saved) "Target contains a saved checkpoint contract: $name"
    $checkpoints = @(Get-ChildItem -LiteralPath $root -Recurse -Force -File | Where-Object {
        $_.Name -in @('final_operating_point.mat','operating_point.mat','checkpoint.mat')
    })
    Require ($checkpoints.Count -eq 0) "Checkpoint file found under rejected target: $name"
    $references = @($running | Where-Object {
        [string]$_.CommandLine -match [regex]::Escape($root)
    })
    Require (-not $Apply -or $references.Count -eq 0) "A MATLAB process references target: $name"
    $observations = @(Get-ChildItem -LiteralPath $root -Recurse -Force -File | Where-Object {
        $_.Name -ieq 'observations.mat'
    })
    Require ($observations.Count -gt 0) "No dense observations found under target: $name"
    foreach ($file in $observations) {
        $records.Add([pscustomobject]@{
            target_root = $name
            relative_path = Get-RelativePath $repo $file.FullName
            bytes = [int64]$file.Length
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            reason = 'rejected or superseded diagnostic raw; preserve contract and scalar audit'
            production_recovery_allowed = $false
        })
    }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$package = Join-Path $auditRoot "marked_diagnostic_raw_retirement_$stamp"
New-Item -ItemType Directory -Path $package -Force | Out-Null
$planPath = Join-Path $package 'retirement_plan.json'
$plan = [ordered]@{
    schema = 'heatdrive_ecc_marked_diagnostic_raw_retirement_plan_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    target_roots = @($TargetRootName)
    targets = @($records)
    preserved = @('cold_chamber_execution.json','REJECTED_DO_NOT_RESUME.txt',
        'MATLAB diary','configuration','topology and inventory metadata','scalar audits')
    production_recovery_allowed = $false
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $records) {
        $path = [IO.Path]::GetFullPath((Join-Path $repo ([string]$target.relative_path)))
        Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $target.sha256) "Hash changed: $path"
        if ($PSCmdlet.ShouldProcess($path, 'Remove rejected diagnostic raw observation')) {
            Remove-Item -LiteralPath $path -Force
            Require (-not (Test-Path -LiteralPath $path)) "Deletion failed: $path"
            $deleted.Add($target)
        }
    }
    foreach ($name in $TargetRootName) {
        $markerPath = Join-Path (Get-Contained $outputs $name) 'RAW_OBSERVATIONS_RETIRED.txt'
        @(
            'status=rejected_raw_compacted'
            'production_recovery_allowed=false'
            'preserved_execution_contract=true'
            'preserved_rejection_marker=true'
            "receipt=$((Join-Path $package 'retirement_receipt.json').Substring($repo.Length + 1))"
        ) | Set-Content -LiteralPath $markerPath -Encoding utf8
    }
}

$receipt = [ordered]@{
    schema = 'heatdrive_ecc_marked_diagnostic_raw_retirement_receipt_v1'
    completed_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    plan_path = $planPath
    targets = @($records)
    deleted = @($deleted)
    deleted_bytes = [int64]$(if ($deleted.Count -gt 0) { ($deleted | Measure-Object bytes -Sum).Sum } else { 0 })
    production_recovery_allowed = $false
}
$receiptPath = Join-Path $package 'retirement_receipt.json'
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 8
