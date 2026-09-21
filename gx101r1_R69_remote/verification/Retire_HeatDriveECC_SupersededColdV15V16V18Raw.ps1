[CmdletBinding()]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$auditRoot = Join-Path $repo 'outputs_storage_audit\superseded_cold_raw_retirement_20260922'
$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'

$targets = @(
    'qian_coupled_retuned_cold_seed_20260920_v15\native',
    'qian_coupled_retuned_cold_seed_20260920_v15\conservative',
    'qian_coupled_retuned_cold_seed_20260920_v15\cache',
    'qian_coupled_retuned_cold_seed_20260920_v15\codegen',
    'qian_coupled_retuned_cold_seed_20260920_v15\component_build',
    'qian_coupled_retuned_cold_seed_20260920_v15\buffer_component_build',
    'qian_coupled_retuned_cold_seed_20260920_v16\native',
    'qian_coupled_retuned_cold_seed_20260920_v16\conservative',
    'qian_coupled_retuned_cold_seed_20260920_v16\cache',
    'qian_coupled_retuned_cold_seed_20260920_v16\codegen',
    'qian_coupled_retuned_cold_seed_20260920_v16\component_build',
    'qian_coupled_retuned_cold_seed_20260920_v16\buffer_component_build',
    'qian_coupled_retuned_cold_20cycle_20260921_v18\native',
    'qian_coupled_retuned_cold_20cycle_20260921_v18\conservative',
    'qian_coupled_retuned_cold_20cycle_20260921_v18\cache',
    'qian_coupled_retuned_cold_20cycle_20260921_v18\codegen',
    'qian_coupled_retuned_cold_20cycle_20260921_v18\component_build',
    'qian_coupled_retuned_cold_20cycle_20260921_v18\buffer_component_build'
)

$runs = @(
    'qian_coupled_retuned_cold_seed_20260920_v15',
    'qian_coupled_retuned_cold_seed_20260920_v16',
    'qian_coupled_retuned_cold_20cycle_20260921_v18'
)

foreach ($run in $runs) {
    $marker = Join-Path (Join-Path $outputs $run) 'REJECTED_DO_NOT_RESUME.txt'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
        throw "Missing rejection marker: $marker"
    }
}

$active = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^MATLAB(\.exe)?$' -and
    ($_.CommandLine -match 'qian_coupled_retuned_cold_seed_20260920_v1[56]' -or
        $_.CommandLine -match 'qian_coupled_retuned_cold_20cycle_20260921_v18')
})
if ($active.Count -gt 0) { throw 'A MATLAB process still references a retirement target.' }

function Resolve-Target([string]$relative) {
    $full = [IO.Path]::GetFullPath((Join-Path $outputs $relative)).TrimEnd('\')
    $prefix = $outputs.TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing target outside outputs: $full"
    }
    return $full
}

function Get-Inventory([string]$path) {
    return @(Get-ChildItem -LiteralPath $path -File -Recurse -Force | ForEach-Object {
        [ordered]@{
            relative_path = $_.FullName.Substring($repo.Length + 1)
            bytes = [int64]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
}

$records = foreach ($relative in $targets) {
    $path = Resolve-Target $relative
    if (-not (Test-Path -LiteralPath $path)) {
        [ordered]@{ target = $relative; present = $false; bytes = 0; files = @() }
        continue
    }
    $files = Get-Inventory $path
    $bytes = [int64](($files | ForEach-Object { [int64]$_['bytes'] } | Measure-Object -Sum).Sum)
    [ordered]@{ target = $relative; present = $true; bytes = $bytes; files = $files }
}

$plannedBytes = [int64](($records | ForEach-Object { [int64]$_['bytes'] } | Measure-Object -Sum).Sum)
$summary = [ordered]@{
    schema = 'heatdrive_ecc_superseded_cold_raw_retirement_v1'
    generated_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    repository = $repo
    rationale = 'v15/v16 rejected raw superseded by qualified v17; interrupted v18 raw superseded by complete v19 rerun'
    retained = @('execution contracts','MATLAB diaries','rejection markers','flow/pressure audits','reports','v17','v19','v20','v21','C180','C200')
    target_count = $targets.Count
    present_target_count = @($records | Where-Object present).Count
    planned_bytes = $plannedBytes
    targets = @($records)
}

if (-not $Apply) {
    $summary | ConvertTo-Json -Depth 8
    exit 0
}
if (Test-Path -LiteralPath $receiptPath) { throw 'Refusing to overwrite retirement receipt.' }

New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
foreach ($record in $records | Where-Object present) {
    $path = Resolve-Target $record.target
    Remove-Item -LiteralPath $path -Recurse -Force
}

$summary.deleted_at = (Get-Date).ToString('o')
$summary.deleted_bytes = $plannedBytes
$summary.post_delete_present_targets = @($records | Where-Object {
    Test-Path -LiteralPath (Resolve-Target $_.target)
}).Count
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
Write-Output ("RETIREMENT_APPLIED bytes=" + $plannedBytes + " receipt=" + $receiptPath)
