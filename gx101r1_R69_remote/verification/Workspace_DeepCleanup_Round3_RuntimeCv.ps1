$ErrorActionPreference = 'Stop'

$repo = 'C:\Users\86182\Desktop\正逆耦合'
$worktreeRoot = 'C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合'
$targetRoot = Join-Path $worktreeRoot 'gx101r1_R69_remote'
$outputsRoot = Join-Path $targetRoot 'outputs'
$auditRoot = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r2'
$inventoryPath = Join-Path $auditRoot 'runtime_cv_json_large_files.json'

New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null

$targetNames = @(
    'observations.mat',
    'diagnostic_state_observation.mat',
    'internal_state_observation.mat',
    'physical_simscape_result.mat'
)
$protectedGroupPatterns = @(
    'qian_table4_fixed',
    'C200',
    'final_operating',
    'shared_endpoint_OP_C100'
)
$explicitCandidates = @(
    'v40_storage_warmup_r2\native\observations.mat',
    'v40_storage_warmup_r2\native\diagnostic_state_observation.mat',
    'v41_storage_warmup_from_C22_r1\native\observations.mat',
    'v41_storage_warmup_from_C22_r1\native\diagnostic_state_observation.mat'
)
$keepRepresentativeGroups = @('v43_storage_warmup_from_C42_r1')
$scriptExtensions = @('.m','.mlx','.py','.ps1','.psm1','.bat','.cmd','.sh','.json','.yaml','.yml')

function Get-RelativePath([string]$base, [string]$path) {
    return [IO.Path]::GetRelativePath($base, $path).Replace('/','\')
}

function Test-AnyName([string[]]$names, [string]$pattern) {
    return @($names | Where-Object { $_ -like $pattern }).Count -gt 0
}

function Get-ScriptReferences([string]$groupName, [string]$relativePath, [string]$fileName) {
    $refs = [ordered]@{ direct = @(); group = @(); generic_name = @() }
    $searchRoots = @($worktreeRoot, $repo)
    foreach ($root in $searchRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $patterns = @()
        $patterns += $relativePath
        $patterns += ($relativePath -replace '\\','/')
        $patterns += ($groupName + '\\' + $fileName)
        foreach ($pattern in $patterns | Select-Object -Unique) {
            $args = @('-l','-F','--hidden','--no-messages','--glob','!**/.git/**','--glob','!**/outputs/**','--glob','!**/outputs_storage_audit/**')
            foreach ($ext in $scriptExtensions) { $args += @('--glob', ('*' + $ext)) }
            $args += @('--', $pattern, $root)
            $matches = @(& rg.exe @args 2>$null)
            foreach ($m in $matches) {
                if ($m) { $refs.direct += $m }
            }
        }
        $nameArgs = @('-l','-F','--hidden','--no-messages','--glob','!**/.git/**','--glob','!**/outputs/**','--glob','!**/outputs_storage_audit/**')
        foreach ($ext in $scriptExtensions) { $nameArgs += @('--glob', ('*' + $ext)) }
        $nameArgs += @('--', $fileName, $root)
        $nameMatches = @(& rg.exe @nameArgs 2>$null)
        foreach ($m in $nameMatches) {
            if ($m) { $refs.generic_name += $m }
        }
    }
    $refs.direct = @($refs.direct | Sort-Object -Unique)
    $refs.group = @($refs.group | Sort-Object -Unique)
    $refs.generic_name = @($refs.generic_name | Sort-Object -Unique)
    return $refs
}

if (-not (Test-Path -LiteralPath $outputsRoot -PathType Container)) { throw "Missing outputs root: $outputsRoot" }

$auditFiles = @()
$receiptMetadata = @()
$mainAuditRoot = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit'
if (Test-Path -LiteralPath $mainAuditRoot -PathType Container) {
    $auditFiles = @(Get-ChildItem -LiteralPath $mainAuditRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('storage_receipt.json','retirement_receipt.json','packet_manifest.json','collection_result.json','cycle_physical_summary.csv','cold_public_targets.mat','final_operating_point.mat') -or $_.Name -like 'HISTORICAL_*_RETIRED.json' -or $_.Name -like 'COMPLETED_*_RETIRED.json' })
    foreach ($receiptFile in @($auditFiles | Where-Object { $_.Name -in @('storage_receipt.json','retirement_receipt.json') })) {
        try {
            $receiptJson = Get-Content -LiteralPath $receiptFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $receiptStrings = @()
            function Add-JsonStringLeaves($value) {
                if ($null -eq $value) { return }
                if ($value -is [string]) { $script:receiptStrings += $value; return }
                if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [hashtable])) {
                    foreach ($item in $value) { Add-JsonStringLeaves $item }
                    return
                }
                if ($value.PSObject) {
                    foreach ($prop in $value.PSObject.Properties) { Add-JsonStringLeaves $prop.Value }
                }
            }
            $script:receiptStrings = @()
            Add-JsonStringLeaves $receiptJson
            $receiptStrings = @($script:receiptStrings)
            $sourceGroups = @($receiptStrings | ForEach-Object {
                if ($_ -match '\\outputs\\([^\\/]+)') { $Matches[1] }
            } | Sort-Object -Unique)
            $receiptMetadata += [ordered]@{ path=$receiptFile.FullName; kind=$receiptFile.Name; group_names=$sourceGroups; production_recovery_allowed=if($receiptJson.PSObject.Properties.Name -contains 'production_recovery_allowed'){$receiptJson.production_recovery_allowed}else{$null} }
        } catch {
            # A malformed historical receipt is recorded by path but never used as deletion evidence.
            $receiptMetadata += [ordered]@{ path=$receiptFile.FullName; kind=$receiptFile.Name; group_names=@(); production_recovery_allowed=$null; parse_error=$_.Exception.Message }
        }
    }
}

