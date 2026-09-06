[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'dual_switch_release_20260907'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_RestrictedFlowPackage.ps1') | Out-Null
$result = Read-Json (Join-Path $audit 'dual_chamber_switch_20260907_v4/failure_matrix_audit.json')
if ($result.schema -ne 'heatdrive_ecc_dual_switch_failure_matrix_v1' -or -not $result.diagnostic_audit_complete -or
        $result.execution_commit -ne '390a734598c991467e09ef5a8a29a73353995190' -or
        $result.attempted_independent_cases -ne 12 -or $result.cases.Count -ne 12 -or $result.completed_simulations -ne 0 -or
        -not $result.all_fail_at_route_switch -or $result.physical_temperature_lower_bound_K -ne 273.16 -or
        $result.physical_temperature_gate_relaxed -or $result.production_model_changed -or $result.production_recovery_allowed -or
        $result.whole_model_first_law_verified -or $result.table4_reproduction_claim) { throw 'Failure scope changed.' }
foreach ($case in $result.cases) {
    if ($case.final_time_s -ne .5 -or $case.first_out_of_domain_temperature_K -ge 273.16 -or
            -not $case.invalid_terminal_sample_retained -or $case.valid_physical_solution_at_terminal_sample -or
            $case.simulation_completion_pass -or $case.production_recovery_allowed) { throw 'Rejected sample was promoted.' }
}
$retired = Read-Json (Join-Path $audit 'dual_chamber_switch_20260907/retirement_audit.json')
if ($retired.deleted_files -ne 9 -or $retired.deleted_bytes -ne 11872035 -or $retired.production_raw_deleted -or
        $retired.new_failure_matrix_raw_deleted) { throw 'Retirement scope changed.' }
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
    $evidence = @('dual_chamber_switch_20260907','dual_chamber_switch_20260907_v2',
        'dual_chamber_switch_20260907_v3','dual_chamber_switch_20260907_v4') | ForEach-Object {
        Get-ChildItem -LiteralPath (Join-Path $audit $_) -File -Recurse
    }
    $files = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    [ordered]@{measured_at=(Get-Date).ToString('o');bytes=($files | Measure-Object Length -Sum).Sum;file_count=$files.Count;
        retained_stage_evidence_bytes=($evidence | Measure-Object Length -Sum).Sum;copied_production_raw_bytes=0;
        deleted_superseded_raw_bytes=$retired.deleted_bytes;git_objects=(git -C $workspace count-objects -vH)} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch,(Join-Path $root 'python_tests.log'),(Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $audit 'restricted_flow_release_20260907/release.json'),
        (Join-Path $audit 'restricted_flow_release_20260907/result_manifest.csv'))
    $paths += @($evidence | Select-Object -ExpandProperty FullName)
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace,$_);bytes=(Get-Item -LiteralPath $_).Length;
            sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_dual_switch_diagnostic_release_v1';source_commit=$commit;source_base_commit=$base.source_commit;
        required_file_count=$rows.Count;tests_exit_code=$testCode;complete_thermally_excited_switch_cases=0;
        scientific_switch_gate_pass=$false;production_recovery_allowed=$false;whole_model_first_law_verified=$false;
        table4_reproduction_claim=$false;source_package='Stage17 full ZIP plus this direct-from-base patch; no production raw copy'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_dual_switch_diagnostic_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or $release.tests_exit_code -ne 0 -or
        $release.complete_thermally_excited_switch_cases -ne 0 -or $release.scientific_switch_gate_pass -or
        $release.production_recovery_allowed -or $release.whole_model_first_law_verified -or $release.table4_reproduction_claim) {
    throw 'Release scope overstated.'
}
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence escapes workspace.'
    }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) {
        throw "Changed evidence: $path"
    }
}
[ordered]@{package_integrity_pass=$true;scientific_switch_gate_pass=$false;required_files=$manifest.Count;
    source_commit=$release.source_commit;production_recovery_allowed=$false;
    source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
