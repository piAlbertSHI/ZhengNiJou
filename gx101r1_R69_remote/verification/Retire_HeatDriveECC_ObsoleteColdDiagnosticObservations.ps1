[CmdletBinding()]
param(
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs = [IO.Path]::GetFullPath((Join-Path $repo 'outputs'))
$auditRoot = [IO.Path]::GetFullPath((Join-Path $repo 'outputs_storage_audit'))
$receiptRoot = Join-Path $auditRoot 'obsolete_cold_observations_retirement_20260913'

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and
    ($_.CommandLine -match [regex]::Escape($outputs) -or $_.CommandLine -match 'HeatDriveECC')
})
if ($Apply -and $running.Count -gt 0) {
    throw 'MATLAB references the project outputs; cleanup is disabled until it exits.'
}

# These are rejected, superseded, or preflight observations. Their contracts and scalar audits remain.
$targets = @(
    [pscustomobject]@{ root='cold_chamber_flux_compensated_onset_0p85_20260913'; reason='failed before conservative arm; superseded by corrected v2/v3/v4 evidence' },
    [pscustomobject]@{ root='cold_chamber_flux_compensated_onset_0p85_20260913_v2'; reason='failed before conservative arm; superseded by corrected v3/v4 evidence' },
    [pscustomobject]@{ root='cold_chamber_nonlinear_localbe_onset_0p85_20260913'; reason='nonlinear local-BE mass ledger failed; retain rejection audit, not raw trajectory' },
    [pscustomobject]@{ root='cold_chamber_onset_specific_0p85_20260912'; reason='0.2 s onset preflight superseded by full-cycle cold diagnostics' },
    [pscustomobject]@{ root='cold_chamber_preflight_1s_0p85_20260912'; reason='1 s preflight superseded by full-cycle cold diagnostics' },
    [pscustomobject]@{ root='cold_chamber_flux_compensated_onset_0p85_20260913_v3'; reason='superseded by strict-passing calibrated v7 onset evidence' },
    [pscustomobject]@{ root='cold_chamber_flux_compensated_onset_0p85_20260913_v4'; reason='failed model property-source lookup; retain execution error, not native trajectory' },
    [pscustomobject]@{ root='cold_chamber_flux_compensated_onset_0p85_20260913_v5'; reason='failed model table discovery assertion; retain execution error, not native trajectory' },
    [pscustomobject]@{ root='cold_chamber_flux_compensated_onset_0p85_20260913_v6'; reason='calibration trajectory superseded by v7; retain v6 audit JSON as calibration evidence' }
    [pscustomobject]@{ root='cold_chamber_mass_offset_fullcycle_kp126_225_0p85_20260914_v10'; reason='failed before conservative arm; source whitelist omission diagnosed and superseded by v12' }
    [pscustomobject]@{ root='cold_chamber_mass_offset_fullcycle_kp126_225_0p85_20260914_v11'; reason='failed before conservative simulation; offset target-compensation mask omission diagnosed and superseded by v12' }
    [pscustomobject]@{ root='cold_chamber_pressure_probe_seed_20260919_v8'; reason='one-cycle pressure-probe diagnostic superseded by the completed v9 20-cycle pressure audit; preserve contracts and scalar audits' }
    [pscustomobject]@{ root='qian_coupled_retuned_cold_seed_20260920_v10'; reason='10 s seed superseded by passing v12 seed; preserve v10 audit and contract, retire dense duplicate observations' }
    [pscustomobject]@{ root='qian_coupled_retuned_cold_20cycle_20260920_v11'; reason='20-cycle stage-4 flow failure superseded by the closer v13 boundary result; preserve v11 audit and rejection marker' }
)
$rows = foreach ($target in $targets) {
    $root = Join-Path $outputs $target.root
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    $execution = Join-Path $root 'cold_chamber_execution.json'
    if (-not (Test-Path -LiteralPath $execution -PathType Leaf)) {
        throw "Missing execution contract: $execution"
    }
    $executionRecord = Get-Content -LiteralPath $execution -Raw | ConvertFrom-Json
    if ([bool]$executionRecord.production_recovery_allowed -or
            [bool]$executionRecord.periodic_steady_state -or
            [bool]$executionRecord.checkpoint_saved) {
        throw "Target is not an obsolete diagnostic: $($target.root)."
    }
    foreach ($relative in @('native\observations.mat','conservative\observations.mat')) {
        $path = Join-Path $root $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $file = Get-Item -LiteralPath $path
        [pscustomobject]@{
            target_root = $target.root
            relative_path = [IO.Path]::GetRelativePath($outputs, $path)
            bytes = $file.Length
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            reason = $target.reason
            disposition = 'delete_obsolete_raw_preserve_contracts_and_audits'
        }
    }
}
$rows = @($rows)
New-Item -ItemType Directory -Path $receiptRoot -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$planPath = Join-Path $receiptRoot "retirement_plan_$stamp.csv"
$rows | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding utf8

function Get-Bytes($items) {
    if (@($items).Count -eq 0) { return [int64]0 }
    return [int64](($items | Measure-Object bytes -Sum).Sum)
}

$deleted = @()
if ($Apply) {
    foreach ($row in $rows) {
        $path = [IO.Path]::GetFullPath((Join-Path $outputs $row.relative_path))
        if (-not $path.StartsWith($outputs + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) { throw "Target escaped outputs: $path" }
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
            $deleted += $row
        }
    }
    foreach ($target in $targets) {
        $root = Join-Path $outputs $target.root
        if (Test-Path -LiteralPath $root -PathType Container) {
            "Retired only native/conservative observations after hash-bound audit. Reason: $($target.reason)" |
                Set-Content -LiteralPath (Join-Path $root 'OBSOLETE_RAW_COMPACTED.txt') -Encoding utf8
        }
    }
}
$receipt = [ordered]@{
    schema = 'heatdrive_ecc_obsolete_cold_observations_retirement_v1'
    generated_at = (Get-Date).ToString('o')
    mode = if ($Apply) { 'apply' } else { 'audit_only' }
    repository = $repo
    target_count = $targets.Count
    planned_file_count = $rows.Count
    planned_bytes = Get-Bytes $rows
    deleted_file_count = $deleted.Count
    deleted_bytes = Get-Bytes $deleted
    plan_csv = $planPath
    preserved = 'execution contracts, configuration, connectivity, inventory metadata, logs, summaries, audit JSON, hashes, rejection explanations'
    excluded = 'C200/C180/C240 authority, 120/225 and 125/225 key raw observations, passing 0.75 MPa onset'
    files = @($rows)
}
$receiptPath = Join-Path $receiptRoot "retirement_receipt_$stamp.json"
$receipt | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 7
