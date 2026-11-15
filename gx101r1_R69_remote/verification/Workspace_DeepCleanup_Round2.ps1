$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\86182\Desktop\正逆耦合'
$auditRoot = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r1'
$inventory = Get-Content -LiteralPath (Join-Path $auditRoot 'workspace_ownership_and_space_inventory.json') -Raw | ConvertFrom-Json
$candidatePaths = @(
    'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v47_C62_recording_split_preflight_r2\native\split_observation\reference\mechanism.json',
    'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v47_C62_recording_split_preflight_r2\native\split_observation\reference\native\observations.mat',
    'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v47_C62_recording_split_preflight_r2\native\split_observation\reference\observed_states.mat'
)
$failureMarker = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v47_C62_recording_split_preflight_r2\native\split_observation\REJECTED_DO_NOT_RESUME.json'
$preflight = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v47_C62_recording_split_preflight_r2\native\split_observation\split_observation_preflight.json'
$replacementEvidence = @(
    'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\v47_split_observation_snapshot_20261015\storage_receipt.json',
    'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v47_C62_recording_split_preflight_r3\native\split_observation\prefix_comparison.json',
    'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v47_C62_recording_split_preflight_r3\native\split_observation\suffix_comparison.json'
)
$processes = @(Get-CimInstance Win32_Process | Select-Object ProcessId,Name,CommandLine)
$hashRows = foreach ($p in $candidatePaths) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Candidate missing: $p" }
    $h = Get-FileHash -LiteralPath $p -Algorithm SHA256
    [ordered]@{ path=$p; bytes=[int64](Get-Item -LiteralPath $p).Length; sha256=$h.Hash; process_reference_count=@($processes | Where-Object { $_.CommandLine -and $_.CommandLine.Replace('/','\').Contains($p) }).Count }
}
$markerJson = Get-Content -LiteralPath $failureMarker -Raw | ConvertFrom-Json
$preflightJson = Get-Content -LiteralPath $preflight -Raw | ConvertFrom-Json
if ($markerJson.failed_comparison_state_may_propagate -ne $false -or $markerJson.production_recovery_allowed -ne $false) { throw 'Failure marker does not prove non-propagation.' }
if ($preflightJson.pass -ne $false -or $preflightJson.production_recovery_allowed -ne $false -or $preflightJson.outer_solve_eligible -ne $false) { throw 'Preflight is not a failed non-production run.' }
$evidenceRows = foreach ($p in $replacementEvidence) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing replacement/audit evidence: $p" }
    $h=Get-FileHash -LiteralPath $p -Algorithm SHA256
    [ordered]@{path=$p;sha256=$h.Hash;bytes=[int64](Get-Item -LiteralPath $p).Length}
}
$classRows = foreach ($w in $inventory.in_scope) {
    foreach ($f in $w.large_file_inventory) {
        $tier='D';$basis='Large file retained pending content/reference audit.'
        $rel=$f.relative_path.Replace('/','\');$name=[IO.Path]::GetFileName($f.path)
        if ($w.key -eq 'runtime-cv-json-contract') {$tier='D';$basis='Deletion blocked by checkout identity contradiction.'}
        elseif ($rel -match '(^|\\)(verification|Tools|项目文档|参考|热回收驱动弹热冷却系统)(\\|$)' -or $name -match '\.(m|py|ps1|slx|ssc|mexw64|dll|h|hpp|c|cpp)$') {$tier='A';$basis='Source/model/runtime dependency.'}
        elseif ($rel -match 'outputs_storage_audit' -and $name -match '\.(json|csv|txt|md|log|svg|png|pdf)$') {$tier='A';$basis='Audit or final-artifact evidence.'}
        elseif ($name -match '^(cold_public_targets|cycle_physical_summary|stage_temperature_probes_50samples|cold_chamber_execution|packet_manifest|collection_result|collection_progress|final_operating_point|storage_receipt|retirement_receipt)\.' -or $name -like 'retained_key_evidence_shared_*.h5' -or $name -like 'HISTORICAL_*_RETIRED.json' -or $name -like 'COMPLETED_*_RETIRED.json') {$tier='A';$basis='User-designated key result or retirement evidence.'}
        elseif ($name -match 'physical_simscape_result\.mat$') {$tier='B';$basis='Potential representative benchmark; keep until replacement/reference audit.'}
        elseif ($name -match '^(observations|observed_states|diagnostic_state_observation|internal_state_observation)\.mat$') {$tier='C';$basis='Regenerable observation/state payload; delete only with replacement receipt.'}
        [pscustomobject]@{tier=$tier;worktree=$w.key;path=$f.path;bytes=$f.bytes;basis=$basis}
    }
}
$classRows += $hashRows | ForEach-Object { [pscustomobject]@{tier='C-high-confidence';worktree='stage4-phase-local-blend-diagnostic';path=$_.path;bytes=$_.bytes;basis='Failed split-observation preflight; rejected marker and non-production gate retained; exact hash recorded.'} }
$classRows | Export-Csv -LiteralPath (Join-Path $auditRoot 'file_retention_classification.csv') -NoTypeInformation -Encoding utf8
$plan = [ordered]@{
    schema='agent5_workspace_deep_cleanup_round2_v1';generated_utc=(Get-Date).ToUniversalTime().ToString('o');read_only=$true;deletion_performed=$false
    tier_definitions=[ordered]@{ A='Must retain source/runtime/final/audit evidence'; B='Selective representative or benchmark result'; C='Candidate only after replacement/hash/reference proof'; D='Unresolved or blocked; do not delete' }
    high_confidence_candidate=[ordered]@{ files=$hashRows; failed_marker=$failureMarker; preflight=$preflight; marker_sha256=(Get-FileHash -LiteralPath $failureMarker -Algorithm SHA256).Hash; preflight_sha256=(Get-FileHash -LiteralPath $preflight -Algorithm SHA256).Hash; evidence=$evidenceRows; expected_reclaimed_bytes=[int64](($hashRows | ForEach-Object {[int64]$_.bytes} | Measure-Object -Sum).Sum); replacement_or_loss='Deletes only failed split-observation raw payloads; preserves rejected marker, preflight JSON, logs, manifests and audit receipt. No recovery source or paper result is removed.' }
    blocked=[ordered]@{ runtime_cv_json_contract='Observed full checkout despite user description of empty runtime-cv-contract; no deletion'; excluded_worktrees='positive-bias, pressure-bias, tmp/native_chamber_endpoint_run, tmp/independent_cold_v37 remain untouched'; current_main='C100 tmp continuation and protected canonical SLX remain untouched' }
    classification_counts=@($classRows | Group-Object tier | ForEach-Object {[ordered]@{tier=$_.Name;files=$_.Count;bytes=[int64](($_.Group|Measure-Object bytes -Sum).Sum)}})
}
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $auditRoot 'round2_retention_classification_and_candidate_plan.json') -Encoding utf8
[pscustomobject]@{classification_csv=(Join-Path $auditRoot 'file_retention_classification.csv');candidate_count=$hashRows.Count;candidate_bytes=$plan.high_confidence_candidate.expected_reclaimed_bytes;read_only=$true;deletion_performed=$false} | ConvertTo-Json
