[CmdletBinding()]
param(
    [string]$RecoveryRoot = '',
    [string]$AuditRoot = '',
    [switch]$PreferCompactedEvidence
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $RecoveryRoot) {
    $RecoveryRoot = Join-Path $repo 'outputs\qian_coupled_runtime_shutdown_recovery_from60_20260905'
}
$RecoveryRoot = [IO.Path]::GetFullPath($RecoveryRoot)
if (-not $AuditRoot) {
    $AuditRoot = Join-Path $repo 'outputs_storage_audit\shutdown_recovery_20260905\package'
}
$AuditRoot = [IO.Path]::GetFullPath($AuditRoot)
$snapshotPath = Join-Path $repo 'outputs_storage_audit\shutdown_recovery_20260905\source_snapshot.zip'
if (-not $RecoveryRoot.StartsWith((Join-Path $repo 'outputs') + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'RecoveryRoot must remain inside repository outputs.'
}

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}
function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Require-Hash([string]$Path, [string]$Expected) {
    Require ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Expected) "Hash mismatch: $Path"
}
$script:archiveVerified = $false
$script:archiveFiles = [Collections.Generic.List[string]]::new()
$script:compactedRawCount = 0
function Resolve-RawEvidence([string]$Path, [string]$Expected) {
    if ((Test-Path -LiteralPath $Path -PathType Leaf) -and -not $PreferCompactedEvidence) {
        Require-Hash $Path $Expected
        return $Path
    }
    $archiveRoot = Join-Path $repo 'outputs_storage_audit\c40_c60_prefix_archive_20260908_v3'
    if (-not $script:archiveVerified) {
        $output = & python -X utf8 (Join-Path $PSScriptRoot 'Archive_HeatDriveECC_RawPrefixes.py') --verify
        Require ($LASTEXITCODE -eq 0) 'Compacted raw reconstruction audit failed.'
        $verified = $output | ConvertFrom-Json
        Require ($verified.archive_verification_pass -and -not $verified.production_recovery_allowed) 'Wrong archive scope.'
        $matlabPath = Join-Path $archiveRoot 'matlab_materialization_audit.json'
        $matlab = Read-Json $matlabPath
        Require ($matlab.load_and_value_comparison_pass -and -not $matlab.production_recovery_allowed -and
            $matlab.cases.Count -eq 2 -and [string]::IsNullOrEmpty($matlab.error_message)) 'MATLAB archive loading was not verified.'
        $script:archiveFiles.Add($matlabPath)
        $script:archiveVerified = $true
    }
    foreach ($cycles in @(40,60)) {
        $folder = Join-Path $archiveRoot "c$cycles"
        $descriptorPath = Join-Path $folder 'archive.json'
        $descriptor = Read-Json $descriptorPath
        $original = [IO.Path]::GetFullPath((Join-Path $repo $descriptor.source_path))
        if ($original -ne [IO.Path]::GetFullPath($Path)) { continue }
        Require ($descriptor.source_sha256 -eq $Expected -and $descriptor.exact_logical_data_preserved -and
            -not $descriptor.original_mat_container_bytes_preserved -and -not $descriptor.production_recovery_allowed) 'Wrong retired raw identity.'
        foreach ($name in @('metadata.h5','endpoints.h5','matlab_header.bin','materialized_validation.json')) {
            $script:archiveFiles.Add((Join-Path $folder $name))
        }
        $script:compactedRawCount++
        return $descriptorPath
    }
    throw "No verified archive exists for missing raw: $Path"
}

$contractPath = Join-Path $RecoveryRoot 'audited_recovery_contract.json'
$c = Read-Json $contractPath
Require ($c.schema -eq 'heatdrive_ecc_interrupted_recovery_v1') 'Unknown recovery schema.'
Require ($c.mechanism_pass -and $c.strict_restore_pass -and -not $c.state_reset -and
    -not $c.original_state_modified -and -not $c.steady_parameter_study_allowed -and
    -not $c.table4_reproduction_claimed) 'Recovery scope or acceptance contract failed.'
Require ($c.source_recorded_cycles -eq 40 -and $c.recovered_cycles -eq 60 -and
    $c.mechanism_gate_start_cycle -eq 3) 'This audit covers the declared C40-to-C60 interruption only.'
Require ([IO.Path]::GetFullPath($c.output_root) -eq $RecoveryRoot) 'Recovery output root differs.'
$resultEvidence = Resolve-RawEvidence $c.result_path $c.result_sha256
Require-Hash $c.checkpoint_path $c.checkpoint_sha256
Require-Hash $c.source_state_path $c.source_state_sha256
$strict = Read-Json $c.strict_audit_path
$energy = Read-Json $c.energy_audit_path
$savedPath = Join-Path (Split-Path $c.result_path) 'saved_result_audit.json'
$saved = Read-Json $savedPath
Require ($strict.strict_restore_pass -and $strict.complete_operating_point_restore_verified -and
    $strict.production_logging_and_final_state_settings_matched -and
    -not $strict.partial_diagnostic_executed -and
    -not $strict.contents_checksum_mismatch_detected -and
    $strict.result_cycles -eq $c.recovered_cycles -and
    $strict.checkpoint_time_s -eq $strict.result_end_time_s) 'Strict restore audit failed.'
Require ($saved.mechanism_pass -and -not $saved.simulation_executed -and
    -not $saved.continuation_state_modified) 'Saved-result audit failed.'
Require ($energy.local_exchanger_kcl_pass -and $energy.boundary_direction_pass -and
    $energy.modeled_thermal_closure_pass -and $energy.fluid_mass_conservation_pass -and
    -not $energy.complete_device_first_law_closure) 'Modeled energy or device boundary audit failed.'

