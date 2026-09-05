[CmdletBinding()]
param(
    [string]$ReleaseRoot = '',
    [string]$SimulationCommit = '6a5df5c456c550c4e580e382eb6d3dcdf60f658a'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $ReleaseRoot) {
    $ReleaseRoot = Join-Path $workspace 'gx101r1_R69_remote\outputs_storage_audit\runtime_c180_release_20260906'
}
$commit = (& git -C $workspace rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve source commit.' }
$simulationHash = (& git -C $workspace rev-parse --verify "$SimulationCommit^{commit}").Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve simulation source commit.' }
$dirty = @(& git -C $workspace status --porcelain)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'Commit reviewed source before making a release snapshot.' }
New-Item -ItemType Directory -Path $ReleaseRoot -Force | Out-Null
$zip = Join-Path $ReleaseRoot 'source_snapshot.zip'
$meta = Join-Path $ReleaseRoot 'source_snapshot_sha256.json'
if (Test-Path -LiteralPath $zip) {
    $prior = Get-Content -LiteralPath $meta -Raw | ConvertFrom-Json
    if ($prior.source_commit -ne $commit -or $prior.simulation_commit -ne $simulationHash -or
        $prior.sha256 -ne (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash) {
        throw 'Existing snapshot differs. Use a new ReleaseRoot; do not overwrite release evidence.'
    }
    $prior | ConvertTo-Json
    return
}
& git -C $workspace archive --format=zip "--output=$zip" HEAD
if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }
$result = [ordered]@{
    schema='heatdrive_ecc_runtime_source_snapshot_v1'
    generated_at=(Get-Date).ToString('o'); source_commit=$commit
    simulation_commit=$simulationHash
    archive_path=[IO.Path]::GetFullPath($zip); bytes=(Get-Item -LiteralPath $zip).Length
    sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    content='All Git-tracked source, models, verification and documents at source_commit.'
    raw_results_duplicated=$false
}
$result | ConvertTo-Json | Set-Content -LiteralPath $meta -Encoding utf8
$result | ConvertTo-Json
