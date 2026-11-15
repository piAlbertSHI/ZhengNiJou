$ErrorActionPreference = 'Stop'

# Round 1 is inventory only. It deliberately never removes, moves, hashes, or rewrites
# any experiment file. Reparse points are recorded and skipped to avoid double counting.
$repo = 'C:\Users\86182\Desktop\正逆耦合'
$auditRoot = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r1'
New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null

$threadId = '019e9312-444b-7090-a68e-0888598c1598'
$projectId = 'local-fcaf271142833b7c831d59b517a103c6'
$scopes = @(
    [ordered]@{ key='fixed-stage4-kp237-endpoint'; path='C:\Users\86182\.codex\worktrees\fixed-stage4-kp237-endpoint\正逆耦合'; ownership='Agent5 attached worktree'; artifact_id='01a0ceb2-6ddb-7e62-b751-72b06d85adf8'; status='in_scope' },
    [ordered]@{ key='runtime-cv-json-contract'; path='C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合'; ownership='Agent5 attached worktree; user description conflicts with observed non-empty checkout'; artifact_id='01a1090b-a5a9-7080-b29d-2c0c24b253c6'; status='in_scope_but_deletion_blocked' },
    [ordered]@{ key='stage4-default-cold-diagnostic'; path='C:\Users\86182\.codex\worktrees\stage4-default-cold-diagnostic\正逆耦合'; ownership='Agent5 attached worktree'; artifact_id='01a0e05f-4d8c-7db2-bc6b-b69a988f043d'; status='in_scope' },
    [ordered]@{ key='stage4-phase-local-blend-diagnostic'; path='C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合'; ownership='Agent5 attached worktree'; artifact_id='01a0e3ab-afdc-75f0-9af6-63bf421c6943'; status='in_scope' }
)
$excluded = @(
    [ordered]@{ key='stage4-positive-bias-diagnostic'; path='C:\Users\86182\.codex\worktrees\stage4-positive-bias-diagnostic\正逆耦合'; reason='User marked external or ownership unconfirmed; no deletion' },
    [ordered]@{ key='stage4-pressure-bias-diagnostic'; path='C:\Users\86182\.codex\worktrees\stage4-pressure-bias-diagnostic\正逆耦合'; reason='User marked external or ownership unconfirmed; no deletion' },
    [ordered]@{ key='native_chamber_endpoint_run'; path='C:\Users\86182\Desktop\正逆耦合\tmp\native_chamber_endpoint_run'; reason='User marked external or ownership unconfirmed; no deletion' },
    [ordered]@{ key='independent_cold_v37'; path='C:\Users\86182\Desktop\正逆耦合\tmp\independent_cold_v37'; reason='Found in Git worktree registry but not in user-confirmed scope; no deletion' },
    [ordered]@{ key='runtime-cv-contract'; path='C:\Users\86182\.codex\worktrees\runtime-cv-contract'; reason='Archived attachment described by user as empty; no deletion or archive mutation' }
)

function Get-GitText([string]$worktree, [string[]]$arguments) {
    $value = & git -C $worktree @arguments 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return (($value | Out-String).Trim())
}

