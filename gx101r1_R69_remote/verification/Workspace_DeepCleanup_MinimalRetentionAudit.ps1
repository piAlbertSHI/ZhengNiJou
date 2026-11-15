$ErrorActionPreference = 'Stop'

$repo = 'C:\Users\86182\Desktop\正逆耦合'
$worktreeRoot = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote'
$auditRoot = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_minimal_retention_audit'
$verificationRoots = @(
    (Join-Path $worktreeRoot 'verification'),
    (Join-Path $repo 'gx101r1_R69_remote\verification')
)
$groups = @(
    [ordered]@{ name='v64c1'; audit='v64_Tc272p85_phase_rejection_20261016'; keep=@('C110','C118'); disputed=@('C116'); candidate=@('C116'); audit_aliases=@() },
    [ordered]@{ name='v65c1'; audit='v65_Tc273p85_phase_rejection_20261017'; keep=@('C110','C126'); disputed=@('C124'); candidate=@('C116','C118','C120','C122','C124'); audit_aliases=@() },
    [ordered]@{ name='v66_sensitivity_nominal_20261017'; audit='v66_nominal_cold_20cycle_20261017'; keep=@('C020'); disputed=@(); candidate=@('fresh_native_probe','C002','C012','C014','C016','C018'); audit_aliases=@() },
    [ordered]@{ name='v68r2'; audit='v68_L8case01_C20_20261017'; keep=@('C020'); disputed=@(); candidate=@('fresh_native_probe','C002','C012','C014','C016','C018'); audit_aliases=@('v68_L8case01_C60_20261017') },
    [ordered]@{ name='v70case2'; audit='v70_L8case02_C20_20261018'; keep=@('C020'); disputed=@(); candidate=@('fresh_native_probe','C002','C012','C014','C016','C018'); audit_aliases=@('v70_L8case02_C60_20261018') },
    [ordered]@{ name='v71case3'; audit='v71_L8case03_C20_20261018'; keep=@('C020'); disputed=@(); candidate=@('fresh_native_probe','C002','C004','C006','C008','C010','C012','C014','C016','C018'); audit_aliases=@() }
)
$rawNames = @('observations.mat','observed_states.mat','diagnostic_state_observation.mat','internal_state_observation.mat','physical_simscape_result.mat')
$auditEvidenceNames = @('cold_public_targets.mat','configuration.mat','collection_result.json','cold_chamber_execution.json','packet_manifest.json','cycle_physical_summary.csv','stage_temperature_probes_50samples.csv','mechanism.json','boundary_comparison.json','REJECTED_DO_NOT_RESUME.json','HISTORICAL_RAW_RETIRED.json','COMPLETED_RAW_PREFIX_RETIRED.json','storage_receipt.json','retirement_receipt.json','case_closeout.json','post_retirement_storage_classification.json','storage_classification.json','phase_attribution.json','phase_attribution_v2.json','selected_C200_runtime_family_bridge.json','target_window_stability.json','measured_window.json')

New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null

function Get-TreeStats([string]$path) {
    $files = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue)
    $bytes = [int64]0
    foreach ($f in $files) { $bytes += [int64]$f.Length }
    return [ordered]@{ file_count=$files.Count; bytes=$bytes }
}
function Get-Json([string]$path) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    return $null
}
function Get-ReceiptSummary([string]$path) {
    $j = Get-Json $path
    if ($null -eq $j) { return [ordered]@{ path=$path; exists=$false } }
    $summary = [ordered]@{ path=$path; exists=$true; classification=$j.classification; raw_copied_bytes=$j.raw_copied_bytes; raw_deleted_bytes=$j.raw_deleted_bytes; compact_copied_bytes=$j.compact_copied_bytes; retained_single_execution_bytes=$j.retained_single_execution_bytes; production_recovery_allowed=$j.production_recovery_allowed; outer_solve_eligible=$j.outer_solve_eligible; protected_packet_input_count=@($j.protected_packet_inputs).Count; compact_copy_count=@($j.compact_copies).Count }
    return $summary
}
function Get-PacketKey([string]$relativePath) {
    if ($relativePath -match 'fresh_native_probe') { return 'fresh_native_probe' }
    if ($relativePath -match 'packet_(C\d+)(?:_attempt)?') { return $Matches[1] }
    return 'other'
}
function Get-ScriptRefs([string]$relativePath) {
    $found = @()
    foreach ($root in $verificationRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $args = @('-l','-F','--hidden','--no-messages','--glob','!**/.git/**')
        foreach ($ext in @('.m','.mlx','.py','.ps1','.psm1','.bat','.cmd','.sh','.json','.yaml','.yml')) { $args += @('--glob',('*' + $ext)) }
        $args += @('--', $relativePath.Replace('\\','/'), $root)
        $found += @(& rg.exe @args 2>$null)
    }
    return @($found | Where-Object { $_ -and $_ -notlike '*Workspace_DeepCleanup_MinimalRetentionAudit.ps1' } | Sort-Object -Unique)
}

