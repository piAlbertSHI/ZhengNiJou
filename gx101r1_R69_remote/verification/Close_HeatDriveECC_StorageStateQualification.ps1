[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionWorkspace,
      [Parameter(Mandatory=$true)][string]$StateAuditPath,
      [Parameter(Mandatory=$true)][string]$RestoreAuditPath,
      [Parameter(Mandatory=$true)][string]$ReceiptRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputs=[IO.Path]::GetFullPath((Join-Path $ExecutionWorkspace 'gx101r1_R69_remote\outputs'))
$dest=[IO.Path]::GetFullPath($ReceiptRoot)
if ((Test-Path -LiteralPath $dest) -or -not $dest.StartsWith((Join-Path $repo 'outputs_storage_audit')+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Require a fresh scoped snapshot.'}
if (@(Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'MATLAB.exe' -and $_.CommandLine -match 'HeatDriveECC'}).Count) {throw 'Do not retire files of a live ECC program.'}
$state=Get-Content -LiteralPath $StateAuditPath -Raw | ConvertFrom-Json
$restore=Get-Content -LiteralPath $RestoreAuditPath -Raw | ConvertFrom-Json
$source=[IO.Path]::GetFullPath($state.source_root)
$verified=[IO.Path]::GetFullPath($restore.restored_root)
if ($source -ne (Join-Path $outputs 'v39_density_c2_r1\candidate') -or
    $verified -ne (Join-Path $outputs 'v39_density_restore_r1') -or
    -not $state.full_mechanism_pass -or -not $state.local_inventory_pass -or
    -not $restore.complete_cycle_restore_verified -or $restore.production_recovery_allowed) {throw 'Wrong completed state/restore scope.'}
$retained=@()
foreach($row in $state.input_sha256.psobject.Properties) {
    $retained+=[pscustomobject]@{path=(Join-Path $source ('native\'+$row.Name));sha256=$row.Value;role='current_C2_complete_state_and_physics_keep'}
}
foreach($row in $restore.input_sha256.psobject.Properties) {
    $retained+=[pscustomobject]@{path=(Join-Path $verified $row.Name);sha256=$row.Value;role='complete_cycle_restore_evidence_keep'}
}
foreach($name in @('c200_mainline_freeze_contract.json','runtime_c180_recovery_contract.json')) {
    $freeze=Get-Content -LiteralPath (Join-Path $PSScriptRoot $name) -Raw | ConvertFrom-Json
    foreach($kind in @('result','checkpoint')) {
        $retained+=[pscustomobject]@{path=(Join-Path $repo $freeze."${kind}_relative_path");sha256=$freeze."${kind}_sha256";role='frozen_authority_keep'}
    }
}
foreach($file in $retained) {if((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256){throw 'Required evidence changed.'}}
New-Item -ItemType Directory -Path $dest | Out-Null
$copies=@()
$sets=@(@{name='C2';root=$source;names=@('cold_chamber_execution.json','matlab_diary.log',
    'native\cold_mechanism_audit.json','native\diagnostic_state_capture.json','native\state_restore_preflight.json',
    'native\compiled_inventory_tags.json','native\inventory_metadata.json',
    'native\pressure_only_inverse_density_map_1.json','native\pressure_only_inverse_density_map_2.json')},
    @{name='C3_restore';root=$verified;names=@('cold_chamber_execution.json','matlab_diary.log',
    'native\rebuilt_cycle_restore.json','native\physical_validation_report.txt',
    'native\inventory_metadata.json','native\pressure_only_inverse_density_map_1.json','native\pressure_only_inverse_density_map_2.json')})
foreach($set in $sets) {
    $target=Join-Path $dest $set.name;New-Item -ItemType Directory -Path $target | Out-Null
    foreach($relative in $set.names) {
        $from=Join-Path $set.root $relative;$to=Join-Path $target ([IO.Path]::GetFileName($relative))
        Copy-Item -LiteralPath $from -Destination $to
        $hash=(Get-FileHash -LiteralPath $from).Hash
        if((Get-FileHash -LiteralPath $to).Hash -ne $hash){throw 'Snapshot bytes changed.'}
        $copies+=[pscustomobject]@{source=$from;copy=$to;sha256=$hash;bytes=(Get-Item -LiteralPath $to).Length}
    }
}
$targets=@()
foreach($root in @($source,$verified)) {foreach($name in @('cache','codegen')) {
    $path=[IO.Path]::GetFullPath((Join-Path $root $name))
    if(-not $path.StartsWith($outputs+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Escaped cache target.'}
    if(-not (Test-Path -LiteralPath $path)){continue}
    if((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint -or
       @(Get-ChildItem -LiteralPath $path -Recurse -Force | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Do not follow reparse points.'}
    $files=@(Get-ChildItem -LiteralPath $path -File -Recurse -Force | ForEach-Object {
        [pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })
    $targets+=[pscustomobject]@{path=$path;classification='reproducible_cache_only';files=$files}
}}
$planPath=Join-Path $dest 'storage_plan.json'
$plan=[ordered]@{schema='heatdrive_ecc_storage_state_closeout_v1';retained=$retained;copies=$copies;targets=$targets}
[IO.File]::WriteAllText($planPath,($plan|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$removed=0L
foreach($target in $targets) {
    foreach($file in $target.files){if((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256){throw 'Cache changed after plan.'}}
    Remove-Item -LiteralPath $target.path -Recurse -Force
    if(Test-Path -LiteralPath $target.path){throw 'Cache retirement failed.'}
    foreach($file in $target.files){$removed+=[long]$file.bytes}
}
foreach($file in $retained){if((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256){throw 'Required evidence changed after retirement.'}}
$receipt=[ordered]@{actual_deleted_bytes=$removed;retired_directories=$targets.Count;retained_files=$retained.Count;
    retained_hashes_pass=$true;compact_copies=$copies;plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash;
    original_raw_one_execution_copy=$true;C200_C180_four_hashes_pass=$true;Agent6_untouched=$true}
[IO.File]::WriteAllText((Join-Path $dest 'storage_receipt.json'),($receipt|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[pscustomobject]$receipt|Select-Object actual_deleted_bytes,retired_directories,retained_files,retained_hashes_pass|ConvertTo-Json
