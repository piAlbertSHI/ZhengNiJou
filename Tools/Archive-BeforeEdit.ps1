[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string[]]$Path,

    [Parameter()]
    [string]$Label = 'before_edit'
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$workspacePrefix = $workspaceRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
$safeLabel = ($Label -replace '[^0-9A-Za-z_-]', '_').Trim('_')
if ([string]::IsNullOrWhiteSpace($safeLabel)) {
    $safeLabel = 'before_edit'
}

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$archiveDirectoryName = ([char]0x5F52).ToString() + ([char]0x6863).ToString()
$archiveRoot = Join-Path $workspaceRoot (Join-Path $archiveDirectoryName ($stamp + '_' + $safeLabel))
$records = New-Object System.Collections.Generic.List[object]

foreach ($inputPath in $Path) {
    $candidate = if ([System.IO.Path]::IsPathRooted($inputPath)) {
        $inputPath
    } else {
        Join-Path $workspaceRoot $inputPath
    }
    $resolved = [System.IO.Path]::GetFullPath($candidate)
    if (-not ($resolved.Equals($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $resolved.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Refusing to archive a path outside the workspace: $resolved"
    }
    if (-not (Test-Path -LiteralPath $resolved)) {
        throw "Archive source does not exist: $resolved"
    }

    $files = if ((Get-Item -LiteralPath $resolved).PSIsContainer) {
        Get-ChildItem -LiteralPath $resolved -Recurse -File
    } else {
        @(Get-Item -LiteralPath $resolved)
    }

    foreach ($file in $files) {
        $source = [System.IO.Path]::GetFullPath($file.FullName)
        $relative = $source.Substring($workspacePrefix.Length)
        $destination = Join-Path $archiveRoot $relative
        $destinationParent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $records.Add([pscustomobject]@{
                relative_path = $relative
                sha256 = $hash
                size_bytes = $file.Length
                archived_at = (Get-Date).ToString('o')
            })
    }
}

New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
$records | Export-Csv -LiteralPath (Join-Path $archiveRoot 'manifest.csv') -NoTypeInformation -Encoding UTF8
$records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $archiveRoot 'manifest.json') -Encoding UTF8
Write-Output $archiveRoot
