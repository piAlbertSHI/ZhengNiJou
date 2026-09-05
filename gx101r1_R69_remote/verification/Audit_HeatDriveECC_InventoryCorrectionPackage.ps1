[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$root = Join-Path $repo 'outputs_storage_audit\native_inventory_port_comparison_20260906'
$modelRoot = Join-Path $repo 'outputs_storage_audit\native_inventory_model_metadata_20260906'
$release = Join-Path $repo 'outputs_storage_audit\inventory_correction_release_20260906'
$contractPath = Join-Path $PSScriptRoot 'runtime_c180_recovery_contract.json'
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$policy = $contract.control_volume_basis_review
if ($policy.production_continuation_allowed -or -not $policy.strict_inventory_diagnostic_allowed -or
        $policy.equation_matched_thermal_closure_verified -or
        $policy.equation_matched_mass_conservation_verified -or $contract.steady_parameter_study_allowed) {
    throw 'The unresolved component ledger must not authorize production or parameter studies.'
}
$probe = Get-Content -LiteralPath (Join-Path $root 'native_inventory_probe.json') -Raw | ConvertFrom-Json
$catalog = Get-Content -LiteralPath (Join-Path $root 'native_inventory_catalog.json') -Raw | ConvertFrom-Json
$coverage = Get-Content -LiteralPath (Join-Path $root 'internal_state_coverage_v3.json') -Raw | ConvertFrom-Json
$modelPath = Join-Path $modelRoot 'storage_model_metadata.json'
if (-not $probe.collection_pass -or -not $probe.strict_restore_pass -or $probe.probe_state_may_resume -or
        $catalog.component_count -ne 119 -or -not $catalog.all_four_workspace_signals_match_port_A -or
        $catalog.equation_matched_cycle_closure_verified -or $catalog.production_continuation_allowed -or
        $catalog.complete_internal_state_periodicity_verified -or $catalog.diagnostic_checkpoint_recovery_allowed -or
        $catalog.probe_json_sha256 -ne (Get-FileHash -LiteralPath (Join-Path $root 'native_inventory_probe.json')).Hash -or
        $catalog.model_metadata_sha256 -ne (Get-FileHash -LiteralPath $modelPath).Hash -or
        $coverage.schema -ne 'heatdrive_ecc_internal_state_coverage_v3' -or
        $coverage.native_buffer_internal_temperature_periodicity_verified) {
    throw 'Correction evidence or semantic boundary mismatch.'
}
$required = @($contractPath, $modelPath, (Join-Path $modelRoot 'matlab_stdout.log'),
    (Join-Path $modelRoot 'matlab_stderr.log'))
$required += @('native_inventory_probe.json','native_inventory_probe.mat','native_inventory_catalog.json',
    'native_inventory_catalog.csv','internal_state_coverage_v3.json','matlab_stdout.log','matlab_stderr.log',
    'Fig08_v2_pdf_render.png') | ForEach-Object { Join-Path $root $_ }
$observationContractPath = Join-Path $PSScriptRoot 'runtime_observation_c200_diagnostic_contract.json'
$observationContract = Get-Content -LiteralPath $observationContractPath -Raw | ConvertFrom-Json
$required += $observationContractPath
$hashes = @{}
foreach ($c in @($contract, $observationContract)) {
    $kinds = @('result','checkpoint')
    if ($c.PSObject.Properties.Name -contains 'observation_relative_path') { $kinds += 'observation' }
    foreach ($kind in $kinds) {
        $path = [IO.Path]::GetFullPath((Join-Path $repo $c."${kind}_relative_path"))
        if (-not $path.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence path escapes repository.' }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($hash -ne $c."${kind}_sha256") { throw "Frozen $kind has changed." }
        $hashes[$path] = $hash
        $required += $path
    }
}
if ($probe.source_result_sha256 -ne $contract.result_sha256 -or
        $probe.source_checkpoint_sha256 -ne $contract.checkpoint_sha256 -or
        $coverage.source_sha256 -ne $observationContract.result_sha256) { throw 'Source chain mismatch.' }
$resultRoot = Split-Path -Parent (Join-Path $repo $observationContract.result_relative_path)
$figureRoot = Join-Path $resultRoot 'figures_state_audit_v2'
$qaPath = Join-Path $figureRoot 'figure_visual_qa.json'
$qa = Get-Content -LiteralPath $qaPath -Raw | ConvertFrom-Json
$sourcePath = Join-Path $figureRoot 'figure_source.json'
$source = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
if (-not $qa.png_review_pass -or -not $qa.pdf_render_review_pass -or
        -not $qa.port_temperature_semantics_review_pass -or $qa.values_changed_from_v1 -or
        $source.full_internal_steady_claim -or $source.table4_reproduction_claim -or
        $source.source_coverage_sha256 -ne (Get-FileHash -LiteralPath (Join-Path $root 'internal_state_coverage_v3.json')).Hash) {
    throw 'Figure semantic/visual review is incomplete.'
}
$required += @($qaPath, $sourcePath)
foreach ($f in $qa.files) {
    $path = Join-Path $figureRoot $f.name
    if ((Get-FileHash -LiteralPath $path).Hash -ne $f.sha256) { throw 'Reviewed figure changed.' }
    $required += $path
}
$snapshotPath = Join-Path $release 'source_snapshot_sha256.json'
$snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $snapshot.archive_path).Hash -ne $snapshot.sha256) { throw 'Source archive changed.' }
$required += @($snapshotPath, $snapshot.archive_path,
    (Join-Path $workspace '项目文档\报告\SMA-SE正逆耦合_第十六阶段控制体语义更正与工作区管理报告.md'),
    (Join-Path $workspace '项目文档\研究笔记\长任务运行纪律.md'))
$manifest = foreach ($path in ($required | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing evidence: $path" }
    $hash = if ($hashes.ContainsKey($path)) { $hashes[$path] } else { (Get-FileHash -LiteralPath $path).Hash }
    [pscustomobject]@{path=$path; bytes=(Get-Item -LiteralPath $path).Length; sha256=$hash}
}
$manifest | Export-Csv -LiteralPath (Join-Path $release 'correction_manifest.csv') -NoTypeInformation -Encoding utf8
$result = [ordered]@{
    schema='heatdrive_ecc_inventory_correction_package_v1'; generated_at=(Get-Date).ToString('o')
    package_integrity_pass=$true; required_count=@($manifest).Count; source_commit=$snapshot.source_commit
    production_simulation_commit=$snapshot.simulation_commit
    diagnostic_probe_executed_from_uncommitted_definition=$true
    old_report_and_figure_values_superseded_only_in_semantics=$true
    equation_matched_cycle_closure_verified=$false; complete_internal_state_periodicity_verified=$false
    production_continuation_allowed=$false; steady_parameter_study_allowed=$false; table4_reproduction=$false
}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $release 'correction_package_audit.json') -Encoding utf8
$result | ConvertTo-Json
