[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$CandidateRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'outputs'))
$candidate = [IO.Path]::GetFullPath($CandidateRoot)
$prefix = $outputsRoot + [IO.Path]::DirectorySeparatorChar
if (-not $candidate.StartsWith($prefix,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "Candidate must remain inside repository outputs: $candidate"
}
$rejectMarker = Join-Path $candidate 'REJECTED_DO_NOT_RESUME.txt'
$compactMarker = Join-Path $candidate 'COMPACTED_AFTER_SCALAR_EXTRACTION.txt'
if (-not (Test-Path -LiteralPath $rejectMarker) -or
        -not (Test-Path -LiteralPath $compactMarker)) {
    throw 'Rejected and compaction markers are both required before deletion.'
}
$active = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '^MATLAB(.exe)?$' -and
    $_.CommandLine -like "*$candidate*"
}
if ($null -ne $active) {
    throw 'A MATLAB process still references this candidate root.'
}

$names = @(
    'physical_simscape_result.mat',
    'final_operating_point.mat',
    'stage_temperature_probes_50samples.csv'
)
$targets = @(
    Get-ChildItem -LiteralPath $candidate -Recurse -File |
        Where-Object { $_.Name -in $names }
    Get-ChildItem -LiteralPath $candidate -Recurse -Directory |
        Where-Object { $_.Name -eq 'figures' }
)
$deletedBytes = 0L
$deletedCount = 0
foreach ($target in $targets) {
    $resolved = [IO.Path]::GetFullPath($target.FullName)
    $candidatePrefix = $candidate + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($candidatePrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Deletion target escaped candidate root: $resolved"
    }
    if ($target -is [IO.FileInfo]) {
        $deletedBytes += $target.Length
    } else {
        $deletedBytes += (Get-ChildItem -LiteralPath $resolved -Recurse -File |
            Measure-Object Length -Sum).Sum
    }
    if ($PSCmdlet.ShouldProcess($resolved, 'Remove rejected raw artifact')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
        $deletedCount++
    }
}

$remaining = Get-ChildItem -LiteralPath $candidate -Recurse -File
[ordered]@{
    candidate_root = $candidate
    deleted_count = $deletedCount
    deleted_bytes = $deletedBytes
    remaining_file_count = $remaining.Count
    remaining_bytes = ($remaining | Measure-Object Length -Sum).Sum
    raw_result_count = @($remaining | Where-Object {
        $_.Name -eq 'physical_simscape_result.mat'
    }).Count
    checkpoint_count = @($remaining | Where-Object {
        $_.Name -eq 'final_operating_point.mat'
    }).Count
} | ConvertTo-Json -Depth 3
