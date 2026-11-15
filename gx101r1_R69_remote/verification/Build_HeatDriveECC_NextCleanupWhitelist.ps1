param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\86182\Desktop\正逆耦合'
$auditRoot = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_next_20261115'
$runtime = 'C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合'
$phase = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合'
$roots = @(
    'C:\Users\86182\.codex\worktrees\fixed-stage4-kp237-endpoint\正逆耦合',
    $runtime,
    'C:\Users\86182\.codex\worktrees\stage4-default-cold-diagnostic\正逆耦合',
    $phase
)

if (Test-Path -LiteralPath $auditRoot) { throw "Audit root already exists: $auditRoot" }

function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

function Assert-NoReparse([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse candidate: $Path"
    }
    $parent = $item.Directory
    while ($null -ne $parent) {
        if (($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse ancestor: $Path"
        }
        $parent = $parent.Parent
    }
}

function Tree-Stats([string]$Path) {
    $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction Stop)
    $bytes = [int64]0
    foreach ($file in $files) { $bytes += [int64]$file.Length }
    [ordered]@{ file_count = $files.Count; logical_bytes = $bytes }
}

$live = @(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '(?i)^matlab(\.exe)?$|simulink|sldriver'
    })
if ($live.Count -gt 0) {
    throw ('A related MATLAB/Simulink process is alive: ' + ($live | Select-Object ProcessId, Name, CommandLine | ConvertTo-Json -Compress))
}

$cacheTargets = @(
    "$runtime\gx101r1_R69_remote\outputs\v9_warmup20p\buffer_component_build",
    "$runtime\gx101r1_R69_remote\outputs\v9_warmup20p\component_build",
    "$runtime\gx101r1_R69_remote\outputs\v10_distributed_ff_10s\buffer_component_build",
    "$runtime\gx101r1_R69_remote\outputs\v10_distributed_ff_10s\component_build",
    "$runtime\gx101r1_R69_remote\outputs\v11_distributed_ff_10s\cache",
    "$runtime\gx101r1_R69_remote\outputs\v11_distributed_ff_10s\buffer_component_build",
    "$runtime\gx101r1_R69_remote\outputs\v11_distributed_ff_10s\component_build",
    "$runtime\gx101r1_R69_remote\outputs\v11_distributed_ff_10s\codegen",
    "$runtime\gx101r1_R69_remote\outputs\v13_missing_conservative_10s\cache",
    "$runtime\gx101r1_R69_remote\outputs\v13_missing_conservative_10s\buffer_component_build",
    "$runtime\gx101r1_R69_remote\outputs\v13_missing_conservative_10s\component_build",
    "$runtime\gx101r1_R69_remote\outputs\v13_missing_conservative_10s\codegen",
    "$runtime\gx101r1_R69_remote\outputs\v14_distributed_ff20c\cache",
    "$runtime\gx101r1_R69_remote\outputs\v14_distributed_ff20c\buffer_component_build",
    "$runtime\gx101r1_R69_remote\outputs\v14_distributed_ff20c\component_build",
    "$runtime\gx101r1_R69_remote\outputs\v14_distributed_ff20c\codegen",
    "$runtime\gx101r1_R69_remote\outputs\v16_distributed_envelope_20c\buffer_component_build",
    "$runtime\gx101r1_R69_remote\outputs\v16_distributed_envelope_20c\component_build",
    "$runtime\gx101r1_R69_remote\outputs\v21_bounded_complete_cycle_restore\buffer_component_build",
    "$runtime\gx101r1_R69_remote\outputs\v21_bounded_complete_cycle_restore\component_build"
)

$eligible = @()
foreach ($directory in $cacheTargets) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
    $groupRoot = Split-Path -Parent $directory
    $markers = @(Get-ChildItem -LiteralPath $groupRoot -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'REJECTED_DO_NOT_RESUME|HISTORICAL_CONSERVATIVE_RAW_RETIRED|WARMUP_ONLY_NOT_RECOVERY' })
    if ($markers.Count -eq 0) { throw "Cache target lacks a terminal marker: $directory" }
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -File -Recurse -Force -ErrorAction Stop)) {
        Assert-NoReparse $file.FullName
        $eligible += [ordered]@{
            path = $file.FullName
            bytes = [int64]$file.Length
            sha256 = Hash $file.FullName
            classification = 'regenerable_rejected_run_build_cache'
            group = $groupRoot
            replacement_evidence = @($markers.FullName)
            direct_script_references = @()
            live_process_references = @()
            deletion_impact = 'No scientific result, model, configuration, public target, audit, or plot source; rebuildable from retained code/model.'
        }
    }
}

