[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'dual_ramp_release_20260907'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_DualSwitchPackage.ps1') | Out-Null
$modes = @('ramp','projection','tight')
foreach ($mode in $modes) {
    $result = Read-Json (Join-Path $audit "dual_chamber_${mode}_20260907/${mode}_audit_v1.json")
    if ($result.schema -ne "heatdrive_ecc_dual_chamber_${mode}_audit_v1" -or -not $result.computation_complete -or
            $result.actual_simscape_cases -ne 12 -or $result.cases.Count -ne 12 -or $result.actual_scalar_trace_count -ne 948 -or
            $result.mass_absolute_gate_kg -ne 1e-15 -or $result.energy_absolute_gate_J -ne 1e-8 -or
            -not $result.all_valve_commands_pass -or -not $result.all_thermal_excitation_observed -or
            -not $result.all_pump_mode_formulas_pass -or $result.tested_dual_inventory_closure_verified -or
            $result.hard_switch_failure_resolved -or $result.production_model_changed -or $result.production_recovery_allowed -or
            $result.whole_model_first_law_verified -or $result.table4_reproduction_claim -or $result.omitted_event_intervals -ne 0) {
        throw "Diagnostic scope changed: $mode"
    }
    if ($result.all_spatial_port_identities_pass -ne ($mode -eq 'tight')) { throw 'Spatial gate changed.' }
    foreach ($case in $result.cases) {
        if ($case.valve_transition_s -ne .01 -or $case.stop_s -ne 1 -or
                $case.omitted_event_intervals -ne 0 -or ($case.formulation -eq 'conservative' -and $case.dual_inventory_closure_pass)) {
            throw 'Unqualified case promoted or event omitted.'
        }
    }
}
$coordinate = Read-Json (Join-Path $audit 'dual_chamber_tight_20260907/coordinate_diagnosis_v1.json')
if ($coordinate.schema -ne 'heatdrive_ecc_dual_chamber_coordinate_diagnosis_v1' -or $coordinate.cases.Count -ne 12 -or
        -not $coordinate.observed_TP_coordinate_equations_match -or -not $coordinate.all_intervals_retained -or
        $coordinate.compiler_state_selection_directly_observed -or $coordinate.physical_inventory_gate_pass -or
        $coordinate.production_recovery_allowed -or $coordinate.whole_model_first_law_verified -or $coordinate.table4_reproduction_claim) {
    throw 'Coordinate explanation promoted into physical closure.'
}
foreach ($row in $coordinate.cases) {
    if ($row.omitted_intervals -ne 0 -or $row.diagnostic_correction_subtracted_from_physical_gate -or
            $row.mass_coefficient_max_interval_error_kg -gt 1e-15 -or $row.energy_coefficient_max_interval_error_J -gt 1e-8) {
        throw 'Coordinate equation comparison failed.'
    }
}
if ($Create) {
    if (Test-Path -LiteralPath $root) { throw 'Do not overwrite a release.' }
    $dirty = @(git -C $workspace status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Commit reviewed source first.' }
    $commit = (git -C $workspace rev-parse HEAD).Trim()
    $base = Read-Json (Join-Path $audit 'tl_inventory_release_20260906/release.json')
    New-Item -ItemType Directory -Path $root | Out-Null
    $patch = Join-Path $root 'source_delta.patch'
    git -C $workspace diff --binary --output=$patch $base.source_commit $commit
    if ($LASTEXITCODE -ne 0) { throw 'Source delta creation failed.' }
    git -C $workspace apply --reverse --check $patch
    if ($LASTEXITCODE -ne 0) { throw 'Source delta verification failed.' }
    $tests = & python -m unittest discover -s (Join-Path $repo 'verification') -p 'test_*.py' -v 2>&1
    $testCode = $LASTEXITCODE
    $tests | Set-Content -LiteralPath (Join-Path $root 'python_tests.log') -Encoding utf8
    if ($testCode -ne 0) { throw 'Regression tests failed.' }
    $recomputed = @()
    foreach ($mode in @('ramp','projection','tight','coordinates')) {
        $temp = Join-Path $root "recompute_${mode}.json"
        if ($mode -eq 'coordinates') {
            & python (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_DualChamberCoordinates.py') --repo $repo --output $temp | Out-Null
            $source = Join-Path $audit 'dual_chamber_tight_20260907/coordinate_diagnosis_v1.json'
        } else {
            $options = @('--repo',$repo,'--output',$temp)
            if ($mode -ne 'ramp') { $options += "--$mode" }
            & python (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_DualChamberRampResult.py') @options | Out-Null
            $source = Join-Path $audit "dual_chamber_${mode}_20260907/${mode}_audit_v1.json"
        }
        if ($LASTEXITCODE -ne 0) { throw "Independent recomputation failed: $mode" }
        $hash = (Get-FileHash -LiteralPath $source).Hash
        if ((Get-FileHash -LiteralPath $temp).Hash -ne $hash) { throw "Recomputation differs: $mode" }
        $recomputed += [pscustomobject]@{mode=$mode;exit_code=0;identical=$true;sha256=$hash}
        Remove-Item -LiteralPath $temp
    }
    $recomputed | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'independent_recomputation.json') -Encoding utf8
    $evidence = @($modes | ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $audit "dual_chamber_${_}_20260907") -File -Recurse })
    $files = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    $retired = Read-Json (Join-Path $audit 'dual_chamber_tight_20260907/figure_retirement.json')
    [ordered]@{measured_at=(Get-Date).ToString('o');bytes=($files | Measure-Object Length -Sum).Sum;file_count=$files.Count;
        retained_stage_evidence_bytes=($evidence | Measure-Object Length -Sum).Sum;copied_production_raw_bytes=0;
        deleted_superseded_figure_bytes=$retired.deleted_bytes;deleted_stage_raw_bytes=0;
        git_objects=(git -C $workspace count-objects -vH)} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch,(Join-Path $root 'python_tests.log'),(Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $root 'independent_recomputation.json'),
        (Join-Path $audit 'dual_switch_release_20260907/release.json'),(Join-Path $audit 'dual_switch_release_20260907/result_manifest.csv'),
        (Join-Path $audit 'cleanup_summary_20260907_072632.txt'),(Join-Path $audit 'cleanup_candidates_20260907_072632.csv'))
    $paths += @($evidence | Select-Object -ExpandProperty FullName)
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace,$_);bytes=(Get-Item -LiteralPath $_).Length;
            sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_dual_ramp_diagnostic_release_v1';source_commit=$commit;source_base_commit=$base.source_commit;
        required_file_count=$rows.Count;tests_exit_code=$testCode;completed_diagnostic_cases=36;scientific_inventory_gate_pass=$false;
        coordinate_equation_explanation_pass=$true;production_recovery_allowed=$false;whole_model_first_law_verified=$false;
        table4_reproduction_claim=$false;source_package='Stage17 full ZIP plus this direct-from-base patch; no production raw copy'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_dual_ramp_diagnostic_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or $release.tests_exit_code -ne 0 -or
        $release.completed_diagnostic_cases -ne 36 -or $release.scientific_inventory_gate_pass -or
        -not $release.coordinate_equation_explanation_pass -or $release.production_recovery_allowed -or
        $release.whole_model_first_law_verified -or $release.table4_reproduction_claim) { throw 'Release scope overstated.' }
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence escapes workspace.'
    }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) {
        throw "Changed evidence: $path"
    }
}
[ordered]@{package_integrity_pass=$true;scientific_inventory_gate_pass=$false;required_files=$manifest.Count;
    completed_diagnostic_cases=36;coordinate_equation_explanation_pass=$true;source_commit=$release.source_commit;
    production_recovery_allowed=$false;source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
