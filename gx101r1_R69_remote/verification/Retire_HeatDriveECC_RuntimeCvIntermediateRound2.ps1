$ErrorActionPreference = 'Stop'

$repo = 'C:\Users\86182\Desktop\正逆耦合'
$worktreeRoot = 'C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合'
$targetRoot = Join-Path $worktreeRoot 'gx101r1_R69_remote'
$auditRoot = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r2'
$receiptPath = Join-Path $auditRoot 'round2_runtime_cv_retirement_receipt.json'
$planPath = Join-Path $auditRoot 'round2_runtime_cv_retirement_plan.json'

New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null
if (Test-Path -LiteralPath $receiptPath) { throw "Refusing repeat deletion because receipt already exists: $receiptPath" }

$candidates = @(
    [ordered]@{
        path = "$targetRoot\outputs\v40_storage_warmup_r2\native\observations.mat"
        group = 'v40_storage_warmup_r2'
        role = 'old C22 warmup raw observations; replaced by compact targets and retained longer representative'
        storage_receipt = "$repo\gx101r1_R69_remote\outputs_storage_audit\v40_storage_snapshot_20261014\storage_receipt.json"
        replacement_paths = @(
            "$targetRoot\outputs\v40_storage_warmup_r2\native\cold_public_targets.mat"
            "$targetRoot\outputs\v40_storage_warmup_r2\native\diagnostic_complete_operating_point.mat"
            "$repo\gx101r1_R69_remote\outputs_storage_audit\v40_storage_snapshot_20261014\storage_receipt.json"
        )
        structure = [ordered]@{matlab_format='MATLAB 7.3 HDF5';dataset_count=9469;shape_count=51;principal_leaf_names=@('block_path','channel_count','state_name','time_s','unit','values','temperature','pressure_differential','pump_power_se_W','pump_power_sma_W','chex_fluid_heat_flow_W','hhex_fluid_heat_flow_W','shex_fluid_heat_flow_W')}
    }
    [ordered]@{
        path = "$targetRoot\outputs\v40_storage_warmup_r2\native\diagnostic_state_observation.mat"
        group = 'v40_storage_warmup_r2'
        role = 'old C22 diagnostic trajectory; replaced by compact OP/audit and retained longer representative'
        storage_receipt = "$repo\gx101r1_R69_remote\outputs_storage_audit\v40_storage_snapshot_20261014\storage_receipt.json"
        replacement_paths = @(
            "$targetRoot\outputs\v40_storage_warmup_r2\native\diagnostic_complete_operating_point.mat"
            "$targetRoot\outputs\v40_storage_warmup_r2\native\cold_public_targets.mat"
            "$repo\gx101r1_R69_remote\outputs_storage_audit\v40_storage_snapshot_20261014\storage_receipt.json"
        )
        structure = [ordered]@{matlab_format='MATLAB 7.3 HDF5';dataset_count=528;shape_count=30;principal_leaf_names=@('block_path','channel_count','complete_requested_window','state_name','time_s','unit','values','complete_internal_state_periodicity_verified')}
    }
    [ordered]@{
        path = "$targetRoot\outputs\v41_storage_warmup_from_C22_r1\native\observations.mat"
        group = 'v41_storage_warmup_from_C22_r1'
        role = 'old C42 restart raw observations; replaced by compact targets and retained longer representative'
        storage_receipt = "$repo\gx101r1_R69_remote\outputs_storage_audit\v41_storage_snapshot_20261015\storage_receipt.json"
        replacement_paths = @(
            "$targetRoot\outputs\v41_storage_warmup_from_C22_r1\native\cold_public_targets.mat"
            "$targetRoot\outputs\v41_storage_warmup_from_C22_r1\native\diagnostic_complete_operating_point.mat"
            "$repo\gx101r1_R69_remote\outputs_storage_audit\v41_storage_snapshot_20261015\storage_receipt.json"
        )
        structure = [ordered]@{matlab_format='MATLAB 7.3 HDF5';dataset_count=9469;shape_count=51;principal_leaf_names=@('block_path','channel_count','state_name','time_s','unit','values','temperature','pressure_differential','pump_power_se_W','pump_power_sma_W','chex_fluid_heat_flow_W','hhex_fluid_heat_flow_W','shex_fluid_heat_flow_W')}
    }
    [ordered]@{
        path = "$targetRoot\outputs\v41_storage_warmup_from_C22_r1\native\diagnostic_state_observation.mat"
        group = 'v41_storage_warmup_from_C22_r1'
        role = 'old C42 diagnostic trajectory; replaced by compact OP/audit and retained longer representative'
        storage_receipt = "$repo\gx101r1_R69_remote\outputs_storage_audit\v41_storage_snapshot_20261015\storage_receipt.json"
        replacement_paths = @(
            "$targetRoot\outputs\v41_storage_warmup_from_C22_r1\native\cold_public_targets.mat"
            "$targetRoot\outputs\v41_storage_warmup_from_C22_r1\native\diagnostic_complete_operating_point.mat"
            "$repo\gx101r1_R69_remote\outputs_storage_audit\v41_storage_snapshot_20261015\storage_receipt.json"
        )
        structure = [ordered]@{matlab_format='MATLAB 7.3 HDF5';dataset_count=528;shape_count=30;principal_leaf_names=@('block_path','channel_count','complete_requested_window','state_name','time_s','unit','values','complete_internal_state_periodicity_verified')}
    }
)

