[CmdletBinding(SupportsShouldProcess)]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workspace = [IO.Path]::GetFullPath((Split-Path -Parent $repo))
$tmp = [IO.Path]::GetFullPath((Join-Path $workspace 'tmp'))
$auditRoot = Join-Path $repo 'outputs_storage_audit\failed_cold_seed_retirement_20260916'
$activeV4 = Join-Path $tmp 'cold_chamber_control_volume_seed_20260916_v4'

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Get-ContainedPath([string]$Base, [string]$RelativePath) {
    $baseFull = [IO.Path]::GetFullPath($Base)
    $absolute = [IO.Path]::GetFullPath((Join-Path $baseFull $RelativePath))
    Require $absolute.StartsWith($baseFull + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase) "Path escaped base directory: $absolute"
    return $absolute
}

function Get-RelativePath([string]$Base, [string]$Path) {
    $baseFull = [IO.Path]::GetFullPath($Base).TrimEnd('\') + '\'
    $pathFull = [IO.Path]::GetFullPath($Path)
    $baseUri = [Uri]$baseFull
    $pathUri = [Uri]$pathFull
    return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

function Get-FileRecords([string]$Root) {
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File | ForEach-Object {
        [pscustomobject]@{
            relative_path = Get-RelativePath $Root $_.FullName
            bytes = [int64]$_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
}

function Assert-RejectedExecution([string]$ExecutionPath, [int]$ExpectedCompletedArms) {
    Require (Test-Path -LiteralPath $ExecutionPath -PathType Leaf) "Missing execution contract: $ExecutionPath"
    $record = Get-Content -LiteralPath $ExecutionPath -Raw | ConvertFrom-Json
    Require (-not [bool]$record.collection_pass) "Execution unexpectedly passed: $ExecutionPath"
    Require (-not [bool]$record.production_recovery_allowed) "Execution permits recovery: $ExecutionPath"
    Require (-not [bool]$record.periodic_steady_state) "Execution claims periodic state: $ExecutionPath"
    Require (-not [bool]$record.full_device_first_law_verified) "Execution claims first-law closure: $ExecutionPath"
    Require (-not [bool]$record.checkpoint_saved) "Execution saved a checkpoint: $ExecutionPath"
    Require (@($record.cases).Count -eq $ExpectedCompletedArms) "Unexpected completed-arm count: $ExecutionPath"
    return $record
}

function Copy-PreservedFiles([string]$SourceRoot, [string]$DestinationRoot) {
    $files = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -Force -File | Where-Object {
        $_.Name -ne 'observations.mat' -and
        $_.FullName -notmatch '(?i)[\\/](cache|codegen|component_build|buffer_component_build)[\\/]'
    })
    foreach ($file in $files) {
        $relative = Get-RelativePath $SourceRoot $file.FullName
        $destination = Get-ContainedPath $DestinationRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        Require ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq
            (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) "Archive copy mismatch: $relative"
    }
    return @($files | ForEach-Object { Get-RelativePath $SourceRoot $_.FullName })
}

function Test-AuthorityFile([pscustomobject]$Contract, [string]$PathProperty, [string]$HashProperty) {
    $path = [IO.Path]::GetFullPath((Join-Path $repo ([string]$Contract.$PathProperty)))
    Require (Test-Path -LiteralPath $path -PathType Leaf) "Missing authority file: $path"
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Require ($actual -eq [string]$Contract.$HashProperty) "Authority hash mismatch: $path"
    return [pscustomobject]@{ path = Get-RelativePath $workspace $path; sha256 = $actual }
}

$c200 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'c200_mainline_freeze_contract.json') -Raw | ConvertFrom-Json
$c180 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime_c180_recovery_contract.json') -Raw | ConvertFrom-Json
$authority = @(
    Test-AuthorityFile $c200 'result_relative_path' 'result_sha256'
    Test-AuthorityFile $c200 'checkpoint_relative_path' 'checkpoint_sha256'
    Test-AuthorityFile $c180 'result_relative_path' 'result_sha256'
    Test-AuthorityFile $c180 'checkpoint_relative_path' 'checkpoint_sha256'
)

Require (Test-Path -LiteralPath $activeV4 -PathType Container) "Active v4 package is missing: $activeV4"
$v4ExecutionPath = Join-Path $activeV4 'cold_chamber_execution.json'
$v4 = Get-Content -LiteralPath $v4ExecutionPath -Raw | ConvertFrom-Json
Require ([bool]$v4.collection_pass -and @($v4.cases).Count -eq 2) 'Active v4 package is not the completed dual-arm diagnostic.'
Require (-not [bool]$v4.production_recovery_allowed -and -not [bool]$v4.checkpoint_saved) 'Active v4 package crossed its diagnostic boundary.'
$activeRecord = [ordered]@{
    relative_path = Get-RelativePath $workspace $activeV4
    action = 'keep_full_raw_pending_strict_audit'
    execution_sha256 = (Get-FileHash -LiteralPath $v4ExecutionPath -Algorithm SHA256).Hash
    observation_sha256 = @($v4.cases | ForEach-Object { $_.observation_sha256 })
}

$packageSpecs = @(
    [pscustomobject]@{
        id = 'missing_compiled_inventory_prerequisite'
        root = Get-ContainedPath $tmp 'cold_chamber_control_volume_seed_20260916'
        execution = 'cold_chamber_execution.json'
        expected_arms = 0
        reason = 'failed before simulation because the isolated worktree lacked the compiled inventory audit'
    },
    [pscustomobject]@{
        id = 'missing_initial_flux_prerequisite_after_native'
        root = Get-ContainedPath $tmp 'cold_chamber_control_volume_seed_20260916_v3'
        execution = 'cold_chamber_execution.json'
        expected_arms = 1
        reason = 'native arm completed but conservative initialization failed before a valid dual-arm package existed'
    },
    [pscustomobject]@{
        id = 'missing_c200_authority_first_attempt'
        root = Get-ContainedPath $tmp 'c200_c201_worktree_v2\gx101r1_R69_remote\outputs_failed_first_attempt_20260916\qian_cold_chamber_control_volume_seed_20260916'
        execution = 'cold_chamber_execution.json'
        expected_arms = 0
        reason = 'first isolated attempt lacked the required frozen C200 authority files'
    }
)

$packages = [Collections.Generic.List[object]]::new()
foreach ($spec in $packageSpecs) {
    Require (Test-Path -LiteralPath $spec.root -PathType Container) "Missing rejected package: $($spec.root)"
    $execution = Assert-RejectedExecution (Join-Path $spec.root $spec.execution) $spec.expected_arms
    $checkpoints = @(Get-ChildItem -LiteralPath $spec.root -Recurse -Force -File | Where-Object {
        $_.Name -in @('final_operating_point.mat','operating_point.mat','checkpoint.mat')
    })
    Require ($checkpoints.Count -eq 0) "Rejected package contains a checkpoint: $($spec.root)"
    $records = Get-FileRecords $spec.root
    $packages.Add([pscustomobject]@{
        id = $spec.id
        relative_path = Get-RelativePath $workspace $spec.root
        bytes = [int64](($records | Measure-Object bytes -Sum).Sum)
        file_count = $records.Count
        completed_arms = @($execution.cases).Count
        reason = $spec.reason
        files = $records
        production_recovery_allowed = $false
    })
}

$cacheTargets = @(
    Get-ContainedPath $tmp 'slprj'
    Get-ContainedPath $tmp 'heatdrive_ecc_coupled_se21.slxc'
)
$cacheRecords = @($cacheTargets | ForEach-Object {
    Require (Test-Path -LiteralPath $_) "Missing disposable cache target: $_"
    $item = Get-Item -LiteralPath $_ -Force
    $bytes = if ($item.PSIsContainer) {
        [int64]((Get-ChildItem -LiteralPath $_ -Recurse -Force -File | Measure-Object Length -Sum).Sum)
    } else { [int64]$item.Length }
    [pscustomobject]@{ relative_path = Get-RelativePath $workspace $_; bytes = $bytes; reason = 'regenerable Simulink cache' }
})

$failedMount = Get-ContainedPath $tmp 'c200_c201_worktree_v2\gx101r1_R69_remote\outputs_storage_audit_mount_failed_20260916'
Require (Test-Path -LiteralPath $failedMount -PathType Container) "Missing failed audit mount: $failedMount"
$mountItem = Get-Item -LiteralPath $failedMount -Force
Require (($mountItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'Failed audit mount is not a reparse point.'
$expectedMountTarget = [IO.Path]::GetFullPath((Join-Path $repo 'outputs_storage_audit'))
Require ([IO.Path]::GetFullPath([string]$mountItem.Target) -eq $expectedMountTarget) 'Failed audit mount targets an unexpected directory.'

$processRefs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $command = [string]$_.CommandLine
    $command -and ($packageSpecs | Where-Object { $command -match [regex]::Escape([string]$_.root) })
})
Require (-not $Apply -or $processRefs.Count -eq 0) 'A running process references a rejected package.'

New-Item -ItemType Directory -Path $auditRoot -Force | Out-Null
$planPath = Join-Path $auditRoot 'retirement_plan.json'
$plan = [ordered]@{
    schema = 'heatdrive_ecc_failed_cold_seed_retirement_plan_v1'
    generated_at = (Get-Date).ToString('o')
    apply = [bool]$Apply
    authority_hashes = $authority
    protected_active_package = $activeRecord
    rejected_packages = @($packages)
    cache_targets = $cacheRecords
    failed_mount = [ordered]@{ relative_path = Get-RelativePath $workspace $failedMount; target = $expectedMountTarget }
    production_recovery_allowed = $false
}
$plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $planPath -Encoding utf8

$deleted = [Collections.Generic.List[object]]::new()
if ($Apply) {
    $archiveRoot = Join-Path $auditRoot 'preserved_metadata'
    foreach ($spec in $packageSpecs) {
        $destination = Join-Path $archiveRoot $spec.id
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        $preserved = Copy-PreservedFiles $spec.root $destination
        $package = @($packages | Where-Object { $_.id -eq $spec.id })[0]
        if ($PSCmdlet.ShouldProcess($spec.root, 'Remove rejected cold-seed attempt after metadata archive')) {
            Remove-Item -LiteralPath $spec.root -Recurse -Force
            Require (-not (Test-Path -LiteralPath $spec.root)) "Deletion failed: $($spec.root)"
            $deleted.Add([pscustomobject]@{
                id = $spec.id
                relative_path = $package.relative_path
                bytes = $package.bytes
                preserved_files = $preserved
            })
        }
    }
    $emptyFirstAttempt = Get-ContainedPath $tmp 'c200_c201_worktree_v2\gx101r1_R69_remote\outputs_failed_first_attempt_20260916'
    if (Test-Path -LiteralPath $emptyFirstAttempt -PathType Container) {
        Remove-Item -LiteralPath $emptyFirstAttempt -Recurse -Force
    }
    foreach ($cache in $cacheTargets) {
        if ($PSCmdlet.ShouldProcess($cache, 'Remove regenerable Simulink cache')) {
            Remove-Item -LiteralPath $cache -Recurse -Force
            Require (-not (Test-Path -LiteralPath $cache)) "Cache deletion failed: $cache"
        }
    }
    if ($PSCmdlet.ShouldProcess($failedMount, 'Remove obsolete audit junction only')) {
        Remove-Item -LiteralPath $failedMount -Force
        Require (-not (Test-Path -LiteralPath $failedMount)) "Junction removal failed: $failedMount"
        Require (Test-Path -LiteralPath $expectedMountTarget -PathType Container) 'Junction target was damaged.'
    }
    foreach ($entry in $authority) {
        $path = [IO.Path]::GetFullPath((Join-Path $workspace $entry.path))
        Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $entry.sha256) "Authority changed during cleanup: $path"
    }
}

$receipt = [ordered]@{
    schema = 'heatdrive_ecc_failed_cold_seed_retirement_receipt_v1'
    completed_at = (Get-Date).ToString('o')
    applied = [bool]$Apply
    plan_path = $planPath
    protected_active_package = $activeRecord
    rejected_packages = @($packages)
    deleted_packages = @($deleted)
    deleted_package_bytes = [int64]$(if ($deleted.Count -gt 0) { ($deleted | Measure-Object bytes -Sum).Sum } else { 0 })
    deleted_cache_bytes = [int64]$(if ($Apply) { ($cacheRecords | Measure-Object bytes -Sum).Sum } else { 0 })
    removed_failed_mount = [bool]$Apply
    authority_hashes_pass = $true
    production_recovery_allowed = $false
}
$receiptPath = Join-Path $auditRoot 'retirement_receipt.json'
$receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding utf8
$receipt | ConvertTo-Json -Depth 12
