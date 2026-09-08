[CmdletBinding()]
param([switch]$Apply)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$root = Join-Path $repo 'outputs_storage_audit\c40_c60_prefix_archive_20260908_v3'
function Require([bool]$Test,[string]$Message) { if (-not $Test) { throw $Message } }
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Check-ContainedLeaf([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    Require ($absolute.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) 'Target escaped repository.'
    $item = Get-Item -LiteralPath $absolute
    Require (-not $item.PSIsContainer) 'Only explicitly listed files may be removed.'
    while ($null -ne $item -and $item.FullName.StartsWith($repo,[StringComparison]::OrdinalIgnoreCase)) {
        Require (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'Reparse-point targets are not allowed.'
        $item = if ($item -is [IO.FileInfo]) { $item.Directory } else { $item.Parent }
    }
    return $absolute
}
$running = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '(?i)^matlab\.exe$' -and ($_.CommandLine -match [regex]::Escape($repo) -or $_.CommandLine -match 'HeatDriveECC')
})
Require ($running.Count -eq 0) 'A repository MATLAB process is still running.'
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$auditRoot = Join-Path $root "retirement_package_$stamp"
$package = (& (Join-Path $PSScriptRoot 'Audit_HeatDriveECC_InterruptedRecoveryPackage.ps1') `
    -PreferCompactedEvidence -AuditRoot $auditRoot) | ConvertFrom-Json
Require ($package.recovery_package_pass -and $package.compacted_raw_files_used -eq 2) 'Archived historical package failed.'
$matlab = Read-Json (Join-Path $root 'matlab_materialization_audit.json')
Require ($matlab.load_and_value_comparison_pass -and $matlab.cases.Count -eq 2 -and
    [string]::IsNullOrEmpty($matlab.error_message)) 'Actual MATLAB loading was not verified.'
$expected = @{
    40 = @{folder='qian2019_table2_table4_simscape_40cycle_20260904_183855'; hash='80C12F151242EB9ED079319776AE45B2F835F9940A881954A8731A5A7B0D7DF1'; bytes=1003890832L}
    60 = @{folder='qian2019_table2_table4_simscape_60cycle_20260904_204717'; hash='91C799777FBF750E9803B7D6971AECA144099D7756B15B38FBDC6A2D22BA3E19'; bytes=1505863465L}
}
$plan = foreach ($cycles in @(40,60)) {
    $record = $expected[$cycles]
    $folder = Join-Path $root "c$cycles"
    $descriptor = Read-Json (Join-Path $folder 'archive.json')
    $materialized = Read-Json (Join-Path $folder 'materialized_validation.json')
    $raw = Join-Path (Join-Path $repo 'outputs\qian_coupled_runtime_strict_coldstart_gate3_20260904') "$($record.folder)\physical_simscape_result.mat"
    Require ([IO.Path]::GetFullPath((Join-Path $repo $descriptor.source_path)) -eq [IO.Path]::GetFullPath($raw) -and
        $descriptor.source_sha256 -eq $record.hash -and $descriptor.source_bytes -eq $record.bytes) 'Unexpected old raw identity.'
    $case = @($matlab.cases | Where-Object cycles -eq $cycles)
    Require ($case.Count -eq 1 -and $case[0].source_sha256 -eq $record.hash -and
        $case[0].restored_sha256 -eq $materialized.sha256 -and $case[0].variables.Count -eq 5) 'Wrong MATLAB comparison case.'
    $targets = @(
        @{path=$raw; hash=$record.hash; bytes=$record.bytes; reason='old_raw_replaced_by_exact_logical_prefix_archive'},
        @{path=(Join-Path $folder 'restored_validation.mat'); hash=$materialized.sha256; bytes=$materialized.bytes; reason='temporary_materialization_after_MATLAB_verification'}
    )
    foreach ($target in $targets) {
        $path = Check-ContainedLeaf $target.path
        $file = Get-Item -LiteralPath $path
        Require ($file.Length -eq $target.bytes -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $target.hash) 'Retirement target changed.'
        [pscustomobject]@{path=$path; bytes=$file.Length; sha256=$target.hash; reason=$target.reason}
    }
}
$approval = [ordered]@{
    schema='heatdrive_ecc_raw_retirement_plan_v1'; generated_at=(Get-Date).ToString('o'); apply=[bool]$Apply
    raw_bytes=2509754297L; targets=@($plan); replacement_package=$auditRoot
    original_container_hashes_preserved=$false; exact_logical_data_preserved=$true
    all_operating_points_retained=$true; production_recovery_allowed=$false
}
$planPath = Join-Path $root "retirement_plan_$stamp.json"
$approval | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8
$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    foreach ($target in $plan) {
        $path = Check-ContainedLeaf $target.path
        Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $target.sha256) 'Target changed after plan creation.'
        Remove-Item -LiteralPath $path -Force
        Require (-not (Test-Path -LiteralPath $path)) 'Deletion did not complete.'
        $deleted.Add($target)
        # Persist each completed deletion so an interruption cannot erase the receipt.
        $deleted.ToArray() | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root "retirement_receipt_$stamp.json") -Encoding utf8
    }
}
[ordered]@{
    applied=[bool]$Apply; target_count=$plan.Count; deleted_files=$deleted.Count
    retired_old_raw_bytes=if($Apply){2509754297L}else{0L}
    deleted_bytes=($deleted | Measure-Object bytes -Sum).Sum; plan_path=$planPath
    checkpoints_deleted=0; production_recovery_allowed=$false
} | ConvertTo-Json
