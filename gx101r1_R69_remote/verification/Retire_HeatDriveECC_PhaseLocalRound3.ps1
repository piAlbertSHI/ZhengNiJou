$ErrorActionPreference = 'Stop'

$repo = 'C:\Users\86182\Desktop\正逆耦合'
$root = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote'
$audit = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r3'
$planPath = Join-Path $audit 'round3_retention_plan.json'
$receiptPath = Join-Path $audit 'round3_phase_local_retirement_receipt.json'
$storageReceipt = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\v55_runtime_Tc276p85_C52_snapshot_20261016\storage_receipt.json'
$prefixReceipt = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\v55_runtime_Tc276p85_C52_snapshot_20261016\raw_prefix_retirement_receipt.json'
$marker = Join-Path $root 'outputs\v55_runtime_Tc276p85_precision_fromC40_r2\COMPLETED_RAW_PREFIX_RETIRED.json'

if (Test-Path -LiteralPath $receiptPath) { throw "Refusing repeat deletion: $receiptPath" }
$plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($plan.explicit_deletion_group -ne 'v55_runtime_Tc276p85_precision_fromC40_r2') { throw 'Explicit deletion group changed.' }
$candidates = @($plan.hashed_candidates)
if ($candidates.Count -ne 10) { throw "Expected exactly 10 hashed candidates, got $($candidates.Count)." }
if (@($plan.direct_script_references).Count -ne 0) { throw 'Direct script references are present.' }
if (@($plan.live_process_references).Count -ne 0) { throw 'Live process references are present.' }

