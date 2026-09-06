[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'native_residual_release_20260906'
$diagnostic = Join-Path $audit 'native_residual_localization_20260906'
$experiment = Join-Path $audit 'native_solver_refinement_20260906'

function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Resolve-Evidence([string]$Relative) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $Relative))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence path escapes workspace.'
    }
    return $path
}
function Assert-Scope {
    $failed = Read-Json (Join-Path $experiment 'native_refinement_result.json')
    $first = Read-Json (Join-Path $experiment 'case_1_audit.json')
    $local = Read-Json (Join-Path $diagnostic 'solver_contract_v2/local_solver_contract.json')
    $balance = Read-Json (Join-Path $diagnostic 'localization_v3_water_budget.json')
    if ($failed.collection_pass -or $failed.cases.Count -ne 1 -or
            $failed.error_identifier -ne 'HeatDriveECC:RefinementStrictRestoreFailed' -or
            $failed.production_recovery_allowed -or $failed.temporal_convergence_verified -or
            $failed.execution_commit -ne '72823d0b46777178cf2cbd030d76d332072eee14') {
        throw 'Expected rejected refinement evidence changed.'
    }
    if (-not $first.diagnostic_case_pass -or -not $first.initial_observed.initial_state_bits_equal -or
            -not $first.original_prefix_comparisons.native.float64_bits_identical -or
            -not $first.original_prefix_comparisons.observed.float64_bits_identical -or
            $first.original_prefix_comparisons.native.scalar_comparisons -ne 373240 -or
            $first.original_prefix_comparisons.observed.scalar_comparisons -ne 414176 -or
            (Get-FileHash -LiteralPath (Join-Path $experiment 'case_1_traces.mat')).Hash -ne $first.case_file_sha256) {
        throw 'Verified 1 ms prefix evidence failed.'
    }
    if (-not $local.actual_solver_contract_pass -or $local.actual_solver_blocks.Count -ne 1 -or
            $local.actual_solver_blocks[0].LocalSolverChoice -ne 'NE_BACKWARD_EULER_ADVANCER' -or
            [double]$local.actual_solver_blocks[0].LocalSolverSampleTime -ne .001 -or
            $local.simulation_input_solver -ne 'ode3' -or $local.simulation_input_fixed_step_s -ne .001 -or
            $local.simulation_run -or -not $balance.original_ledger_recalculation_pass -or
            -not $balance.interval_partition_pass -or $balance.production_recovery_allowed -or
            $balance.equation_matched_cycle_closure_verified -or $balance.full_internal_periodicity_verified -or
            $balance.table4_reproduction_claim -or $balance.sma_water_stage_mass_budget.Count -ne 4) {
        throw 'Solver or diagnostic balance scope failed.'
    }
}

& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_NativePilotPackage.ps1') | Out-Null
Assert-Scope
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
        file_count=$files.Count; deletion_performed_by_this_release=$false} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch, (Join-Path $root 'python_tests.log'), (Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $audit 'native_pilot_release_20260906/release.json'),
        (Join-Path $audit 'native_pilot_release_20260906/result_manifest.csv'),
        (Join-Path $audit 'cleanup_candidates_20260906_175209.csv'),
        (Join-Path $audit 'cleanup_summary_20260906_175209.txt'))
    foreach ($directory in @($diagnostic, $experiment)) {
        $paths += @(Get-ChildItem -LiteralPath $directory -File -Recurse | Select-Object -ExpandProperty FullName)
    }
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace, $_);
            bytes=(Get-Item -LiteralPath $_).Length; sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_native_residual_release_v1'; source_commit=$commit;
        source_base_commit=$base.source_commit; simulation_execution_commit='72823d0b46777178cf2cbd030d76d332072eee14';
        required_file_count=$rows.Count; tests_exit_code=$testCode; physical_experiment_exit_code=1;
        verified_nominal_short_windows=1; solver_refinement_pass=$false; rejected_global_step_s=.0005;
        production_recovery_allowed=$false; equation_matched_cycle_closure_verified=$false;
        full_internal_periodicity_verified=$false; table4_reproduction_claim=$false;
        copied_production_raw_bytes=0; source_package='stage17 full ZIP plus this direct-from-base patch'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_native_residual_release_v1' -or
        $manifest.Count -ne $release.required_file_count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or
        $release.tests_exit_code -ne 0 -or $release.physical_experiment_exit_code -ne 1 -or
        $release.solver_refinement_pass -or $release.production_recovery_allowed -or
        $release.equation_matched_cycle_closure_verified -or $release.full_internal_periodicity_verified -or
        $release.table4_reproduction_claim) { throw 'Release scope overstated.' }
foreach ($row in $manifest) {
    $path = Resolve-Evidence $row.relative_path
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or
            (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) { throw "Changed evidence: $path" }
}
[ordered]@{package_pass=$true; required_files=$manifest.Count; source_commit=$release.source_commit;
    physical_experiment_exit_code=1; solver_refinement_pass=$false; production_recovery_allowed=$false;
    copied_production_raw_bytes=0; source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
