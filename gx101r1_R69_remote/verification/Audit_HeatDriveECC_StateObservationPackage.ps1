[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$release = Join-Path $repo 'outputs_storage_audit\runtime_observation_c200_release_20260906'
$contractPath = Join-Path $PSScriptRoot 'runtime_observation_c200_diagnostic_contract.json'
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
if ($contract.schema -ne 'heatdrive_ecc_runtime_state_observation_diagnostic_v1' -or
        $contract.recovery_policy.state_recovery_allowed -or
        $contract.periodic_steady_state -or $contract.steady_parameter_study_allowed -or
        $contract.strict_table4_reproduction -or -not $contract.mechanism_pass) {
    throw 'Runtime C200 must remain a mechanism-valid, nonperiodic observation, not an authority.'
}
$hashes = @{}
foreach ($kind in @('result','checkpoint','observation')) {
    $path = [IO.Path]::GetFullPath((Join-Path $repo $contract."${kind}_relative_path"))
    if (-not $path.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) { throw 'Observation artifact escapes repository.' }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -ne $contract."${kind}_sha256") { throw "Observation $kind hash mismatch." }
    $hashes[$path] = $hash
    if ($kind -eq 'result') { $resultDir = Split-Path -Parent $path }
}
$energy = Get-Content -LiteralPath (Join-Path $resultDir 'system_energy_audit.json') -Raw | ConvertFrom-Json
$completion = Get-Content -LiteralPath (Join-Path $resultDir 'observation_completion.json') -Raw | ConvertFrom-Json
if (-not $energy.mechanism_pass -or -not $energy.local_exchanger_kcl_pass -or
        -not $energy.boundary_direction_pass -or -not $energy.fluid_mass_conservation_pass -or
        -not $energy.modeled_thermal_closure_pass -or $energy.production_pass -or
        $energy.periodic_steady_state -or $completion.status -ne 'transient_observation_complete' -or
        -not $completion.physical_gates_pass -or $completion.steady_parameter_study_allowed -or
        $completion.checkpoint_recovery_authorized_by_this_audit) { throw 'Gate classification mismatch.' }
$drift = Get-Content -LiteralPath (Join-Path $resultDir 'internal_state_drift.json') -Raw | ConvertFrom-Json
if ($drift.observation_sha256 -ne $contract.observation_sha256 -or
        $drift.logged_group_count -ne 73 -or $drift.logged_coordinate_count -ne 1376 -or
        -not $drift.all_three_PI_memories_observed -or
        -not $drift.all_logged_groups_have_ten_cycle_comparisons -or
        $drift.complete_internal_state_periodicity_verified) { throw 'State observation coverage mismatch.' }
$coverage = Get-Content -LiteralPath (Join-Path $resultDir 'internal_state_coverage.json') -Raw | ConvertFrom-Json
if ($coverage.source_sha256 -ne $contract.result_sha256 -or
        -not $coverage.PI_route_memory_timeseries_recorded -or
        $coverage.complete_internal_state_periodicity_verified) { throw 'Physical coverage mismatch.' }
$terminal = Get-Content -LiteralPath (Join-Path $resultDir 'terminal_state_comparison.json') -Raw | ConvertFrom-Json
if ($terminal.source_result_sha256 -ne $contract.result_sha256 -or
        -not $terminal.phase_rms_fails_both_grids -or $terminal.production_gate_changed -or
        $terminal.recovery_authorized) { throw 'Terminal diagnostic boundary mismatch.' }
$figureRoot = Join-Path $resultDir 'figures_state_audit'
$qaPath = Join-Path $figureRoot 'figure_visual_qa.json'
$qa = Get-Content -LiteralPath $qaPath -Raw | ConvertFrom-Json
if (-not $qa.png_review_pass -or -not $qa.pdf_render_review_pass -or
        $qa.source_result_sha256 -ne $contract.result_sha256) { throw 'Figure review missing.' }
foreach ($file in $qa.files) {
    $path = Join-Path $figureRoot $file.name
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $file.sha256) {
        throw 'Reviewed figure hash mismatch.'
    }
}
$snapshot = Get-Content -LiteralPath (Join-Path $release 'source_snapshot_sha256.json') -Raw | ConvertFrom-Json
$expectedSimulation = (& git -C $repo rev-parse "$($contract.simulation_code_commit)^{commit}").Trim()
if ($snapshot.simulation_commit -ne $expectedSimulation -or
        (Get-FileHash -LiteralPath $snapshot.archive_path -Algorithm SHA256).Hash -ne $snapshot.sha256) {
    throw 'Source snapshot provenance mismatch.'
}
$chain = Split-Path -Parent $resultDir
$required = @($contractPath) + @($hashes.Keys) + @(
    'physical_validation_report.txt','cycle_physical_summary.csv','qian2019_table2_table4_parameter_contract.csv',
    'system_energy_audit.json','observation_completion.json','internal_state_drift.json',
    'internal_state_coverage.json','terminal_state_comparison.json'
) | ForEach-Object { if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $resultDir $_ } }
$required += @('matlab_stdout.log','matlab_stderr.log','steady_continuation_progress.csv',
    'steady_continuation_state.mat','observation_launch.json','launch_process.json','monitor_30min_second.json') |
    ForEach-Object { Join-Path $chain $_ }
$required += @($qaPath, (Join-Path $figureRoot 'figure_source.json'))
$required += @($qa.files | ForEach-Object { Join-Path $figureRoot $_.name })
$required += @($snapshot.archive_path, (Join-Path $release 'source_snapshot_sha256.json'),
    (Join-Path $workspace '项目文档\报告\SMA-SE正逆耦合_第十五阶段内部状态观测与未稳态诊断报告.md'))
$manifest = foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing required artifact: $path" }
    $hash = if ($hashes.ContainsKey($path)) { $hashes[$path] } else {
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    [pscustomobject]@{path=$path; bytes=(Get-Item -LiteralPath $path).Length; sha256=$hash}
}
$manifest | Export-Csv -LiteralPath (Join-Path $release 'result_package_manifest.csv') -NoTypeInformation -Encoding utf8
$result = [ordered]@{
    schema='heatdrive_ecc_state_observation_package_v1'; generated_at=(Get-Date).ToString('o')
    package_pass=$true; required_count=@($required).Count; source_commit=$snapshot.source_commit
    simulation_commit=$expectedSimulation; mechanism_pass=$true; thermal_mass_pass=$true
    declared_periodic_gate_pass=$false; complete_internal_state_periodicity_verified=$false
    steady_parameter_study_allowed=$false; checkpoint_recovery_authorized=$false
    strict_table4_reproduction=$false
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $release 'package_audit.json') -Encoding utf8
$result | ConvertTo-Json
