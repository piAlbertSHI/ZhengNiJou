[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputs = (Resolve-Path (Join-Path $repo 'outputs')).Path
$auditRoot = Join-Path $repo 'outputs_storage_audit\chamber_only_intermediate_retirement_20260919'
$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'

# These are generated caches or an unpaired failed arm. v5 is deliberately
# absent: its 0.2 s observations are the current compact onset evidence.
$relativeTargets = @(
    'cold_chamber_only_probe_20260919_v1\cache',
    'cold_chamber_only_probe_20260919_v1\codegen',
    'cold_chamber_only_probe_20260919_v1\component_build',
    'cold_chamber_only_probe_20260919_v2\cache',
    'cold_chamber_only_probe_20260919_v2\codegen',
    'cold_chamber_only_probe_20260919_v2\component_build',
    'cold_chamber_only_probe_20260919_v2\native',
    'cold_chamber_only_probe_20260919_v3\cache',
    'cold_chamber_only_probe_20260919_v3\codegen',
    'cold_chamber_only_probe_20260919_v3\component_build',
    'cold_chamber_only_probe_20260919_v3\native',
    'cold_chamber_only_paired_onset_20260919_v4\cache',
    'cold_chamber_only_paired_onset_20260919_v4\codegen',
    'cold_chamber_only_paired_onset_20260919_v4\component_build'
)

$active = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^MATLAB(\.exe)?$' -and
        $_.CommandLine -match 'cold_chamber_only_(probe|paired_onset)_20260919_v[1-4]' }
if ($active) { throw 'A MATLAB process still references a chamber-only v1-v4 package.' }

function Assert-UnderOutputs([string]$path) {
    $full = [IO.Path]::GetFullPath($path).TrimEnd('\')
    $base = $outputs.TrimEnd('\') + '\'
    if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing target outside outputs: $full"
    }
    return $full
}

function Inventory([string]$path) {
    $files = @(Get-ChildItem -LiteralPath $path -File -Recurse -Force)
    return @($files | ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        [ordered]@{
            relative_path = $_.FullName.Substring($repo.Length + 1)
            bytes = [int64]$_.Length
            sha256 = $hash
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
    schema = 'heatdrive_ecc_chamber_only_intermediate_retirement_v1'
    generated_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    repository = $repo
    protected_current_onset = 'outputs/cold_chamber_only_paired_onset_20260919_v5'
    target_count = $relativeTargets.Count
    present_target_count = @($records | Where-Object present).Count
    planned_bytes = $plannedBytes
    targets = $records
}

if (-not $Apply) {
    $summary | ConvertTo-Json -Depth 8
    exit 0
}

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
