[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Apply,
    [string]$ExpectedPlanSha256 = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $repo))
$auditRoot = Join-Path $repo 'outputs_storage_audit\intermediate_packet_retirement_20261023'
$planPath = Join-Path $auditRoot 'retirement_plan.json'
$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-RelativePath([string]$Base, [string]$Path) {
    $baseUri = [Uri](([IO.Path]::GetFullPath($Base).TrimEnd('\')) + '\')
    $pathUri = [Uri][IO.Path]::GetFullPath($Path)
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

function Get-Files([string]$Root) {
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Where-Object {
        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0
    })
}

function Get-Record([string]$Path, [string]$Role) {
    $files = @(Get-Files $Path)
    Require ($files.Count -gt 0) "Empty packet target: $Path"
    $bytes = [int64](($files | Measure-Object -Property Length -Sum).Sum)
    $manifest = $files | Where-Object { $_.Name -eq 'packet_manifest.json' } | Select-Object -First 1
    $gate = $files | Where-Object { $_.Name -eq 'packet_gate.json' } | Select-Object -First 1
    [pscustomobject]@{
        role = $Role
        path = Get-RelativePath $workspace $Path
        bytes = $bytes
        file_count = $files.Count
        files = @($files | ForEach-Object {
            [ordered]@{
                relative_path = Get-RelativePath $workspace $_.FullName
                bytes = [int64]$_.Length
                sha256 = if ($_.Length -le 10MB) { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } else { $null }
            }
        })
        packet_manifest_sha256 = if ($manifest) { (Get-FileHash -LiteralPath $manifest.FullName -Algorithm SHA256).Hash } else { $null }
        packet_gate_sha256 = if ($gate) { (Get-FileHash -LiteralPath $gate.FullName -Algorithm SHA256).Hash } else { $null }
    }
}

function Assert-Root([string]$Root, [string[]]$KeepPackets) {
    Require (Test-Path -LiteralPath $Root -PathType Container) "Missing collection root: $Root"
    foreach ($name in $KeepPackets) {
        $path = Join-Path $Root $name
        Require (Test-Path -LiteralPath $path -PathType Container) "Missing protected packet: $path"
        Require (((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "Protected packet is a reparse point: $path"
        $manifest = Join-Path $path 'packet_manifest.json'
        Require (Test-Path -LiteralPath $manifest -PathType Leaf) "Protected packet has no manifest: $path"
    }
}

$collections = @(
    [pscustomobject]@{
        id = 'completed_case01_v67c1'
        root = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v67c1'
        keep = @('packet_C060_attempt01')
    },
    [pscustomobject]@{
        id = 'completed_case01_v68c1'
        root = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v68c1'
        keep = @('packet_C060_attempt01')
    },
    [pscustomobject]@{
        id = 'completed_case02_v70c1'
        root = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v70c1'
        keep = @('packet_C060_attempt01')
    },
    [pscustomobject]@{
        id = 'paused_case03_v71c1'
        root = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v71c1'
        keep = @('packet_C050_attempt01')
    }
)

foreach ($collection in $collections) { Assert-Root $collection.root $collection.keep }

$processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$'
})
Require (-not $Apply -or $processes.Count -eq 0) 'MATLAB is running; intermediate packet retirement is disabled.'

$keep = @()
$targets = @()
foreach ($collection in $collections) {
    foreach ($packet in $collection.keep) {
        $keep += Get-Record (Join-Path $collection.root $packet) "protected_$($collection.id)_$packet"
    }
    $packetDirs = @(Get-ChildItem -LiteralPath $collection.root -Directory -Force | Where-Object {
        $_.Name -match '^packet_C\d+_attempt\d+$'
    })
    foreach ($packetDir in $packetDirs) {
        if ($collection.keep -notcontains $packetDir.Name) {
            $targets += Get-Record $packetDir.FullName "retire_intermediate_$($collection.id)_$($packetDir.Name)"
        }
    }
}

Require ($targets.Count -gt 0) 'No intermediate packet targets found; refuse a no-op apply.'
$plan = [ordered]@{
    schema = 'heatdrive_ecc_intermediate_packet_retirement_v1'
    generated_at_utc = [DateTime]::UtcNow.ToString('o')
    apply = [bool]$Apply
    reason = 'Retain root contracts, final accepted packet, current accepted C50 packet and cold-start evidence; retire earlier regenerable packet payloads.'
    collections = @($collections | ForEach-Object { [ordered]@{ id=$_.id; root=(Get-RelativePath $workspace $_.root); keep=@($_.keep) } })
    protected_packets = $keep
    retired_packets = $targets
    protected_pause_contract = 'gx101r1_R69_remote/verification/current_runtime_user_pause.json'
    protected_cold_case_contract = 'gx101r1_R69_remote/verification/current_runtime_L8_case03.json'
    scientific_gates_changed = $false
    production_recovery_claim = $false
}

if (Test-Path -LiteralPath $planPath) {
    Require (-not [string]::IsNullOrWhiteSpace($ExpectedPlanSha256)) "Existing plan requires an exact expected SHA: $planPath"
    $actual = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
    Require ($actual -eq $ExpectedPlanSha256) "Plan SHA mismatch: $actual"
} else {
    New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
    $plan | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $planPath -Encoding utf8
    if ($ExpectedPlanSha256) {
        $actual = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
        Require ($actual -eq $ExpectedPlanSha256) "Plan SHA mismatch: $actual"
    }
}

$deleted = @()
if ($Apply) {
    foreach ($target in $targets) {
        $absolute = [IO.Path]::GetFullPath((Join-Path $workspace $target.path))
        Require (Test-Path -LiteralPath $absolute -PathType Container) "Target disappeared: $absolute"
        Require (((Get-Item -LiteralPath $absolute).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "Target became a reparse point: $absolute"
        if ($PSCmdlet.ShouldProcess($absolute, 'Remove retired intermediate packet')) {
            Remove-Item -LiteralPath $absolute -Recurse -Force
        }
        Require (-not (Test-Path -LiteralPath $absolute)) "Deletion failed: $absolute"
        $deleted += $target
    }
    foreach ($protected in $keep) {
        $absolute = [IO.Path]::GetFullPath((Join-Path $workspace $protected.path))
        Require (Test-Path -LiteralPath $absolute -PathType Container) "Protected packet missing after cleanup: $absolute"
        Require ((Get-FileHash -LiteralPath (Join-Path $absolute 'packet_manifest.json') -Algorithm SHA256).Hash -eq $protected.packet_manifest_sha256) "Protected manifest changed: $absolute"
    }
    $receipt = [ordered]@{
        schema = 'heatdrive_ecc_intermediate_packet_retirement_receipt_v1'
        completed_at_utc = [DateTime]::UtcNow.ToString('o')
        plan_sha256 = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
        deleted_packets = $deleted
        deleted_bytes = [int64](($deleted | Measure-Object -Property bytes -Sum).Sum)
        protected_packets_rehashed = $keep.Count
        scientific_gates_changed = $false
        production_recovery_claim = $false
    }
    $receipt | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $receiptPath -Encoding utf8
}

[ordered]@{
    plan_path = $planPath
    plan_sha256 = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
    apply = [bool]$Apply
    protected_packet_count = $keep.Count
    retired_packet_count = $targets.Count
    retired_bytes = [int64](($targets | Measure-Object -Property bytes -Sum).Sum)
    deleted_packet_count = $deleted.Count
    deleted_bytes = [int64](($deleted | Measure-Object -Property bytes -Sum).Sum)
    scientific_gates_changed = $false
} | ConvertTo-Json -Depth 5
