[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionWorkspace,
      [Parameter(Mandatory=$true)][string]$RunName,
      [Parameter(Mandatory=$true)][string]$MechanismAudit,
      [Parameter(Mandatory=$true)][string]$OutputReceipt,
      [switch]$RetireInterruptedV23b)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$execution=[IO.Path]::GetFullPath($ExecutionWorkspace)
$outputs=Join-Path $execution 'gx101r1_R69_remote\outputs'
$audit=Join-Path $repo 'outputs_storage_audit'
$destination=[IO.Path]::GetFullPath($OutputReceipt)
if ($RunName -notmatch '^v[0-9]+_[a-zA-Z0-9_]+$' -or
    -not $destination.StartsWith($audit+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $destination)) { throw 'Require an exact new run and main-audit receipt.' }
$root=[IO.Path]::GetFullPath((Join-Path $outputs $RunName))
if ((Split-Path -Parent $root) -ne $outputs) { throw 'Escaped run root.' }
$completed=Get-Content -LiteralPath (Join-Path $root 'cold_chamber_execution.json') -Raw | ConvertFrom-Json
$mechanism=Get-Content -LiteralPath $MechanismAudit -Raw | ConvertFrom-Json
if (-not $completed.requested_arm_collection_pass -or $completed.error_message -ne '' -or
    $completed.production_recovery_allowed -or -not $mechanism.mechanism_pass -or
    @($mechanism.checks.PSObject.Properties).Count -ne 73 -or
    @($mechanism.checks.PSObject.Properties | Where-Object { $_.Value -ne $true }).Count -ne 0 -or
    $mechanism.source_root -ne $root -or
    $mechanism.source_observation_sha256 -ne (Get-FileHash -LiteralPath (Join-Path $root 'native\observations.mat')).Hash -or
    $mechanism.source_execution_sha256 -ne (Get-FileHash -LiteralPath (Join-Path $root 'cold_chamber_execution.json')).Hash) {
    throw 'The current raw must be complete and mechanism passing before storage closeout.'
}
function Manifest([string]$Path) {
    return @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force | Where-Object {
        $_.FullName -notmatch '\\(cache|codegen)\\'
    } | ForEach-Object {
        [pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    })
}
function Total-Bytes([object[]]$Rows,[string]$Property) {
    $total=0L;foreach ($row in $Rows) { $total+=[long]$row.$Property };return $total
}
$current=Manifest $root
$retire=@();$oldKeep=@();$old='';$resumedPlan=$false
if ($RetireInterruptedV23b) {
    $old=[IO.Path]::GetFullPath((Join-Path $outputs 'v23b_directional_cold_qualification_2c'))
    if ((Split-Path -Parent $old) -ne $outputs -or
        -not (Test-Path -LiteralPath (Join-Path $old 'INCOMPLETE_DO_NOT_RESUME.json'))) {
        throw 'Only the specifically interrupted, forbidden v23b raw may retire.'
    }
    $names=@('cold_mechanism_observation.mat','public_observations.mat',
        'diagnostic_complete_operating_point.mat','diagnostic_state_observation.mat')
    $targets=@($names | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $old ('native\'+$_))) })
    $plan=$destination+'.retirement_plan.json'
    if (Test-Path -LiteralPath $plan) {
        $planned=Get-Content -LiteralPath $plan -Raw | ConvertFrom-Json
        $retire=@($planned.retire);$oldKeep=@($planned.retain);$resumedPlan=$true
        if ($retire.Count -ne 4 -or @($retire.path | Select-Object -Unique).Count -ne 4 -or
            @($retire | Where-Object { $_.path -notin $targets -or $_.sha256 -notmatch '^[0-9A-F]{64}$' }).Count -ne 0 -or
            @($oldKeep | Where-Object { -not $_.path.StartsWith($old+'\',[StringComparison]::OrdinalIgnoreCase) }).Count -ne 0) {
            throw 'Existing plan does not describe the exact interrupted retirement.'
        }
    } else {
        foreach ($target in $targets) {
            if ((Split-Path -Parent $target) -ne (Join-Path $old 'native') -or
                -not (Test-Path -LiteralPath $target -PathType Leaf)) { throw 'Missing or escaped retirement target.' }
            $retire+=[pscustomobject]@{path=$target;bytes=(Get-Item -LiteralPath $target).Length;
                sha256=(Get-FileHash -LiteralPath $target).Hash;
                reason='Obsolete reboot-interrupted matrices; never a recovery source; newer C2/C3 and latest endpoint retained.'}
        }
        $oldKeep=@(Manifest $old | Where-Object { $_.path -notin $targets })
        [IO.File]::WriteAllText($plan,(@{retire=$retire;retain=$oldKeep}|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
    }
    foreach ($file in $retire) {
        if (-not (Test-Path -LiteralPath $file.path)) { continue }
        if ((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) { throw 'Retirement input changed.' }
        Remove-Item -LiteralPath $file.path -Force
        if (Test-Path -LiteralPath $file.path) { throw 'Retirement did not complete.' }
    }
    $marker=Join-Path $old 'SUPERSEDED_RAW_COMPACTED.txt'
    if (-not (Test-Path -LiteralPath $marker)) {
        [IO.File]::WriteAllText($marker,'Four obsolete interrupted matrices retired by the hash-bound plan. INCOMPLETE marker, logs, scalar audits, configuration and generated component sources remain. Never resume.',[Text.UTF8Encoding]::new($false))
    }
}
$caches=@()
foreach ($name in @('cache','codegen')) {
    $target=[IO.Path]::GetFullPath((Join-Path $root $name))
    if ((Split-Path -Parent $target) -ne $root -or
        $target -notin @((Join-Path $root 'cache'),(Join-Path $root 'codegen'))) { throw 'Escaped exact cache target.' }
    if (Test-Path -LiteralPath $target -PathType Container) {
        $files=@(Get-ChildItem -LiteralPath $target -File -Recurse -Force)
        $caches+=[pscustomobject]@{path=$target;bytes=(Total-Bytes $files 'Length')}
        Remove-Item -LiteralPath $target -Recurse -Force
        if (Test-Path -LiteralPath $target) { throw 'Cache deletion incomplete.' }
    }
}
foreach ($file in @($current)+@($oldKeep)) {
    if ((Get-FileHash -LiteralPath $file.path).Hash -ne $file.sha256) { throw 'Retained evidence changed.' }
}
$receipt=[ordered]@{schema='heatdrive_ecc_qualified_segment_storage_closeout_v1';
    source_root=$root;total_cycles=$completed.cycle_count;classification='mechanism_pass_latest_diagnostic_endpoint';
    production_recovery_allowed=$false;retained_current_files=$current;
    retired_obsolete_interrupted_files=$retire;retained_interrupted_summary=$oldKeep;
    retired_raw_bytes=(Total-Bytes $retire 'bytes');resumed_existing_retirement_plan=$resumedPlan;
    retired_cache_bytes=(Total-Bytes $caches 'bytes');deleted_regenerable_caches=$caches;
    current_raw_retired=$false;C2_C3_C22_dependencies_untouched=$true;
    C200_C180_untouched=$true;protected_SLX_untouched=$true;Agent6_untouched=$true;
    full_workspace_size_evaluated=$false;generated_at=(Get-Date).ToString('o')}
[IO.File]::WriteAllText($destination,($receipt|ConvertTo-Json -Depth 9)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{retired_raw_bytes=$receipt.retired_raw_bytes;retired_cache_bytes=$receipt.retired_cache_bytes;
    current_cycles=$completed.cycle_count;receipt=$destination}|ConvertTo-Json
