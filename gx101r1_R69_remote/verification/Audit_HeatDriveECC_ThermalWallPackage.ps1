[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'thermal_wall_release_20260907'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
$thermalPath = Join-Path $audit 'thermal_connectivity_20260907/thermal_capacity_audit_v1.json'
$wallPath = Join-Path $audit 'dual_pipe_wall_20260907_v2/wall_audit_v1.json'
$thermal = Read-Json $thermalPath
$wall = Read-Json $wallPath
$rejected = Read-Json (Join-Path $audit 'dual_pipe_wall_20260907/rejected_initial_state.json')
if (-not $thermal.thermal_connectivity_verified -or $thermal.thermal_port_count -ne 906 -or
        $thermal.thermal_wire_net_count -ne 192 -or $thermal.actual_thermal_mass_count -ne 46 -or
        -not $thermal.existing_declared_capacities_match_material_and_reservoir_formulas -or
        $thermal.explicit_connector_wall_capacity_present -or $thermal.production_recovery_allowed -or
        $thermal.article_connector_assignment_fully_proven -or $thermal.whole_model_first_law_verified) { throw 'Thermal scope changed.' }
if ($wall.schema -ne 'heatdrive_ecc_dual_pipe_wall_audit_v1' -or $wall.actual_simscape_cases -ne 6 -or
        $wall.actual_scalar_trace_count -ne 582 -or -not $wall.all_inventory_pass -or -not $wall.all_wall_heat_transfer_pass -or
        $wall.mass_absolute_gate_kg -ne 1e-15 -or $wall.energy_absolute_gate_J -ne 1e-8 -or
        $wall.production_recovery_allowed -or $wall.whole_model_first_law_verified -or $wall.table4_reproduction_claim -or
        $wall.omitted_event_intervals -ne 0) { throw 'Wall scope or scientific gate changed.' }
foreach ($case in $wall.cases) {
    if (-not $case.dual_inventory_closure_pass -or -not $case.wall_heat_transfer_pass) { throw 'Per-case gate failed.' }
}
if ($rejected.scientific_acceptance -or $rejected.completed_cases -ne 6 -or $rejected.actual_initial_temperature_K_in_all_twelve_walls -ne 300 -or
        $rejected.production_recovery_allowed -or $rejected.gate_relaxed) { throw 'Rejected evidence was promoted.' }
if ($Create) {
    if (Test-Path -LiteralPath $root) { throw 'Do not overwrite a release.' }
    $dirty = @(git -C $workspace status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Commit reviewed source first.' }
    $commit = (git -C $workspace rev-parse HEAD).Trim()
    $base = Read-Json (Join-Path $audit 'tl_inventory_release_20260906/release.json')
    New-Item -ItemType Directory -Path $root | Out-Null
    $patch = Join-Path $root 'source_delta.patch'
    git -C $workspace diff --binary --output=$patch $base.source_commit $commit
    if ($LASTEXITCODE -ne 0) { throw 'Source delta failed.' }
    git -C $workspace apply --reverse --check $patch
    if ($LASTEXITCODE -ne 0) { throw 'Source delta verification failed.' }
    $tests = & python -m unittest discover -s (Join-Path $repo 'verification') -p 'test_*.py' -v 2>&1
    $testCode = $LASTEXITCODE
    $tests | Set-Content -LiteralPath (Join-Path $root 'python_tests.log') -Encoding utf8
    if ($testCode -ne 0) { throw 'Regression tests failed.' }
    foreach ($item in @(@('ThermalConnectivity',$thermalPath),@('DualPipeWall',$wallPath))) {
        $output = Join-Path $root ("recomputed_"+$item[0]+'.json')
        & python -X utf8 (Join-Path $PSScriptRoot ("Audit_HeatDriveECC_"+$item[0]+'.py')) --repo $repo --output $output | Out-Null
        if ($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath $output).Hash -ne (Get-FileHash -LiteralPath $item[1]).Hash) {
            throw 'Independent recomputation differs.'
        }
    }
    $evidence = @('thermal_connectivity_20260907','dual_pipe_wall_20260907','dual_pipe_wall_20260907_v2') |
        ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $audit $_) -File -Recurse }
    $all = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    [ordered]@{measured_at=(Get-Date).ToString('o');workspace_bytes=($all|Measure-Object Length -Sum).Sum;file_count=$all.Count;
        new_evidence_bytes=($evidence|Measure-Object Length -Sum).Sum;copied_production_raw_bytes=0;deleted_bytes=0;
        git_objects=(git -C $workspace count-objects -vH)} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $authorityPath = Join-Path $PSScriptRoot 'c200_mainline_freeze_contract.json'
    $authority = Read-Json $authorityPath
    $authorityFiles = @()
    foreach ($kind in @('result','checkpoint')) {
        $path = Join-Path $repo $authority[($kind+'_relative_path')]
        if ((Get-FileHash -LiteralPath $path).Hash -ne $authority[($kind+'_sha256')]) { throw 'C200 authority changed.' }
        $authorityFiles += $path
    }
    $sourceZip = Join-Path $audit 'tl_inventory_release_20260906/source_snapshot.zip'
    if ((Get-FileHash -LiteralPath $sourceZip).Hash -ne $base.source_archive_sha256) { throw 'Base source changed.' }
    $paths = @($evidence.FullName) + @((Get-ChildItem -LiteralPath $root -File).FullName) + $authorityFiles + @(
        $authorityPath,$sourceZip,(Join-Path $audit 'tl_inventory_release_20260906/release.json'),
        (Join-Path $audit 'route_ablation_release_20260907/release.json'),
        (Join-Path $audit 'route_ablation_release_20260907/result_manifest.csv')) + @(
        'thermal_connectivity_20260907_stdout.log','dual_pipe_wall_20260907_stdout.log','dual_pipe_wall_20260907_v2_stdout.log',
        'cleanup_summary_20260907_085420.txt','cleanup_candidates_20260907_085420.csv' | ForEach-Object {Join-Path $audit $_})
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace,$_);bytes=(Get-Item -LiteralPath $_).Length;
            sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_thermal_wall_release_v1';source_commit=$commit;source_base_commit=$base.source_commit;
        required_file_count=$rows.Count;tests_exit_code=$testCode;actual_simscape_cases=12;accepted_wall_cases=6;rejected_wall_cases=6;
        production_recovery_allowed=$false;whole_model_first_law_verified=$false;table4_reproduction_claim=$false;
        parent_release_full_reaudit=$false;parent_manifest_retained=$true;C200_hashes_verified=$true;
        source_package='Stage17 ZIP plus direct baseline patch; production MAT files referenced without copying'} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_thermal_wall_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path|Sort-Object -Unique).Count -ne $manifest.Count -or $release.tests_exit_code -ne 0 -or
        $release.accepted_wall_cases -ne 6 -or $release.rejected_wall_cases -ne 6 -or $release.production_recovery_allowed -or
        $release.whole_model_first_law_verified -or $release.table4_reproduction_claim -or -not $release.C200_hashes_verified) { throw 'Release scope changed.' }
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Path outside workspace.' }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) {
        throw "Changed evidence: $path"
    }
}
[ordered]@{package_integrity_pass=$true;required_files=$manifest.Count;source_commit=$release.source_commit;
    accepted_wall_cases=6;rejected_wall_cases=6;production_recovery_allowed=$false;whole_model_first_law_verified=$false} | ConvertTo-Json