$blockedRawPaths = @(
    "$runtime\gx101r1_R69_remote\outputs\v9_warmup20p\native\observations.mat",
    "$runtime\gx101r1_R69_remote\outputs\v10_distributed_ff_10s\native\observations.mat",
    "$runtime\gx101r1_R69_remote\outputs\v11_distributed_ff_10s\native\observations.mat",
    "$runtime\gx101r1_R69_remote\outputs\v13_missing_conservative_10s\conservative\observations.mat",
    "$runtime\gx101r1_R69_remote\outputs\v16_distributed_envelope_20c\native\observations.mat",
    "$runtime\gx101r1_R69_remote\outputs\v38_density_r3\candidate\native\observations.mat"
)
$blockedRaw = @()
foreach ($path in $blockedRawPaths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $groupRoot = Split-Path -Parent (Split-Path -Parent $path)
    $evidence = @(Get-ChildItem -LiteralPath $groupRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'REJECTED_DO_NOT_RESUME|HISTORICAL_CONSERVATIVE_RAW_RETIRED|WARMUP_ONLY_NOT_RECOVERY|retained_key_evidence_shared_.*\.h5$|cold_public_targets\.mat$|runtime_inventory_targets\.json$|storage_closure_execution\.json$' } |
        Select-Object -ExpandProperty FullName)
    $blockedRaw += [ordered]@{
        path = $path
        bytes = [int64](Get-Item -LiteralPath $path).Length
        sha256 = Hash $path
        classification = 'blocked_unique_or_full_native_diagnostic_raw'
        replacement_evidence = @($evidence | Select-Object -Unique)
        reference_conclusion = 'No active script path reference was found, but compact evidence is not a complete replacement for the retained native/full diagnostic arm; current storage policy retains this raw.'
        deletion_impact = 'Would remove the full native diagnostic trajectory and prevent exact raw re-audit or same-arm reconstruction.'
    }
}

$blockedPhaseGroups = @()
foreach ($name in @('v56_runtime_Tc277p05_precision_fromC40_r1', 'v61c1', 'v67c1', 'v68c1', 'v70c1', 'v71c1')) {
    $group = Join-Path $phase "gx101r1_R69_remote\outputs\$name"
    if (-not (Test-Path -LiteralPath $group -PathType Container)) { continue }
    $files = @(Get-ChildItem -LiteralPath $group -File -Recurse -Force -ErrorAction Stop)
    $raw = @($files | Where-Object { $_.Name -in @('observations.mat', 'observed_states.mat') })
    $blockedPhaseGroups += [ordered]@{
        group = $group
        logical_bytes = [int64](($files | Measure-Object Length -Sum).Sum)
        raw_bytes = [int64](($raw | Measure-Object Length -Sum).Sum)
        raw_file_count = $raw.Count
        classification = 'blocked_current_or_protected_diagnostic_chain'
        reference_conclusion = 'Current runtime/L8 contracts, protected packet inputs, split-comparison or representative precision evidence still depend on this chain.'
        deletion_impact = 'Would remove current diagnostic/recovery evidence; no compact replacement with equivalent raw-state contract was verified.'
    }
}

$c200Audit = Get-Content -LiteralPath "$repo\gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_convergence_20261115\c200_duplicate_checkout_audit.json" -Raw | ConvertFrom-Json
$c200 = @()
$op = @()
foreach ($copy in $c200Audit.copies) {
    $path = $copy.physical_path
    $c200 += [ordered]@{ path = $path; bytes = [int64]$copy.physical_bytes; sha256 = Hash $path; expected_sha256 = $copy.physical_sha256; link_type = (Get-Item -LiteralPath $path).LinkType; hardlink_listing = @(fsutil hardlink list $path); classification = 'already_hardlinked_checkout_path'; reclaimable_bytes = 0 }
    $path = $copy.op_path
    $op += [ordered]@{ path = $path; bytes = [int64]$copy.op_bytes; sha256 = Hash $path; expected_sha256 = $copy.op_sha256; link_type = (Get-Item -LiteralPath $path).LinkType; hardlink_listing = @(fsutil hardlink list $path); classification = 'already_hardlinked_checkout_path'; reclaimable_bytes = 0 }
}

