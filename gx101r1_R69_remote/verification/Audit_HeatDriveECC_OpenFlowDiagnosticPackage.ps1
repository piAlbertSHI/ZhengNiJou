[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'open_flow_diagnostic_release_20260907'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_ConservativeChamberPackage.ps1') | Out-Null
$result = Read-Json (Join-Path $audit 'chamber_open_flow_20260907_v2/open_flow_audit_v3.json')
if ($result.schema -ne 'heatdrive_ecc_chamber_open_flow_audit_v1' -or -not $result.computation_complete -or
        $result.actual_simscape_cases -ne 18 -or $result.cases.Count -ne 18 -or
        $result.trial_execution_commit -ne 'a85c89b700a296d19ac4a6c0b9043c4432faf416' -or
        -not $result.all_spatial_port_identities_pass -or $result.tested_open_flow_inventory_closure_verified -or
        $result.omitted_event_intervals -ne 0 -or $result.nonzero_pump_head_verified -or
        $result.full_sma_se_switching_verified -or $result.whole_model_first_law_verified -or
        $result.production_recovery_allowed -or $result.table4_reproduction_claim) { throw 'Failed diagnostic scope changed.' }
foreach ($case in @($result.cases | Where-Object formulation -eq 'conservative')) {
    if ($case.open_flow_inventory_closure_pass -or $case.temperature_coordinate_diagnostic.compiler_state_selection_directly_observed -or
            $case.temperature_coordinate_diagnostic.coefficient_energy_interval_max_residual_J -gt 1e-9 -or
            $case.temperature_coordinate_diagnostic.coefficient_mass_interval_max_residual_kg -gt 1e-15) {
        throw 'Coordinate diagnosis or retained failed gate changed.'
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
    $evidence = @('chamber_open_flow_20260907','chamber_open_flow_20260907_v2') | ForEach-Object {
        Get-ChildItem -LiteralPath (Join-Path $audit $_) -File -Recurse
    }
    $files = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    $retirement = Read-Json (Join-Path $audit 'chamber_open_flow_20260907_v2/figure_retirement.json')
    [ordered]@{measured_at=(Get-Date).ToString('o'); bytes=($files | Measure-Object Length -Sum).Sum;
        file_count=$files.Count; retained_stage_evidence_bytes=($evidence | Measure-Object Length -Sum).Sum;
        copied_production_raw_bytes=0; deleted_rejected_figure_bytes=$retirement.bytes} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch, (Join-Path $root 'python_tests.log'), (Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $audit 'conservative_chamber_release_20260907/release.json'),
        (Join-Path $audit 'conservative_chamber_release_20260907/result_manifest.csv'))
    $paths += @($evidence | Select-Object -ExpandProperty FullName)
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace, $_); bytes=(Get-Item -LiteralPath $_).Length;
            sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_open_flow_diagnostic_release_v1'; source_commit=$commit; source_base_commit=$base.source_commit;
        required_file_count=$rows.Count; tests_exit_code=$testCode; actual_simscape_cases=18;
        scientific_inventory_gate_pass=$false; spatial_port_identities_pass=$true;
        production_recovery_allowed=$false; whole_model_first_law_verified=$false; table4_reproduction_claim=$false;
        source_package='stage17 full ZIP plus this direct-from-base patch'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_open_flow_diagnostic_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or $release.tests_exit_code -ne 0 -or
        $release.actual_simscape_cases -ne 18 -or $release.scientific_inventory_gate_pass -or
        -not $release.spatial_port_identities_pass -or $release.production_recovery_allowed -or
        $release.whole_model_first_law_verified -or $release.table4_reproduction_claim) { throw 'Release scope overstated.' }
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence escapes workspace.' }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) {
        throw "Changed evidence: $path"
    }
}
[ordered]@{package_integrity_pass=$true; scientific_inventory_gate_pass=$false; required_files=$manifest.Count;
    source_commit=$release.source_commit; production_recovery_allowed=$false;
    source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
