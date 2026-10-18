param([Parameter(Mandatory=$true)][string]$Plan,[Parameter(Mandatory=$true)][string]$ExpectedPlanSha256)
$ErrorActionPreference='Stop'
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function Write-Json([string]$p,$v){
    if(Test-Path -LiteralPath $p){throw "Never overwrite evidence: $p"}
    [IO.File]::WriteAllText($p,($v | ConvertTo-Json -Depth 30)+"`n",[Text.UTF8Encoding]::new($false))
}
function Check-Records($rows){foreach($r in $rows){if((Hash $r.path) -ne $r.sha256){throw "Protected evidence changed: $($r.path)"}}}
if((Hash $Plan) -ne $ExpectedPlanSha256){throw 'Reviewed exact plan SHA required'}
$q=Get-Content -LiteralPath $Plan -Raw -Encoding utf8 | ConvertFrom-Json
$receiptPath=Join-Path (Split-Path -Parent $Plan) 'arm_retirement_receipt.json'
if($q.schema -ne 'heatdrive_ecc_obsolete_arm_relief_v1' -or $q.arms.Count -ne 10){throw 'Wrong exact batch'}
if(Test-Path -LiteralPath $receiptPath){throw 'Already retired; do not repeat'}
$e=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $Plan) 'arm_key_evidence_receipt.json') -Raw -Encoding utf8 | ConvertFrom-Json
if($e.plan_sha256 -ne $ExpectedPlanSha256 -or $e.arms.Count -ne $q.arms.Count){throw 'Wrong key evidence batch'}
$names=@('qian_coupled_stage4_settled_integrator_20260929_2cycle','qian_coupled_stage4_p_active_settled_i_20260929_2cycle',
    'qian_coupled_stage4_commutation_precharge50_20260928_10s','v9_warmup20p','v16_distributed_envelope_20c',
    'v10_distributed_ff_10s','qian_coupled_stage4_warmup20_logmean_kp50_20260927_wt',
    'qian_coupled_stage4_default_kp160_20260927_20cycle','qian_stage4_reentryblend_p024_20261004_10s_v1',
    'qian_stage4_activityramp_p024_20261005_10s_v1')
$base='C:\Users\86182\.codex\worktrees'
$allowed=@{}
for($i=0;$i -lt 10;$i++){
    $wt=if($i -lt 3){'stage4-phase-local-blend-diagnostic'}elseif($i -lt 6){'runtime-cv-json-contract'}elseif($i -eq 6){'fixed-stage4-kp237-endpoint'}elseif($i -eq 7){'stage4-default-cold-diagnostic'}else{'stage4-positive-bias-diagnostic'}
    $allowed[(Join-Path $base "$wt\正逆耦合\gx101r1_R69_remote\outputs\$($names[$i])\conservative\observations.mat").ToLowerInvariant()]=$true
}
Check-Records $q.protected_files
$processes=@(Get-CimInstance Win32_Process -Filter "Name = 'MATLAB.exe'")
foreach($a in $q.arms){
    $p=[IO.Path]::GetFullPath($a.source);$root=[IO.Path]::GetFullPath($a.root)
    if(-not $allowed.ContainsKey($p.ToLowerInvariant()) -or
       $p -ne (Join-Path $root 'conservative\observations.mat')){throw 'Outside immutable exact allowlist'}
    $ancestor=$p
    while($ancestor.Length -ge $base.Length){
        if((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point forbidden'}
        if($ancestor -eq $base){break};$ancestor=Split-Path -Parent $ancestor
    }
    if($processes | Where-Object {$_.CommandLine -like "*$([IO.Path]::GetFileName($root))*"}){throw 'Trial has a live MATLAB process'}
    if((Hash $p) -ne $a.source_sha256 -or (Hash $a.marker) -ne $a.marker_sha256){throw 'Changed rejected source'}
    $key=@($e.arms | Where-Object {$_.source_path -eq $p})
    if($key.Count -ne 1 -or -not $key[0].retained_bytes_exact -or
       $key[0].archive_path -ne $a.key_archive -or (Hash $a.key_archive) -ne $key[0].archive_sha256){throw 'Missing or changed exact key traces'}
}
$deletions=@()
foreach($a in $q.arms){
    $key=@($e.arms | Where-Object {$_.source_path -eq $a.source})[0]
    Write-Json (Join-Path $a.root 'HISTORICAL_CONSERVATIVE_RAW_RETIRED.json') ([pscustomobject]@{
        classification='obsolete_arm_raw_retired_with_native_full_and_exact_key_traces_retained';
        original_source_sha256=$a.source_sha256;plan_path=$Plan;plan_sha256=$ExpectedPlanSha256;
        key_evidence_path=$a.key_archive;key_evidence_sha256=$key.archive_sha256;
        native_full_raw_retained=$true;all_other_original_files_retained=$true;
        full_original_dual_arm_raw_reverification_available=$false;production_recovery_allowed=$false;
        numeric_samples_resampled=$false;scientific_gates_changed=$false})
    Remove-Item -LiteralPath $a.source -ErrorAction Stop
    if(Test-Path -LiteralPath $a.source){throw 'Retirement incomplete'}
    $deletions += [pscustomobject]@{path=$a.source;sha256=$a.source_sha256;bytes=$a.source_bytes;
        retained_key_evidence_bytes=$key.archive_bytes;retained_key_evidence_sha256=$key.archive_sha256}
}
Check-Records $q.protected_files
$r=[pscustomobject]@{schema=$q.schema;plan_sha256=$ExpectedPlanSha256;deletions=$deletions;
    raw_deleted_bytes=($deletions | Measure-Object bytes -Sum).Sum;
    retained_new_key_evidence_bytes=($deletions | Measure-Object retained_key_evidence_bytes -Sum).Sum;
    protected_original_files_rehashed=$q.protected_files.Count;recursive_delete_used=$false;
    active_case_and_all_OPs_untouched=$true;scientific_gates_changed=$false}
Write-Json $receiptPath $r
$r | Select-Object raw_deleted_bytes,retained_new_key_evidence_bytes,protected_original_files_rehashed,active_case_and_all_OPs_untouched | ConvertTo-Json
