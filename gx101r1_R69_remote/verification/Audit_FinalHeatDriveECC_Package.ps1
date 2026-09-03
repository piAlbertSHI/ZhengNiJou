<#
.SYNOPSIS
    Build a reproducible manifest and SHA-256 inventory for the final package.

.DESCRIPTION
    This is a read-only audit of the completed fixed-CHEX result. It does not
    load MAT files, start MATLAB, modify a checkpoint, or delete old outputs.
    The rejected 270 K branch is represented by its reports and rejection
    marker only; its raw MAT is deliberately excluded from the final package.
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = '',
    [string]$AuditRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
} else {
    $WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)
}
$repoRoot = Join-Path $WorkspaceRoot 'gx101r1_R69_remote'
if ([string]::IsNullOrWhiteSpace($AuditRoot)) {
    $AuditRoot = Join-Path $repoRoot 'outputs_storage_audit'
} else {
    $AuditRoot = [System.IO.Path]::GetFullPath($AuditRoot)
}

$mainRoot = Join-Path $repoRoot 'outputs\qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821'
$mainRun = Join-Path $mainRoot 'qian2019_table2_table4_simscape_200cycle_20260821_121246'
$rejectedRoot = Join-Path $repoRoot 'outputs\qian_table4_fixed_Tc_270p000K_kp136_255_rootpoint_20260821'
$rejectedRun = Join-Path $rejectedRoot 'qian2019_table2_table4_simscape_20cycle_20260821_142345'
$sourceC240ContractPath = Join-Path $repoRoot 'verification\source_heatflow_c240_recovery_contract.json'
$sourceC240Contract = Get-Content -LiteralPath $sourceC240ContractPath -Raw | ConvertFrom-Json
$sourceC240Run = Join-Path $repoRoot 'outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\qian2019_table2_table4_simscape_240cycle_20260901_001301'
$shexControlRoot = Join-Path $repoRoot `
    'outputs_storage_audit\shex_control_volume_c240_20260903'
$shexControlSummaryPath = Join-Path $shexControlRoot `
    'shex_control_volume_summary.json'
$shexControlPackagePath = Join-Path $shexControlRoot 'package_contract.json'
$shexControlSummary = Get-Content -LiteralPath $shexControlSummaryPath -Raw |
    ConvertFrom-Json
$shexControlPackage = Get-Content -LiteralPath $shexControlPackagePath -Raw |
    ConvertFrom-Json
$shexC242ContractPath = Join-Path $repoRoot `
    'verification\shex_fullcycle_c242_recovery_contract.json'
$shexC242Contract = Get-Content -LiteralPath $shexC242ContractPath -Raw |
    ConvertFrom-Json
$shexC242Root = Join-Path $repoRoot `
    'outputs\qian_coupled_shex_fullcycle_c242_v2_20260903'
$shexC242Run = Join-Path $shexC242Root `
    'qian2019_table2_table4_simscape_242cycle_20260903_173052'
$shexC242AuditPath = Join-Path $shexC242Root `
    'shex_transfer_audit_c242.json'
$shexC242Audit = Get-Content -LiteralPath $shexC242AuditPath -Raw |
    ConvertFrom-Json
$systemC243ContractPath = Join-Path $repoRoot `
    'verification\system_energy_c243_recovery_contract.json'
$systemC243Contract = Get-Content -LiteralPath $systemC243ContractPath -Raw |
    ConvertFrom-Json
$systemC243Root = Join-Path $repoRoot `
    'outputs\qian_coupled_system_energy_c243_20260904'
$systemC243Run = Join-Path $systemC243Root `
    'qian2019_table2_table4_simscape_243cycle_20260904_025423'
$systemC243AuditPath = Join-Path $systemC243Root `
    'system_energy_audit_c243.json'
$systemC243Audit = Get-Content -LiteralPath $systemC243AuditPath -Raw |
    ConvertFrom-Json

New-Item -ItemType Directory -Force -Path $AuditRoot | Out-Null
$manifestPath = Join-Path $AuditRoot 'final_results_manifest_20260824.csv'
$hashPath = Join-Path $AuditRoot 'final_results_sha256_20260824.csv'
$summaryPath = Join-Path $AuditRoot 'final_results_audit_summary_20260824.json'

$entries = [System.Collections.Generic.List[object]]::new()
function Add-Entry {
    param(
        [string]$Role,
        [string]$Path,
        [bool]$Required = $true,
        [string]$Status = 'authoritative'
    )
    $entries.Add([pscustomobject]@{
        role = $Role
        path = [System.IO.Path]::GetFullPath($Path)
        required = $Required
        status = $Status
    })
}

