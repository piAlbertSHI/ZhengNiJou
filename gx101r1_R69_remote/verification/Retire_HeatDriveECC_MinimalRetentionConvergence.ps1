$ErrorActionPreference = 'Stop'

$repo = 'C:\Users\86182\Desktop\正逆耦合'
$worktrees = @(
    'C:\Users\86182\.codex\worktrees\fixed-stage4-kp237-endpoint\正逆耦合',
    'C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合',
    'C:\Users\86182\.codex\worktrees\stage4-default-cold-diagnostic\正逆耦合',
    'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合'
)
$auditRoot = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_minimal_retention_audit'
$inventoryPath = Join-Path $auditRoot 'minimal_retention_audit.json'
$receiptPath = Join-Path $auditRoot 'minimal_retention_execution_receipt.json'
$auditByGroup = @{
    v64c1='C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\v64_Tc272p85_phase_rejection_20261016'
    v65c1='C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\v65_Tc273p85_phase_rejection_20261017'
    v66_sensitivity_nominal_20261017='C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\v66_nominal_cold_20cycle_20261017'
    v68r2='C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\v68_L8case01_C20_20261017'
    v70case2='C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\v70_L8case02_C20_20261018'
    v71case3='C:\Users\86182\Desktop\正逆耦合\gx101r1_R69_remote\outputs_storage_audit\v71_L8case03_C20_20261018'
}
if (Test-Path -LiteralPath $receiptPath) { throw "Refusing repeat deletion: $receiptPath" }
$inventory = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$candidates = @($inventory.raw_inventory | Where-Object { $_.compact_substitution_candidate -eq $true -and $_.keep_representative -ne $true })
$retained = @($inventory.raw_inventory | Where-Object { $_.keep_representative -eq $true })
if ($candidates.Count -ne 64) { throw "Expected 64 exact candidates, got $($candidates.Count)." }
if ([int64](@($candidates | ForEach-Object bytes | Measure-Object -Sum).Sum) -ne [int64]13711080912) { throw 'Candidate byte whitelist changed.' }

function Hash([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Assert-File([string]$p) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing required file: $p" } }
function Assert-NotReparse([string]$p) {
    $i = Get-Item -LiteralPath $p -Force
    if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse-point file: $p" }
    $d = $i.Directory
    while ($null -ne $d) { if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse-point ancestor: $p" }; $d = $d.Parent }
}
function TreeStats([string]$p) {
    $f = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction Stop)
    $s = [int64]0; foreach ($x in $f) { $s += [int64]$x.Length }
    return [ordered]@{ file_count=$f.Count; bytes=$s }
}
function DirectRefs([string]$relativePath) {
    $out = @()
    foreach ($root in @((Join-Path $worktrees[0] 'gx101r1_R69_remote\verification'),(Join-Path $worktrees[3] 'gx101r1_R69_remote\verification'),(Join-Path $repo 'gx101r1_R69_remote\verification'))) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $args = @('-l','-F','--hidden','--no-messages','--glob','!**/.git/**')
        foreach ($e in @('.m','.mlx','.py','.ps1','.psm1','.bat','.cmd','.sh','.json','.yaml','.yml')) { $args += @('--glob',('*' + $e)) }
        $args += @('--', $relativePath.Replace('\\','/'), $root)
        $out += @(& rg.exe @args 2>$null)
    }
    return @($out | Where-Object { $_ -and $_ -notlike '*Workspace_DeepCleanup*' -and $_ -notlike '*Retire_HeatDriveECC_MinimalRetentionConvergence.ps1' } | Sort-Object -Unique)
}

$procs = @(Get-CimInstance Win32_Process | Select-Object ProcessId,Name,CommandLine)
$preRows = @()
$evidence = @()
foreach ($row in $candidates) {
    Assert-File $row.path
    Assert-NotReparse $row.path
    $item = Get-Item -LiteralPath $row.path -Force
    if ([int64]$item.Length -ne [int64]$row.bytes) { throw "Size changed: $($row.path)" }
    $rel = $row.relative_path
    $refs = DirectRefs $rel
    if ($refs.Count -gt 0) { throw "Direct script reference: $($row.path) -> $($refs -join ', ')" }
    $live = @($procs | Where-Object { $_.CommandLine -and ($_.CommandLine.Replace('/','\\').Contains($row.path) -or $_.CommandLine.Replace('/','\\').Contains($rel)) })
    if ($live.Count -gt 0) { throw "Live process reference: $($row.path)" }
    $packetDir = if ($item.Directory.Name -eq 'native') { $item.Directory.Parent.FullName } else { $item.Directory.FullName }
    if ($row.packet -eq 'fresh_native_probe') {
        $freshEvidence = @(Get-ChildItem -LiteralPath $auditByGroup[$row.group] -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'fresh_native_source.json' })
        if ($freshEvidence.Count -eq 0) { throw "Missing compact fresh-native source evidence: $($row.path)" }
        $evidence += @($freshEvidence | ForEach-Object FullName)
    } else {
        foreach ($required in @('stage_temperature_probes_50samples.csv','packet_manifest.json','cycle_physical_summary.csv')) { Assert-File (Join-Path $packetDir $required) }
    }
    $preRows += [ordered]@{ path=$row.path; relative_path=$rel; group=$row.group; packet=$row.packet; bytes=[int64]$item.Length; sha256=(Hash $row.path); structure='MATLAB 7.3/HDF5 structure recorded in minimal_retention_audit.json' }
}

