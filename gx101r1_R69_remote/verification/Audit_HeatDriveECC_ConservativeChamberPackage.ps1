[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'conservative_chamber_release_20260907'
$evidenceRoots = @('conservative_chamber_20260907', 'conservative_chamber_20260907_v2',
    'conservative_chamber_20260907_v3', 'conservative_chamber_20260907_v4')
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_ChamberStepPackage.ps1') | Out-Null
$result = Read-Json (Join-Path $audit 'conservative_chamber_20260907_v4/conservative_audit_v1.json')
if ($result.schema -ne 'heatdrive_ecc_conservative_chamber_audit_v1' -or -not $result.computation_complete -or
        $result.actual_simscape_cases -ne 24 -or $result.cases.Count -ne 24 -or
        -not $result.sealed_component_inventory_closure_verified -or
        $result.trial_execution_commit -ne '3484fa1dcc78753b6ad63d7ccad557203d286dfa' -or
        $result.open_port_transport_verified -or $result.switched_network_verified -or
        $result.whole_model_first_law_verified -or $result.production_recovery_allowed -or
        $result.table4_reproduction_claim) { throw 'Invalid component scope or execution identity.' }
$rejected = Read-Json (Join-Path $audit 'conservative_chamber_20260907_v3/REJECTED_DIAGNOSTIC_ONLY.json')
if ($rejected.scientific_pairing_pass -or $rejected.production_recovery_allowed -or
        $rejected.mismatched_conservative_cases -ne 12) { throw 'Rejected initial-state mismatch evidence changed.' }
$deletion = Read-Json (Join-Path $audit 'conservative_chamber_20260907_v3/deletion_audit.json')
if ($deletion.deleted_count -ne 22 -or $deletion.deleted_bytes -ne 4813323 -or -not $deletion.verified_before_delete) {
    throw 'Rejected data retirement evidence changed.'
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
    $evidence = @($evidenceRoots | ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $audit $_) -File -Recurse })
    [ordered]@{measured_at=(Get-Date).ToString('o'); bytes=($files | Measure-Object Length -Sum).Sum;
        file_count=$files.Count; retained_stage_evidence_bytes=($evidence | Measure-Object Length -Sum).Sum;
        deleted_bytes_this_stage=4813323; copied_production_raw_bytes=0} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch, (Join-Path $root 'python_tests.log'), (Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $audit 'chamber_step_release_20260907/release.json'),
        (Join-Path $audit 'chamber_step_release_20260907/result_manifest.csv'))
    $paths += @($evidence | Select-Object -ExpandProperty FullName)
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace, $_);
            bytes=(Get-Item -LiteralPath $_).Length; sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_conservative_chamber_release_v1'; source_commit=$commit; source_base_commit=$base.source_commit;
        required_file_count=$rows.Count; tests_exit_code=$testCode; actual_accepted_trial_cases=24;
        sealed_component_inventory_closure_verified=$true; open_port_transport_verified=$false;
        whole_model_first_law_verified=$false; production_recovery_allowed=$false; table4_reproduction_claim=$false;
        rejected_trial_initial_state_failure_retained=$true;
        source_package='stage17 full ZIP plus this direct-from-base patch'} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_conservative_chamber_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or $release.tests_exit_code -ne 0 -or
        $release.actual_accepted_trial_cases -ne 24 -or -not $release.sealed_component_inventory_closure_verified -or
        -not $release.rejected_trial_initial_state_failure_retained -or $release.open_port_transport_verified -or
        $release.whole_model_first_law_verified -or $release.production_recovery_allowed -or $release.table4_reproduction_claim) {
    throw 'Release scope overstated.'
}
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence escapes workspace.' }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or
            (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) { throw "Changed evidence: $path" }
}
[ordered]@{package_pass=$true; required_files=$manifest.Count; source_commit=$release.source_commit;
    actual_accepted_trial_cases=24; sealed_component_inventory_closure_verified=$true; production_recovery_allowed=$false;
    source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
