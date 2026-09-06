[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'native_pilot_release_20260906'
$base = Join-Path $audit 'tl_inventory_release_20260906'
$pilot = Join-Path $repo 'outputs/qian_native_inventory_pilot_from_c180_20260906'
$preflight = Join-Path $audit 'native_cycle_preflight_20260906'
$executionCommit = '17d7b85e95e69c5b01e3f328473d49c7557730b2'

function Resolve-Evidence([string]$Relative) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $Relative))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence path escapes workspace.'
    }
    return $path
}

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Assert-Scope {
    $collection = Read-Json (Join-Path $pilot 'native_cycle_result.json')
    $cycle = Read-Json (Join-Path $pilot 'cycle_181/cycle_audit.json')
    $ledger = Read-Json (Join-Path $pilot 'cycle_181/native_ledger.json')
    $system = Read-Json (Join-Path $preflight 'native_system_ledger_C181_v4.json')
    $coverage = Read-Json (Join-Path $preflight 'pilot_command_coverage.json')
    if ($collection.execution_commit -ne $executionCommit -or -not $collection.collection_pass -or
            $collection.collected_cycles -ne 1 -or $collection.requested_cycles -ne 1 -or
            -not $collection.mechanism_all_collected_cycles_pass -or $collection.production_recovery_allowed -or
            $collection.full_internal_periodicity_verified -or $collection.equation_matched_cycle_closure_verified) {
        throw 'Collection identity or diagnostic scope failed.'
    }
    if ($cycle.global_cycle -ne 181 -or $cycle.start_s -ne 1800 -or $cycle.stop_s -ne 1810 -or
            -not $cycle.strict_restore_pass -or -not $cycle.mechanism_pass -or
            -not $cycle.ledger_computation_pass -or $cycle.production_recovery_allowed -or
            -not $ledger.one_cycle_native_coverage_verified -or -not $ledger.ledger_computation_pass -or
            $ledger.equation_matched_cycle_closure_verified -or $ledger.production_recovery_allowed) {
        throw 'Pilot cycle gates failed.'
    }
    if ($system.sample_count -ne 10001 -or $system.window_start_s -ne 1800 -or $system.window_stop_s -ne 1810 -or
            $system.buffer_stage_mass_transport.Count -ne 16 -or -not $system.time_alignment.fixed_step_indices_equal -or
            $system.time_alignment.samples_interpolated -or $system.production_recovery_allowed -or
            $system.equation_matched_cycle_closure_verified -or $system.full_internal_periodicity_verified -or
            $system.full_device_first_law_verified -or $system.table4_reproduction_claim) {
        throw 'System ledger diagnostic scope failed.'
    }
    if (-not $coverage.coverage_pass -or $coverage.command_count -ne 18 -or $coverage.required_end_s -ne 1810 -or
            $coverage.minimum_command_end_s -ne 1820 -or $coverage.nominal_model_stop_time_s -ne 1800) {
        throw 'Actual command coverage correction not verified.'
    }
    $inputFiles = @{packet='native_window.mat'; physical='segment_physical.mat'; ledger='native_ledger.json'; mechanism='cycle_audit.json'}
    foreach ($name in $inputFiles.Keys) {
        $path = Join-Path $pilot ('cycle_181/' + $inputFiles[$name])
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $system.input_sha256.$name) {
            throw "System ledger input changed: $name"
        }
    }
    if ($ledger.packet_sha256 -ne $system.input_sha256.packet) { throw 'Packet hash linkage failed.' }
    $runtime = Read-Json (Join-Path $repo 'verification/runtime_c180_recovery_contract.json')
    if ($runtime.control_volume_basis_review.production_continuation_allowed -or
            $runtime.control_volume_basis_review.diagnostic_output_recovery_allowed -or
            -not $runtime.control_volume_basis_review.strict_inventory_diagnostic_allowed -or
            $runtime.result_sha256 -ne $system.source_result_sha256 -or
            $runtime.checkpoint_sha256 -ne $system.source_checkpoint_sha256 -or
            $collection.source_result_sha256 -ne $runtime.result_sha256 -or
            $collection.source_checkpoint_sha256 -ne $runtime.checkpoint_sha256) {
        throw 'Frozen source identity or restrictions changed.'
    }
}