# C124 was directly reviewed before deletion: it is not a periodic/precision pass, so it remains a candidate.
$v65C124Stability = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v65c1\periodicity_C124_attempt01\target_window_stability.json'
$v65C124Measured = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v65c1\periodicity_C124_attempt01\measured_window.json'
Assert-File $v65C124Stability
Assert-File $v65C124Measured
$v65C124Json = Get-Content -LiteralPath $v65C124Stability -Raw -Encoding UTF8 | ConvertFrom-Json
$v65Decision = [ordered]@{ path=$v65C124Stability; sha256=(Hash $v65C124Stability); measured_window=$v65C124Measured; measured_window_sha256=(Hash $v65C124Measured); precision_pass=$v65C124Json.precision_pass; periodic_steady_state=$v65C124Json.complete_internal_state_periodicity_claim; lift_span_K=$v65C124Json.lift_span_K; SCP_span_W_per_g=$v65C124Json.SCP_span_W_per_g; decision='candidate retained only as compact target-window evidence; raw C124 eligible for this minimal-retention execution' }
if ($v65C124Json.precision_pass -ne $false) { throw 'Unexpected v65 C124 precision result; refuse deletion.' }

$beforeWorktrees = @()
foreach ($wt in $worktrees) { $beforeWorktrees += [ordered]@{ path=$wt; stats=(TreeStats $wt) } }
$protected = @()
foreach ($row in $retained) { Assert-File $row.path; $protected += [ordered]@{path=$row.path;group=$row.group;packet=$row.packet;bytes=[int64](Get-Item $row.path).Length;sha256=(Hash $row.path)} }

$deleted = @()
foreach ($row in $preRows) {
    Remove-Item -LiteralPath $row.path -Force
    if (Test-Path -LiteralPath $row.path) { throw "Candidate remained: $($row.path)" }
    $deleted += $row
}

foreach ($row in $protected) { Assert-File $row.path; if ((Hash $row.path) -ne $row.sha256) { throw "Protected representative changed: $($row.path)" } }
$afterWorktrees = @()
foreach ($wt in $worktrees) { $afterWorktrees += [ordered]@{ path=$wt; stats=(TreeStats $wt) } }
$freed = [int64]0; foreach ($row in $deleted) { $freed += [int64]$row.bytes }
$gitStatus = @(git -C $repo status --short 2>$null)

$receipt = [ordered]@{
    schema='agent5_minimal_retention_execution_receipt_v1';status='completed';generated_utc=(Get-Date).ToUniversalTime().ToString('o');thread_id='019e9312-444b-7090-a68e-0888598c1598';scope='six minimal-retention groups only';read_only_audit_before_execution=$true;
    deleted_files=$deleted;deleted_file_count=$deleted.Count;reclaimed_bytes=$freed;reclaimed_gib=[math]::Round($freed/1GB,6);protected_representative_files=$protected;
    v65_c124_decision=$v65Decision;before_worktrees=$beforeWorktrees;after_worktrees=$afterWorktrees;direct_script_references=@();live_process_references=@();hdf5_external_links='none_found_in_six_groups_or_audit_roots';
    scientific_gates_changed=$false;matlab_simulink_started=$false;C200_touched=$false;physical_simscape_result_touched=$false;main_model_SLX_touched=$false;Agent6_touched=$false;other_worktrees_touched=$false;new_project_touched=$false;agentheat2_touched=$false;
    retention_rule='v64/v65 keep first intervention and last failed packet; v66/v68/v70/v71 keep C020; fresh probe and earlier raw are replaced by packet summaries, probes, manifests, gates, contracts and audit receipts.';
    git_status_after=$gitStatus
}
$receiptPath = Join-Path $auditRoot 'minimal_retention_execution_receipt.json'
$receipt | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 6
