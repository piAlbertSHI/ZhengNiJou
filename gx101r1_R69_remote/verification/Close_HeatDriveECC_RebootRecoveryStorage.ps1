[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionWorkspace,
      [Parameter(Mandatory=$true)][string]$CloseoutPath,
      [Parameter(Mandatory=$true)][string]$ReceiptRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs=[IO.Path]::GetFullPath((Join-Path $ExecutionWorkspace 'gx101r1_R69_remote\outputs'))
$dest=[IO.Path]::GetFullPath($ReceiptRoot)
if (-not $dest.StartsWith((Join-Path $repo 'outputs_storage_audit')+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $dest)) {throw 'Require a fresh main-repository closeout directory.'}
if (@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match '(?i)^matlab\.exe$' -and $_.CommandLine -match 'HeatDriveECC'}).Count) {
    throw 'The real ECC program must exit before cache retirement.'
}
$audit=Get-Content -LiteralPath $CloseoutPath -Raw | ConvertFrom-Json
$root=[IO.Path]::GetFullPath($audit.restored_root)
$source=[IO.Path]::GetFullPath($audit.source_root)
if (-not $audit.full_cycle_restore_verified -or $audit.outer_solve_eligible -or
    $root -ne (Join-Path $outputs 'v37_ref_restore_r1') -or
    $source -ne (Join-Path $outputs 'v36_se_ref2_r1\coherent')) {throw 'Unsupported recovery/storage scope.'}
$retained=@()
foreach ($row in $audit.input_sha256.psobject.Properties) {
    $path=[IO.Path]::GetFullPath((Join-Path $root $row.Name))
    if (-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Escaped evidence path.'}
    $retained+=[pscustomobject]@{path=$path;sha256=$row.Value;role='unique_restored_cycle_evidence_keep'}
}
$retained+=[pscustomobject]@{path=(Join-Path $source 'native\diagnostic_complete_operating_point.mat');sha256=$audit.source_operating_point_sha256;role='C2_resume_point_keep'}
$retained+=[pscustomobject]@{path=(Join-Path $source 'native\diagnostic_state_observation.mat');sha256=$audit.source_history_sha256;role='C2_resume_history_keep'}
foreach($contract in @('c200_mainline_freeze_contract.json','runtime_c180_recovery_contract.json')) {
    $freeze=Get-Content -LiteralPath (Join-Path $PSScriptRoot $contract) -Raw | ConvertFrom-Json
    foreach($kind in @('result','checkpoint')) {
        $path=Join-Path $repo $freeze."${kind}_relative_path"
        $retained+=[pscustomobject]@{path=$path;sha256=$freeze."${kind}_sha256";role='frozen_authority_keep'}
    }
}
foreach($file in $retained) {if ((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) {throw 'Retained evidence changed.'}}
$targets=@()
foreach($name in @('cache','codegen')) {
    $path=[IO.Path]::GetFullPath((Join-Path $root $name))
    if ($path -ne (Join-Path $outputs "v37_ref_restore_r1\$name")) {throw 'Unexpected generated target.'}
    if (-not (Test-Path -LiteralPath $path)) {continue}
    if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint -or
        @(Get-ChildItem -LiteralPath $path -Recurse -Force | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count) {
        throw 'Do not follow reparse points.'
    }
    $files=@(Get-ChildItem -LiteralPath $path -File -Recurse -Force | ForEach-Object {
        [pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })
    $targets+=[pscustomobject]@{path=$path;files=$files;classification='reproducible_cache_only'}
}
New-Item -ItemType Directory -Path $dest | Out-Null
$compact=@('cold_chamber_execution.json','matlab_diary.log','native\rebuilt_cycle_restore.json','native\physical_validation_report.txt')
$copies=@()
foreach($relative in $compact) {
    $from=Join-Path $root $relative
    $to=Join-Path $dest ([IO.Path]::GetFileName($relative))
    Copy-Item -LiteralPath $from -Destination $to
    $hash=(Get-FileHash -LiteralPath $from).Hash
    if((Get-FileHash -LiteralPath $to).Hash -ne $hash) {throw 'Compact copy changed bytes.'}
    $copies+=[pscustomobject]@{source=$from;copy=$to;sha256=$hash;bytes=(Get-Item -LiteralPath $to).Length}
}
$plan=[ordered]@{schema='heatdrive_ecc_reboot_recovery_storage_v1';closeout_sha256=(Get-FileHash -LiteralPath $CloseoutPath).Hash;
    retained=$retained;targets=$targets;compact_copies=$copies;generated_at=(Get-Date).ToString('o')}
$planPath=Join-Path $dest 'storage_plan.json'
[IO.File]::WriteAllText($planPath,($plan|ConvertTo-Json -Depth 10)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$removed=0L
foreach($target in $targets) {
    foreach($file in $target.files) {if ((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) {throw 'Cache changed after plan.'}}
    Remove-Item -LiteralPath $target.path -Recurse -Force
    if(Test-Path -LiteralPath $target.path) {throw 'Generated cache retirement failed.'}
    foreach($file in $target.files) {$removed+=[long]$file.bytes}
}
foreach($file in $retained) {if ((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) {throw 'Retained evidence changed after retirement.'}}
$receipt=[ordered]@{schema=$plan.schema;actual_deleted_bytes=$removed;retired_generated_directories=$targets.Count;
    retained_file_count=$retained.Count;retained_hashes_pass=$true;compact_copies=$copies;
    original_raw_single_execution_copy=$true;Agent6_untouched=$true;unrelated_processes_untouched=$true;
    C200_C180_four_hashes_pass=$true;plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash}
[IO.File]::WriteAllText((Join-Path $dest 'storage_receipt.json'),($receipt|ConvertTo-Json -Depth 6)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$receipt|ConvertTo-Json -Depth 6
