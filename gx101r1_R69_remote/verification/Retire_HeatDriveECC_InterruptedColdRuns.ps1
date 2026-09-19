[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputs = (Resolve-Path (Join-Path $repo 'outputs')).Path
$auditRoot = Join-Path $repo 'outputs_storage_audit\interrupted_cold_run_retirement_20260920'
$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'

# Exact generated targets from two infrastructure-only failures.  The v7
# qualified seed and all of its raw observations are deliberately absent.
$relativeTargets = @(
    'qian_coupled_retuned_cold_seed_20260919_v6\cache',
    'qian_coupled_retuned_cold_seed_20260919_v6\codegen',
    'qian_coupled_retuned_cold_20cycle_20260920_v8\cache',
    'qian_coupled_retuned_cold_20cycle_20260920_v8\codegen',
    'qian_coupled_retuned_cold_20cycle_20260920_v8\component_build',
    'qian_coupled_retuned_cold_20cycle_20260920_v8\buffer_component_build'
)

$active = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^MATLAB(\.exe)?$' -and
        $_.CommandLine -match 'qian_coupled_retuned_cold_(seed_20260919_v6|20cycle_20260920_v8)' }
if ($active) { throw 'A MATLAB process still references v6 or v8.' }

function Assert-UnderOutputs([string]$path) {
    $full = [IO.Path]::GetFullPath($path).TrimEnd('\')
    $base = $outputs.TrimEnd('\') + '\'
    if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing target outside outputs: $full"
    }
    return $full
}

function Inventory([string]$path) {
    return @(Get-ChildItem -LiteralPath $path -File -Recurse -Force | ForEach-Object {
        [ordered]@{
            relative_path = $_.FullName.Substring($repo.Length + 1)
            bytes = [int64]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
}

$records = @()
foreach ($relative in $relativeTargets) {
    $candidate = Assert-UnderOutputs (Join-Path $outputs $relative)
    if (-not (Test-Path -LiteralPath $candidate)) {
        $records += [ordered]@{target = $relative; present = $false; bytes = 0; files = @()}
        continue
    }
    $items = Inventory $candidate
    $bytes = [int64](($items | ForEach-Object { [int64]$_['bytes'] } | Measure-Object -Sum).Sum)
    $records += [ordered]@{target = $relative; present = $true; bytes = $bytes; files = $items}
}

$plannedBytes = [int64](($records | ForEach-Object { [int64]$_['bytes'] } | Measure-Object -Sum).Sum)
$summary = [ordered]@{
    schema = 'heatdrive_ecc_interrupted_cold_run_retirement_v1'
    generated_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    repository = $repo
    protected_seed = 'outputs/qian_coupled_retuned_cold_seed_20260919_v7'
    target_count = $relativeTargets.Count
    present_target_count = @($records | Where-Object present).Count
    planned_bytes = $plannedBytes
    targets = $records
}

if (-not $Apply) {
    $summary | ConvertTo-Json -Depth 8
    exit 0
}
if (Test-Path -LiteralPath $receiptPath) { throw 'Refusing to overwrite retirement receipt.' }

New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
foreach ($record in $records | Where-Object present) {
    $candidate = Assert-UnderOutputs (Join-Path $outputs $record.target)
    Remove-Item -LiteralPath $candidate -Recurse -Force
}

$summary.deleted_at = (Get-Date).ToString('o')
$summary.deleted_bytes = $plannedBytes
$summary.post_delete_present_targets = @($records | Where-Object {
    Test-Path -LiteralPath (Assert-UnderOutputs (Join-Path $outputs $_.target))
}).Count
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
Write-Output ("RETIREMENT_APPLIED bytes=" + $plannedBytes + " receipt=" + $receiptPath)