$processes = @(Get-CimInstance Win32_Process | Select-Object ProcessId,Name,CommandLine)
$allRows = @()
$groupRows = @()
$totalRaw = [int64]0
$totalCandidate = [int64]0
$totalRetainedRepresentative = [int64]0

foreach ($g in $groups) {
    $groupRoot = Join-Path $worktreeRoot ('outputs\' + $g.name)
    $audit = Join-Path $repo ('gx101r1_R69_remote\outputs_storage_audit\' + $g.audit)
    $files = @(Get-ChildItem -LiteralPath $groupRoot -Recurse -File -Force -ErrorAction SilentlyContinue)
    $rawFiles = @($files | Where-Object { $_.Name -in $rawNames })
    $storageReceipt = Join-Path $audit 'storage_receipt.json'
    $caseCloseout = Join-Path $audit 'case_closeout.json'
    $retirementReceipts = @(Get-ChildItem -LiteralPath $audit -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'retirement_receipt.json' } | ForEach-Object FullName)
    $markers = @($files | Where-Object { $_.Name -like '*RETIRED*' -or $_.Name -like 'COMPLETED*' -or $_.Name -like 'REJECTED*' } | ForEach-Object FullName)
    $evidenceFiles = @()
    foreach ($auditPath in @($audit) + @($g.audit_aliases | ForEach-Object { Join-Path $repo ('gx101r1_R69_remote\outputs_storage_audit\' + $_) })) {
        if (Test-Path -LiteralPath $auditPath -PathType Container) {
            $evidenceFiles += @(Get-ChildItem -LiteralPath $auditPath -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -in $auditEvidenceNames })
        }
    }
    $evidenceFiles = @($evidenceFiles | Sort-Object FullName -Unique)
    $receiptSummary = Get-ReceiptSummary $storageReceipt
    $case = Get-Json $caseCloseout
    $hdf5Group = @(Get-ChildItem -LiteralPath $groupRoot -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.h5','.hdf5') } | ForEach-Object FullName)
    $hdf5Audit = @(Get-ChildItem -LiteralPath $audit -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.h5','.hdf5') } | ForEach-Object FullName)
    foreach ($f in $rawFiles) {
        $rel = [IO.Path]::GetRelativePath($worktreeRoot, $f.FullName).Replace('/','\\')
        $packet = Get-PacketKey $rel
        $scriptRefs = Get-ScriptRefs $rel
        $processRefs = @($processes | Where-Object { $_.CommandLine -and ($_.CommandLine.Replace('/','\\').Contains($f.FullName) -or $_.CommandLine.Replace('/','\\').Contains($rel)) } | ForEach-Object { [ordered]@{ pid=$_.ProcessId; name=$_.Name } })
        $keep = $g.keep -contains $packet
        $disputed = $g.disputed -contains $packet
        $candidate = $g.candidate -contains $packet
        $basis = if ($keep) { 'Representative raw packet retained under minimal principle.' } elseif ($disputed) { 'Disputed: last stable/pre-failure window may be useful, but compact gate/summary evidence exists.' } elseif ($candidate) { 'Candidate for compact-evidence substitution after a separate deletion review.' } else { 'Outside the selected minimal plan.' }
        $row = [ordered]@{ group=$g.name; packet=$packet; path=$f.FullName; relative_path=$rel; bytes=[int64]$f.Length; kind=$f.Name; keep_representative=$keep; disputed=$disputed; compact_substitution_candidate=$candidate; basis=$basis; direct_script_references=$scriptRefs; live_process_references=$processRefs; hdf5_external_link_check='no .h5/.hdf5 files found in group or audit root' }
        $allRows += $row
        $totalRaw += [int64]$f.Length
        if ($candidate -and $scriptRefs.Count -eq 0 -and $processRefs.Count -eq 0) { $totalCandidate += [int64]$f.Length }
        if ($keep) { $totalRetainedRepresentative += [int64]$f.Length }
    }
    $groupRawBytes = [int64](@($rawFiles | Measure-Object Length -Sum).Sum)
    $groupCandidateBytes = [int64](@($allRows | Where-Object { $_.group -eq $g.name -and $_.compact_substitution_candidate -and $_.direct_script_references.Count -eq 0 -and $_.live_process_references.Count -eq 0 } | ForEach-Object { $_.bytes } | Measure-Object -Sum).Sum)
    $groupKeepBytes = [int64](@($allRows | Where-Object { $_.group -eq $g.name -and $_.keep_representative } | ForEach-Object { $_.bytes } | Measure-Object -Sum).Sum)
    $groupRows += [ordered]@{
        group=$g.name; group_path=$groupRoot; audit_root=$audit; group_stats=(Get-TreeStats $groupRoot); raw_bytes=$groupRawBytes; raw_file_count=$rawFiles.Count; candidate_bytes=$groupCandidateBytes; retained_representative_bytes=$groupKeepBytes; representative_packets=$g.keep; disputed_packets=$g.disputed; candidate_packets=$g.candidate; must_retain_patterns=@('cold_chamber_execution.json','runtime_evidence_contract.mat','collection_result.json','HISTORICAL_*_RETIRED.json','COMPLETED_*_RETIRED.json','native\configuration.mat','native\cold_public_targets.mat','packet_*\packet_manifest.json','packet_*\cycle_physical_summary.csv','packet_*\stage_temperature_probes_50samples.csv','packet_*\mechanism.json','packet_*\boundary_comparison.json','storage_receipt.json','retirement_receipt.json','case_closeout.json'); markers=$markers; storage_receipt=$receiptSummary; retirement_receipt_paths=$retirementReceipts; case_closeout_path=$caseCloseout; case_closeout_summary=[ordered]@{ production_recovery_allowed=$case.production_recovery_allowed; table4_reproduction_claim=$case.table4_reproduction_claim; steady_sensitivity_response_qualified=$case.steady_sensitivity_response_qualified; all_ten_original_packet_gates_pass=$case.all_ten_original_packet_gates_pass }; evidence_file_count=$evidenceFiles.Count; evidence_bytes=[int64](@($evidenceFiles | Measure-Object Length -Sum).Sum); evidence_sample=@($evidenceFiles | Select-Object -First 20 | ForEach-Object FullName); hdf5_files=@($hdf5Group + $hdf5Audit); hdf5_external_links='not_applicable_no_hdf5_files'
    }
}

$summary = [ordered]@{
    schema='agent5_minimal_retention_audit_v1'; generated_utc=(Get-Date).ToUniversalTime().ToString('o'); thread_id='019e9312-444b-7090-a68e-0888598c1598'; project_path=$repo; worktree_root=$worktreeRoot; read_only=$true; deletion_performed=$false; groups=$groupRows; raw_inventory=$allRows; total_raw_bytes=$totalRaw; total_candidate_bytes=$totalCandidate; total_retained_representative_bytes=$totalRetainedRepresentative; candidate_gib=[math]::Round($totalCandidate/1GB,6); total_raw_gib=[math]::Round($totalRaw/1GB,6); policy_notes=@('v64/v65 representative proposal keeps first intervention and last failure packets; C124 is disputed for v65.','v66/v68/v70/v71 representative proposal keeps C020; fresh_native_probe is a candidate because fresh_native_source/evidence contract is archived.','This is a read-only minimum-retention plan, not authorization to delete. Each candidate requires a separate deletion execution after review.','No HDF5/H5 files were found in any six group or corresponding audit root, so no external links were present to inspect.','The storage receipts may still say keep raw for same-case continuation; that is recorded as a policy conflict/remaining dependency, not treated as proof that all raw must remain.')
}
$jsonPath = Join-Path $auditRoot 'minimal_retention_audit.json'
$csvPath = Join-Path $auditRoot 'minimal_retention_raw_inventory.csv'
$mdPath = Join-Path $auditRoot 'minimal_retention_audit_report.md'
$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $jsonPath -Encoding utf8
$allRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
$lines = @('# Agent5 最小保留只读审计','','本轮只读，不删除、不移动、不修改数据。','','| 组 | raw 总量 | 建议保留代表性 raw | compact 替代候选 | 预计候选释放 |','|---|---:|---|---|---:|')
foreach ($gr in $groupRows) { $lines += "| $($gr.group) | $([math]::Round($gr.raw_bytes/1GB,3)) GiB | $($gr.representative_packets -join ', ') | $($gr.candidate_packets -join ', ') | $([math]::Round($gr.candidate_bytes/1GB,3)) GiB |" }
$lines += @('','## 统一保留对象','','所有组必须保留代码、模型、参数、Git/线程归属、case/phase closeout、collection result、failure marker、packet manifest、cycle summary、temperature probes、mechanism/boundary/contract 文件及 storage/retirement receipt。','','## 争议与限制','','- v64/v65：compact 证据完整，但是否保留 C124 等最后稳定窗口需要在执行删除前单独确认。','- v66/v68/v70/v71：storage receipt 仍把 raw 标为 same-case dependency；本审计按最小保留原则提出候选，但没有执行删除。','- 未发现 `.h5`/`.hdf5`，不存在需要处理的 HDF5 external link。','','## 路径','','- JSON: ' + $jsonPath,'- CSV: ' + $csvPath)
$lines | Set-Content -LiteralPath $mdPath -Encoding utf8
[pscustomobject]@{json=$jsonPath;csv=$csvPath;markdown=$mdPath;groups=$groupRows.Count;raw_bytes=$totalRaw;candidate_bytes=$totalCandidate;candidate_gib=[math]::Round($totalCandidate/1GB,6)} | ConvertTo-Json
