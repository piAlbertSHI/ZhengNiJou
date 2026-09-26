$ErrorActionPreference = 'Stop'

$worktree = (Resolve-Path 'C:\Users\86182\.codex\worktrees\fixed-stage4-kp237-endpoint\正逆耦合').Path
$outputRoot = (Resolve-Path (Join-Path $worktree 'gx101r1_R69_remote\outputs')).Path
$targetNames = @(
    'qian_coupled_stage4_logmean_kp50_20260926_v50b',
    'qian_coupled_stage4_logmean_kp50_ki80_20260926_v52',
    'qian_coupled_stage4_midpoint_mu_kp50_20260926_v53'
)
$retainNames = @(
    'qian_coupled_stage4_blend060_kp50_20260926_v49',
    'qian_coupled_stage4_logmean_kp50_20260926_v51'
)
$auditRoot = (Resolve-Path 'gx101r1_R69_remote\outputs_storage_audit').Path
$receiptDir = Join-Path $auditRoot 'stage4_diagnostic_retirement_20260927'
New-Item -ItemType Directory -Force -Path $receiptDir | Out-Null

$targets = foreach ($name in $targetNames) {
    $path = Join-Path $outputRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        throw "Missing target: $path"
    }
    $item = Get-Item -LiteralPath $path
    if ($item.FullName -notlike ($outputRoot + '\*') -or $item.LinkType) {
        throw "Refusing target outside the exact non-linked output root: $path"
    }
    $files = Get-ChildItem -LiteralPath $path -Recurse -File | ForEach-Object {
        [pscustomobject]@{
            path = $_.FullName
            bytes = [int64]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
        }
    }
    [pscustomobject]@{
        name = $name
        root = $item.FullName
        bytes = [int64](($files | Measure-Object bytes -Sum).Sum)
        files = $files
    }
}

$pre = [pscustomobject]@{
    schema = 'heatdrive_ecc_stage4_diagnostic_retirement_receipt_v1'
    created_utc = (Get-Date).ToUniversalTime().ToString('o')
    worktree = $worktree
    output_root = $outputRoot
    target_roots = $targets
    retained_raw_roots = $retainNames
    deletion_policy = 'Only exact non-linked directories under the named worktree outputs root; compact audits and v49/v51 raw evidence retained.'
    production_recovery_allowed = $false
}
$prePath = Join-Path $receiptDir 'pre_delete_manifest.json'
$pre | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $prePath -Encoding UTF8

foreach ($row in $targets) {
    Remove-Item -LiteralPath $row.root -Recurse -Force
}

$remainingTargets = @($targetNames | ForEach-Object {
    [pscustomobject]@{ name = $_; exists = (Test-Path -LiteralPath (Join-Path $outputRoot $_)) }
})
$remainingRetained = @($retainNames | ForEach-Object {
    [pscustomobject]@{ name = $_; exists = (Test-Path -LiteralPath (Join-Path $outputRoot $_)) }
})
if ($remainingTargets.exists -contains $true) { throw 'A retired target still exists' }
if ($remainingRetained.exists -contains $false) { throw 'A retained raw root is missing' }

$final = [pscustomobject]@{
    schema = $pre.schema
    created_utc = $pre.created_utc
    completed_utc = (Get-Date).ToUniversalTime().ToString('o')
    worktree = $worktree
    output_root = $outputRoot
    target_roots = $targets
    retained_raw_roots = $remainingRetained
    post_delete_target_check = $remainingTargets
    pre_delete_manifest = $prePath
    deleted_bytes = [int64](($targets | Measure-Object bytes -Sum).Sum)
    deleted_gib = [double]((($targets | Measure-Object bytes -Sum).Sum) / 1GB)
    production_recovery_allowed = $false
}
$finalPath = Join-Path $receiptDir 'retirement_receipt.json'
$final | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $finalPath -Encoding UTF8
$final | Select-Object schema,deleted_bytes,deleted_gib | ConvertTo-Json -Depth 3
