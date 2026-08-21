<#
.SYNOPSIS
    Verify and freeze the authoritative C200 recovery contract.

.DESCRIPTION
    Recomputes SHA-256 for the authoritative result and Operating Point,
    verifies the mechanism/periodic report gates, and writes a small audit
    package. It never copies or modifies the multi-gigabyte result files.
#>
[CmdletBinding()]
param(
    [string]$ContractPath = '',
    [string]$AuditRoot = '',
    [switch]$SkipLargeResultHash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($ContractPath)) {
    $ContractPath = Join-Path $PSScriptRoot 'c200_mainline_freeze_contract.json'
}
$ContractPath = [System.IO.Path]::GetFullPath($ContractPath)
if ([string]::IsNullOrWhiteSpace($AuditRoot)) {
    $AuditRoot = Join-Path $repoRoot 'outputs_storage_audit'
}
$AuditRoot = [System.IO.Path]::GetFullPath($AuditRoot)

if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
    throw "Freeze contract is missing: $ContractPath"
}
$contract = Get-Content -LiteralPath $ContractPath -Raw | ConvertFrom-Json
if ($contract.schema -ne 'heatdrive_ecc_mainline_freeze_v1') {
    throw "Unsupported freeze contract schema: $($contract.schema)"
}

function Resolve-ContractPath([string]$RelativePath) {
    $normalized = $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $normalized))
    if (-not $resolved.StartsWith($repoRoot + [System.IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Contract path escapes repository root: $RelativePath"
    }
    return $resolved
}

$resultPath = Resolve-ContractPath $contract.result_relative_path
$checkpointPath = Resolve-ContractPath $contract.checkpoint_relative_path
$reportPath = Resolve-ContractPath $contract.validation_report_relative_path
$progressPath = Resolve-ContractPath $contract.continuation_progress_relative_path
foreach ($path in @($resultPath, $checkpointPath, $reportPath, $progressPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required C200 authority artifact is missing: $path"
    }
}

$checkpointHash = (Get-FileHash -LiteralPath $checkpointPath -Algorithm SHA256).Hash
if ($checkpointHash -ne $contract.checkpoint_sha256) {
    throw "C200 Operating Point SHA-256 mismatch: $checkpointHash"
}
$resultHash = if ($SkipLargeResultHash) {
    'SKIPPED_BY_EXPLICIT_OPTION'
} else {
    (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash
}
if (-not $SkipLargeResultHash -and $resultHash -ne $contract.result_sha256) {
    throw "C200 physical result SHA-256 mismatch: $resultHash"
}

$report = Get-Content -LiteralPath $reportPath -Raw
$mechanismPass = $report -match '(?m)^coupled_mechanism_pass:\s*1\s*$'
$periodicPass = $report -match '(?m)^\s*periodic steady state:\s*1\s*$'
$strictNotClaimed = $report -match '(?m)^\s*strict_table4_reproduction_pass:\s*0\s*$'
if (-not ($mechanismPass -and $periodicPass -and $strictNotClaimed)) {
    throw 'C200 report does not satisfy the frozen mechanism/periodic/claim-boundary contract.'
}

$progress = Import-Csv -LiteralPath $progressPath
$last = $progress | Select-Object -Last 1
if ([int]$last.total_cycles -ne [int]$contract.completed_cycles -or
        [int]$last.mechanism_pass -ne 1) {
    throw 'C200 continuation progress does not match the freeze contract.'
}

New-Item -ItemType Directory -Force -Path $AuditRoot | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$jsonPath = Join-Path $AuditRoot "c200_mainline_freeze_$stamp.json"
$csvPath = Join-Path $AuditRoot "c200_mainline_freeze_files_$stamp.csv"
$rows = @(
    [pscustomobject]@{ role='authoritative_physical_result'; path=$resultPath; bytes=(Get-Item -LiteralPath $resultPath).Length; sha256=$resultHash; expected_sha256=$contract.result_sha256 },
    [pscustomobject]@{ role='sole_mainline_operating_point'; path=$checkpointPath; bytes=(Get-Item -LiteralPath $checkpointPath).Length; sha256=$checkpointHash; expected_sha256=$contract.checkpoint_sha256 },
    [pscustomobject]@{ role='authoritative_validation_report'; path=$reportPath; bytes=(Get-Item -LiteralPath $reportPath).Length; sha256=(Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash; expected_sha256='' },
    [pscustomobject]@{ role='continuation_progress'; path=$progressPath; bytes=(Get-Item -LiteralPath $progressPath).Length; sha256=(Get-FileHash -LiteralPath $progressPath -Algorithm SHA256).Hash; expected_sha256='' }
)
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$audit = [ordered]@{
    schema = 'heatdrive_ecc_mainline_freeze_audit_v1'
    generated_at = (Get-Date).ToString('o')
    contract_path = $ContractPath
    contract_sha256 = (Get-FileHash -LiteralPath $ContractPath -Algorithm SHA256).Hash
    source_code_commit = $contract.source_code_commit
    completed_cycles = [int]$last.total_cycles
    mechanism_pass = $mechanismPass
    periodic_steady_state = $periodicPass
    strict_table4_reproduction = $false
    sole_mainline_recovery_path = $checkpointPath
    checkpoint_sha256 = $checkpointHash
    result_sha256 = $resultHash
    large_result_hash_verified = -not [bool]$SkipLargeResultHash
    rejected_results_may_resume = $false
    rejected_results_may_interpolate = $false
    file_inventory_csv = $csvPath
}
$audit | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$audit | ConvertTo-Json -Depth 6
