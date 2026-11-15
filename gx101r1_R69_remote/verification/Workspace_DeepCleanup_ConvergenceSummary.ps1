$ErrorActionPreference = 'Stop'

$repo = 'C:\Users\86182\Desktop\正逆耦合'
$auditRoot = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_convergence_20261115'
$worktrees = @(
    'C:\Users\86182\.codex\worktrees\fixed-stage4-kp237-endpoint\正逆耦合',
    'C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合',
    'C:\Users\86182\.codex\worktrees\stage4-default-cold-diagnostic\正逆耦合',
    'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合'
)
$minimalGroups = @('v64c1','v65c1','v66_sensitivity_nominal_20261017','v68r2','v70case2','v71case3')
$knownUnique = @('qian_table4_fixed_Tc_276p950K_kp136_255_steady_from_valid107_20260821')
New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null

function SumBytes($items) {
    $s = [int64]0
    foreach ($i in @($items)) { $s += [int64]$i.Length }
    return $s
}
function Classify($groupName, $files) {
    if ($knownUnique -contains $groupName) { return 'protected_C200_duplicate_checkout_copy' }
    if ($minimalGroups -contains $groupName) { return 'compact_evidence_candidate_pending_minimal_retention_review' }
    $names = @($files | ForEach-Object Name)
    $hasReceipt = @($names | Where-Object { $_ -in @('storage_receipt.json','retirement_receipt.json','HISTORICAL_RAW_RETIRED.json','COMPLETED_RAW_PREFIX_RETIRED.json') }).Count -gt 0
    $hasCompact = @($names | Where-Object { $_ -in @('cycle_physical_summary.csv','stage_temperature_probes_50samples.csv','packet_manifest.json','collection_result.json') -or $_ -like 'retained_key_evidence_shared_*.h5' }).Count -gt 0
    if ($hasReceipt -and $hasCompact) { return 'historical_raw_with_compact_evidence' }
    if (@($files | Where-Object { $_.FullName -match '\\(cache|codegen|slprj|simulink_cache)(\\|$)' }).Count -gt 0) { return 'regenerable_cache_or_build_output' }
    if ($groupName -match '^(v\d+|qian_|qcfractional|qcm|qian_coupled)') { return 'historical_or_intermediate_diagnostic_raw' }
    return '用途尚不明确'
}

$rows = @()
$subdirRows = @()
foreach ($wt in $worktrees) {
    $outputs = Join-Path $wt 'gx101r1_R69_remote\outputs'
    if (-not (Test-Path -LiteralPath $outputs -PathType Container)) { continue }
    foreach ($group in Get-ChildItem -LiteralPath $outputs -Directory -Force -ErrorAction SilentlyContinue) {
        $files = @(Get-ChildItem -LiteralPath $group.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
        $rawMat = @($files | Where-Object { $_.Extension -eq '.mat' -and $_.FullName -notmatch '\\(cache|codegen|slprj|simulink_cache)(\\|$)' })
        $cacheFiles = @($files | Where-Object { $_.FullName -match '\\(cache|codegen|slprj|simulink_cache)(\\|$)' })
        $subdirs = @()
        foreach ($child in Get-ChildItem -LiteralPath $group.FullName -Directory -Force -ErrorAction SilentlyContinue) {
            $childFiles = @(Get-ChildItem -LiteralPath $child.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
            $sub = [ordered]@{ relative_path=[IO.Path]::GetRelativePath($outputs,$child.FullName).Replace('/','\\'); file_count=$childFiles.Count; bytes=(SumBytes $childFiles) }
            $subdirs += $sub
            $subdirRows += [ordered]@{ worktree=$wt; group=$group.Name; relative_path=$sub.relative_path; file_count=$sub.file_count; bytes=$sub.bytes }
        }
        $rows += [ordered]@{
            worktree=$wt; group=$group.Name; path=$group.FullName; classification=(Classify $group.Name $files); file_count=$files.Count; bytes=(SumBytes $files); raw_mat_count=$rawMat.Count; raw_mat_bytes=(SumBytes $rawMat); cache_file_count=$cacheFiles.Count; cache_bytes=(SumBytes $cacheFiles); subdirectories=$subdirs; largest_files=@($files | Sort-Object Length -Descending | Select-Object -First 5 | ForEach-Object { [ordered]@{ path=$_.FullName; bytes=[int64]$_.Length; extension=$_.Extension } })
        }
    }
}

$summary = [ordered]@{
    schema='agent5_workspace_convergence_summary_v1';generated_utc=(Get-Date).ToUniversalTime().ToString('o');thread_id='019e9312-444b-7090-a68e-0888598c1598';project_path=$repo;read_only=$true;deletion_performed=$false;worktrees=$worktrees;groups=$rows;subdirectories=$subdirRows;notes=@('This is a metadata-only summary over the four confirmed Agent5 worktrees.','The six minimal-retention groups are not deleted in this audit.','Protected main SLX, Agent6, other worktrees and unconfirmed paths are outside the scan.')
}
$jsonPath = Join-Path $auditRoot 'workspace_convergence_summary.json'
$csvPath = Join-Path $auditRoot 'workspace_convergence_groups.csv'
$subCsvPath = Join-Path $auditRoot 'workspace_convergence_subdirectories.csv'
$mdPath = Join-Path $auditRoot 'workspace_convergence_summary.md'
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding utf8
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
$subdirRows | Export-Csv -LiteralPath $subCsvPath -NoTypeInformation -Encoding utf8
$lines = @('# Agent5 四个 worktree outputs 汇总审计','','本次只读扫描，不删除或移动任何数据。','','| Worktree | 一级 outputs 组数 | outputs 总量 | raw MAT 总量 | cache/build 总量 |','|---|---:|---:|---:|---:|')
foreach ($wt in $worktrees) {
    $r = @($rows | Where-Object worktree -eq $wt)
    if ($r.Count -eq 0) { continue }
    $bytes = [int64](@($r | ForEach-Object bytes | Measure-Object -Sum).Sum)
    $raw = [int64](@($r | ForEach-Object raw_mat_bytes | Measure-Object -Sum).Sum)
    $cache = [int64](@($r | ForEach-Object cache_bytes | Measure-Object -Sum).Sum)
    $lines += "| $wt | $($r.Count) | $([math]::Round($bytes/1GB,3)) GiB | $([math]::Round($raw/1GB,3)) GiB | $([math]::Round($cache/1GB,3)) GiB |"
}
$lines += @('','## 分类说明','','1. current_unique_representative_result：当前唯一基准/代表性结果。','2. historical_raw_with_compact_evidence：有 compact summaries、gate、manifest 或 receipt 的历史 raw。','3. historical_or_intermediate_diagnostic_raw：历史或中间诊断 raw，需结合具体 receipt 再决定。','4. regenerable_cache_or_build_output：可再生缓存或构建输出。','5. compact_evidence_candidate_pending_minimal_retention_review：六组最小保留审计候选，已单独列出代表性 raw 和候选 raw。','','JSON: ' + $jsonPath,'CSV: ' + $csvPath,'Subdirectory CSV: ' + $subCsvPath)
$lines | Set-Content -LiteralPath $mdPath -Encoding utf8
[pscustomobject]@{json=$jsonPath;csv=$csvPath;subdirectories=$subCsvPath;markdown=$mdPath;groups=$rows.Count}|ConvertTo-Json
