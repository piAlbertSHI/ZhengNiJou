[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionWorkspace,
      [Parameter(Mandatory=$true)][string]$OutputReceipt)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$execution=[IO.Path]::GetFullPath($ExecutionWorkspace)
$executionOutputs=Join-Path $execution 'gx101r1_R69_remote\outputs'
$destination=[IO.Path]::GetFullPath($OutputReceipt)
$audit=Join-Path $repo 'outputs_storage_audit'
if (-not $destination.StartsWith($audit+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $destination)) { throw 'Require a new receipt inside the main audit root.' }
$classes=@(
    @{name='v20_bounded_cold_qualification_2c';classification='C2_mechanism_pass_state_interface_candidate_only'},
    @{name='v21_bounded_complete_cycle_restore';classification='C3_flow_RMS_failed_not_a_continuation_source'}
)
$records=@();$retired=@();$bytes=0L
foreach ($row in $classes) {
    $root=[IO.Path]::GetFullPath((Join-Path $executionOutputs $row.name))
    if ((Split-Path -Parent $root) -ne $executionOutputs -or
        -not (Test-Path -LiteralPath (Join-Path $root 'cold_chamber_execution.json'))) {
        throw 'Missing or escaped diagnostic root.'
    }
    $keep=@(Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
        $_.Extension -in @('.mat','.json','.ssc','.slx','.csv','.txt') -and
        $_.FullName -notmatch '\\(cache|codegen)\\'
    })
    $manifest=@($keep | ForEach-Object {
        [pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
    foreach ($name in @('cache','codegen')) {
        $target=[IO.Path]::GetFullPath((Join-Path $root $name))
        if ((Split-Path -Parent $target) -ne $root -or
            $target -notin @((Join-Path $root 'cache'),(Join-Path $root 'codegen'))) {
            throw 'Refuse a computed recursive deletion outside the exact experiment cache.'
        }
        if (Test-Path -LiteralPath $target) {
            $files=@(Get-ChildItem -LiteralPath $target -File -Recurse -Force)
            $size=0L; foreach ($file in $files) { $size+=$file.Length }
            $retired+= [pscustomobject]@{path=$target;files=$files.Count;bytes=$size;
                reason='regenerable compiler cache only; original component source/libraries/state retained'}
            Remove-Item -LiteralPath $target -Recurse -Force
            if (Test-Path -LiteralPath $target) { throw 'Cache retirement failed.' }
            $bytes+=$size
        }
    }
    foreach ($file in $manifest) {
        if ((Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash -ne $file.sha256) {
            throw 'A retained critical result changed during cache cleanup.'
        }
    }
    $records+=[pscustomobject]@{root=$root;classification=$row.classification;
        production_recovery_allowed=$false;retained_bytes=($manifest|Measure-Object bytes -Sum).Sum;files=$manifest}
}
$copy=@(
    @('outputs_storage_audit\v20_domain_component_preflight_20261008\domain_component_preflight.json','v20_domain_component_preflight_20261008.json'),
    @('outputs\v20_bounded_cold_qualification_2c\native\cold_mechanism_audit.json','v20_cold_mechanism_audit_20261008.json'),
    @('outputs\v20_bounded_cold_qualification_2c\native\diagnostic_state_capture.json','v20_state_capture_20261008.json'),
    @('outputs\v20_bounded_cold_qualification_2c\cold_chamber_execution.json','v20_execution_20261008.json'),
    @('outputs\v21_bounded_complete_cycle_restore\native\rebuilt_cycle_restore.json','v21_rebuilt_cycle_restore_20261008.json'),
    @('outputs\v21_bounded_complete_cycle_restore\cold_chamber_execution.json','v21_execution_20261008.json')
)
$copies=@()
foreach ($pair in $copy) {
    $source=Join-Path (Join-Path $execution 'gx101r1_R69_remote') $pair[0]
    $target=Join-Path $audit $pair[1]
    if (Test-Path -LiteralPath $target) { throw 'Never overwrite an evidence copy.' }
    Copy-Item -LiteralPath $source -Destination $target
    $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash) { throw 'Copied evidence hash differs.' }
    $copies+=[pscustomobject]@{source=$source;target=$target;sha256=$hash}
}
$marker=Join-Path $executionOutputs 'v21_bounded_complete_cycle_restore\REJECTED_DO_NOT_RESUME.json'
if (Test-Path -LiteralPath $marker) { throw 'Never overwrite a diagnostic decision.' }
$decision=[ordered]@{schema='heatdrive_ecc_bounded_C3_rejection_v1';
    full_cycle_state_restore_pass=$true;mechanism_pass=$false;
    failed_checks=@('SE_settled_flow_RMS_target','SE_last_cycle_settled_flow_RMS_target');
    twenty_cycle_continuation_allowed=$false;production_recovery_allowed=$false;
    reason='Uniform pressure floor caused tracking saturation; direction-specific pressure qualification required'}
[IO.File]::WriteAllText($marker,($decision|ConvertTo-Json -Depth 5)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
$receipt=[ordered]@{schema='heatdrive_ecc_bounded_diagnostic_closeout_v1';records=$records;
    deleted_regenerable_caches=$retired;retired_bytes=$bytes;evidence_copies=$copies;
    protected_SLX_untouched=$true;Agent6_untouched=$true;C200_C180_untouched=$true;
    source_raw_retired=$false;full_workspace_size_evaluated=$false}
[IO.File]::WriteAllText($destination,($receipt|ConvertTo-Json -Depth 10)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{retired_cache_bytes=$bytes;retained_classes=$records.classification;receipt=$destination}|ConvertTo-Json
