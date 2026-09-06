[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$root = Join-Path $repo 'outputs_storage_audit\tl_inventory_release_20260906'
$manifestPath = Join-Path $root 'result_manifest.csv'
$verifiedHashes = @{}

function Assert-LocalPath([string]$Relative) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $Relative))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence path escapes workspace.'
    }
    return $path
}

if ($Create) {
    if (Test-Path -LiteralPath $root) { throw 'Do not overwrite an existing release.' }
    $dirty = @(git -C $workspace status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Commit reviewed source and report before creating release.' }
    $commit = (git -C $workspace rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit.' }
    New-Item -ItemType Directory -Path $root | Out-Null
    $tests = & python -m unittest discover -s (Join-Path $repo 'verification') -p 'test_*.py' -v 2>&1
    $testCode = $LASTEXITCODE
    $tests | Set-Content -LiteralPath (Join-Path $root 'python_tests.log') -Encoding utf8
    if ($testCode -ne 0) { throw 'Regression tests failed; preserve release diagnostics.' }

    $required = @()
    foreach ($name in @('c200_mainline_freeze_contract.json', 'runtime_c180_recovery_contract.json',
            'runtime_observation_c200_diagnostic_contract.json')) {
        $contractPath = Join-Path $PSScriptRoot $name
        $c = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
        Copy-Item -LiteralPath $contractPath -Destination (Join-Path $root $name)
        $required += Join-Path $root $name
        $kinds = @('result', 'checkpoint')
        if ($c.PSObject.Properties.Name -contains 'observation_relative_path') { $kinds += 'observation' }
        foreach ($kind in $kinds) {
            $path = Assert-LocalPath (Join-Path 'gx101r1_R69_remote' $c."${kind}_relative_path")
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
            if ($hash -ne $c."${kind}_sha256") {
                throw "Frozen evidence changed: $path"
            }
            $verifiedHashes[$path] = $hash
            $required += $path
        }
    }
    $sourcesPath = Join-Path $PSScriptRoot 'native_inventory_equation_sources.json'
    $sources = Get-Content -LiteralPath $sourcesPath -Raw | ConvertFrom-Json
    foreach ($file in $sources.files) {
        $path = Join-Path $sources.local_source_root $file.relative_path
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) {
            throw 'Installed equation source differs from the audited release.'
        }
    }
    Copy-Item -LiteralPath $sourcesPath -Destination (Join-Path $root 'native_inventory_equation_sources.json')
    $required += Join-Path $root 'native_inventory_equation_sources.json'
    $evidence = @(
        'native_inventory_port_comparison_20260906/native_inventory_probe.json',
        'native_inventory_port_comparison_20260906/native_inventory_probe.mat',
        'native_inventory_model_metadata_20260906/storage_model_metadata.json',
        'tl_domain_topology_sourcefix_20260906/tl_domain_metadata.json',
        'tl_branched_connectivity_test_20260906/matlab_stdout.log',
        'tl_branch_checkcode_diagnostic_20260906/matlab_stdout.log',
        'tl_domain_branched_ports_20260906/tl_domain_metadata.json',
        'tl_domain_branched_ports_20260906/matlab_stdout.log',
        'tl_domain_energy_tables_20260906/tl_domain_metadata.json',
        'tl_domain_energy_tables_20260906/matlab_stdout.log',
        'tl_domain_inventory_reconstruction_20260906/domain_inventory.json',
        'tl_domain_inventory_reconstruction_20260906/domain_inventory.csv',
        'native_accumulation_equations_20260906/native_accumulation.json',
        'cleanup_candidates_20260906_105530.csv',
        'cleanup_summary_20260906_105530.txt'
    )
    $required += $evidence | ForEach-Object { Join-Path (Join-Path $repo 'outputs_storage_audit') $_ }
    $required += Join-Path $workspace '项目文档/报告/SMA-SE正逆耦合_第十七阶段物性域与库存方程核对报告.md'
    $archive = Join-Path $root 'source_snapshot.zip'
    & git -C $workspace archive --format=zip "--output=$archive" $commit
    if ($LASTEXITCODE -ne 0) { throw 'Source archive creation failed.' }
    & python -c 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; print("SOURCE_ZIP_CRC_PASS=1")' $archive
    if ($LASTEXITCODE -ne 0) { throw 'Source ZIP CRC failed.' }
    $required += @($archive, (Join-Path $root 'python_tests.log'))
    $files = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    [ordered]@{measured_at=(Get-Date).ToString('o'); workspace=$workspace; file_count=$files.Count;
        bytes=($files | Measure-Object Length -Sum).Sum; deleted_bytes_this_stage=0;
        obsolete_cleanup_candidates=0} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $required += Join-Path $root 'workspace_storage_snapshot.json'
    $rows = foreach ($path in ($required | Select-Object -Unique)) {
        $hash = if ($verifiedHashes.ContainsKey($path)) { $verifiedHashes[$path] } else {
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace, $path);
            bytes=(Get-Item -LiteralPath $path).Length;
            sha256=$hash}
    }
    $rows | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_tl_inventory_release_v1'; source_commit=$commit;
        source_archive_sha256=(Get-FileHash -LiteralPath $archive).Hash;
        topology_energy_export_commit='4cd5c06'; topology_branch_export_from_uncommitted_definition=$true;
        probe_reused_from_stage16=$true; new_production_cycles=0;
        regression_exit_code=$testCode; installed_equation_source_count=3;
        equation_matched_cycle_closure_verified=$false; production_continuation_allowed=$false;
        table4_reproduction_claim=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}

