[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$evidence = Join-Path $audit 'isolated_chamber_steps_20260907'
$root = Join-Path $audit 'chamber_step_release_20260907'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_DiscreteLedgerPackage.ps1') | Out-Null
$result = Read-Json (Join-Path $evidence 'chamber_step_audit_v1.json')
if ($result.schema -ne 'heatdrive_ecc_chamber_step_convergence_v1' -or -not $result.computation_complete -or
        -not $result.isolated_step_convergence_verified -or $result.actual_simscape_case_count -ne 6 -or
        $result.cases.Count -ne 6 -or $result.groups.Count -ne 2 -or
        $result.trial_execution_commit -ne 'b4e6438d0917420802036a39f14d0f4cd9897eb4' -or
        $result.full_device_first_law_verified -or $result.physical_mass_closure_verified -or
        $result.whole_model_convergence_verified -or $result.production_recovery_allowed -or
        $result.table4_reproduction_claim) { throw 'Component result scope or provenance changed.' }
foreach ($group in $result.groups) {
    if (-not $group.observed_first_order -or -not $group.reference_error_separated) { throw 'Convergence evidence failed.' }
}
foreach ($row in $result.cases) {
    if ($row.measured_heat_J -ne 10 -or $row.reference_endpoint_mass_change_kg -le 0 -or
            $row.reference_endpoint_energy_residual_J -ge 0) { throw 'Endpoint defects must not be suppressed.' }
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
        file_count=$files.Count; new_evidence_bytes=(Get-ChildItem -LiteralPath $evidence -File -Recurse | Measure-Object Length -Sum).Sum;
        copied_production_raw_bytes=0; deleted_bytes_this_stage=0;
        cleanup_summary='outputs_storage_audit/cleanup_summary_20260907_044719.txt'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch, (Join-Path $root 'python_tests.log'), (Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $audit 'discrete_ledger_release_20260907/release.json'),
        (Join-Path $audit 'discrete_ledger_release_20260907/result_manifest.csv'),
        (Join-Path $audit 'cleanup_summary_20260907_044719.txt'),
        (Join-Path $audit 'cleanup_candidates_20260907_044719.csv'))
    $paths += @(Get-ChildItem -LiteralPath $evidence -File -Recurse | Select-Object -ExpandProperty FullName)
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace, $_);
            bytes=(Get-Item -LiteralPath $_).Length; sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_chamber_step_release_v1'; source_commit=$commit; source_base_commit=$base.source_commit;
        required_file_count=$rows.Count; tests_exit_code=$testCode; actual_simscape_case_count=6;
        trial_execution_commit=$result.trial_execution_commit; isolated_step_convergence_verified=$true;
        whole_model_convergence_verified=$false; production_recovery_allowed=$false;
        full_device_first_law_verified=$false; physical_mass_closure_verified=$false;
        table4_reproduction_claim=$false; source_package='stage17 full ZIP plus this direct-from-base patch'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_chamber_step_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or $release.tests_exit_code -ne 0 -or
        $release.actual_simscape_case_count -ne 6 -or -not $release.isolated_step_convergence_verified -or
        $release.trial_execution_commit -ne $result.trial_execution_commit -or
        $release.production_recovery_allowed -or $release.whole_model_convergence_verified -or
        $release.full_device_first_law_verified -or $release.physical_mass_closure_verified -or
        $release.table4_reproduction_claim) { throw 'Release scope overstated.' }
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence escapes workspace.' }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or
            (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) { throw "Changed evidence: $path" }
}
[ordered]@{package_pass=$true; required_files=$manifest.Count; source_commit=$release.source_commit;
    actual_simscape_case_count=6; isolated_step_convergence_verified=$true; production_recovery_allowed=$false;
    source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