$paths = [Collections.Generic.List[string]]::new()
foreach ($p in @($contractPath, (Join-Path $RecoveryRoot 'audited_recovery_settings.mat'),
        $resultEvidence, $c.checkpoint_path, $c.source_state_path,
        $c.strict_audit_path, $c.energy_audit_path, $savedPath)) { $paths.Add($p) }
$parentRun = Join-Path (Split-Path $c.source_state_path) 'qian2019_table2_table4_simscape_40cycle_20260904_183855'
$parentRaw = Join-Path $parentRun 'physical_simscape_result.mat'
$parentOp = Join-Path $parentRun 'final_operating_point.mat'
$parentRawEvidence = Resolve-RawEvidence $parentRaw '80C12F151242EB9ED079319776AE45B2F835F9940A881954A8731A5A7B0D7DF1'
Require-Hash $parentOp 'D8A49BD2EC81B8CBFF128F390AF68D2BE417BAFD002BBDDD2AB85DC34954E25A'
$paths.Add($parentRawEvidence)
$paths.Add($parentOp)
foreach ($path in $script:archiveFiles) { $paths.Add($path) }
foreach ($name in @('c200_mainline_freeze_contract.json', 'cold_boundary_runtime_c246_recovery_contract.json')) {
    $path = Join-Path $PSScriptRoot $name
    $frozen = Read-Json $path
    $raw = Join-Path $repo $frozen.result_relative_path
    $op = Join-Path $repo $frozen.checkpoint_relative_path
    $rawRetired = $frozen.PSObject.Properties.Name -contains 'raw_preserved' -and -not $frozen.raw_preserved
    if ($rawRetired) {
        $replacement = (& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_RuntimeBaselinePackage.ps1') `
            -AuditRoot (Join-Path $AuditRoot 'runtime_baseline_reaudit')) | ConvertFrom-Json
        Require $replacement.package_pass 'Replacement baseline failed.'
    } else {
        Require-Hash $raw $frozen.result_sha256
    }
    Require-Hash $op $frozen.checkpoint_sha256
    foreach ($p in @($path, $op)) { $paths.Add($p) }
    if (Test-Path -LiteralPath $raw -PathType Leaf) { $paths.Add($raw) }
}
foreach ($relative in @(
        'Run_HeatDriveECC_EighthRound_Simulink_Cycles.m',
        'Resolve_HeatDriveECC_FigurePolicy.m',
        'verification\Prepare_HeatDriveECC_InterruptedRecovery.m',
        'verification\Audit_HeatDriveECC_SavedResult.m',
        'verification\Audit_HeatDriveECC_OperatingPointRestore.m',
        'verification\Audit_HeatDriveECC_SystemEnergyResult.m',
        'verification\Audit_HeatDriveECC_InterruptedRecoveryPackage.ps1',
        'verification\Run_HeatDriveECC_LongSteadyContinuation.m',
        'verification\WaitAndCheck_HeatDriveECC.ps1',
        'verification\Manage_HeatDriveECC_OutputStorage.ps1',
        'verification\Test_HeatDriveECC_MonitorTermination.ps1',
        'verification\Test_HeatDriveECC_OutputOptions.m')) { $paths.Add((Join-Path $repo $relative)) }
foreach ($relative in @(
        '项目文档\报告\SMA-SE正逆耦合_第十三阶段关机中断恢复与存储治理报告.md',
        '项目文档\报告\SE21_SMA_SE耦合_完整修改与审核报告.md',
        '项目文档\研究笔记\长任务运行纪律.md',
        '项目文档\研究笔记\2026-09-03_Qian本地文献精确定位与模型映射.md')) {
    $paths.Add((Join-Path (Split-Path $repo) $relative))
}
$entries = @($paths | Sort-Object -Unique | ForEach-Object {
    $f = Get-Item -LiteralPath $_
    [pscustomobject]@{
        path = $f.FullName
        bytes = $f.Length
        sha256 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    }
})
if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
    $snapshot = Get-Item -LiteralPath $snapshotPath
    $entries += [pscustomobject]@{
        path = $snapshot.FullName
        bytes = $snapshot.Length
        sha256 = (Get-FileHash -LiteralPath $snapshot.FullName -Algorithm SHA256).Hash
    }
}
New-Item -ItemType Directory -Path $AuditRoot -Force | Out-Null
$entries | Export-Csv -LiteralPath (Join-Path $AuditRoot 'manifest_sha256.csv') -NoTypeInformation -Encoding utf8
$summary = [ordered]@{
    schema = 'heatdrive_ecc_interrupted_recovery_package_v1'
    generated_at = (Get-Date).ToString('o')
    git_commit = (& git -C $repo rev-parse HEAD).Trim()
    recovery_package_pass = $true
    verified_cycles = $c.recovered_cycles
    mechanism_pass = $saved.mechanism_pass
    periodic_steady_state = $saved.performance.periodic_steady_state
    strict_restore_pass = $strict.strict_restore_pass
    modeled_thermal_closure_pass = $energy.modeled_thermal_closure_pass
    fluid_mass_conservation_pass = $energy.fluid_mass_conservation_pass
    state_reset = $false
    complete_device_first_law_closure = $false
    table4_reproduction_claimed = $false
    frozen_hash_contracts_verified = $true
    c246_raw_retired_with_verified_replacement = $true
    source_snapshot_included = Test-Path -LiteralPath $snapshotPath -PathType Leaf
    compacted_raw_files_used = $script:compactedRawCount
    compacted_evidence_scope = 'Exact logical MAT datasets and MATLAB loader comparison; original container hashes retained as provenance, not asserted for regenerated files.'
    file_count = $entries.Count
    audit_root = $AuditRoot
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $AuditRoot 'package_audit.json') -Encoding utf8
$summary | ConvertTo-Json -Depth 5
