[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$auditRoot = Join-Path $repo 'outputs_storage_audit'
$targetRoots = @(
    'cold_chamber_mass_offset_20cycle_kp126_225_0p85_20260914_v18',
    'cold_chamber_mass_offset_20cycle_kp126_225_0p85_20260914_v19'
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
    $_.CommandLine -match [regex]::Escape($repo)
})
Require ($running.Count -eq 0) 'A repository MATLAB process is still running.'

$targets = foreach ($rootName in $targetRoots) {
    $root = Get-ContainedPath $rootName
    Require (Test-Path -LiteralPath $root -PathType Container) "Missing target root: $root"
    $marker = Join-Path $root 'REJECTED_DO_NOT_RESUME.txt'
    Require (Test-Path -LiteralPath $marker -PathType Leaf) "Missing rejection marker: $root"
    $markerText = Get-Content -LiteralPath $marker -Raw
    Require ($markerText -match '(?i)(incomplete|ended|not a mechanism result)') "Unexpected marker: $marker"

    $rawRelative = Join-Path $rootName 'native\observations.mat'
    $raw = Get-ContainedPath $rawRelative
    Require (Test-Path -LiteralPath $raw -PathType Leaf) "Missing raw observation: $raw"
    $file = Get-Item -LiteralPath $raw
    [pscustomobject]@{
        root = $rootName
        relative_path = $rawRelative
        bytes = [int64]$file.Length
        sha256 = (Get-FileHash -LiteralPath $raw -Algorithm SHA256).Hash
        reason = 'incomplete rejected cold diagnostic; retain marker and diary, remove dense raw observation'
        production_recovery_allowed = $false
    }
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$package = Join-Path $auditRoot "cold20_incomplete_raw_retirement_$stamp"
New-Item -ItemType Directory -Path $package -Force | Out-Null
$planPath = Join-Path $package 'retirement_plan.json'
$plan = [ordered]@{
    schema = 'heatdrive_ecc_cold20_incomplete_raw_retirement_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    targets = @($targets)
    preserved = @(
        'REJECTED_DO_NOT_RESUME.txt',
        'matlab_diary.log',
        'configuration and connectivity metadata',
        'v13 diagnostic seed and all C200/C180/C240 evidence'
    )
    production_recovery_allowed = $false
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $targets) {
        $path = Get-ContainedPath $target.relative_path
        Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $target.sha256) "Hash changed: $path"
        if ($PSCmdlet.ShouldProcess($path, 'Remove rejected dense observation')) {
            Remove-Item -LiteralPath $path -Force
            Require (-not (Test-Path -LiteralPath $path)) "Deletion failed: $path"
            $deleted.Add($target)
        }
    }
}

$receipt = [ordered]@{
    schema = 'heatdrive_ecc_cold20_incomplete_raw_retirement_receipt_v1'
    completed_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    plan_path = $planPath
    targets = @($targets)
    deleted = @($deleted)
    deleted_bytes = [int64]$(if ($deleted.Count -gt 0) { ($deleted | Measure-Object bytes -Sum).Sum } else { 0 })
    production_recovery_allowed = $false
}
$receiptPath = Join-Path $package 'retirement_receipt.json'
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 8
