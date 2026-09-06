[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'restricted_flow_release_20260907'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_OpenFlowDiagnosticPackage.ps1') | Out-Null
$result = Read-Json (Join-Path $audit 'chamber_restricted_flow_20260907_v2/restricted_flow_audit_v1.json')
if ($result.schema -ne 'heatdrive_ecc_chamber_restricted_flow_audit_v1' -or -not $result.computation_complete -or
        $result.actual_simscape_cases -ne 18 -or $result.cases.Count -ne 18 -or
        $result.trial_execution_commit -ne '9027cb3de2b66d78024093f586db38a4452dee60' -or
        -not $result.tested_restricted_inventory_closure_verified -or -not $result.all_spatial_port_identities_pass -or
        -not $result.all_pump_power_formulas_pass -or -not $result.nonzero_pump_head_verified -or
        $result.mass_absolute_gate_kg -ne 1e-15 -or $result.energy_absolute_gate_J -ne 1e-8 -or
        $result.fixed_pressure_failure_resolved -or $result.whole_model_first_law_verified -or
        $result.production_recovery_allowed -or $result.table4_reproduction_claim -or $result.omitted_event_intervals -ne 0) {
    throw 'Restricted diagnostic scope or scientific gate changed.'
}
$conservative = @($result.cases | Where-Object formulation -eq 'conservative')
if ($conservative.Count -ne 9) { throw 'Expected nine paired conservative cases.' }
foreach ($case in $conservative) {
    if (-not $case.restricted_inventory_closure_pass -or -not $case.inventory_aliases_match -or
            $case.compiler_state_selection_directly_observed -or
            $case.external_ledger.mass_max_abs_residual_kg -gt 1e-15 -or
            $case.external_ledger.energy_max_abs_residual_J -gt 1e-8 -or
            $case.local_ledger.mass_max_abs_residual_kg -gt 1e-15 -or
            $case.local_ledger.energy_max_abs_residual_J -gt 1e-8) { throw 'Component gate failed.' }
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
    $evidence = @('chamber_restricted_flow_20260907','chamber_restricted_flow_20260907_v2') | ForEach-Object {
        Get-ChildItem -LiteralPath (Join-Path $audit $_) -File -Recurse
    }
    $files = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    $retirement = Read-Json (Join-Path $audit 'chamber_restricted_flow_20260907_v2/figure_retirement.json')
    [ordered]@{measured_at=(Get-Date).ToString('o'); bytes=($files | Measure-Object Length -Sum).Sum;
        file_count=$files.Count; retained_stage_evidence_bytes=($evidence | Measure-Object Length -Sum).Sum;
        copied_production_raw_bytes=0; deleted_rejected_figure_bytes=$retirement.bytes;
        obsolete_large_output_candidates=0; git_objects=(git -C $workspace count-objects -vH)} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch, (Join-Path $root 'python_tests.log'), (Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $audit 'open_flow_diagnostic_release_20260907/release.json'),
        (Join-Path $audit 'open_flow_diagnostic_release_20260907/result_manifest.csv'),
        (Join-Path $audit 'cleanup_summary_20260907_060921.txt'),
        (Join-Path $audit 'cleanup_candidates_20260907_060921.csv'))
    $paths += @($evidence | Select-Object -ExpandProperty FullName)
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace, $_); bytes=(Get-Item -LiteralPath $_).Length;
            sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_restricted_flow_release_v1'; source_commit=$commit; source_base_commit=$base.source_commit;
        required_file_count=$rows.Count; tests_exit_code=$testCode; actual_simscape_cases=18;
        tested_restricted_component_gate_pass=$true; nonzero_pump_head_verified=$true;
        fixed_pressure_failure_resolved=$false; production_recovery_allowed=$false;
        whole_model_first_law_verified=$false; table4_reproduction_claim=$false;
        source_package='stage17 full ZIP plus this direct-from-base patch; no production raw copies'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_restricted_flow_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or $release.tests_exit_code -ne 0 -or
        $release.actual_simscape_cases -ne 18 -or -not $release.tested_restricted_component_gate_pass -or
        -not $release.nonzero_pump_head_verified -or $release.fixed_pressure_failure_resolved -or
        $release.production_recovery_allowed -or $release.whole_model_first_law_verified -or $release.table4_reproduction_claim) {
    throw 'Release scope overstated.'
}
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence escapes workspace.'
    }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) {
        throw "Changed evidence: $path"
    }
}
[ordered]@{package_integrity_pass=$true; tested_restricted_component_gate_pass=$true; required_files=$manifest.Count;
    fixed_pressure_failure_resolved=$false; whole_model_first_law_verified=$false;
    source_commit=$release.source_commit; production_recovery_allowed=$false;
    source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