$groupCache = @{}
$allFiles = @(Get-ChildItem -LiteralPath $outputsRoot -Recurse -File -Force -ErrorAction Stop)
$selectedFiles = @($allFiles | Where-Object { $_.Name -in $targetNames } | Sort-Object Length -Descending)
$rows = @()
foreach ($file in $selectedFiles) {
    $relativeToOutputs = Get-RelativePath $outputsRoot $file.FullName
    $parts = $relativeToOutputs -split '\\'
    $groupName = if ($parts.Count -gt 0) { $parts[0] } else { '<root>' }
    $groupRoot = Join-Path $outputsRoot $groupName
    if (-not $groupCache.ContainsKey($groupName)) {
        $groupFiles = @(Get-ChildItem -LiteralPath $groupRoot -Recurse -File -Force -ErrorAction SilentlyContinue)
        $groupNames = @($groupFiles | ForEach-Object Name)
        $receiptMatches = @($receiptMetadata | Where-Object { $_.group_names -contains $groupName })
        $auditMatches = @($auditFiles | Where-Object { $_.FullName -like ('*' + $groupName + '*') })
        $hasStorage = (Test-AnyName $groupNames 'storage_receipt.json') -or (@($receiptMatches | Where-Object kind -eq 'storage_receipt.json').Count -gt 0)
        $hasRetirement = (Test-AnyName $groupNames 'retirement_receipt.json') -or (@($receiptMatches | Where-Object kind -eq 'retirement_receipt.json').Count -gt 0)
        $hasRetiredMarker = (Test-AnyName $groupNames 'HISTORICAL_*_RETIRED.json') -or (Test-AnyName $groupNames 'COMPLETED_*_RETIRED.json') -or (Test-AnyName $groupNames 'REJECTED_DO_NOT_RESUME*')
        $replacement = @($groupFiles | Where-Object {
            $_.Name -in @('cold_public_targets.mat','cycle_physical_summary.csv','stage_temperature_probes_50samples.csv','final_operating_point.mat','collection_result.json') -or $_.Name -like 'retained_key_evidence_shared_*.h5'
        } | ForEach-Object { $_.FullName })
        $isProtected = @($protectedGroupPatterns | Where-Object { $groupName -like ('*' + $_ + '*') }).Count -gt 0
        $groupCache[$groupName] = [ordered]@{
            files = $groupFiles
            names = $groupNames
            has_storage_receipt = $hasStorage
            has_retirement_receipt = $hasRetirement
            has_retired_marker = $hasRetiredMarker
            replacement_evidence = $replacement
            protected_group = $isProtected
            audit_receipt_paths = @($receiptMatches | ForEach-Object path) + @($auditMatches | ForEach-Object FullName)
            receipt_metadata = $receiptMatches
        }
    }
    $g = $groupCache[$groupName]
    $refs = Get-ScriptReferences $groupName $relativeToOutputs $file.Name
    $directRefs = @($refs.direct | Where-Object { $_ -notlike '*Workspace_DeepCleanup*' -and $_ -notlike '*file_retention_classification*' })
    $explicitRound2Candidate = $explicitCandidates -contains $relativeToOutputs
    $keepRepresentative = $keepRepresentativeGroups -contains $groupName
    $candidate = $explicitRound2Candidate -and ($file.Name -ne 'physical_simscape_result.mat') -and $g.has_storage_receipt -and ($g.replacement_evidence.Count -gt 0) -and (-not $g.protected_group) -and (-not $keepRepresentative) -and ($directRefs.Count -eq 0)
    $rows += [ordered]@{
        path = $file.FullName
        relative_path = $relativeToOutputs
        candidate_group = $groupName
        bytes = [int64]$file.Length
        sha256 = $null
        last_write_utc = $file.LastWriteTimeUtc.ToString('o')
        storage_receipt_present = [bool]$g.has_storage_receipt
        retirement_receipt_present = [bool]$g.has_retirement_receipt
        retired_or_rejected_marker_present = [bool]$g.has_retired_marker
        replacement_evidence_paths = @($g.replacement_evidence)
        protected_group = [bool]$g.protected_group
        explicit_round2_candidate = [bool]$explicitRound2Candidate
        keep_representative_group = [bool]$keepRepresentative
        associated_receipt_paths = @($g.audit_receipt_paths)
        script_references_direct = $directRefs
        script_references_generic_name = @($refs.generic_name | Where-Object { $_ -notlike '*Workspace_DeepCleanup*' -and $_ -notlike '*file_retention_classification*' })
        high_confidence_cleanup_candidate = [bool]$candidate
        cleanup_block_reason = if ($candidate) { $null } elseif ($file.Name -eq 'physical_simscape_result.mat') { 'Physical result retained pending explicit hash-equivalence and benchmark replacement proof.' } elseif (-not $explicitRound2Candidate) { 'Not in the explicit conservative round-2 whitelist.' } elseif ($keepRepresentative) { 'Longest retained representative group.' } elseif ($g.protected_group) { 'Protected benchmark/final candidate group.' } elseif (-not $g.has_storage_receipt) { 'No associated storage receipt.' } elseif ($g.replacement_evidence.Count -eq 0) { 'No compact public target, cycle summary, H5, or final OP replacement found.' } elseif ($directRefs.Count -gt 0) { 'Direct script/path reference found.' } else { 'Unresolved retention condition.' }
    }
}

