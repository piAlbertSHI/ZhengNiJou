[CmdletBinding()]
param(
    [string]$OutputRoot = '',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot 'outputs'
}
$outputRootResolved = [System.IO.Path]::GetFullPath($OutputRoot)
$expectedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot 'outputs'))
if ($outputRootResolved -ne $expectedRoot) {
    throw "Refusing to manage a path other than the repository outputs root: $outputRootResolved"
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
    $_.CommandLine -match [regex]::Escape($outputRootResolved)
})
if ($Apply -and $running.Count -gt 0) {
    throw 'A MATLAB process references this outputs root. Wait for it to finish before applying cleanup.'
}

$freezeContractPath = Join-Path $repoRoot 'verification\c200_mainline_freeze_contract.json'
if (-not (Test-Path -LiteralPath $freezeContractPath -PathType Leaf)) {
    throw "C200 freeze contract is missing: $freezeContractPath"
}
$freezeContract = Get-Content -LiteralPath $freezeContractPath -Raw |
    ConvertFrom-Json
$authorityResult = [System.IO.Path]::GetRelativePath(
    $outputRootResolved,
    (Join-Path $repoRoot $freezeContract.result_relative_path))
$authorityCheckpoint = [System.IO.Path]::GetRelativePath(
    $outputRootResolved,
    (Join-Path $repoRoot $freezeContract.checkpoint_relative_path))
$authorityRun = Split-Path -Parent $authorityResult
$preserveRawPaths = @(
    $authorityResult,
    $authorityCheckpoint,
    (Join-Path $authorityRun 'stage_temperature_probes_50samples.csv')
)
$activeRecoveryContractPath = Join-Path $repoRoot `
    'verification\shex_fullcycle_c242_recovery_contract.json'
if (Test-Path -LiteralPath $activeRecoveryContractPath -PathType Leaf) {
    $activeRecoveryContract = Get-Content -LiteralPath `
        $activeRecoveryContractPath -Raw | ConvertFrom-Json
    if (-not $activeRecoveryContract.mechanism_pass) {
        throw 'Active source heat-flow recovery contract is not mechanism-valid.'
    }
    if ($activeRecoveryContract.PSObject.Properties.Name -contains `
            'direct_shex_control_volume_pass' -and
            -not $activeRecoveryContract.direct_shex_control_volume_pass) {
        throw 'Active recovery contract has not passed the direct SHEX control-volume gate.'
    }
    $preserveRawPaths += [System.IO.Path]::GetRelativePath(
        $outputRootResolved,
        (Join-Path $repoRoot $activeRecoveryContract.result_relative_path))
    $preserveRawPaths += [System.IO.Path]::GetRelativePath(
        $outputRootResolved,
        (Join-Path $repoRoot $activeRecoveryContract.checkpoint_relative_path))
}
$largeProbeNames = @(
    'stage_temperature_probes_50samples.csv'
)
$rawNames = @(
    'physical_simscape_result.mat',
    'final_operating_point.mat',
    'source_heat_flow_reaudit.mat'
)

function Get-RelativePath([string]$Path) {
    return [System.IO.Path]::GetRelativePath($outputRootResolved, $Path)
}

function Test-PreservedRaw([string]$RelativePath) {
    foreach ($path in $preserveRawPaths) {
        if ($RelativePath.Equals($path, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

$allFiles = @(Get-ChildItem -LiteralPath $outputRootResolved -File -Recurse -Force)
$rows = foreach ($file in $allFiles) {
    $relative = Get-RelativePath $file.FullName
    $isRaw = $rawNames -contains $file.Name
    $isDenseProbe = $largeProbeNames -contains $file.Name
    $isLegacyFigure = $relative -match '(?i)(^|\\)figures\\'
    $preserved = Test-PreservedRaw $relative
    if (($isRaw -or $isDenseProbe -or $isLegacyFigure) -and -not $preserved) {
        [pscustomobject]@{
            relative_path = $relative
            bytes = $file.Length
            size_GB = [math]::Round($file.Length / 1GB, 6)
            disposition = 'delete_reproducible_obsolete_raw'
            reason = if ($isDenseProbe) {
                'dense_probe_csv; cycle summary and validation report retained'
            } elseif ($isLegacyFigure) {
                'legacy per-run figure; authoritative figures_sci and source retained'
            } elseif ($file.Name -eq 'final_operating_point.mat') {
                'obsolete_or_failed_checkpoint; must not be propagated'
            } else {
                'obsolete full time-series MAT; reports and summaries retained'
            }
        }
    }
}
$rows = @($rows | Sort-Object relative_path)

$auditDir = Join-Path $repoRoot 'outputs_storage_audit'
New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath = Join-Path $auditDir "cleanup_candidates_$stamp.csv"
$summaryPath = Join-Path $auditDir "cleanup_summary_$stamp.txt"
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8

$beforeBytes = ($allFiles | Measure-Object Length -Sum).Sum
$candidateBytes = if ($rows.Count -gt 0) {
    ($rows | Measure-Object bytes -Sum).Sum
} else {
    0L
}
$deletedBytes = 0L
if ($Apply) {
    foreach ($row in $rows) {
        $target = [System.IO.Path]::GetFullPath((Join-Path $outputRootResolved $row.relative_path))
        if (-not $target.StartsWith($outputRootResolved + [System.IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw "Resolved cleanup target escaped outputs root: $target"
        }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $length = (Get-Item -LiteralPath $target).Length
            Remove-Item -LiteralPath $target -Force
            $deletedBytes += $length
        }
    }
}
$afterBytes = if ($Apply) {
    (Get-ChildItem -LiteralPath $outputRootResolved -File -Recurse -Force |
        Measure-Object Length -Sum).Sum
} else {
    $beforeBytes
}

$summary = @(
    "generated_at=$((Get-Date).ToString('o'))"
    "output_root=$outputRootResolved"
    "mode=$(if ($Apply) { 'apply' } else { 'audit_only' })"
    "running_matlab_references=$($running.Count)"
    "file_count_before=$($allFiles.Count)"
    "bytes_before=$beforeBytes"
    "GB_before=$([math]::Round($beforeBytes / 1GB, 6))"
    "candidate_count=$($rows.Count)"
    "candidate_bytes=$candidateBytes"
    "candidate_GB=$([math]::Round($candidateBytes / 1GB, 6))"
    "deleted_bytes=$deletedBytes"
    "deleted_GB=$([math]::Round($deletedBytes / 1GB, 6))"
    "bytes_after=$afterBytes"
    "GB_after=$([math]::Round($afterBytes / 1GB, 6))"
    "candidate_csv=$csvPath"
    'preserved_authoritative_raw_paths='
    ($preserveRawPaths | ForEach-Object { "  $_" })
    'retained_for_all_runs=reports, cycle summaries, parameter contracts, logs, markers, small state manifests'
    'retained_authoritative_figures=figures_sci'
)
$summary | Set-Content -LiteralPath $summaryPath -Encoding utf8

[ordered]@{
    generated_at = (Get-Date).ToString('o')
    mode = if ($Apply) { 'apply' } else { 'audit_only' }
    output_root = $outputRootResolved
    candidate_count = $rows.Count
    candidate_GB = [math]::Round($candidateBytes / 1GB, 3)
    deleted_GB = [math]::Round($deletedBytes / 1GB, 3)
    before_GB = [math]::Round($beforeBytes / 1GB, 3)
    after_GB = [math]::Round($afterBytes / 1GB, 3)
    candidate_csv = $csvPath
    summary_path = $summaryPath
} | ConvertTo-Json -Depth 4
