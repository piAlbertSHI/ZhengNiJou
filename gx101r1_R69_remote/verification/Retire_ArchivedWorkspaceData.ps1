[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ArchiveRoot = 'C:\Users\86182\Desktop\正逆耦合\归档\2026-06-22_工作区清理',
    [string]$AuditRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$archiveRootResolved = [IO.Path]::GetFullPath($ArchiveRoot).TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($AuditRoot)) {
    $AuditRoot = Join-Path $PSScriptRoot '..\outputs_storage_audit'
}
$auditRootResolved = [IO.Path]::GetFullPath($AuditRoot)
$targets = @(
    (Join-Path $archiveRootResolved 'gx101r1_R69_remote_old_outputs'),
    (Join-Path $archiveRootResolved 'gx101r1_R69_remote_autosave_and_cache')
) | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }

foreach ($target in $targets) {
    if (-not $target.StartsWith($archiveRootResolved + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Target escaped archive root: $target"
    }
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        throw "Missing retirement target: $target"
    }
}

$running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $commandLine = $_.CommandLine
    $commandLine -and (@($targets | Where-Object {
        $commandLine -like "*$_*"
    }).Count -gt 0)
})
if ($running.Count -gt 0) {
    $running | Select-Object ProcessId, Name, CommandLine | Format-List
    throw 'A running process references an archive retirement target.'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$receiptDir = Join-Path $auditRootResolved "archive_retirement_$stamp"
New-Item -ItemType Directory -Path $receiptDir -Force | Out-Null
$files = @($targets | ForEach-Object {
    Get-ChildItem -LiteralPath $_ -File -Recurse -Force -ErrorAction Stop
})
$rows = @($files | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    [pscustomobject]@{
        source_path = $_.FullName
        bytes = $_.Length
        sha256 = $hash
        target_disposition = 'retire_archived_obsolete_output_or_rebuildable_cache'
    }
})
$manifestPath = Join-Path $receiptDir 'retirement_manifest_sha256.csv'
$rows | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding utf8
$bytes = ($files | Measure-Object Length -Sum).Sum

if ($PSCmdlet.ShouldProcess(($targets -join '; '), 'Retire archived obsolete outputs and rebuildable cache')) {
    foreach ($target in $targets) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

$verified = @($targets | Where-Object { Test-Path -LiteralPath $_ }).Count -eq 0
$receipt = [ordered]@{
    generated_at = (Get-Date).ToString('o')
    archive_root = $archiveRootResolved
    target_count = $targets.Count
    file_count = $files.Count
    bytes_retired = $bytes
    GB_retired = [math]::Round($bytes / 1GB, 3)
    manifest = $manifestPath
    targets = $targets
    retirement_verified = $verified
    what_if = [bool]$WhatIfPreference
}
$receiptPath = Join-Path $receiptDir 'retirement_receipt.json'
$receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 4
if (-not $verified -and -not $WhatIfPreference) {
    throw 'Retirement verification failed.'
}
