[CmdletBinding()]
param(
    [string]$OutputRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = Split-Path -Parent $repo
$auditRoot = Join-Path $repo 'outputs_storage_audit\workspace_governance_20260912'
$outputs = Join-Path $repo 'outputs'
$storageAudit = Join-Path $repo 'outputs_storage_audit'
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = $auditRoot
}
$resolvedOutput = [IO.Path]::GetFullPath($OutputRoot)
if (-not $resolvedOutput.StartsWith($storageAudit + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Governance output must remain inside outputs_storage_audit.'
}

function Read-Contract([string]$Name) {
    $path = Join-Path $PSScriptRoot $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing governance contract: $path"
    }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Get-DirectoryBytes([string]$Path) {
    $total = 0L
    foreach ($file in Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue) {
        $total += $file.Length
    }
    return $total
}

$c200 = Read-Contract 'c200_mainline_freeze_contract.json'
$c180 = Read-Contract 'runtime_c180_recovery_contract.json'
$c200Run = Split-Path -Parent ([IO.Path]::GetFullPath((Join-Path $repo $c200.result_relative_path)))
$c200Root = Split-Path -Parent $c200Run
$c180Run = Split-Path -Parent ([IO.Path]::GetFullPath((Join-Path $repo $c180.result_relative_path)))
$c180Root = Split-Path -Parent $c180Run

$explicit = @{
    'qian_runtime_state_observation_from180_20260906' = @{
        class = 'retained_compact_diagnostic'
        action = 'keep_internal_state_and_scalar_evidence'
        reason = 'Nonperiodic runtime C200 observation; recovery prohibited; full physical raw retired by hash.'
    }
    'qian_native_inventory_pilot_from_c180_20260906' = @{
        class = 'retained_inventory_diagnostic'
        action = 'keep'
        reason = 'Native component-ledger evidence still used by inventory audits.'
    }
    'cold_chamber_onset_specific_0p75_20260911' = @{
        class = 'current_cold_diagnostic'
        action = 'keep'
        reason = 'Latest passing dual-arm 0.2 s onset evidence; no recovery authority.'
    }
}

$rows = foreach ($root in @($outputs, $storageAudit)) {
    foreach ($directory in Get-ChildItem -LiteralPath $root -Directory -Force) {
        if ($directory.FullName -eq $resolvedOutput) { continue }
        $bytes = Get-DirectoryBytes $directory.FullName
        $markers = @(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('REJECTED_DO_NOT_RESUME.txt','SUPERSEDED_RAW_COMPACTED.txt',
                    'COMPACTED_AFTER_SCALAR_EXTRACTION.txt') })
        $checkpoints = @(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('final_operating_point.mat','operating_point.mat','checkpoint.mat') })
        $classification = 'historical_diagnostic_or_summary'
        $action = 'retain_pending_explicit_review'
        $reason = 'No automatic deletion rule applies.'
        if ($directory.FullName -eq $c200Root) {
            $classification = 'frozen_C200_paper_authority'
            $action = 'keep_hash_locked'
            $reason = 'Frozen C200 result and Operating Point are protected by the mainline contract.'
        } elseif ($directory.FullName -eq $c180Root) {
            $classification = 'strict_C180_diagnostic_recovery_reference'
            $action = 'keep_hash_locked'
            $reason = 'Authorized only for inventory and PI periodicity diagnostics; still referenced by final audit.'
        } elseif ($root -eq $storageAudit) {
            $classification = 'audit_evidence'
            $action = 'keep_compact_evidence'
            $reason = 'Audit artifacts are retained unless a separate hash-bound retirement contract exists.'
        } elseif ($explicit.ContainsKey($directory.Name)) {
            $classification = $explicit[$directory.Name].class
            $action = $explicit[$directory.Name].action
            $reason = $explicit[$directory.Name].reason
        } elseif ($markers.Count -gt 0) {
            $classification = 'rejected_or_superseded_run'
            $action = 'retain_summary_remove_only_explicit_raw'
            $reason = 'Markers prohibit recovery; raw deletion still requires an exact retirement receipt.'
        }
        [pscustomobject]@{
            root = [IO.Path]::GetRelativePath($workspace, $root)
            directory = $directory.Name
            relative_path = [IO.Path]::GetRelativePath($workspace, $directory.FullName)
            classification = $classification
            action = $action
            bytes = $bytes
            GiB = [math]::Round($bytes / 1GB, 6)
            file_count = @(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Force -ErrorAction SilentlyContinue).Count
            checkpoint_count = $checkpoints.Count
            marker_count = $markers.Count
            reason = $reason
        }
    }
}

New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
$rows = @($rows | Sort-Object bytes -Descending)
$csvPath = Join-Path $resolvedOutput 'workspace_directory_classification.csv'
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8

$gitRows = @(& git -C $workspace log '2b1c865..HEAD' '--date=iso-strict' '--pretty=format:%H%x09%ad%x09%s') |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object {
        $parts = $_ -split "`t", 3
        [pscustomobject]@{ commit = $parts[0]; date = $parts[1]; subject = $parts[2] }
    }
$gitPath = Join-Path $resolvedOutput 'git_commits_since_c200_freeze.csv'
$gitRows | Export-Csv -LiteralPath $gitPath -NoTypeInformation -Encoding utf8

$authorityFiles = foreach ($contract in @($c200, $c180)) {
    foreach ($kind in @('result','checkpoint')) {
        $path = [IO.Path]::GetFullPath((Join-Path $repo $contract."${kind}_relative_path"))
        [pscustomobject]@{
            contract = $contract.schema
            kind = $kind
            path = [IO.Path]::GetRelativePath($workspace, $path)
            exists = Test-Path -LiteralPath $path -PathType Leaf
            bytes = if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-Item -LiteralPath $path).Length } else { 0 }
            actual_sha256 = if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash } else { '' }
            expected_sha256 = $contract."${kind}_sha256"
        }
    }
}
$authorityPass = @($authorityFiles | Where-Object { -not $_.exists -or $_.actual_sha256 -ne $_.expected_sha256 }).Count -eq 0
if (-not $authorityPass) { throw 'Authority or recovery hash verification failed.' }

$classifiedBytes = 0L
foreach ($row in $rows) { $classifiedBytes += $row.bytes }
$summary = [ordered]@{
    schema = 'heatdrive_ecc_workspace_governance_v1'
    generated_at = (Get-Date).ToString('o')
    workspace = $workspace
    branch = (& git -C $workspace branch --show-current).Trim()
    head = (& git -C $workspace rev-parse HEAD).Trim()
    commits_since_c200_freeze = $gitRows.Count
    directory_count = $rows.Count
    total_classified_bytes = $classifiedBytes
    total_classified_GiB = [math]::Round($classifiedBytes / 1GB, 6)
    frozen_C200_hash_pass = $authorityPass
    authority_files = @($authorityFiles)
    untracked_Agent6_untouched = Test-Path -LiteralPath (Join-Path $workspace 'Agent6') -PathType Container
    classification_csv = $csvPath
    git_ledger_csv = $gitPath
}
$jsonPath = Join-Path $resolvedOutput 'workspace_governance_summary.json'
$summary | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $jsonPath -Encoding utf8
$summary | ConvertTo-Json -Depth 7
