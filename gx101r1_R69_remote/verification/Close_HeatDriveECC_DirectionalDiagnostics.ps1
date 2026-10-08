[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionWorkspace,
      [Parameter(Mandatory=$true)][string]$OutputReceipt)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$execution=[IO.Path]::GetFullPath($ExecutionWorkspace)
$executionRepo=Join-Path $execution 'gx101r1_R69_remote'
$outputs=Join-Path $executionRepo 'outputs'
$audit=Join-Path $repo 'outputs_storage_audit'
$destination=[IO.Path]::GetFullPath($OutputReceipt)
if (-not $destination.StartsWith($audit+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $destination)) { throw 'Require a new main-audit receipt.' }
$classes=@(
    @{name='v22c_directional_pressure_static';class='static_configuration_interface_failure'},
    @{name='v22d_directional_pressure_static';class='passed_static_directional_contract'},
    @{name='v23b_directional_cold_qualification_2c';class='user_reboot_interrupted_collection_not_resume_source'},
    @{name='v24_directional_directlog_cold_2c';class='qualified_C2_intact_diagnostic_recovery_dependency'},
    @{name='v25_directional_directlog_full_cycle_restore';class='qualified_C3_exact_complete_cycle_proof_dependency'},
    @{name='v26_directional_directlog_resume_20c';class='completed_C22_mechanism_pass_unsteady_diagnostic_candidate'}
)
$records=@();$retired=@();$bytes=0L
foreach ($row in $classes) {
    $root=[IO.Path]::GetFullPath((Join-Path $outputs $row.name))
    if ((Split-Path -Parent $root) -ne $outputs -or -not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "Missing or escaped exact experiment: $root"
    }
    $keep=@(Get-ChildItem -LiteralPath $root -File -Recurse -Force |
        Where-Object { $_.FullName -notmatch '\\(cache|codegen)\\' })
    $manifest=@($keep | ForEach-Object {
        [pscustomobject]@{path=$_.FullName;bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
    foreach ($name in @('cache','codegen')) {
        $target=[IO.Path]::GetFullPath((Join-Path $root $name))
        if ((Split-Path -Parent $target) -ne $root -or
            $target -notin @((Join-Path $root 'cache'),(Join-Path $root 'codegen'))) {
            throw 'Refuse recursive deletion outside an exact experiment cache.'
        }
        if (Test-Path -LiteralPath $target -PathType Container) {
            $files=@(Get-ChildItem -LiteralPath $target -File -Recurse -Force)
            $size=0L;foreach ($file in $files) { $size+=$file.Length }
            $retired+=[pscustomobject]@{path=$target;files=$files.Count;bytes=$size;
                reason='Regenerable compiler cache only; numerical evidence, libraries and OP remain.'}
            Remove-Item -LiteralPath $target -Recurse -Force
            if (Test-Path -LiteralPath $target) { throw 'Cache retirement failed.' }
            $bytes+=$size
        }
    }
    foreach ($file in $manifest) {
        if ((Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash -ne $file.sha256) {
            throw 'Retained critical evidence changed during cleanup.'
        }
    }
    $records+=[pscustomobject]@{root=$root;classification=$row.class;
        production_recovery_allowed=$false;retained_bytes=($manifest|Measure-Object bytes -Sum).Sum;files=$manifest}
}
$pairs=@(
    @('outputs\v24_directional_directlog_cold_2c\cold_chamber_execution.json','v24_directional_execution_20261008.json'),
    @('outputs\v24_directional_directlog_cold_2c\native\cold_mechanism_audit.json','v24_directional_C2_mechanism_20261008.json'),
    @('outputs\v24_directional_directlog_cold_2c\native\postprocessing_profile.json','v24_directional_postprocessing_profile_20261008.json'),
    @('outputs\v25_directional_directlog_full_cycle_restore\native\rebuilt_cycle_restore.json','v25_directional_C3_restore_20261008.json'),
    @('outputs\v25_directional_directlog_full_cycle_restore\rebuilt_local_ledger_audit.json','v25_directional_C3_local_ledger_20261008.json'),
    @('outputs\v26_directional_directlog_resume_20c\cold_chamber_execution.json','v26_directional_execution_20261008.json'),
    @('outputs\v26_directional_directlog_resume_20c\native\diagnostic_state_capture.json','v26_directional_C22_state_capture_20261008.json'),
    @('outputs_storage_audit\v26_directional_C22_saved_mechanism\saved_mechanism_audit.json','v26_directional_C22_full_mechanism_20261008.json')
)
$copies=@()
foreach ($pair in $pairs) {
    $source=Join-Path $executionRepo $pair[0];$target=Join-Path $audit $pair[1]
    if (Test-Path -LiteralPath $target) { throw 'Never overwrite evidence copies.' }
    Copy-Item -LiteralPath $source -Destination $target
    $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash) { throw 'Evidence copy mismatch.' }
    $copies+=[pscustomobject]@{source=$source;target=$target;sha256=$hash}
}
$receipt=[ordered]@{schema='heatdrive_ecc_directional_diagnostic_closeout_v1';
    generated_at=(Get-Date).ToString('o');records=$records;evidence_copies=$copies;
    retired_cache_bytes=$bytes;deleted_regenerable_caches=$retired;source_raw_retired=$false;
    user_reboot_followup=@{source='human statement in this chat';
        affected_run='v23b_directional_cold_qualification_2c';
        interpretation='User reports reboot caused termination; prior unknown-cause receipt is preserved.'};
    scope='Six exact execution-worktree experiments only; not the full workspace or Agent6.';
    protected_SLX_untouched=$true;Agent6_untouched=$true;C200_C180_untouched=$true}
[IO.File]::WriteAllText($destination,($receipt|ConvertTo-Json -Depth 10)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{retired_cache_bytes=$bytes;retained_classes=$records.classification;
    retained_bytes=($records|Measure-Object retained_bytes -Sum).Sum;receipt=$destination}|ConvertTo-Json
