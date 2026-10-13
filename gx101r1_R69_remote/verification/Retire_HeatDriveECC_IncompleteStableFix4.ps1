[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionWorkspace,
      [Parameter(Mandatory=$true)][string]$ReceiptRoot,
      [switch]$Apply)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$execRepo=[IO.Path]::GetFullPath((Join-Path $ExecutionWorkspace 'gx101r1_R69_remote'))
$root=[IO.Path]::GetFullPath((Join-Path $execRepo 'outputs\v31_stable_constitutive_from_C82_C102_fix4'))
$dest=[IO.Path]::GetFullPath($ReceiptRoot)
$auditRoot=Join-Path $repo 'outputs_storage_audit'
if (-not $dest.StartsWith($auditRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $dest)) { throw 'Require a fresh receipt directory inside the main audit root.' }
$snapshotPath=Join-Path $auditRoot 'v32_stable_evidence_snapshot_20261013\snapshot_receipt.json'
$snapshot=Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
$marker=Join-Path $root 'INCOMPLETE_DO_NOT_RESUME.json'
$incomplete=Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
if ($incomplete.resume_allowed -or $incomplete.production_recovery_allowed -or
    $incomplete.status -ne 'incomplete_postprocessing_contract') { throw 'Not the exact incomplete fix4.' }
$running=@(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '(?i)^matlab\.exe$' -and $_.CommandLine -match 'HeatDriveECC'
})
if ($running.Count -ne 0) { throw 'An ECC MATLAB process is still active.' }
$source=Join-Path $execRepo 'outputs\v31_stable_constitutive_from_C82_C102_fix6'
$execution=Get-Content -LiteralPath (Join-Path $source 'cold_chamber_execution.json') -Raw | ConvertFrom-Json
$mechanismPath=Join-Path $execRepo 'outputs_storage_audit\v31_stable_constitutive_from_C82_C102_fix6_saved_mechanism\saved_mechanism_audit.json'
$mechanism=Get-Content -LiteralPath $mechanismPath -Raw | ConvertFrom-Json
if (-not $execution.requested_arm_collection_pass -or $execution.error_message -ne '' -or
    -not $mechanism.mechanism_pass -or @($mechanism.checks.PSObject.Properties).Count -ne 73 -or
    @($mechanism.checks.PSObject.Properties | Where-Object {$_.Value -ne $true}).Count -ne 0 -or
    $mechanism.source_observation_sha256 -ne (Get-FileHash -LiteralPath (Join-Path $source 'native\observations.mat')).Hash -or
    $mechanism.source_execution_sha256 -ne (Get-FileHash -LiteralPath (Join-Path $source 'cold_chamber_execution.json')).Hash) {
    throw 'The complete replacement C102 is not jointly hash-bound and mechanism passing.'
}
$names=@('diagnostic_complete_operating_point.mat','diagnostic_state_observation.mat','public_observations.mat')
$targets=@()
foreach ($name in $names) {
    $path=[IO.Path]::GetFullPath((Join-Path $root ('native\'+$name)))
    if ((Split-Path -Parent $path) -ne (Join-Path $root 'native') -or
        -not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Escaped exact fix4 native target.' }
    $rows=@($snapshot.obsolete_candidates | Where-Object { $_.path -eq $path })
    if ($rows.Count -ne 1 -or $rows[0].classification -ne 'obsolete_incomplete_raw_candidate_not_deleted' -or
        -not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Item -LiteralPath $path).Length -ne $rows[0].bytes -or
        (Get-FileHash -LiteralPath $path).Hash -ne $rows[0].sha256) { throw 'Retirement candidate differs from the committed snapshot.' }
    $targets+=$rows[0]
}
$frozen=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'c200_mainline_freeze_contract.json') -Raw | ConvertFrom-Json
$authority=@()
foreach ($row in @(@($frozen.result_relative_path,$frozen.result_sha256),@($frozen.checkpoint_relative_path,$frozen.checkpoint_sha256))) {
    $path=Join-Path $repo $row[0]
    if ((Get-FileHash -LiteralPath $path).Hash -ne $row[1]) { throw 'C200 authority changed.' }
    $authority+=[pscustomobject]@{path=$path;sha256=$row[1]}
}
$retained=@(Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object { $_.FullName -notin $targets.path } |
    ForEach-Object { [pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash} })
New-Item -ItemType Directory -Path $dest | Out-Null
$plan=[ordered]@{schema='heatdrive_ecc_exact_incomplete_fix4_retirement_v1';apply_requested=[bool]$Apply;
    incomplete_marker_sha256=(Get-FileHash -LiteralPath $marker).Hash;
    snapshot_sha256=(Get-FileHash -LiteralPath $snapshotPath).Hash;
    replacement_mechanism_sha256=(Get-FileHash -LiteralPath $mechanismPath).Hash;
    targets=$targets;retained=$retained;C200_authority=$authority;generated_at=(Get-Date).ToString('o')}
[IO.File]::WriteAllText((Join-Path $dest 'retirement_plan.json'),($plan|ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$deletedBytes=0L
if ($Apply) {
    foreach ($row in $targets) {
        if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Candidate changed after the plan was written.' }
        Remove-Item -LiteralPath $row.path -Force
        if (Test-Path -LiteralPath $row.path) { throw 'Exact file retirement did not complete.' }
        $deletedBytes+=[long]$row.bytes
    }
    foreach ($row in @($retained)+@($authority)) {
        if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'A retained artifact changed.' }
    }
}
$receipt=[ordered]@{schema=$plan.schema;applied=[bool]$Apply;files_deleted=if($Apply){$targets.Count}else{0};
    actual_deleted_bytes=$deletedBytes;retained_files_verified=$retained.Count;
    C200_hash_pass=$true;qualified_chain_untouched=$true;Agent6_untouched=$true;
    root=$root;plan_sha256=(Get-FileHash -LiteralPath (Join-Path $dest 'retirement_plan.json')).Hash}
[IO.File]::WriteAllText((Join-Path $dest 'retirement_receipt.json'),($receipt|ConvertTo-Json -Depth 6)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$receipt|ConvertTo-Json
