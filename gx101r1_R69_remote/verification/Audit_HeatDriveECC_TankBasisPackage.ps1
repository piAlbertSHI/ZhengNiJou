[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$evidence = Join-Path $audit 'tank_energy_basis_20260907'
$root = Join-Path $audit 'tank_basis_release_20260907'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_NativeResidualPackage.ps1') | Out-Null
$basis = Read-Json (Join-Path $evidence 'tank_energy_basis_v3.json')
if ($basis.schema -ne 'heatdrive_ecc_tank_energy_basis_v2' -or
        -not $basis.independent_dead_volume_hypothesis_pass -or -not $basis.coupled_tank_discrete_equations_match -or
        $basis.independent_cases.Count -ne 6 -or $basis.coupled_C181_tanks.Count -ne 4 -or
        $basis.trial_execution_commit -ne '322a6b7affa7bee46c91d046f2bf5b1ebefcca0a' -or
        $basis.fitted_correction_used -or $basis.historical_ledger_overwritten -or $basis.protected_source_decoded -or
        $basis.equation_matched_cycle_closure_verified -or $basis.full_internal_periodicity_verified -or
        $basis.production_recovery_allowed -or $basis.table4_reproduction_claim) { throw 'Tank evidence scope changed.' }
foreach ($case in $basis.independent_cases) {
    $path = Join-Path $evidence ('isolated_trial/case_{0}.mat' -f $case.case_index)
    if ((Get-FileHash -LiteralPath $path).Hash -ne $case.trial_sha256 -or $case.sample_count -ne 101 -or
            -not $case.extra_volume_and_head_BE_roundoff_match) { throw 'Independent tank trial changed.' }
}
foreach ($tank in $basis.coupled_C181_tanks) {
    if ($tank.sample_count -ne 10001 -or $tank.area_m2 -ne .001 -or
            -not $tank.extra_volume_and_head_BE_roundoff_match) { throw 'C181 tank comparison failed.' }
}
if ($Create) {
    if (Test-Path -LiteralPath $root) { throw 'Do not overwrite a release.' }
    $dirty = @(git -C $workspace status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Commit reviewed source first.' }
    $commit = (git -C $workspace rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve source commit.' }
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
    $files = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    [ordered]@{measured_at=(Get-Date).ToString('o'); bytes=($files | Measure-Object Length -Sum).Sum;
        file_count=$files.Count; deletion_performed_by_this_release=$false;
        new_evidence_bytes=(Get-ChildItem -LiteralPath $evidence -File -Recurse | Measure-Object Length -Sum).Sum;
        copied_production_raw_bytes=0} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch, (Join-Path $root 'python_tests.log'), (Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $audit 'native_residual_release_20260906/release.json'),
        (Join-Path $audit 'native_residual_release_20260906/result_manifest.csv'))
    $paths += @(Get-ChildItem -LiteralPath $evidence -File -Recurse | Select-Object -ExpandProperty FullName)
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace, $_);
            bytes=(Get-Item -LiteralPath $_).Length; sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_tank_basis_release_v1'; source_commit=$commit; source_base_commit=$base.source_commit;
        required_file_count=$rows.Count; tests_exit_code=$testCode; isolated_experiment_exit_code=0;
        coupled_tank_discrete_equations_match=$true; production_recovery_allowed=$false;
        full_internal_periodicity_verified=$false; equation_matched_cycle_closure_verified=$false;
        table4_reproduction_claim=$false; source_package='stage17 full ZIP plus this direct-from-base patch'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_tank_basis_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or
        $release.tests_exit_code -ne 0 -or $release.isolated_experiment_exit_code -ne 0 -or
        -not $release.coupled_tank_discrete_equations_match -or $release.production_recovery_allowed -or
        $release.full_internal_periodicity_verified -or $release.equation_matched_cycle_closure_verified -or
        $release.table4_reproduction_claim) { throw 'Release scope overstated.' }
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence path escapes workspace.'
    }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or
            (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) { throw "Changed evidence: $path" }
}
[ordered]@{package_pass=$true; required_files=$manifest.Count; source_commit=$release.source_commit;
    isolated_experiment_exit_code=0; coupled_tank_discrete_equations_match=$true;
    production_recovery_allowed=$false; source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
