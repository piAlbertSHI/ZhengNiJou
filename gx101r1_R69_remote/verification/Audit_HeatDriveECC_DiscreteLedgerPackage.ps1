[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$evidence = Join-Path $audit 'discrete_system_ledger_20260907'
$root = Join-Path $audit 'discrete_ledger_release_20260907'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_TankBasisPackage.ps1') | Out-Null
$ledger = Read-Json (Join-Path $evidence 'discrete_system_ledger_v4.json')
if ($ledger.schema -ne 'heatdrive_ecc_discrete_system_ledger_v1' -or -not $ledger.computation_complete -or
        -not $ledger.all_discrete_component_energy_equations_match -or $ledger.components.Count -ne 119 -or
        $ledger.summary.native_trace_count -ne 1240 -or $ledger.summary.scalar_energy_intervals -ne 1190000 -or
        $ledger.summary.discrete_equation_matching_components -ne 119 -or
        $ledger.summary.endpoint_fluid_mass_change_kg -le 1e-6 -or
        $ledger.full_device_first_law_verified -or $ledger.physical_mass_closure_verified -or
        $ledger.full_internal_periodicity_verified -or $ledger.production_recovery_allowed -or
        $ledger.table4_reproduction_claim -or $ledger.historical_ledger_overwritten) { throw 'Ledger evidence or claim scope changed.' }
foreach ($component in $ledger.components) {
    if (-not $component.discrete_energy_equation_match -or $component.sample_count -ne 10001 -or
            $component.physical_energy_closure_verified -or $component.physical_mass_closure_verified) { throw 'Invalid component scope.' }
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
        copied_production_raw_bytes=0; earlier_verified_duplicate_deletion_bytes=152109} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch, (Join-Path $root 'python_tests.log'), (Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $audit 'tank_basis_release_20260907/release.json'),
        (Join-Path $audit 'tank_basis_release_20260907/result_manifest.csv'))
    $paths += @(Get-ChildItem -LiteralPath $evidence -File -Recurse | Select-Object -ExpandProperty FullName)
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace, $_);
            bytes=(Get-Item -LiteralPath $_).Length; sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_discrete_ledger_release_v1'; source_commit=$commit; source_base_commit=$base.source_commit;
        required_file_count=$rows.Count; tests_exit_code=$testCode; simulation_run=$false;
        discrete_energy_matching_components=119; production_recovery_allowed=$false;
        full_device_first_law_verified=$false; physical_mass_closure_verified=$false;
        full_internal_periodicity_verified=$false; table4_reproduction_claim=$false;
        source_package='stage17 full ZIP plus this direct-from-base patch'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_discrete_ledger_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or $release.tests_exit_code -ne 0 -or
        $release.simulation_run -or $release.discrete_energy_matching_components -ne 119 -or
        $release.production_recovery_allowed -or $release.full_device_first_law_verified -or
        $release.physical_mass_closure_verified -or $release.full_internal_periodicity_verified -or
        $release.table4_reproduction_claim) { throw 'Release scope overstated.' }
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence path escapes workspace.' }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or
            (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) { throw "Changed evidence: $path" }
}
[ordered]@{package_pass=$true; required_files=$manifest.Count; source_commit=$release.source_commit;
    simulation_run=$false; discrete_energy_matching_components=119; production_recovery_allowed=$false;
    source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
