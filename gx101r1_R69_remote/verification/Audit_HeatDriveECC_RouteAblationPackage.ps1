[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'route_ablation_release_20260907'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_DualPipePackage.ps1') | Out-Null
$modes = @('no_friction_long_port','friction_short_port','no_friction_short_port')
foreach ($mode in $modes) {
    $r = Read-Json (Join-Path $audit "ablation_${mode}_20260907/ablation_audit_v1.json")
    if ($r.schema -ne 'heatdrive_ecc_pipe_ablation_audit_v1' -or $r.mode -ne $mode -or -not $r.computation_complete -or
            $r.actual_simscape_cases -ne 6 -or $r.cases.Count -ne 6 -or $r.actual_scalar_trace_count -ne 558 -or
            $r.mass_absolute_gate_kg -ne 1e-15 -or $r.energy_absolute_gate_J -ne 1e-8 -or $r.valve_transition_s -ne 0 -or
            $r.conservative_inventory_all_pass -ne ($mode -eq 'friction_short_port') -or
            -not $r.all_spatial_port_identities_pass -or -not $r.all_declared_friction_observed -or
            -not $r.all_thermal_excitation_observed -or -not $r.all_valve_commands_pass -or
            $r.production_model_changed -or $r.production_recovery_allowed -or $r.whole_model_first_law_verified -or
            $r.table4_reproduction_claim -or $r.omitted_event_intervals -ne 0) { throw "Ablation scope changed: $mode" }
    foreach ($case in $r.cases) {
        if ($case.dual_inventory_closure_pass -ne ($mode -eq 'friction_short_port')) { throw 'Per-case inventory status changed.' }
    }
}
$geometry = Read-Json (Join-Path $audit 'production_route_geometry_20260907/route_geometry_audit_v2.json')
if (-not $geometry.geometry_audit_complete -or $geometry.physical_geometry_count -ne 115 -or
        $geometry.intended_sma_routes.Count -ne 2 -or $geometry.unassigned_thermal_mass_blocks.Count -ne 0 -or
        $geometry.explicit_connector_named_thermal_mass_blocks.Count -ne 0 -or
        $geometry.thermal_connectivity_verified -or $geometry.article_connector_assignment_fully_proven -or
        $geometry.production_geometry_modified -or $geometry.production_recovery_allowed -or $geometry.whole_model_first_law_verified) {
    throw 'Geometry inventory or qualification changed.'
}
foreach ($route in $geometry.intended_sma_routes) {
    if ($route.pipes.Count -ne 22 -or $route.manifolds.Count -ne 2 -or
            [math]::Abs($route.equivalent_public_connector_length_m-.4) -gt 1e-12 -or
            $route.physical_public_connector_friction_length_m -ne 0) { throw 'Route changed.' }
}
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
    $receipt = @()
    foreach ($mode in @($modes)+@('geometry')) {
        $temp = Join-Path $root "recompute_${mode}.json"
        if ($mode -eq 'geometry') {
            & python (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_RouteGeometryResult.py') --repo $repo --output $temp | Out-Null
            $source = Join-Path $audit 'production_route_geometry_20260907/route_geometry_audit_v2.json'
        } else {
            & python (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_PipeAblation.py') --repo $repo --mode $mode --output $temp | Out-Null
            $source = Join-Path $audit "ablation_${mode}_20260907/ablation_audit_v1.json"
        }
        if ($LASTEXITCODE -ne 0) { throw 'Independent audit failed.' }
        $hash = (Get-FileHash -LiteralPath $source).Hash
        if ((Get-FileHash -LiteralPath $temp).Hash -ne $hash) { throw "Recomputation differs: $mode" }
        $receipt += [pscustomobject]@{mode=$mode;exit_code=0;identical=$true;sha256=$hash}
        Remove-Item -LiteralPath $temp
    }
    $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'independent_recomputation.json') -Encoding utf8
    $dirs = @($modes | ForEach-Object { "ablation_${_}_20260907" }) + @('production_route_geometry_20260907')
    $evidence = @($dirs | ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $audit $_) -File -Recurse })
    $files = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    [ordered]@{measured_at=(Get-Date).ToString('o');bytes=($files|Measure-Object Length -Sum).Sum;file_count=$files.Count;
        retained_stage_evidence_bytes=($evidence|Measure-Object Length -Sum).Sum;copied_production_raw_bytes=0;deleted_bytes=0;
        git_objects=(git -C $workspace count-objects -vH)} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch,(Join-Path $root 'python_tests.log'),(Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $root 'independent_recomputation.json'),(Join-Path $audit 'dual_pipe_release_20260907/release.json'),
        (Join-Path $audit 'dual_pipe_release_20260907/result_manifest.csv')) + @($evidence | Select-Object -ExpandProperty FullName)
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace,$_);bytes=(Get-Item -LiteralPath $_).Length;
            sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_route_ablation_release_v1';source_commit=$commit;source_base_commit=$base.source_commit;
        required_file_count=$rows.Count;tests_exit_code=$testCode;new_actual_simscape_cases=18;new_inventory_passed_cases=6;
        new_inventory_failed_cases=12;production_recovery_allowed=$false;whole_model_first_law_verified=$false;
        table4_reproduction_claim=$false;source_package='Stage17 ZIP plus direct baseline patch; no production raw copies'} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_route_ablation_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path|Sort-Object -Unique).Count -ne $manifest.Count -or $release.tests_exit_code -ne 0 -or
        $release.new_actual_simscape_cases -ne 18 -or $release.new_inventory_passed_cases -ne 6 -or
        $release.new_inventory_failed_cases -ne 12 -or $release.production_recovery_allowed -or
        $release.whole_model_first_law_verified -or $release.table4_reproduction_claim) { throw 'Release scope changed.' }
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence escapes workspace.'
    }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) {
        throw "Changed evidence: $path"
    }
}
[ordered]@{package_integrity_pass=$true;required_files=$manifest.Count;source_commit=$release.source_commit;
    new_actual_simscape_cases=18;new_inventory_passed_cases=6;new_inventory_failed_cases=12;
    production_recovery_allowed=$false;whole_model_first_law_verified=$false;
    source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