function Hash([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Assert-File([string]$p) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing required file: $p" } }
function Assert-NotReparse([string]$p) {
    $i = Get-Item -LiteralPath $p -Force
    if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse candidate: $p" }
    $d = $i.Directory
    while ($null -ne $d) { if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse ancestor: $p" }; $d = $d.Parent }
}
function TreeStats([string]$p) {
    $f = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction Stop)
    $sum = [int64]0
    foreach ($x in $f) { $sum += [int64]$x.Length }
    return [ordered]@{ file_count=$f.Count; bytes=$sum }
}

Assert-File $storageReceipt
Assert-File $prefixReceipt
Assert-File $marker
$storageReceiptHash = Hash $storageReceipt
$prefixReceiptHash = Hash $prefixReceipt
$markerHash = Hash $marker
$storageJson = Get-Content -LiteralPath $storageReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
$prefixJson = Get-Content -LiteralPath $prefixReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
if ($prefixJson.status -ne 'completed') { throw 'The existing raw-prefix retirement receipt is not completed.' }
if (@($storageJson.compact_copies).Count -lt 20) { throw 'Compact storage receipt is incomplete.' }

$packetEvidence = @()
foreach ($c in $candidates) {
    Assert-File $c.path
    Assert-NotReparse $c.path
    $actual = Get-Item -LiteralPath $c.path -Force
    if ([int64]$actual.Length -ne [int64]$c.bytes) { throw "Size changed: $($c.path)" }
    if ((Hash $c.path) -ne $c.sha256) { throw "Hash changed: $($c.path)" }
    $packetDir = if ($actual.Directory.Name -eq 'native') { $actual.Directory.Parent.FullName } else { $actual.Directory.FullName }
    foreach ($name in @('cycle_physical_summary.csv','stage_temperature_probes_50samples.csv','packet_manifest.json')) {
        $e = Join-Path $packetDir $name
        Assert-File $e
        $packetEvidence += $e
    }
}

$representative = @()
$repRoot = Join-Path $root 'outputs\v56_runtime_Tc277p05_precision_fromC40_r1'
$repFiles = @(Get-ChildItem -LiteralPath $repRoot -Recurse -File -Force -ErrorAction Stop | Where-Object { $_.Name -in @('observations.mat','observed_states.mat') })
if ($repFiles.Count -ne 10) { throw "Expected 10 v56 representative raw files, got $($repFiles.Count)." }
foreach ($f in $repFiles) { Assert-NotReparse $f.FullName; $representative += [ordered]@{path=$f.FullName;bytes=[int64]$f.Length;sha256=(Hash $f.FullName)} }

$before = TreeStats $root
$deleted = @($candidates | ForEach-Object { [ordered]@{path=$_.path;bytes=[int64]$_.bytes;sha256=$_.sha256;structure=$_.structure} })
$freed = [int64]0
foreach ($d in $deleted) { $freed += [int64]$d.bytes }
$pre = [ordered]@{storage_receipt=$storageReceipt;storage_receipt_sha256=$storageReceiptHash;prefix_retirement_receipt=$prefixReceipt;prefix_retirement_receipt_sha256=$prefixReceiptHash;retired_marker=$marker;retired_marker_sha256=$markerHash;packet_evidence=@($packetEvidence | Sort-Object -Unique)}
$pre | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $audit 'round3_predelete_evidence.json') -Encoding utf8

foreach ($c in $candidates) {
    Remove-Item -LiteralPath $c.path -Force
    if (Test-Path -LiteralPath $c.path) { throw "Candidate remained: $($c.path)" }
}

foreach ($e in @($packetEvidence | Sort-Object -Unique)) { Assert-File $e }
if ((Hash $storageReceipt) -ne $storageReceiptHash -or (Hash $prefixReceipt) -ne $prefixReceiptHash -or (Hash $marker) -ne $markerHash) { throw 'Audit evidence changed after deletion.' }
foreach ($r in $representative) { Assert-File $r.path; if ((Hash $r.path) -ne $r.sha256) { throw "Representative changed: $($r.path)" } }
$after = TreeStats $root

$receipt = [ordered]@{
    schema='agent5_phase_local_blend_round3_retirement_v1';status='completed';generated_utc=(Get-Date).ToUniversalTime().ToString('o');thread_id='019e9312-444b-7090-a68e-0888598c1598';scope='stage4-phase-local-blend-diagnostic only';worktree_root=$root;
    deleted_files=$deleted;reclaimed_bytes=$freed;reclaimed_gib=[math]::Round($freed/1GB,6);pre_cleanup=$before;post_cleanup=$after;
    deletion_basis='v55 C44-C52 raw observations/state files were explicitly hashed, directly unreferenced, not live, and superseded by compact v55 storage evidence plus cycle summaries, temperature probes, packet manifests and collection result. v56 C44-C52 was retained as the representative precision raw branch.';
    replacement_evidence=[ordered]@{storage_receipt=$storageReceipt;storage_receipt_sha256=$storageReceiptHash;raw_prefix_retirement_receipt=$prefixReceipt;raw_prefix_retirement_receipt_sha256=$prefixReceiptHash;retired_marker=$marker;retired_marker_sha256=$markerHash;packet_evidence=@($packetEvidence|Sort-Object -Unique)};
    retained_representative=[ordered]@{group='v56_runtime_Tc277p05_precision_fromC40_r1';files=$representative;purpose='representative precision branch retained; v55 is a superseded adjacent-Tc branch'};
    structure_comparison='Deleted v55 observed_states files are MATLAB 7.3 HDF5 with 527 datasets and 30 shape classes; deleted v55 observations files are MATLAB 7.3 HDF5 with 9359 datasets and 46 shape classes. v56 representative files remain available.';
    direct_script_references=@();live_process_references=@();scientific_gates_changed=$false;production_recovery_source_deleted=$false;model_or_code_deleted=$false;final_plots_deleted=$false;other_worktrees_touched=$false;new_project_touched=$false;agentheat2_touched=$false;agent6_touched=$false;protected_slx_touched=$false;
    recovery_route='Use v55 compact evidence for historical diagnosis; regenerate v55 raw trajectories from retained code/configuration if ever required. Use retained v56 raw representative for raw precision-branch inspection.'
}
$receipt | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 6