$before = @()
foreach ($root in $roots) { $stats = Tree-Stats $root; $before += [ordered]@{ path = $root; file_count = $stats.file_count; logical_bytes = $stats.logical_bytes } }
New-Item -ItemType Directory -Path $auditRoot | Out-Null
$whitelist = [ordered]@{
    schema = 'agent5_next_cleanup_whitelist_v1'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    thread_id = '019e9312-444b-7090-a68e-0888598c1598'
    scope = 'Agent5 confirmed worktrees only; no New project, Agentheat2, Agent6, positive/pressure worktrees, or native_chamber_endpoint_run'
    active_matlab_processes_before = @()
    deletion_performed = $false
    eligible_files = $eligible
    blocked_large_raw = $blockedRaw
    blocked_phase_groups = $blockedPhaseGroups
    c200_physical = $c200
    c200_operating_points = $op
    before_worktrees = $before
    policy = 'Only regenerable rejected-run cache files are eligible now. Native/full diagnostic raw remains blocked unless a complete equivalent evidence package is verified. C200 logical copies are already NTFS hardlinks and have zero reclaimable space.'
}
$whitelistPath = Join-Path $auditRoot 'next_cleanup_whitelist.json'
$whitelist | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $whitelistPath -Encoding utf8

$deleted = @()
if ($Apply) {
    foreach ($candidate in $eligible) {
        if ((Hash $candidate.path) -ne $candidate.sha256) { throw "Candidate changed before deletion: $($candidate.path)" }
        Remove-Item -LiteralPath $candidate.path -Force
        if (Test-Path -LiteralPath $candidate.path) { throw "Candidate remained: $($candidate.path)" }
        $deleted += $candidate
    }
}

$after = @()
foreach ($root in $roots) { $stats = Tree-Stats $root; $after += [ordered]@{ path = $root; file_count = $stats.file_count; logical_bytes = $stats.logical_bytes } }
$whitelist.deletion_performed = $Apply.IsPresent
$whitelist.deleted_files = $deleted
$whitelist.reclaimed_bytes = [int64](($deleted | Measure-Object bytes -Sum).Sum)
$whitelist.after_worktrees = $after
$whitelist | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $whitelistPath -Encoding utf8

$receipt = [ordered]@{
    schema = 'agent5_next_cleanup_execution_receipt_v1'
    status = 'completed'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    whitelist = $whitelistPath
    deleted_files = $deleted
    deleted_file_count = $deleted.Count
    reclaimed_bytes = [int64](($deleted | Measure-Object bytes -Sum).Sum)
    reclaimed_gib = [math]::Round((($deleted | Measure-Object bytes -Sum).Sum) / 1GB, 6)
    blocked_large_raw = $blockedRaw
    blocked_phase_groups = $blockedPhaseGroups
    c200_actual_reclaimable_bytes = 0
    matlab_simulink_started_or_interrupted = $false
    scientific_gates_changed = $false
    main_model_SLX_touched = $false
    Agent6_touched = $false
    other_worktrees_touched = $false
}
$receiptPath = Join-Path $auditRoot 'next_cleanup_execution_receipt.json'
$receipt | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $receiptPath -Encoding utf8
[pscustomobject]@{ status = $receipt.status; deleted_count = $receipt.deleted_file_count; reclaimed_bytes = $receipt.reclaimed_bytes; reclaimed_gib = $receipt.reclaimed_gib; blocked_raw_count = $blockedRaw.Count; blocked_phase_group_count = $blockedPhaseGroups.Count; c200_reclaimable = $receipt.c200_actual_reclaimable_bytes; audit_root = $auditRoot } | ConvertTo-Json