Add-Entry 'C200 physical result' (Join-Path $mainRun 'physical_simscape_result.mat')
Add-Entry 'C200 final Operating Point' (Join-Path $mainRun 'final_operating_point.mat')
Add-Entry 'C200 continuation progress' (Join-Path $mainRoot 'steady_continuation_progress.csv')
Add-Entry 'C200 continuation state' (Join-Path $mainRoot 'steady_continuation_state.mat')
Add-Entry 'C200 validation report' (Join-Path $mainRun 'physical_validation_report.txt')
Add-Entry 'C200 cycle summary' (Join-Path $mainRun 'cycle_physical_summary.csv')
Add-Entry 'C200 parameter contract' (Join-Path $mainRun 'qian2019_table2_table4_parameter_contract.csv')
Add-Entry 'C200 temperature probe sample' (Join-Path $mainRun 'stage_temperature_probes_50samples.csv')
Add-Entry 'C200 figure manifest' (Join-Path $mainRun 'figures_sci\figure_manifest.txt')
foreach ($stem in @(
    'Fig01_last_cycle_mechanism',
    'Fig02_last_cycle_axial_fields',
    'Fig03_periodic_convergence',
    'Fig04_control_and_energy',
    'Fig05_table4_boundary_audit')) {
    Add-Entry "SCI figure PNG $stem" (Join-Path $mainRun "figures_sci\$stem.png")
    Add-Entry "SCI figure PDF $stem" (Join-Path $mainRun "figures_sci\$stem.pdf")
}
Add-Entry 'C200 fixed-reservoir manifest' (Join-Path $mainRoot 'fixed_reservoir_point_manifest.txt')
Add-Entry 'C200 stdout' (Join-Path $mainRoot 'matlab_stdout.log')
Add-Entry 'C200 stderr' (Join-Path $mainRoot 'matlab_stderr.log')
Add-Entry 'C200 freeze contract' (Join-Path $repoRoot 'verification\c200_mainline_freeze_contract.json')
Add-Entry 'C240 superseded physical result' (Join-Path $sourceC240Run 'physical_simscape_result.mat') $false 'historical_superseded'
Add-Entry 'C240 superseded Operating Point' (Join-Path $sourceC240Run 'final_operating_point.mat') $false 'historical_superseded'
Add-Entry 'C240 source heat-flow validation report' (Join-Path $repoRoot 'outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\qian2019_table2_table4_simscape_240cycle_20260901_001301\physical_validation_report.txt')
Add-Entry 'C240 source heat-flow result audit' (Join-Path $repoRoot 'outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\qian2019_table2_table4_simscape_240cycle_20260901_001301\source_heat_flow_result_audit.mat')
Add-Entry 'C240 source heat-flow cycle summary' (Join-Path $sourceC240Run 'cycle_physical_summary.csv')
Add-Entry 'C240 source heat-flow parameter contract' (Join-Path $sourceC240Run 'qian2019_table2_table4_parameter_contract.csv')
Add-Entry 'C240 source heat-flow continuation state' (Join-Path $repoRoot 'outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\steady_continuation_state.mat')
Add-Entry 'C240 source heat-flow continuation progress' (Join-Path $repoRoot 'outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\steady_continuation_progress.csv')
Add-Entry 'C240 source heat-flow figures manifest' (Join-Path $repoRoot 'outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\qian2019_table2_table4_simscape_240cycle_20260901_001301\figures_sci\figure_manifest.txt')
foreach ($stem in @(
    'Fig01_last_cycle_mechanism',
    'Fig02_last_cycle_axial_fields',
    'Fig03_periodic_convergence',
    'Fig04_control_and_energy',
    'Fig05_table4_boundary_audit')) {
    Add-Entry "C240 source heat-flow SCI figure PNG $stem" (Join-Path $repoRoot "outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\qian2019_table2_table4_simscape_240cycle_20260901_001301\figures_sci\$stem.png")
    Add-Entry "C240 source heat-flow SCI figure PDF $stem" (Join-Path $repoRoot "outputs\qian_coupled_source_heatflow_steady_from_c220_20260831\qian2019_table2_table4_simscape_240cycle_20260901_001301\figures_sci\$stem.pdf")
}
Add-Entry 'C240 source heat-flow recovery contract' (Join-Path $repoRoot 'verification\source_heatflow_c240_recovery_contract.json')
foreach ($name in @(
        'shex_control_volume_audit.mat',
        'shex_control_volume_summary.json',
        'shex_control_volume_sample.csv',
        'Fig06_frozen_C240_SHEX_control_volume.png',
        'Fig06_frozen_C240_SHEX_control_volume.pdf',
        'artifact_manifest_sha256.csv',
        'package_contract.json',
        'matlab_stdout.log',
        'matlab_stderr.log')) {
    Add-Entry "C240 frozen SHEX control-volume artifact $name" `
        (Join-Path $shexControlRoot $name)
}

Add-Entry 'C242 superseded SHEX physical result' (Join-Path $shexC242Run 'physical_simscape_result.mat') $false 'historical_superseded'
Add-Entry 'C242 superseded SHEX final Operating Point' (Join-Path $shexC242Run 'final_operating_point.mat') $false 'historical_superseded'
Add-Entry 'C242 SHEX validation report' (Join-Path $shexC242Run 'physical_validation_report.txt')
Add-Entry 'C242 SHEX cycle summary' (Join-Path $shexC242Run 'cycle_physical_summary.csv')
Add-Entry 'C242 SHEX parameter contract' (Join-Path $shexC242Run 'qian2019_table2_table4_parameter_contract.csv')
Add-Entry 'C242 continuation progress' (Join-Path $shexC242Root 'steady_continuation_progress.csv')
Add-Entry 'C242 continuation state' (Join-Path $shexC242Root 'steady_continuation_state.mat')
Add-Entry 'C242 source heat-flow run contract' (Join-Path $shexC242Root 'source_heat_flow_run_contract.json')
Add-Entry 'C242 direct SHEX transfer audit' $shexC242AuditPath
Add-Entry 'C242 recovery contract' $shexC242ContractPath
Add-Entry 'C241 historical recovery contract' (Join-Path $repoRoot 'verification\shex_branchdiag_c241_recovery_contract.json')
Add-Entry 'C242 MATLAB stdout' (Join-Path $shexC242Root 'matlab_stdout.log')
Add-Entry 'C242 MATLAB stderr' (Join-Path $shexC242Root 'matlab_stderr.log')
Add-Entry 'C242 SCI figure manifest' (Join-Path $shexC242Run 'figures_sci\figure_manifest.txt')
foreach ($stem in @(
    'Fig01_last_cycle_mechanism',
    'Fig02_last_cycle_axial_fields',
    'Fig03_periodic_convergence',
    'Fig04_control_and_energy',
    'Fig05_table4_boundary_audit',
    'Fig06_direct_SHEX_control_volume')) {
    Add-Entry "C242 SCI figure PNG $stem" (Join-Path $shexC242Run "figures_sci\$stem.png")
    Add-Entry "C242 SCI figure PDF $stem" (Join-Path $shexC242Run "figures_sci\$stem.pdf")
}

Add-Entry 'C243 system-energy physical result' (Join-Path $systemC243Run 'physical_simscape_result.mat')
Add-Entry 'C243 system-energy final Operating Point' (Join-Path $systemC243Run 'final_operating_point.mat')
Add-Entry 'C243 validation report' (Join-Path $systemC243Run 'physical_validation_report.txt')
Add-Entry 'C243 cycle summary' (Join-Path $systemC243Run 'cycle_physical_summary.csv')
Add-Entry 'C243 parameter contract' (Join-Path $systemC243Run 'qian2019_table2_table4_parameter_contract.csv')
Add-Entry 'C243 continuation progress' (Join-Path $systemC243Root 'steady_continuation_progress.csv')
Add-Entry 'C243 continuation state' (Join-Path $systemC243Root 'steady_continuation_state.mat')
Add-Entry 'C243 source heat-flow run contract' (Join-Path $systemC243Root 'source_heat_flow_run_contract.json')
Add-Entry 'C243 modeled system-energy audit' $systemC243AuditPath
Add-Entry 'C243 recovery contract' $systemC243ContractPath
Add-Entry 'C243 MATLAB stdout' (Join-Path $systemC243Root 'matlab_stdout.log')
Add-Entry 'C243 MATLAB stderr' (Join-Path $systemC243Root 'matlab_stderr.log')
Add-Entry 'C243 SCI figure manifest' (Join-Path $systemC243Run 'figures_sci\figure_manifest.txt')
foreach ($stem in @(
    'Fig01_last_cycle_mechanism',
    'Fig02_last_cycle_axial_fields',
    'Fig03_periodic_convergence',
    'Fig04_control_and_energy',
    'Fig05_table4_boundary_audit',
    'Fig06_direct_SHEX_control_volume',
    'Fig07_modeled_system_energy_ledger')) {
    Add-Entry "C243 SCI figure PNG $stem" (Join-Path $systemC243Run "figures_sci\$stem.png")
    Add-Entry "C243 SCI figure PDF $stem" (Join-Path $systemC243Run "figures_sci\$stem.pdf")
}

Add-Entry 'Rejected 270 K report' (Join-Path $rejectedRun 'physical_validation_report.txt') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K summary' (Join-Path $rejectedRun 'cycle_physical_summary.csv') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K parameter contract' (Join-Path $rejectedRun 'qian2019_table2_table4_parameter_contract.csv') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K marker' (Join-Path $rejectedRun 'REJECTED_DO_NOT_RESUME.txt') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K manifest' (Join-Path $rejectedRoot 'fixed_reservoir_point_manifest.txt') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K stdout' (Join-Path $rejectedRoot 'matlab_stdout.log') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K progress' (Join-Path $rejectedRoot 'steady_continuation_progress.csv') $true 'diagnostic_rejected'

Add-Entry 'SCI figure source' (Join-Path $repoRoot 'Plot_HeatDriveECC_SCI_FigureSet.m')
Add-Entry 'Coupled trade-off figure source' (Join-Path $repoRoot 'Plot_HeatDriveECC_CoupledTradeoff.m')
Add-Entry 'Local sensitivity figure source' (Join-Path $repoRoot 'Plot_HeatDriveECC_LocalSensitivityAudit.m')
Add-Entry 'SHEX source heat-flow model integration' (Join-Path $repoRoot 'Integrate_HeatDriveECC_Constitutive21_Interface.m')
Add-Entry 'SHEX source heat-flow extraction' (Join-Path $repoRoot 'Run_HeatDriveECC_EighthRound_Simulink_Cycles.m')
Add-Entry 'SHEX source heat-flow performance summary' (Join-Path $repoRoot 'Summarize_HeatDriveECC_EighthRound_Output.m')
Add-Entry 'Control-volume contract source' (Join-Path $repoRoot 'verification\Build_HeatDriveECC_ControlVolumeContract.m')
Add-Entry 'SHEX source heat-flow topology audit' (Join-Path $repoRoot 'verification\Audit_HeatDriveECC_SourceHeatFlow.m')
Add-Entry 'SHEX source heat-flow result audit' (Join-Path $repoRoot 'verification\Audit_HeatDriveECC_SourceHeatFlowResult.m')
Add-Entry 'SHEX source and sink-to-fluid transfer audit' (Join-Path $repoRoot 'verification\Audit_HeatDriveECC_SHEXTransferResult.m')
Add-Entry 'Modeled system-energy result audit' (Join-Path $repoRoot 'verification\Audit_HeatDriveECC_SystemEnergyResult.m')
Add-Entry 'Native system-energy logging diagnostic' (Join-Path $repoRoot 'verification\Diagnose_HeatDriveECC_SystemEnergyLogging.m')
Add-Entry 'C243 pump-fluid energy transition assessment' (Join-Path $repoRoot 'verification\pump_fluid_energy_transition_assessment_c243.json')
Add-Entry 'Frozen C240 SHEX control-volume audit' (Join-Path $repoRoot 'verification\Audit_HeatDriveECC_FrozenSHEXControlVolume.m')
Add-Entry 'Frozen C240 SHEX package builder' (Join-Path $repoRoot 'verification\Build_HeatDriveECC_FrozenSHEXControlVolumePackage.ps1')
Add-Entry 'SHEX source heat-flow validation launcher' (Join-Path $repoRoot 'verification\Start_HeatDriveECC_SourceHeatFlowValidation.ps1')
Add-Entry 'MATLAB package verifier' (Join-Path $repoRoot 'verification\Verify_FinalHeatDriveECC_Package.m')
Add-Entry 'PowerShell package auditor' (Join-Path $repoRoot 'verification\Audit_FinalHeatDriveECC_Package.ps1')
Add-Entry 'Superseded raw cleanup script' (Join-Path $repoRoot 'verification\Prune_Superseded_HeatDriveECC_Raw.ps1')
Add-Entry 'Rejected candidate compactor' (Join-Path $repoRoot 'verification\Compact_HeatDriveECC_RejectedCandidate.ps1')
Add-Entry 'Output storage manager' (Join-Path $repoRoot 'verification\Manage_HeatDriveECC_OutputStorage.ps1')
Add-Entry 'Long-task discipline' (Join-Path $WorkspaceRoot '项目文档\研究笔记\长任务运行纪律.md')
Add-Entry 'Complete modification report' (Join-Path $WorkspaceRoot '项目文档\报告\SE21_SMA_SE耦合_完整修改与审核报告.md')
Add-Entry 'Eighth-stage strict audit report' (Join-Path $WorkspaceRoot '项目文档\报告\SMA-SE正逆耦合_第八阶段完整实施与严格审核报告.md')
Add-Entry 'Ninth-stage SHEX and literature report' (Join-Path $WorkspaceRoot '项目文档\报告\SMA-SE正逆耦合_第九阶段SHEX控制体与文献对标报告.md')
Add-Entry 'Tenth-stage C242 direct SHEX and storage report' (Join-Path $WorkspaceRoot '项目文档\报告\SMA-SE正逆耦合_第十阶段C242原生SHEX闭合与存储治理报告.md')
Add-Entry 'Eleventh-stage C243 modeled system-energy report' (Join-Path $WorkspaceRoot '项目文档\报告\SMA-SE正逆耦合_第十一阶段C243整机热控制体闭合与设备边界报告.md')
Add-Entry 'Qian local literature location index' (Join-Path $WorkspaceRoot '项目文档\研究笔记\2026-09-03_Qian本地文献精确定位与模型映射.md')

$nativeDiagnosticRoot = Join-Path $AuditRoot `
    'checkpoint_continuation_diagnostics_20260903'
foreach ($name in @(
        'README.md',
        'shex_native_short_continuation.json',
        'shex_native_fullcycle_continuation.json',
        'shex_native_fullcycle_historyfix.json')) {
    Add-Entry "SHEX native diagnostic $name" `
        (Join-Path $nativeDiagnosticRoot $name)
}

$controlRoot = Join-Path $AuditRoot 'control_volume_contract'
foreach ($name in @('control_volume_contract.csv', 'control_volume_contract.json',
        'control_volume_contract.md', 'qian_eq9_eq10_contract.csv')) {
    Add-Entry "Control-volume contract $name" (Join-Path $controlRoot $name)
}
$pairedRoot = Join-Path $AuditRoot 'paired_table4_endpoint_audit'
foreach ($name in @('paired_table4_endpoint_audit.json',
        'paired_table4_endpoint_audit.mat', 'paired_table4_endpoint_audit.txt')) {
    Add-Entry "Paired endpoint audit $name" (Join-Path $pairedRoot $name)
}
$tradeoffRoot = Join-Path $AuditRoot 'coupled_tradeoff_figure'
foreach ($name in @('Fig06_coupled_cycle_tradeoff.png',
        'Fig06_coupled_cycle_tradeoff.pdf',
        'coupled_tradeoff_sensitivity_data.csv',
        'coupled_tradeoff_boundary_data.csv',
        'coupled_tradeoff_manifest.txt')) {
    Add-Entry "Coupled trade-off artifact $name" (Join-Path $tradeoffRoot $name)
}
$localFigureRoot = Join-Path $AuditRoot 'local_sensitivity_figure'
foreach ($name in @('Fig07_local_sensitivity_audit.png',
        'Fig07_local_sensitivity_audit.pdf',
        'local_sensitivity_results.csv',
        'local_sensitivity_effects.csv',
        'local_sensitivity_manifest.txt')) {
    Add-Entry "Local sensitivity artifact $name" (Join-Path $localFigureRoot $name)
}
foreach ($relative in @(
        'outputs\qian_table4_zero_load_outer_solve_v3_20260822\outer_candidate_summary.csv',
        'outputs\qian_table4_zero_load_outer_solve_v3_20260822\outer_solve_summary.json',
        'outputs\qian_table4_zero_lift_outer_solve_20260824\outer_candidate_summary.csv',
        'outputs\qian_table4_zero_lift_outer_solve_20260824\outer_solve_summary.json',
        'outputs\qian_table4_L8_sensitivity_v3_20260822\sensitivity_results.csv',
        'outputs\qian_table4_L8_sensitivity_v3_20260822\sensitivity_effects.csv',
        'outputs\qian_table4_L8_sensitivity_v3_20260822\sensitivity_summary.json',
        'outputs\qian_table4_L8_sensitivity_v4_admissible_20260823\sensitivity_results.csv',
        'outputs\qian_table4_L8_sensitivity_v4_admissible_20260823\sensitivity_effects.csv',
        'outputs\qian_table4_L8_sensitivity_v4_admissible_20260823\sensitivity_summary.json',
        'outputs\qian_table4_local_oat_sensitivity_20260824\sensitivity_design.csv',
        'outputs\qian_table4_local_oat_sensitivity_20260824\sensitivity_results.csv',
        'outputs\qian_table4_local_oat_sensitivity_20260824\sensitivity_effects.csv',
        'outputs\qian_table4_local_oat_sensitivity_20260824\sensitivity_summary.json',
        'outputs\qian_table4_local_oat_refined_sensitivity_20260826\sensitivity_design.csv',
        'outputs\qian_table4_local_oat_refined_sensitivity_20260826\sensitivity_results.csv',
        'outputs\qian_table4_local_oat_refined_sensitivity_20260826\sensitivity_effects.csv',
        'outputs\qian_table4_local_oat_refined_sensitivity_20260826\sensitivity_summary.json',
        'outputs\qian_table4_endpoint_capacity_ultrafine_20260830\sensitivity_design.csv',
        'outputs\qian_table4_endpoint_capacity_ultrafine_20260830\sensitivity_results.csv',
        'outputs\qian_table4_endpoint_capacity_ultrafine_20260830\sensitivity_effects.csv',
        'outputs\qian_table4_endpoint_capacity_ultrafine_20260830\sensitivity_summary.json')) {
    Add-Entry "Mechanism-gated scalar result $relative" (Join-Path $repoRoot $relative)
}
$refinedRoot = Join-Path $repoRoot `
    'outputs\qian_table4_local_oat_refined_sensitivity_20260826'
$refinedEvidenceNames = @(
    'matlab_stdout.log', 'matlab_stderr.log',
    'matlab_stdout_resume_20260829_004355.log',
    'matlab_stderr_resume_20260829_004355.log',
    'matlab_stdout_resume_20260829_221144.log',
    'matlab_stderr_resume_20260829_221144.log',
    'ADMITTED_SENSITIVITY_POINT.txt', 'REJECTED_SENSITIVITY_POINT.txt',
    'COMPACTED_AFTER_SCALAR_EXTRACTION.txt',
    'sensitivity_candidate_record.mat', 'steady_continuation_progress.csv',
    'steady_continuation_state.mat', 'fixed_reservoir_point_manifest.txt',
    'physical_validation_report.txt', 'cycle_physical_summary.csv',
    'qian2019_table2_table4_parameter_contract.csv')
foreach ($file in (Get-ChildItem -LiteralPath $refinedRoot -File -Recurse |
        Where-Object { $refinedEvidenceNames -contains $_.Name })) {
    Add-Entry 'Refined local OAT gate evidence' $file.FullName
}
$ultrafineRoot = Join-Path $repoRoot `
    'outputs\qian_table4_endpoint_capacity_ultrafine_20260830'
foreach ($file in (Get-ChildItem -LiteralPath $ultrafineRoot -File -Recurse |
        Where-Object { $refinedEvidenceNames -contains $_.Name })) {
    Add-Entry 'Ultrafine endpoint-capacity gate evidence' $file.FullName
}
$cleanupSummary = Get-ChildItem -LiteralPath $AuditRoot -File -Filter 'cleanup_summary_*.txt' |
    Where-Object { @(Get-Content -LiteralPath $_.FullName |
            Where-Object { $_ -eq 'mode=apply' }).Count -gt 0 } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($null -eq $cleanupSummary) {
    throw "Applied storage cleanup audit is missing from $AuditRoot"
}
Add-Entry 'Applied storage cleanup summary' $cleanupSummary.FullName
$candidateLine = Get-Content -LiteralPath $cleanupSummary.FullName |
    Where-Object { $_ -like 'candidate_csv=*' } | Select-Object -First 1
if ($null -eq $candidateLine) {
    throw "Cleanup summary does not identify its candidate CSV: $($cleanupSummary.FullName)"
}
Add-Entry 'Applied storage cleanup candidate inventory' $candidateLine.Substring('candidate_csv='.Length)

$manifest = foreach ($entry in $entries) {
    $exists = Test-Path -LiteralPath $entry.path -PathType Leaf
    [pscustomobject]@{
        role = $entry.role
        path = $entry.path
        relative_path = [System.IO.Path]::GetRelativePath($WorkspaceRoot, $entry.path)
        required = $entry.required
        status = $entry.status
        exists = $exists
        bytes = if ($exists) { (Get-Item -LiteralPath $entry.path).Length } else { $null }
    }
}
$manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

$missing = @($manifest | Where-Object { $_.required -and -not $_.exists })
if ($missing.Count -gt 0) {
    throw ('Required package files are missing: ' + ($missing.relative_path -join '; '))
}

$initialSummaryPath = Join-Path $repoRoot `
    'outputs\qian_table4_local_oat_sensitivity_20260824\sensitivity_summary.json'
$refinedSummaryPath = Join-Path $repoRoot `
    'outputs\qian_table4_local_oat_refined_sensitivity_20260826\sensitivity_summary.json'
$initialSummary = Get-Content -LiteralPath $initialSummaryPath -Raw | ConvertFrom-Json
$refinedSummary = Get-Content -LiteralPath $refinedSummaryPath -Raw | ConvertFrom-Json
$ultrafineSummaryPath = Join-Path $repoRoot `
    'outputs\qian_table4_endpoint_capacity_ultrafine_20260830\sensitivity_summary.json'
$ultrafineSummary = Get-Content -LiteralPath $ultrafineSummaryPath -Raw | ConvertFrom-Json
if ($initialSummary.completed_count -ne 12 -or $initialSummary.pending_count -ne 0 -or
        $initialSummary.strict_local_pair_count -ne 2) {
    throw ('Unexpected local OAT completion contract: completed={0}, pending={1}, strict_pairs={2}' -f
        $initialSummary.completed_count, $initialSummary.pending_count,
        $initialSummary.strict_local_pair_count)
}
if ($refinedSummary.completed_count -ne 10 -or $refinedSummary.pending_count -ne 2 -or
        $refinedSummary.strict_local_pair_count -ne 4) {
    throw ('Unexpected refined OAT contract: completed={0}, pending={1}, strict_pairs={2}' -f
        $refinedSummary.completed_count, $refinedSummary.pending_count,
        $refinedSummary.strict_local_pair_count)
}
if ($ultrafineSummary.completed_count -ne 2 -or
        $ultrafineSummary.admissible_count -ne 1 -or
        $ultrafineSummary.rejected_count -ne 1 -or
        $ultrafineSummary.pending_count -ne 10 -or
        $ultrafineSummary.strict_local_pair_count -ne 0) {
    throw ('Unexpected ultrafine endpoint contract: completed={0}, admissible={1}, rejected={2}, pending={3}, strict_pairs={4}' -f
        $ultrafineSummary.completed_count, $ultrafineSummary.admissible_count,
        $ultrafineSummary.rejected_count, $ultrafineSummary.pending_count,
        $ultrafineSummary.strict_local_pair_count)
}
if (-not [bool]$shexC242Contract.mechanism_pass -or
        -not [bool]$shexC242Contract.periodic_steady_state -or
        -not [bool]$shexC242Contract.direct_shex_control_volume_pass -or
        [bool]$shexC242Contract.system_energy_closure_complete -or
        [int]$shexC242Contract.completed_cycles -ne 242 -or
        [bool]$shexC242Contract.recovery_policy.state_recovery_allowed -or
        [bool]$shexC242Contract.recovery_policy.preserve_final_operating_point -or
        [string]$shexC242Contract.authority_status -ne
            'superseded_by_C243_modeled_system_energy_authority') {
    throw 'Unexpected C242 SHEX recovery contract gates.'
}
if (-not [bool]$shexC242Audit.production_pass -or
        -not [bool]$shexC242Audit.periodic_steady_state -or
        -not [bool]$shexC242Audit.source_direction_pass -or
        -not [bool]$shexC242Audit.sink_to_fluid_direction_pass -or
        -not [bool]$shexC242Audit.direct_control_volume_pass -or
        [string]$shexC242Audit.sink_to_fluid_window_contract -ne
            'final_complete_cycle_only' -or
        [double]$shexC242Audit.sink_to_fluid_observed_duration_s -ne 10.0 -or
        [math]::Abs([double]$shexC242Audit.transfer_ratio - 1.0) -gt 1.0e-4 -or
        [double]$shexC242Audit.direct_control_volume_residual_relative -gt 1.0e-3 -or
        [bool]$shexC242Audit.system_energy_closure_complete) {
    throw 'Unexpected C242 direct SHEX control-volume gates.'
}
$systemC243Result = Join-Path $systemC243Run 'physical_simscape_result.mat'
$systemC243Checkpoint = Join-Path $systemC243Run 'final_operating_point.mat'
if (-not [bool]$systemC243Contract.mechanism_pass -or
        -not [bool]$systemC243Contract.periodic_steady_state -or
        -not [bool]$systemC243Contract.modeled_thermal_closure_pass -or
        -not [bool]$systemC243Contract.fluid_mass_conservation_pass -or
        [bool]$systemC243Contract.complete_device_first_law_closure -or
        [int]$systemC243Contract.completed_cycles -ne 243 -or
        -not [bool]$systemC243Contract.recovery_policy.state_recovery_allowed -or
        -not [bool]$systemC243Contract.recovery_policy.preserve_final_operating_point) {
    throw 'Unexpected C243 modeled system-energy recovery contract gates.'
}
if ((Get-FileHash -LiteralPath $systemC243Result -Algorithm SHA256).Hash -ne
        [string]$systemC243Contract.result_sha256) {
    throw 'C243 system-energy result SHA-256 mismatch.'
}
if ((Get-FileHash -LiteralPath $systemC243Checkpoint -Algorithm SHA256).Hash -ne
        [string]$systemC243Contract.checkpoint_sha256) {
    throw 'C243 system-energy Operating Point SHA-256 mismatch.'
}
if (-not [bool]$systemC243Audit.production_pass -or
        -not [bool]$systemC243Audit.periodic_steady_state -or
        -not [bool]$systemC243Audit.local_exchanger_kcl_pass -or
        -not [bool]$systemC243Audit.boundary_direction_pass -or
        -not [bool]$systemC243Audit.fluid_mass_conservation_pass -or
        -not [bool]$systemC243Audit.modeled_thermal_closure_pass -or
        [bool]$systemC243Audit.complete_device_first_law_closure -or
        [string]$systemC243Audit.window_contract -ne 'final_complete_cycle_only' -or
        [double]$systemC243Audit.window_duration_s -ne 10.0 -or
        [double]$systemC243Audit.modeled_thermal_residual_relative -gt 1.0e-3 -or
        [double]$systemC243Audit.fluid_mass_drift_relative -gt 1.0e-5) {
    throw 'Unexpected C243 modeled thermal-system gates.'
}
if ([bool]$shexControlSummary.system_energy_closure_complete -or
        [bool]$shexControlPackage.frozen_files_modified) {
    throw 'Historical C240 reconstruction has an invalid completion claim.'
}

$hashes = foreach ($item in ($manifest | Where-Object exists)) {
    $hash = Get-FileHash -LiteralPath $item.path -Algorithm SHA256
    [pscustomobject]@{
        role = $item.role
        path = $item.path
        relative_path = $item.relative_path
        status = $item.status
        bytes = [int64]$item.bytes
        sha256 = $hash.Hash
    }
}
$hashes | Export-Csv -LiteralPath $hashPath -NoTypeInformation -Encoding UTF8

$summary = [ordered]@{
    schema = 'heatdrive_ecc_final_package_audit_v6'
    generated_at = (Get-Date).ToString('o')
    workspace_root = $WorkspaceRoot
    authoritative_result = (Join-Path $mainRun 'physical_simscape_result.mat')
    authoritative_cycles = 200
    mechanism_pass = 1
    periodic_steady_state = 1
    strict_table4_reproduction = 0
    paired_table4_endpoint_pass = 0
    heat_driven_system_COP_available = 0
    shex_c242_cycles = $shexC242Contract.completed_cycles
    shex_c242_mechanism_pass = [bool]$shexC242Contract.mechanism_pass
    shex_c242_periodic_steady_state = [bool]$shexC242Contract.periodic_steady_state
    shex_c242_direct_control_volume_pass = `
        [bool]$shexC242Audit.direct_control_volume_pass
    shex_c242_source_heat_input_W = [double]$shexC242Audit.source_heat_input_W
    shex_c242_sink_to_fluid_heat_input_W = `
        [double]$shexC242Audit.sink_to_fluid_heat_input_W
    shex_c242_transfer_ratio = [double]$shexC242Audit.transfer_ratio
    shex_c242_control_volume_residual_relative = `
        [double]$shexC242Audit.direct_control_volume_residual_relative
    shex_c242_complete_system_closure = `
        [bool]$shexC242Audit.system_energy_closure_complete
    shex_c242_authority_status = [string]$shexC242Contract.authority_status
    system_c243_cycles = $systemC243Contract.completed_cycles
    system_c243_mechanism_pass = [bool]$systemC243Contract.mechanism_pass
    system_c243_periodic_steady_state = [bool]$systemC243Contract.periodic_steady_state
    system_c243_local_exchanger_kcl_pass = [bool]$systemC243Audit.local_exchanger_kcl_pass
    system_c243_fluid_mass_conservation_pass = [bool]$systemC243Audit.fluid_mass_conservation_pass
    system_c243_modeled_thermal_closure_pass = [bool]$systemC243Audit.modeled_thermal_closure_pass
    system_c243_modeled_thermal_residual_W = [double]$systemC243Audit.modeled_thermal_residual_W
    system_c243_modeled_thermal_residual_relative = [double]$systemC243Audit.modeled_thermal_residual_relative
    system_c243_complete_device_first_law_closure = [bool]$systemC243Audit.complete_device_first_law_closure
    continuation_authority = 'C243_modeled_system_energy'
    paper_benchmark_authority = 'C200_fixed_CHEX'
    c240_reconstruction_status = 'historical_diagnostic_superseded_by_C242_then_C243_measurement'
    initial_local_OAT_completed_count = $initialSummary.completed_count
    initial_local_OAT_admissible_count = $initialSummary.admissible_count
    initial_local_OAT_strict_pair_count = $initialSummary.strict_local_pair_count
    refined_local_OAT_completed_count = $refinedSummary.completed_count
    refined_local_OAT_admissible_count = $refinedSummary.admissible_count
    refined_local_OAT_pending_count = $refinedSummary.pending_count
    refined_local_OAT_strict_pair_count = $refinedSummary.strict_local_pair_count
    ultrafine_endpoint_completed_count = $ultrafineSummary.completed_count
    ultrafine_endpoint_admissible_count = $ultrafineSummary.admissible_count
    ultrafine_endpoint_rejected_count = $ultrafineSummary.rejected_count
    ultrafine_endpoint_pending_count = $ultrafineSummary.pending_count
    ultrafine_endpoint_strict_pair_count = $ultrafineSummary.strict_local_pair_count
    consolidated_local_OAT_point_count = 12
    consolidated_local_OAT_admissible_count = 11
    consolidated_local_OAT_strict_pair_count = 5
    rejected_branch = $rejectedRoot
    required_file_count = @($manifest | Where-Object required).Count
    present_file_count = @($manifest | Where-Object exists).Count
    missing_file_count = $missing.Count
    manifest_csv = $manifestPath
    sha256_csv = $hashPath
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$summary | ConvertTo-Json -Depth 6
