[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ExperimentRoot,
    [Parameter(Mandatory=$true)][string]$ReceiptPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ExperimentRoot).Path
if ((Split-Path -Leaf (Split-Path -Parent $root)) -ne 'outputs') {
    throw 'Require an explicit experiment immediately below outputs.'
}
$executionPath = Join-Path $root 'cold_chamber_execution.json'
$launcherPath = Join-Path $root 'launcher_contract.json'
if (-not (Test-Path -LiteralPath $executionPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
    throw 'Do not retire caches of an unfinalized run.'
}
$execution = Get-Content -LiteralPath $executionPath -Raw | ConvertFrom-Json
$launcher = Get-Content -LiteralPath $launcherPath -Raw | ConvertFrom-Json
if (-not $execution.collection_pass -or $launcher.lifecycle_state -ne 'completed') {
    throw 'Require completed physical collection and a final launcher contract.'
}
$repo = Split-Path -Parent (Split-Path -Parent $root)
$running = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and $_.CommandLine -and
    $_.CommandLine.Contains($repo)
})
if ($running.Count -gt 0) { throw 'A MATLAB process still references this diagnostic checkout.' }
$receipt = [IO.Path]::GetFullPath($ReceiptPath)
if (Test-Path -LiteralPath $receipt) { throw 'Never overwrite a retirement receipt.' }
$targets = @()
$manifest = @()
foreach ($name in @('cache','codegen')) {
    $candidate = [IO.Path]::GetFullPath((Join-Path $root $name))
    if (-not $candidate.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Parent $candidate) -ne $root) { throw 'Unsafe computed cache target.' }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
    $entries = @((Get-Item -LiteralPath $candidate -Force)) +
        @(Get-ChildItem -LiteralPath $candidate -Recurse -Force)
    if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
        throw 'Do not follow reparse points during recursive retirement.'
    }
    $targets += $candidate
    foreach ($file in $entries | Where-Object { -not $_.PSIsContainer }) {
        if ($file.Name -in @('observations.mat','final_operating_point.mat','configuration.mat',
                            'runtime_evidence_contract.mat','cold_chamber_execution.json')) {
            throw 'Scientific authority file unexpectedly present in cache.'
        }
        $manifest += [ordered]@{ path=$file.FullName; bytes=$file.Length;
            sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    }
}
$bytes = 0L
foreach ($row in $manifest) { $bytes += $row.bytes }
$record = [ordered]@{
    schema='heatdrive_ecc_diagnostic_cache_retirement_v1'
    created_at=(Get-Date).ToString('o')
    experiment_root=$root
    execution_sha256=(Get-FileHash -LiteralPath $executionPath -Algorithm SHA256).Hash
    status='planned'
    retired_bytes=$bytes
    targets=$targets
    files=$manifest
    preserved=@('native','conservative','component_build','buffer_component_build',
                'runtime_evidence_contract.mat','cold_chamber_execution.json','launcher_contract.json')
    production_recovery_allowed=$false
}
New-Item -ItemType Directory -Path (Split-Path -Parent $receipt) -Force | Out-Null
$record | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $receipt -Encoding utf8
foreach ($target in $targets) { Remove-Item -LiteralPath $target -Recurse -Force }
foreach ($target in $targets) { if (Test-Path -LiteralPath $target) { throw 'Cache deletion incomplete.' } }
$record.status = 'completed'
$record | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $receipt -Encoding utf8
[ordered]@{status='completed'; retired_bytes=$bytes; receipt=$receipt} | ConvertTo-Json