$groupRows = @($groupCache.GetEnumerator() | Sort-Object Name | ForEach-Object {
    $g = $_.Value
    [ordered]@{
        candidate_group = $_.Key
        file_count = @($g.files).Count
        bytes = [int64](@($g.files | Measure-Object Length -Sum).Sum)
        has_storage_receipt = [bool]$g.has_storage_receipt
        has_retirement_receipt = [bool]$g.has_retirement_receipt
        retired_or_rejected_marker_present = [bool]$g.has_retired_marker
        replacement_evidence_paths = @($g.replacement_evidence)
        protected_group = [bool]$g.protected_group
        audit_receipt_paths = @($g.audit_receipt_paths)
    }
})

$out = [ordered]@{
    schema = 'agent5_runtime_cv_json_large_files_v2'
    generated_utc = (Get-Date).ToUniversalTime().ToString('o')
    thread_id = '019e9312-444b-7090-a68e-0888598c1598'
    project_path = $repo
    worktree_root = $worktreeRoot
    read_only_inventory = $true
    deletion_performed = $false
    target_file_names = $targetNames
    group_summaries = $groupRows
    files = $rows
    high_confidence_candidate_count = @($rows | Where-Object high_confidence_cleanup_candidate).Count
    high_confidence_candidate_bytes = [int64](@($rows | Where-Object high_confidence_cleanup_candidate | Measure-Object bytes -Sum).Sum)
    notes = @(
        'physical_simscape_result.mat is never auto-selected for deletion in this round.',
        'Generic producer references to a basename are reported separately; deletion requires no direct path/group reference.',
        'Only this attached runtime-cv-json-contract worktree is scanned; other worktrees and unconfirmed paths are untouched.'
    )
}
$out | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $inventoryPath -Encoding utf8
$out | Select-Object schema,generated_utc,high_confidence_candidate_count,high_confidence_candidate_bytes | ConvertTo-Json
