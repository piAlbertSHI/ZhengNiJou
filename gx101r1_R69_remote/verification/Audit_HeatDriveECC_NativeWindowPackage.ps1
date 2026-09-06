[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'native_window_release_20260906'
$base = Join-Path $audit 'tl_inventory_release_20260906'

function Resolve-Evidence([string]$Relative) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $Relative))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence path escapes workspace.'
    }
    return $path
}

if ($Create) {
    if (Test-Path -LiteralPath $root) { throw 'Do not overwrite a release.' }
    $dirty = @(git -C $workspace status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Commit reviewed source first.' }
    $commit = (git -C $workspace rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve source commit.' }
    $previous = Get-Content -LiteralPath (Join-Path $base 'release.json') -Raw | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath (Join-Path $base 'source_snapshot.zip')).Hash -ne $previous.source_archive_sha256) {
        throw 'Base source archive changed.'
    }
    New-Item -ItemType Directory -Path $root | Out-Null
    $patch = Join-Path $root 'source_delta.patch'
    git -C $workspace diff --binary --output=$patch $previous.source_commit $commit
    if ($LASTEXITCODE -ne 0) { throw 'Source delta creation failed.' }
    git -C $workspace apply --reverse --check $patch
    if ($LASTEXITCODE -ne 0) { throw 'Source delta does not match the committed working tree.' }
    $tests = & python -m unittest discover -s (Join-Path $repo 'verification') -p 'test_*.py' -v 2>&1
    $testCode = $LASTEXITCODE
    $tests | Set-Content -LiteralPath (Join-Path $root 'python_tests.log') -Encoding utf8
    if ($testCode -ne 0) { throw 'Regression tests failed.' }
    $files = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    [ordered]@{measured_at=(Get-Date).ToString('o'); bytes=($files | Measure-Object Length -Sum).Sum;
        file_count=$files.Count; deletion_performed_by_this_release=$false} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch, (Join-Path $root 'python_tests.log'), (Join-Path $root 'workspace_storage_snapshot.json'))
    foreach ($directory in @('segmented_inventory_restore_20260906', 'native_window_packing_test_20260906')) {
        $paths += @(Get-ChildItem -LiteralPath (Join-Path $audit $directory) -File -Recurse | Select-Object -ExpandProperty FullName)
    }
    foreach ($relative in @('tl_inventory_release_20260906/source_snapshot.zip',
            'tl_inventory_release_20260906/release.json', 'tl_inventory_release_20260906/result_manifest.csv',
            'native_inventory_port_comparison_20260906/native_inventory_probe.json',
            'native_inventory_model_metadata_20260906/storage_model_metadata.json',
            'tl_domain_energy_tables_20260906/tl_domain_metadata.json',
            'cleanup_candidates_20260906_150721.csv', 'cleanup_summary_20260906_150721.txt')) {
        $paths += Join-Path $audit $relative
    }
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing evidence: $path" }
    }
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace, $_);
            bytes=(Get-Item -LiteralPath $_).Length; sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_native_window_release_v1'; source_commit=$commit;
        source_base_commit=$previous.source_commit; source_delta='source_delta.patch';
        simulation_execution_commit='1246409'; packaging_tests_exit_code=$testCode;
        required_file_count=$rows.Count; new_production_cycles=0;
        package_kind='existing full source ZIP plus binary-capable source patch and in-place data manifest';
        production_recovery_allowed=$false; equation_matched_cycle_closure_verified=$false;
        full_internal_periodicity_verified=$false; table4_reproduction_claim=$false} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}

$release = Get-Content -LiteralPath (Join-Path $root 'release.json') -Raw | ConvertFrom-Json
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($manifest.Count -ne $release.required_file_count -or $release.production_recovery_allowed -or
        $release.equation_matched_cycle_closure_verified -or $release.full_internal_periodicity_verified -or
        $release.table4_reproduction_claim -or $release.new_production_cycles -ne 0) { throw 'Invalid release scope.' }
foreach ($row in $manifest) {
    $path = Resolve-Evidence $row.relative_path
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $row.sha256) {
        throw "Changed evidence: $path"
    }
}
$split = Get-Content -Raw -LiteralPath (Join-Path $audit 'segmented_inventory_restore_20260906/independent_evidence_v2.json') | ConvertFrom-Json
$ledger = Get-Content -Raw -LiteralPath (Join-Path $audit 'segmented_inventory_restore_20260906/native_window_ledger_v1.json') | ConvertFrom-Json
$packing = Get-Content -Raw -LiteralPath (Join-Path $audit 'native_window_packing_test_20260906/independent_lossless_audit.json') | ConvertFrom-Json
if (-not $split.independent_mat_recalculation_pass -or -not $ledger.partition_integrals_match -or
        -not $packing.lossless_packing_pass -or $packing.scalar_value_comparisons -ne 78480 -or
        $split.scalar_comparisons -ne 41856) { throw 'Independent result gates failed.' }
[ordered]@{package_pass=$true; required_files=$manifest.Count; source_commit=$release.source_commit;
    source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length;
    copied_production_raw_bytes=0; production_recovery_allowed=$false;
    equation_matched_cycle_closure_verified=$false} | ConvertTo-Json
