[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionWorkspace,
      [Parameter(Mandatory=$true)][string]$ReceiptRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace=Split-Path -Parent $repo
$execRepo=[IO.Path]::GetFullPath((Join-Path $ExecutionWorkspace 'gx101r1_R69_remote'))
$outputs=Join-Path $execRepo 'outputs'
$dest=[IO.Path]::GetFullPath($ReceiptRoot)
if (-not $dest.StartsWith((Join-Path $repo 'outputs_storage_audit')+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $dest)) { throw 'Require a fresh main-repository closeout directory.' }
if (@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match '(?i)^matlab\.exe$' -and $_.CommandLine -match 'HeatDriveECC'}).Count) {
    throw 'An ECC MATLAB process is active; do not retire its generated files.'
}
$manifest=Get-Content -LiteralPath (Join-Path $outputs 'v34_inventory_r4\counterfactual_execution.json') -Raw | ConvertFrom-Json
if ($manifest.status -ne 'collected_requires_physical_comparison' -or $manifest.cases.Count -ne 2) { throw 'Incomplete paired collection.' }
$retained=@()
foreach($case in $manifest.cases) {
    $root=[IO.Path]::GetFullPath($case.case_root)
    if (-not $root.StartsWith($outputs+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Escaped actual case root.' }
    $record=Get-Content -LiteralPath (Join-Path $root 'cold_chamber_execution.json') -Raw | ConvertFrom-Json
    if (-not $record.requested_arm_collection_pass -or $record.error_message -ne '' -or
        (Get-FileHash -LiteralPath (Join-Path $root 'native\observations.mat')).Hash -ne $record.cases[0].observation_sha256) {
        throw 'Changed completed observations.'
    }
    $retained+=@(Get-ChildItem -LiteralPath (Join-Path $root 'native') -File -Recurse | ForEach-Object {
        [pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash;classification='current_structural_cold_evidence_keep'}
    })
}
$cacheRoots=@()
$failed=@('v34_manifold_inventory_counterfactual_20261013\baseline',
    'v34_manifold_inventory_counterfactual_20261013_fix1\baseline','v34_inventory_r3\volume_0p1')
foreach($relative in $failed) {
    foreach($directory in @('component_build','buffer_component_build','cache','codegen')) {
        $cacheRoots+=Join-Path $outputs ($relative+'\'+$directory)
    }
}
foreach($case in $manifest.cases) {
    foreach($directory in @('cache','codegen')) {$cacheRoots+=Join-Path $case.case_root $directory}
}
$targets=@()
foreach($path in $cacheRoots) {
    $absolute=[IO.Path]::GetFullPath($path)
    if (-not $absolute.StartsWith($outputs+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Escaped generated directory.' }
    if (-not (Test-Path -LiteralPath $absolute)) { continue }
    if ((Get-Item -LiteralPath $absolute).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Do not follow reparse points.' }
    if (@(Get-ChildItem -LiteralPath $absolute -Recurse -Force | Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count) {
        throw 'Generated directory contains a reparse point.'
    }
    $files=@(Get-ChildItem -LiteralPath $absolute -File -Recurse -Force | ForEach-Object {
        [pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })
    $targets+=[pscustomobject]@{path=$absolute;classification='reproducible_build_cache_retire';files=$files}
}
$q=Get-Content -LiteralPath (Join-Path $execRepo 'outputs_storage_audit\v31_stable_constitutive_from_C122_C142_fix1_endpoint_qualification\diagnostic_resume_qualification.json') -Raw | ConvertFrom-Json
$retained+=@($q.files | Where-Object role -In @('operating_point','history','observation'))
$freeze=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'c200_mainline_freeze_contract.json') -Raw | ConvertFrom-Json
$retained+=[pscustomobject]@{path=(Join-Path $repo $freeze.checkpoint_relative_path);sha256=$freeze.checkpoint_sha256}
foreach($file in $retained) {if ((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) {throw 'Retained evidence changed before retirement.'}}
New-Item -ItemType Directory -Path $dest | Out-Null
$plan=[ordered]@{schema='heatdrive_ecc_manifold_diagnostic_storage_v1';targets=$targets;retained=$retained;generated_at=(Get-Date).ToString('o')}
$planPath=Join-Path $dest 'storage_plan.json'
[IO.File]::WriteAllText($planPath,($plan|ConvertTo-Json -Depth 10)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$removed=0L
foreach($target in $targets) {
    foreach($file in $target.files) {if ((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) {throw 'Cache changed after plan.'}}
    Remove-Item -LiteralPath $target.path -Recurse -Force
    if(Test-Path -LiteralPath $target.path){throw 'Cache retirement failed.'}
    foreach($file in $target.files){$removed+=[long]$file.bytes}
}
foreach($file in $retained) {if ((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) {throw 'Retained evidence changed after retirement.'}}
$receipt=[ordered]@{schema=$plan.schema;actual_deleted_bytes=$removed;retired_generated_directories=$targets.Count;
    retained_file_count=$retained.Count;retained_hashes_pass=$true;C142_and_C200_checkpoint_hashes_pass=$true;
    failed_markers_and_logs_kept=$true;Agent6_untouched=$true;plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash}
[IO.File]::WriteAllText((Join-Path $dest 'storage_receipt.json'),($receipt|ConvertTo-Json)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$receipt|ConvertTo-Json