$v43Paths = @(
    "$targetRoot\outputs\v43_storage_warmup_from_C42_r1\native\observations.mat"
    "$targetRoot\outputs\v43_storage_warmup_from_C42_r1\native\diagnostic_state_observation.mat"
)
$v43Receipt = "$repo\gx101r1_R69_remote\outputs_storage_audit\v43_storage_snapshot_20261015\storage_receipt.json"

function Normalize([string]$p) { return $p.Replace('/','\') }
function Hash([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Assert-File([string]$p) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Missing required file: $p" } }
function Assert-NotReparse([string]$p) {
    $i = Get-Item -LiteralPath $p -Force
    if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse-point candidate: $p" }
    $d = $i.Directory
    while ($null -ne $d) {
        if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse-point ancestor: $p" }
        $d = $d.Parent
    }
}
function TreeStats([string]$p) {
    $files = @(Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction Stop)
    return [ordered]@{ file_count=$files.Count; bytes=[int64](@($files | Measure-Object Length -Sum).Sum) }
}

foreach ($c in $candidates) {
    Assert-File $c.path
    Assert-NotReparse $c.path
    foreach ($e in $c.replacement_paths) { Assert-File $e }
    Assert-File $c.storage_receipt
    $receiptJson = Get-Content -LiteralPath $c.storage_receipt -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($receiptJson.PSObject.Properties.Name -contains 'production_recovery_allowed' -and $receiptJson.production_recovery_allowed -ne $false) { throw "Receipt permits production recovery: $($c.storage_receipt)" }
    $entries = @()
    foreach ($propertyName in @('retained_current_raw','retained_raw')) {
        if ($receiptJson.PSObject.Properties.Name -contains $propertyName) { $entries += @($receiptJson.$propertyName) }
    }
    $entry = @($entries | Where-Object { (Normalize ([string]$_.path)) -eq (Normalize $c.path) }) | Select-Object -First 1
    if ($null -eq $entry) { throw "Storage receipt does not identify candidate: $($c.path)" }
    if ((Hash $c.path) -ne $entry.sha256) { throw "Candidate hash disagrees with storage receipt: $($c.path)" }
}

Assert-File $v43Receipt
$v43ReceiptJson = Get-Content -LiteralPath $v43Receipt -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($p in $v43Paths) {
    Assert-File $p
    Assert-NotReparse $p
    $entries = @()
    foreach ($propertyName in @('retained_current_raw','retained_raw')) { if ($v43ReceiptJson.PSObject.Properties.Name -contains $propertyName) { $entries += @($v43ReceiptJson.$propertyName) } }
    $entry = @($entries | Where-Object { (Normalize ([string]$_.path)) -eq (Normalize $p) }) | Select-Object -First 1
    if ($null -eq $entry -or (Hash $p) -ne $entry.sha256) { throw "Retained v43 representative failed receipt hash check: $p" }
}

$verificationRoots = @(
    (Join-Path $targetRoot 'verification'),
    (Join-Path $repo 'gx101r1_R69_remote\verification')
)
$directRefs = @()
foreach ($c in $candidates) {
    $relative = [IO.Path]::GetRelativePath($targetRoot, $c.path).Replace('/','\')
    $patterns = @($relative, $relative.Replace('\','/'), "outputs\$relative", "outputs/$($relative.Replace('\','/'))")
    foreach ($root in $verificationRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($pattern in $patterns) {
            $args = @('-l','-F','--hidden','--no-messages','--glob','!**/.git/**')
            foreach ($ext in @('.m','.mlx','.py','.ps1','.psm1','.bat','.cmd','.sh','.json','.yaml','.yml')) { $args += @('--glob',('*' + $ext)) }
            $args += @('--', $pattern, $root)
            $matches = @(& rg.exe @args 2>$null)
            foreach ($m in $matches) { if ($m) { $directRefs += [ordered]@{candidate=$c.path;pattern=$pattern;script=$m} } }
        }
    }
}
$directRefs = @($directRefs | Where-Object { $_.script -ne $PSCommandPath -and $_.script -notlike '*Workspace_DeepCleanup_Round3_RuntimeCv.ps1' })
if ($directRefs.Count -gt 0) { throw ('Direct script references found: ' + ($directRefs | ConvertTo-Json -Depth 5 -Compress)) }

$processes = @(Get-CimInstance Win32_Process | Select-Object ProcessId,Name,CommandLine)
$liveRefs = @()
foreach ($proc in $processes) {
    if (-not $proc.CommandLine) { continue }
    foreach ($c in $candidates) {
        $cmd = $proc.CommandLine.Replace('/','\')
        if ($cmd.Contains($c.path) -or $cmd.Contains(([IO.Path]::GetRelativePath($targetRoot, $c.path)).Replace('/','\'))) {
            $liveRefs += [ordered]@{pid=$proc.ProcessId;name=$proc.Name;candidate=$c.path}
        }
    }
}
if ($liveRefs.Count -gt 0) { throw ('Live process references found: ' + ($liveRefs | ConvertTo-Json -Depth 5 -Compress)) }

$before = TreeStats $targetRoot
$preRows = @()
foreach ($c in $candidates) {
    $i = Get-Item -LiteralPath $c.path -Force
    $preRows += [ordered]@{path=$c.path;bytes=[int64]$i.Length;sha256=(Hash $c.path);role=$c.role;storage_receipt=$c.storage_receipt;replacement_paths=$c.replacement_paths;structure=$c.structure}
}
$plan = [ordered]@{
    schema='agent5_runtime_cv_round2_retirement_plan_v1';generated_utc=(Get-Date).ToUniversalTime().ToString('o');status='ready_for_exact_whitelist_deletion';scope='runtime-cv-json-contract only';thread_id='019e9312-444b-7090-a68e-0888598c1598';
    before_tree=$before; candidates=$preRows; direct_script_references=$directRefs; live_process_references=$liveRefs;
    retained_representative=[ordered]@{paths=$v43Paths;receipt=$v43Receipt;purpose='longest retained v43 C62 raw diagnostic reference; not deleted'};
    scientific_gates_changed=$false;other_worktrees_touched=$false;matlab_simulink_started=$false
}
$plan | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = @()
foreach ($c in $candidates) {
    Remove-Item -LiteralPath $c.path -Force
    if (Test-Path -LiteralPath $c.path) { throw "Candidate remained after deletion: $($c.path)" }
    $deleted += $preRows | Where-Object path -eq $c.path
}

# Recheck all compact replacements, receipts, the retained v43 representative, and the protected main worktree.
foreach ($c in $candidates) { foreach ($e in $c.replacement_paths) { Assert-File $e } }
foreach ($p in $v43Paths) { Assert-File $p }
$after = TreeStats $targetRoot
$freed = [int64]0
foreach ($d in $deleted) { $freed += [int64]$d.bytes }
$gitStatus = @(git -C $repo status --short 2>$null)
$gitWorktrees = @(git -C $repo worktree list --porcelain 2>$null)

$receipt = [ordered]@{
    schema='agent5_runtime_cv_round2_retirement_v1';status='completed';generated_utc=(Get-Date).ToUniversalTime().ToString('o');scope='runtime-cv-json-contract only';thread_id='019e9312-444b-7090-a68e-0888598c1598';project_path=$repo;worktree_root=$worktreeRoot;
    deleted_files=$deleted;reclaimed_bytes=$freed;reclaimed_gib=[math]::Round($freed/1GB,6);pre_cleanup=$before;post_cleanup=$after;
    candidate_basis='v40/v41 raw observations and diagnostic trajectories were non-production, receipt-hashed, directly unreferenced, and replaced by compact public targets, diagnostic OP/configuration, and archived storage receipts. v43 C62 was retained as the longest raw representative.';
    replacement_evidence=(@($candidates | ForEach-Object { $_.replacement_paths } | Select-Object -Unique | ForEach-Object { [ordered]@{path=$_;bytes=[int64](Get-Item -LiteralPath $_).Length;sha256=(Hash $_)} }));
    storage_receipts=(@($candidates | ForEach-Object storage_receipt | Select-Object -Unique | ForEach-Object { [ordered]@{path=$_;sha256=(Hash $_)} }));
    retained_representative=[ordered]@{paths=@($v43Paths | ForEach-Object { [ordered]@{path=$_;bytes=[int64](Get-Item -LiteralPath $_).Length;sha256=(Hash $_)} });receipt=$v43Receipt;receipt_sha256=(Hash $v43Receipt);structure=$candidates[0].structure};
    mat_structure_comparison=[ordered]@{observations='All v40/v41/v43 observations files were MATLAB 7.3 HDF5 with 9469 datasets and 51 shape classes; v40/v41/v43 diagnostic_state_observation files were MATLAB 7.3 HDF5 with 528 datasets and 30 shape classes. They are separate cycle records, not byte-identical duplicates; the two earlier records were retired only as regenerable intermediate trajectories.'};
    direct_script_references=$directRefs;live_process_references=$liveRefs;scientific_gates_changed=$false;production_recovery_source_deleted=$false;model_or_code_deleted=$false;final_plots_deleted=$false;other_worktrees_touched=$false;new_project_touched=$false;agentheat2_touched=$false;agent6_touched=$false;protected_slx_touched=$false;
    recovery_route='Recreate v40/v41 trajectories from the retained source/model/configuration and archived storage receipts; use retained v43 C62 raw representative or later validated checkpoints for state-based work. Deleted files are not authorized as production recovery sources.';
    git_status=$gitStatus;git_worktrees=$gitWorktrees
}
$receipt | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 6