if ($Create) {
    if (Test-Path -LiteralPath $root) { throw 'Do not overwrite a release.' }
    $dirty = @(git -C $workspace status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Commit reviewed source first.' }
    $commit = (git -C $workspace rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve source commit.' }
    $previous = Read-Json (Join-Path $base 'release.json')
    if ((Get-FileHash -LiteralPath (Join-Path $base 'source_snapshot.zip')).Hash -ne $previous.source_archive_sha256) {
        throw 'Base source archive changed.'
    }
    Assert-Scope
    $frozenPaths = @()
    foreach ($contractName in @('c200_mainline_freeze_contract.json', 'runtime_c180_recovery_contract.json')) {
        $contractPath = Join-Path $PSScriptRoot $contractName
        $contract = Read-Json $contractPath
        foreach ($kind in @('result', 'checkpoint')) {
            $path = Resolve-Evidence ('gx101r1_R69_remote/' + $contract.($kind + '_relative_path'))
            if ((Get-FileHash -LiteralPath $path).Hash -ne $contract.($kind + '_sha256')) {
                throw "Frozen $kind changed: $contractName"
            }
            $frozenPaths += $path
        }
        $frozenPaths += $contractPath
    }
    New-Item -ItemType Directory -Path $root | Out-Null
    $patch = Join-Path $root 'source_delta.patch'
    git -C $workspace diff --binary --output=$patch $previous.source_commit $commit
    if ($LASTEXITCODE -ne 0) { throw 'Source delta creation failed.' }
    git -C $workspace apply --reverse --check $patch
    if ($LASTEXITCODE -ne 0) { throw 'Source delta does not match committed source.' }
    $tests = & python -m unittest discover -s (Join-Path $repo 'verification') -p 'test_*.py' -v 2>&1
    $testCode = $LASTEXITCODE
    $tests | Set-Content -LiteralPath (Join-Path $root 'python_tests.log') -Encoding utf8
    if ($testCode -ne 0) { throw 'Regression tests failed.' }
    $files = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    [ordered]@{measured_at=(Get-Date).ToString('o'); bytes=($files | Measure-Object Length -Sum).Sum;
        file_count=$files.Count; deletion_performed_by_this_release=$false} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch, (Join-Path $root 'python_tests.log'), (Join-Path $root 'workspace_storage_snapshot.json')) + $frozenPaths
    $paths += @(Get-ChildItem -LiteralPath $pilot -File -Recurse | Select-Object -ExpandProperty FullName)
    $paths += @(Get-ChildItem -LiteralPath $preflight -File | Select-Object -ExpandProperty FullName)
    foreach ($relative in @('tl_inventory_release_20260906/source_snapshot.zip',
            'tl_inventory_release_20260906/release.json', 'tl_inventory_release_20260906/result_manifest.csv',
            'native_inventory_port_comparison_20260906/native_inventory_probe.json',
            'native_inventory_model_metadata_20260906/storage_model_metadata.json',
            'tl_domain_energy_tables_20260906/tl_domain_metadata.json',
            'cleanup_candidates_20260906_165247.csv', 'cleanup_summary_20260906_165247.txt')) {
        $paths += Join-Path $audit $relative
    }
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) { throw "Missing evidence: $_" }
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace, $_);
            bytes=(Get-Item -LiteralPath $_).Length; sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_native_pilot_release_v1'; source_commit=$commit;
        source_base_commit=$previous.source_commit; source_delta='source_delta.patch';
        simulation_execution_commit=$executionCommit; packaging_tests_exit_code=$testCode;
        required_file_count=$rows.Count; diagnostic_complete_cycles=1; new_production_cycles=0;
        package_kind='existing full source ZIP plus binary-capable source patch and in-place data manifest';
        production_recovery_allowed=$false; equation_matched_cycle_closure_verified=$false;
        full_internal_periodicity_verified=$false; full_device_first_law_verified=$false;
        table4_reproduction_claim=$false} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}

$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_native_pilot_release_v1' -or
        $manifest.Count -ne $release.required_file_count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or
        $release.simulation_execution_commit -ne $executionCommit -or $release.packaging_tests_exit_code -ne 0 -or
        $release.production_recovery_allowed -or $release.equation_matched_cycle_closure_verified -or
        $release.full_internal_periodicity_verified -or $release.full_device_first_law_verified -or
        $release.table4_reproduction_claim -or $release.new_production_cycles -ne 0 -or $release.diagnostic_complete_cycles -ne 1) {
    throw 'Invalid release scope.'
}
foreach ($row in $manifest) {
    $path = Resolve-Evidence $row.relative_path
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $row.sha256) {
        throw "Changed evidence: $path"
    }
}
Assert-Scope
[ordered]@{package_pass=$true; required_files=$manifest.Count; source_commit=$release.source_commit;
    simulation_execution_commit=$release.simulation_execution_commit;
    source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length;
    copied_production_raw_bytes=0; diagnostic_complete_cycles=1; production_recovery_allowed=$false;
    equation_matched_cycle_closure_verified=$false; full_internal_periodicity_verified=$false} | ConvertTo-Json
