[CmdletBinding()]
param([switch]$Create)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$audit = Join-Path $repo 'outputs_storage_audit'
$root = Join-Path $audit 'dual_pipe_release_20260907'
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_DualRampPackage.ps1') | Out-Null
$sources = @('dual_pipe_friction_20260907_v2/pipe_friction_audit_v1.json','dual_pipe_hard_switch_20260907/pipe_hard_audit_v1.json')
foreach ($source in $sources) {
    $result = Read-Json (Join-Path $audit $source)
    if (-not $result.computation_complete -or $result.actual_simscape_cases -ne 12 -or $result.cases.Count -ne 12 -or
            $result.actual_scalar_trace_count -ne 1092 -or $result.mass_absolute_gate_kg -ne 1e-15 -or $result.energy_absolute_gate_J -ne 1e-8 -or
            -not $result.conservative_inventory_all_pass -or -not $result.all_spatial_port_identities_pass -or
            -not $result.all_pump_mode_formulas_pass -or -not $result.all_momentum_pressure_pass -or
            -not $result.all_thermal_excitation_observed -or -not $result.all_valve_commands_pass -or
            $result.production_model_changed -or $result.production_recovery_allowed -or $result.whole_model_first_law_verified -or
            $result.hard_switch_failure_resolved -or $result.table4_reproduction_claim -or $result.omitted_event_intervals -ne 0) {
        throw 'Pipe diagnostic scope or gates changed.'
    }
    foreach ($case in $result.cases) {
        if ($case.formulation -eq 'conservative' -and -not $case.dual_inventory_closure_pass) { throw 'Rejected case promoted.' }
        if ($case.pipe_contract.production_qualification -or $case.pipe_contract.inertia) { throw 'Pipe scope changed.' }
    }
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
    if ($LASTEXITCODE -ne 0) { throw 'Source delta creation failed.' }
    git -C $workspace apply --reverse --check $patch
    if ($LASTEXITCODE -ne 0) { throw 'Source delta verification failed.' }
    $tests = & python -m unittest discover -s (Join-Path $repo 'verification') -p 'test_*.py' -v 2>&1
    $testCode = $LASTEXITCODE
    $tests | Set-Content -LiteralPath (Join-Path $root 'python_tests.log') -Encoding utf8
    if ($testCode -ne 0) { throw 'Regression tests failed.' }
    $receipt = @()
    for ($i=0; $i -lt $sources.Count; $i++) {
        $temp = Join-Path $root "recompute_$i.json"
        $options = @('--repo',$repo,'--output',$temp)
        if ($i -eq 1) { $options += '--hard' }
        & python (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_DualPipeResult.py') @options | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Independent pipe audit failed.' }
        $hash = (Get-FileHash -LiteralPath (Join-Path $audit $sources[$i])).Hash
        if ((Get-FileHash -LiteralPath $temp).Hash -ne $hash) { throw 'Independent recomputation changed.' }
        $receipt += [pscustomobject]@{source=$sources[$i];exit_code=0;identical=$true;sha256=$hash}
        Remove-Item -LiteralPath $temp
    }
    $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'independent_recomputation.json') -Encoding utf8
    $evidence = @(@('dual_pipe_friction_20260907','dual_pipe_friction_20260907_v2','dual_pipe_hard_switch_20260907') |
        ForEach-Object { Get-ChildItem -LiteralPath (Join-Path $audit $_) -File -Recurse })
    $files = @(Get-ChildItem -LiteralPath $workspace -File -Recurse -Force)
    [ordered]@{measured_at=(Get-Date).ToString('o');bytes=($files|Measure-Object Length -Sum).Sum;file_count=$files.Count;
        retained_stage_evidence_bytes=($evidence|Measure-Object Length -Sum).Sum;copied_production_raw_bytes=0;deleted_bytes=0;
        git_objects=(git -C $workspace count-objects -vH)} | ConvertTo-Json |
        Set-Content -LiteralPath (Join-Path $root 'workspace_storage_snapshot.json') -Encoding utf8
    $paths = @($patch,(Join-Path $root 'python_tests.log'),(Join-Path $root 'workspace_storage_snapshot.json'),
        (Join-Path $root 'independent_recomputation.json'),(Join-Path $audit 'dual_ramp_release_20260907/release.json'),
        (Join-Path $audit 'dual_ramp_release_20260907/result_manifest.csv'))
    $paths += @($evidence | Select-Object -ExpandProperty FullName)
    $rows = @($paths | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{relative_path=[IO.Path]::GetRelativePath($workspace,$_);bytes=(Get-Item -LiteralPath $_).Length;
            sha256=(Get-FileHash -LiteralPath $_).Hash}
    })
    $rows | Export-Csv -LiteralPath (Join-Path $root 'result_manifest.csv') -NoTypeInformation -Encoding utf8
    [ordered]@{schema='heatdrive_ecc_dual_pipe_release_v1';source_commit=$commit;source_base_commit=$base.source_commit;
        required_file_count=$rows.Count;tests_exit_code=$testCode;actual_simscape_cases=24;conservative_inventory_passed_cases=12;
        pipe_diagnostic_gate_pass=$true;production_recovery_allowed=$false;whole_model_first_law_verified=$false;
        table4_reproduction_claim=$false;source_package='Stage17 full ZIP plus this direct-from-base patch; no production raw copy'} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'release.json') -Encoding utf8
}
$release = Read-Json (Join-Path $root 'release.json')
$manifest = @(Import-Csv -LiteralPath (Join-Path $root 'result_manifest.csv'))
if ($release.schema -ne 'heatdrive_ecc_dual_pipe_release_v1' -or $release.required_file_count -ne $manifest.Count -or
        @($manifest.relative_path | Sort-Object -Unique).Count -ne $manifest.Count -or $release.tests_exit_code -ne 0 -or
        $release.actual_simscape_cases -ne 24 -or $release.conservative_inventory_passed_cases -ne 12 -or
        -not $release.pipe_diagnostic_gate_pass -or $release.production_recovery_allowed -or
        $release.whole_model_first_law_verified -or $release.table4_reproduction_claim) { throw 'Release scope overstated.' }
foreach ($row in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $workspace $row.relative_path))
    if (-not $path.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence escapes workspace.'
    }
    if ((Get-Item -LiteralPath $path).Length -ne [long]$row.bytes -or (Get-FileHash -LiteralPath $path).Hash -ne $row.sha256) {
        throw "Changed evidence: $path"
    }
}
[ordered]@{package_integrity_pass=$true;pipe_diagnostic_gate_pass=$true;required_files=$manifest.Count;
    actual_simscape_cases=24;conservative_inventory_passed_cases=12;source_commit=$release.source_commit;
    production_recovery_allowed=$false;whole_model_first_law_verified=$false;
    source_delta_bytes=(Get-Item -LiteralPath (Join-Path $root 'source_delta.patch')).Length} | ConvertTo-Json