function Get-Inventory([hashtable]$scope, [object[]]$processes) {
    $path = $scope.path
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return [ordered]@{ key=$scope.key; path=$path; status='missing'; file_count=0; bytes=0; reparse_points_skipped=@(); max_files=@(); extension_totals=@(); top_level_totals=@(); markers=@(); process_references=@() }
    }
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($path)
    $files = [System.Collections.Generic.List[object]]::new()
    $reparse = [System.Collections.Generic.List[string]]::new()
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $reparse.Add($child.FullName)
                continue
            }
            if ($child.PSIsContainer) { $stack.Push($child.FullName); continue }
            $relative = $child.FullName.Substring($path.Length).TrimStart('\')
            $first = if ($relative.Contains('\')) { $relative.Split('\')[0] } else { '<root-file>' }
            $extension = if ([string]::IsNullOrEmpty($child.Extension)) { '<no_extension>' } else { $child.Extension.ToLowerInvariant() }
            $files.Add([pscustomobject]@{ path=$child.FullName; relative_path=$relative; bytes=[int64]$child.Length; extension=$extension; top_level=$first; last_write_utc=$child.LastWriteTimeUtc.ToString('o') })
        }
    }
    $procRefs = @($processes | Where-Object { $_.CommandLine -and $_.CommandLine.Replace('/','\').Contains($path) } | ForEach-Object { [ordered]@{ pid=[int]$_.ProcessId; name=$_.Name; command_line=$_.CommandLine } })
    $markerNames = @('codex-thread.json','storage_receipt.json','retirement_receipt.json','storage_receipt','retirement_receipt')
    $markers = @($files | Where-Object { $markerNames -contains ([IO.Path]::GetFileName($_.path)) -or ([IO.Path]::GetFileName($_.path) -like 'HISTORICAL_*_RETIRED.json') -or ([IO.Path]::GetFileName($_.path) -like 'COMPLETED_*_RETIRED.json') } | ForEach-Object { $_.path })
    $ext = @($files | Group-Object extension | ForEach-Object { [ordered]@{ extension=$_.Name; file_count=$_.Count; bytes=[int64](($_.Group | Measure-Object bytes -Sum).Sum) } } | Sort-Object bytes -Descending)
    $top = @($files | Group-Object top_level | ForEach-Object { [ordered]@{ top_level=$_.Name; file_count=$_.Count; bytes=[int64](($_.Group | Measure-Object bytes -Sum).Sum) } } | Sort-Object bytes -Descending)
    $max = @($files | Sort-Object bytes -Descending | Select-Object -First 25 | ForEach-Object { [ordered]@{ path=$_.path; relative_path=$_.relative_path; bytes=$_.bytes; extension=$_.extension; last_write_utc=$_.last_write_utc } })
    $last = if ($files.Count) { ($files | Sort-Object last_write_utc -Descending | Select-Object -First 1).last_write_utc } else { $null }
    $head = Get-GitText $path @('rev-parse','HEAD')
    $branch = Get-GitText $path @('branch','--show-current')
    $symbolic = Get-GitText $path @('symbolic-ref','-q','HEAD')
    $status = @(git -C $path status --short 2>$null | Out-String).Trim()
    $statusPaths = @($status -split "`r?`n" | Where-Object { $_ })
    return [ordered]@{
        key=$scope.key; path=$path; status=$scope.status; ownership=$scope.ownership; thread_id=$threadId; project_id=$projectId; artifact_id=$scope.artifact_id
        git_head=$head; git_branch=$branch; git_symbolic_ref=$symbolic; git_status_entries=$statusPaths
        file_count=$files.Count; bytes=[int64](($files | Measure-Object bytes -Sum).Sum); last_write_utc=$last
        reparse_points_skipped=@($reparse); max_files=$max; extension_totals=$ext; top_level_totals=$top; markers=$markers; process_references=$procRefs
        open_handle_status='not directly observable without elevated handle enumeration; process command-line references recorded above'
        large_file_inventory=@($files | Where-Object { $_.extension -in @('.mat','.h5','.hdf5','.slx','.fig','.png','.pdf','.zip','.mexw64','.dll') } | Sort-Object bytes -Descending | Select-Object -First 200 | ForEach-Object { [ordered]@{ path=$_.path; relative_path=$_.relative_path; bytes=$_.bytes; extension=$_.extension; last_write_utc=$_.last_write_utc } })
    }
}

$processes = @(Get-CimInstance Win32_Process | Select-Object ProcessId,Name,CommandLine)
$records = @($scopes | ForEach-Object { Get-Inventory $_ $processes })
$excludedRecords = @($excluded | ForEach-Object {
    $exists = Test-Path -LiteralPath $_.path
    [ordered]@{ key=$_.key; path=$_.path; exists=$exists; reason=$_.reason; deletion_allowed=$false }
})
$worktreeList = @(git -C $repo worktree list --porcelain 2>$null | Out-String).Trim() -split "`r?`n"
$result = [ordered]@{
    schema='agent5_workspace_deep_cleanup_round1_v1'; generated_utc=(Get-Date).ToUniversalTime().ToString('o'); read_only=$true; deletion_performed=$false; move_performed=$false; hash_performed=$false
    current_thread_id=$threadId; project_id=$projectId; project_path=$repo; in_scope=$records; excluded_or_unconfirmed=$excludedRecords
    process_snapshot=$processes; git_worktree_list_porcelain=$worktreeList
    contradictions=@('User described runtime-cv-contract as empty, while runtime-cv-json-contract contains a full checkout; deletion is blocked for both until identity is resolved.', 'The Git registry contains tmp/independent_cold_v37, which was not in the confirmed scope; it is recorded as unconfirmed and untouched.')
    next_round='Classify files, then hash and reference-check only candidates with complete replacement evidence. Do not clean in-scope runtime-cv-json-contract until the naming/ownership conflict is resolved.'
}
$jsonPath = Join-Path $auditRoot 'workspace_ownership_and_space_inventory.json'
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding utf8
$csvRows = foreach ($r in $records) {
    [pscustomobject]@{ key=$r.key; path=$r.path; ownership=$r.ownership; thread_id=$r.thread_id; artifact_id=$r.artifact_id; git_head=$r.git_head; git_branch=$r.git_branch; file_count=$r.file_count; bytes=$r.bytes; size_gib=[math]::Round($r.bytes / 1GB, 6); last_write_utc=$r.last_write_utc; marker_count=@($r.markers).Count; process_reference_count=@($r.process_references).Count; reparse_skipped_count=@($r.reparse_points_skipped).Count; status=($r.status) }
}
$csvRows | Export-Csv -LiteralPath (Join-Path $auditRoot 'workspace_ownership_and_space_inventory.csv') -NoTypeInformation -Encoding utf8
$records | ForEach-Object { $_.large_file_inventory | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $auditRoot ($_.key + '_large_files.json')) -Encoding utf8 }
$grandBytes = [int64](($records | ForEach-Object { [int64]$_.bytes } | Measure-Object -Sum).Sum)
[pscustomobject]@{ audit_root=$auditRoot; worktrees=$records.Count; total_bytes=$grandBytes; total_gib=[math]::Round($grandBytes / 1GB, 6); deletion_performed=$false; json=$jsonPath } | ConvertTo-Json