$release = Get-Content -LiteralPath (Join-Path $root 'release.json') -Raw | ConvertFrom-Json
$rows = @(Import-Csv -LiteralPath $manifestPath)
if ($rows.Count -eq 0 -or @($rows.relative_path | Select-Object -Unique).Count -ne $rows.Count) { throw 'Empty/duplicate manifest.' }
foreach ($row in $rows) {
    $path = Assert-LocalPath $row.relative_path
    $hash = if ($Create -and $verifiedHashes.ContainsKey($path)) { $verifiedHashes[$path] } else {
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or
            $hash -ne $row.sha256) { throw "Manifest mismatch: $path" }
}
if ((Get-FileHash -LiteralPath (Join-Path $root 'source_snapshot.zip')).Hash -ne $release.source_archive_sha256) {
    throw 'Release source archive hash mismatch.'
}
$densityPath = Join-Path $repo 'outputs_storage_audit/tl_domain_inventory_reconstruction_20260906/domain_inventory.json'
$energyPath = Join-Path $repo 'outputs_storage_audit/native_accumulation_equations_20260906/native_accumulation.json'
$density = Get-Content -LiteralPath $densityPath -Raw | ConvertFrom-Json
$energy = Get-Content -LiteralPath $energyPath -Raw | ConvertFrom-Json
$c180 = Get-Content -LiteralPath (Join-Path $root 'runtime_c180_recovery_contract.json') -Raw | ConvertFrom-Json
if ($density.hydraulic_domain_count -ne 2 -or $density.pipe_count -ne 67 -or $density.fluid_storage_count -ne 73 -or
        -not $density.nominal_pipe_storage_reconstruction_pass -or -not $density.density_lookup_matches_native -or
        $energy.component_count -ne 73 -or -not $energy.internal_energy_lookup_matches_native -or
        $energy.production_continuation_allowed -or $density.production_continuation_allowed -or
        $energy.equation_matched_cycle_closure_verified -or $release.production_continuation_allowed -or
        $c180.control_volume_basis_review.production_continuation_allowed) { throw 'Scope or diagnostic gates inconsistent.' }
[ordered]@{package_integrity_pass=$true; required_count=$rows.Count; source_commit=$release.source_commit;
    source_archive_sha256=$release.source_archive_sha256; package_root=$root;
    hydraulic_domain_count=2; equation_matched_cycle_closure_verified=$false;
    production_continuation_allowed=$false; table4_reproduction_claim=$false} | ConvertTo-Json
