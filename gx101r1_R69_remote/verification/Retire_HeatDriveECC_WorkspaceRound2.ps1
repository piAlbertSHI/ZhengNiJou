$ErrorActionPreference='Stop'
$repo='C:\Users\86182\Desktop\正逆耦合'
$auditRoot=Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r1'
$plan=Get-Content -LiteralPath (Join-Path $auditRoot 'round2_retention_classification_and_candidate_plan.json') -Raw | ConvertFrom-Json
$receipt=Join-Path $auditRoot 'round2_retirement_receipt.json'
if(Test-Path -LiteralPath $receipt){throw 'Round 2 retirement receipt already exists; refusing a second deletion.'}
$candidates=@($plan.high_confidence_candidate.files)
if($candidates.Count -ne 3){throw 'Candidate whitelist changed.'}
$marker=$plan.high_confidence_candidate.failed_marker
$preflight=$plan.high_confidence_candidate.preflight
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function Assert-Hash([string]$p,[string]$h){if((Hash $p) -ne $h){throw "Hash changed: $p"}}
Assert-Hash $marker $plan.high_confidence_candidate.marker_sha256
Assert-Hash $preflight $plan.high_confidence_candidate.preflight_sha256
foreach($e in @($plan.high_confidence_candidate.evidence)){Assert-Hash $e.path $e.sha256}
$procs=@(Get-CimInstance Win32_Process | Select-Object ProcessId,Name,CommandLine)
foreach($p in $procs){foreach($c in $candidates){if($p.CommandLine -and $p.CommandLine.Replace('/','\').Contains($c.path)){throw "Live process references candidate: $($p.ProcessId)"}}}
$before=@();
foreach($c in $candidates){
    if(-not(Test-Path -LiteralPath $c.path -PathType Leaf)){throw "Candidate missing: $($c.path)"}
    $item=Get-Item -LiteralPath $c.path -Force
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "Reparse-point candidate: $($c.path)"}
    $parent=$item.Directory
    while($null -ne $parent){if(($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "Reparse-point ancestor: $($c.path)"};$parent=$parent.Parent}
    if([int64]$item.Length -ne [int64]$c.bytes){throw "Size changed: $($c.path)"}
    Assert-Hash $c.path $c.sha256
    $before += [ordered]@{path=$c.path;bytes=[int64]$item.Length;sha256=$c.sha256}
}
$deleted=@();$freed=[int64]0
foreach($c in $candidates){Remove-Item -LiteralPath $c.path -Force;if(Test-Path -LiteralPath $c.path){throw "Candidate remained: $($c.path)"};$deleted+=$c.path;$freed += [int64]$c.bytes}
Assert-Hash $marker $plan.high_confidence_candidate.marker_sha256
Assert-Hash $preflight $plan.high_confidence_candidate.preflight_sha256
foreach($e in @($plan.high_confidence_candidate.evidence)){Assert-Hash $e.path $e.sha256}
$r=[ordered]@{
    schema='agent5_workspace_deep_cleanup_round2_retirement_v1';status='completed';generated_utc=(Get-Date).ToUniversalTime().ToString('o');scope='Agent5 stage4-phase-local-blend-diagnostic only';recursive_delete_used=$false
    deleted_files=$before;deleted_paths=$deleted;reclaimed_bytes=$freed;expected_reclaimed_bytes=[int64]$plan.high_confidence_candidate.expected_reclaimed_bytes
    failed_marker=$marker;preflight=$preflight;failure_summary_preserved=$true;replacement_or_audit_evidence_preserved=$true;scientific_gates_changed=$false;production_recovery_source_deleted=$false
    runtime_cv_json_contract_touched=$false;external_or_unconfirmed_paths_touched=$false;protected_hashes_verified_after=$true;live_process_reference_count=0
}
$r | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receipt -Encoding utf8
$r | ConvertTo-Json -Depth 6
