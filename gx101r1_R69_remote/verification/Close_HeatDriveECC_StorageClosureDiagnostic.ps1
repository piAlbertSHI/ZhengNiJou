[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionWorkspace,
      [Parameter(Mandatory=$true)][string]$AuditPath,
      [Parameter(Mandatory=$true)][string]$ReceiptRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace=Split-Path -Parent $repo
$outputs=[IO.Path]::GetFullPath((Join-Path $ExecutionWorkspace 'gx101r1_R69_remote\outputs'))
$dest=[IO.Path]::GetFullPath($ReceiptRoot)
if ((Test-Path -LiteralPath $dest) -or -not $dest.StartsWith((Join-Path $repo 'outputs_storage_audit')+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Require a fresh local snapshot.'}
if (@(Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'MATLAB.exe' -and $_.CommandLine -match 'HeatDriveECC'}).Count) {throw 'Do not retire files of a live ECC process.'}
$audit=Get-Content -LiteralPath $AuditPath -Raw | ConvertFrom-Json
$root=[IO.Path]::GetFullPath($audit.source_root)
if ($root -ne (Join-Path $outputs 'v38_density_r4') -or -not $audit.candidate_numerical_inventory_qualification -or $audit.outer_solve_eligible) {throw 'Wrong current storage-closure qualification.'}
$retained=@()
foreach($index in @(3,4)) {
    $case=Join-Path $outputs "v38_density_r$index\candidate"
    $record=Get-Content -LiteralPath (Join-Path $case 'cold_chamber_execution.json') -Raw | ConvertFrom-Json
    if (-not $record.requested_arm_collection_pass -or $record.error_message -ne '' -or
        (Get-FileHash -LiteralPath (Join-Path $case 'native\observations.mat')).Hash -ne $record.cases[0].observation_sha256) {throw 'Completed observations changed.'}
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $case 'native') -File -Filter '*.mat') {
        $retained+=[pscustomobject]@{path=$file.FullName;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash;
            classification=$(if($index -eq 4){'current_formulation_diagnostic_keep'}else{'rejected_compiler_state_counterexample_keep'})}
    }
}
foreach($name in @('c200_mainline_freeze_contract.json','runtime_c180_recovery_contract.json')) {
    $freeze=Get-Content -LiteralPath (Join-Path $PSScriptRoot $name) -Raw | ConvertFrom-Json
    foreach($kind in @('result','checkpoint')) {
        $path=Join-Path $repo $freeze."${kind}_relative_path"
        if ((Get-FileHash -LiteralPath $path).Hash -ne $freeze."${kind}_sha256") {throw 'Frozen authority changed.'}
        $retained+=[pscustomobject]@{path=$path;sha256=$freeze."${kind}_sha256";classification='frozen_authority_keep'}
    }
}
New-Item -ItemType Directory -Path $dest | Out-Null
$copies=@()
foreach($index in @(1,2,3,4)) {
    $case=Join-Path $outputs "v38_density_r$index"
    $target=Join-Path $dest "r$index"
    New-Item -ItemType Directory -Path $target | Out-Null
    $names=@('storage_closure_execution.json','candidate_config.json','candidate\cold_chamber_execution.json','candidate\matlab_diary.log',
        'candidate\native\compiled_inventory_tags.json','candidate\native\inventory_metadata.json',
        'candidate\native\pressure_only_inverse_density_map_1.json','candidate\native\pressure_only_inverse_density_map_2.json',
        'candidate\REJECTED_DO_NOT_RESUME.json','candidate\component_build\+ecc_inventory_pressure_only\conservative_chamber.ssc')
    foreach($name in $names) {
        $from=Join-Path $case $name
        if (-not (Test-Path -LiteralPath $from)) {continue}
        $to=Join-Path $target ([IO.Path]::GetFileName($name))
        Copy-Item -LiteralPath $from -Destination $to
        $hash=(Get-FileHash -LiteralPath $from).Hash
        if ((Get-FileHash -LiteralPath $to).Hash -ne $hash) {throw 'Snapshot bytes changed.'}
        $copies+=[pscustomobject]@{source=$from;copy=$to;sha256=$hash;bytes=(Get-Item -LiteralPath $to).Length}
    }
}
$targets=@()
foreach($index in @(1,2,3,4)) {foreach($name in @('cache','codegen')) {$targets+=Join-Path $outputs "v38_density_r$index\candidate\$name"}}
foreach($name in @('v38_manifold_storage_closure_20261014','v38_manifold_storage_closure_20261014_reviewed')) {$targets+=Join-Path $workspace "output\pdf\$name"}
$plan=@()
foreach($path in $targets) {
    $path=[IO.Path]::GetFullPath($path)
    if (-not ($path.StartsWith($outputs+'\',[StringComparison]::OrdinalIgnoreCase) -or
        $path.StartsWith((Join-Path $workspace 'output\pdf')+'\',[StringComparison]::OrdinalIgnoreCase))) {throw 'Escaped retirement target.'}
    if (-not (Test-Path -LiteralPath $path)) {continue}
    if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint -or
        @(Get-ChildItem -LiteralPath $path -Recurse -Force | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count) {throw 'Do not follow reparse points.'}
    $files=@(Get-ChildItem -LiteralPath $path -Recurse -File -Force | ForEach-Object {
        [pscustomobject]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash;bytes=$_.Length}
    })
    $plan+=[pscustomobject]@{path=$path;classification='reproducible_cache_or_superseded_plot';files=$files}
}
$planPath=Join-Path $dest 'storage_plan.json'
[IO.File]::WriteAllText($planPath,([ordered]@{schema='heatdrive_ecc_storage_closure_retirement_v1';retained=$retained;compact_copies=$copies;targets=$plan}|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$removed=0L
foreach($target in $plan) {
    foreach($file in $target.files) {if((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) {throw 'Retirement target changed.'}}
    Remove-Item -LiteralPath $target.path -Recurse -Force
    if (Test-Path -LiteralPath $target.path) {throw 'Retirement failed.'}
    foreach($file in $target.files) {$removed+=[long]$file.bytes}
}
foreach($file in $retained) {if((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) {throw 'Required original evidence changed.'}}
$receipt=[ordered]@{actual_deleted_bytes=$removed;retired_directories=$plan.Count;retained_files=$retained.Count;
    retained_hashes_pass=$true;compact_copies=$copies;plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash;
    Agent6_untouched=$true;original_raw_one_execution_copy=$true;current_and_rejected_scientific_raw_kept=$true}
[IO.File]::WriteAllText((Join-Path $dest 'storage_receipt.json'),($receipt|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[pscustomobject]$receipt|Select-Object actual_deleted_bytes,retired_directories,retained_files,retained_hashes_pass|ConvertTo-Json
