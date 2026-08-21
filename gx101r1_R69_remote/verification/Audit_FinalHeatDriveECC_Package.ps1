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
if ([string]::IsNullOrWhiteSpace($AuditRoot)) {
    $AuditRoot = Join-Path $WorkspaceRoot 'outputs_storage_audit'
} else {
    $AuditRoot = [System.IO.Path]::GetFullPath($AuditRoot)
}

$repoRoot = Join-Path $WorkspaceRoot 'gx101r1_R69_remote'
$mainRoot = Join-Path $repoRoot 'outputs\qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821'
$mainRun = Join-Path $mainRoot 'qian2019_table2_table4_simscape_200cycle_20260821_121246'
$rejectedRoot = Join-Path $repoRoot 'outputs\qian_table4_fixed_Tc_270p000K_kp136_255_rootpoint_20260821'
$rejectedRun = Join-Path $rejectedRoot 'qian2019_table2_table4_simscape_20cycle_20260821_142345'

New-Item -ItemType Directory -Force -Path $AuditRoot | Out-Null
$manifestPath = Join-Path $AuditRoot 'final_results_manifest_20260821.csv'
$hashPath = Join-Path $AuditRoot 'final_results_sha256_20260821.csv'
$summaryPath = Join-Path $AuditRoot 'final_results_audit_summary_20260821.json'

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

Add-Entry 'Rejected 270 K report' (Join-Path $rejectedRun 'physical_validation_report.txt') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K summary' (Join-Path $rejectedRun 'cycle_physical_summary.csv') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K parameter contract' (Join-Path $rejectedRun 'qian2019_table2_table4_parameter_contract.csv') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K marker' (Join-Path $rejectedRun 'REJECTED_DO_NOT_RESUME.txt') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K manifest' (Join-Path $rejectedRoot 'fixed_reservoir_point_manifest.txt') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K stdout' (Join-Path $rejectedRoot 'matlab_stdout.log') $true 'diagnostic_rejected'
Add-Entry 'Rejected 270 K progress' (Join-Path $rejectedRoot 'steady_continuation_progress.csv') $true 'diagnostic_rejected'

Add-Entry 'SCI figure source' (Join-Path $repoRoot 'Plot_HeatDriveECC_SCI_FigureSet.m')
Add-Entry 'MATLAB package verifier' (Join-Path $repoRoot 'verification\Verify_FinalHeatDriveECC_Package.m')
Add-Entry 'PowerShell package auditor' (Join-Path $repoRoot 'verification\Audit_FinalHeatDriveECC_Package.ps1')
Add-Entry 'Superseded raw cleanup script' (Join-Path $repoRoot 'verification\Prune_Superseded_HeatDriveECC_Raw.ps1')
Add-Entry 'Long-task discipline' (Join-Path $WorkspaceRoot '项目文档\研究笔记\长任务运行纪律.md')
Add-Entry 'Complete modification report' (Join-Path $WorkspaceRoot '项目文档\报告\SE21_SMA_SE耦合_完整修改与审核报告.md')
Add-Entry 'Storage cleanup audit' (Join-Path $AuditRoot 'superseded_raw_cleanup_20260821.md')

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
    schema = 'heatdrive_ecc_final_package_audit_v1'
    generated_at = (Get-Date).ToString('o')
    workspace_root = $WorkspaceRoot
    authoritative_result = (Join-Path $mainRun 'physical_simscape_result.mat')
    authoritative_cycles = 200
    mechanism_pass = 1
    periodic_steady_state = 1
    strict_table4_reproduction = 0
    rejected_branch = $rejectedRoot
    required_file_count = @($manifest | Where-Object required).Count
    present_file_count = @($manifest | Where-Object exists).Count
    missing_file_count = $missing.Count
    manifest_csv = $manifestPath
    sha256_csv = $hashPath
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$summary | ConvertTo-Json -Depth 6
