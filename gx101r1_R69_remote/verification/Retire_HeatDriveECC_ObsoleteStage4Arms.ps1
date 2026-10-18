param([switch]$Apply,[string]$ExpectedPlanSha256)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$exec='C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs'
$names=@('qian_coupled_stage4_phase_local_blend_20260928_20cycle_warmup',
    'qian_coupled_stage4_single_target_contract_20260929_20cycle_progress_contract')
$expected=@('3C97A3E8A11DD9AC3C9FBF7702ABD2247837231C47E75BA3B53CB558524CB78B',
    'D96D2790B981A2C51F284B943DC379A33A625A52A906173B3BF0DB431094CBD2')
$archive=Join-Path $repo 'outputs_storage_audit\v70_obsolete_stage4_arms_20261018'
$planPath=Join-Path $archive 'retirement_plan.json'
$receiptPath=Join-Path $archive 'retirement_receipt.json'
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function Write-Json([string]$p,$value){
    if(Test-Path -LiteralPath $p){throw "Never overwrite evidence: $p"}
    [IO.File]::WriteAllText($p,($value | ConvertTo-Json -Depth 25)+"`n",[Text.UTF8Encoding]::new($false))
}
function Read-Json([string]$p){Get-Content -LiteralPath $p -Raw -Encoding utf8 | ConvertFrom-Json}
function Check-Path([string]$p,[string]$root){
    $p=[IO.Path]::GetFullPath($p);$root=[IO.Path]::GetFullPath($root)
    if(-not $p.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Target escaped exact root'}
    $a=$p
    while($a.Length -ge $root.Length){
        if((Get-Item -LiteralPath $a).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse points forbidden'}
        if($a -eq $root){break};$a=Split-Path -Parent $a
    }
}
function Check-Records($rows){foreach($r in $rows){if((Hash $r.path) -ne $r.sha256){throw "Changed file: $($r.path)"}}}
function Assert-NoRun {
    $runs=Get-CimInstance Win32_Process -Filter "Name = 'MATLAB.exe'" | Where-Object {
        $_.CommandLine -match 'phase_local_blend_20260928_20cycle_warmup|single_target_contract_20260929_20cycle_progress_contract'}
    if($runs){throw 'A selected old trial still has a live MATLAB process'}
}
if(Test-Path -LiteralPath $receiptPath){throw 'Already retired; do not repeat'}
Assert-NoRun
if(-not $Apply){
    if(Test-Path -LiteralPath $archive){throw 'Review existing plan instead of regenerating'}
    $files=@();$keep=@()
    for($i=0;$i -lt 2;$i++){
        $root=Join-Path $exec $names[$i]
        $marker=Get-Content -LiteralPath (Join-Path $root 'REJECTED_DO_NOT_RESUME.txt') -Raw
        if($marker -notmatch 'status=rejected_scientific_gate' -or
           $marker -notmatch 'production_recovery_allowed=false' -or
           $marker -notmatch 'checkpoint_saved=false'){throw 'Not an explicitly rejected no-checkpoint trial'}
        $p=Join-Path $root 'conservative\observations.mat';Check-Path $p $root
        if((Hash $p) -ne $expected[$i]){throw 'Unexpected obsolete array'}
        $files += [pscustomobject]@{path=$p;bytes=(Get-Item -LiteralPath $p).Length;sha256=$expected[$i]}
        foreach($f in Get-ChildItem -LiteralPath $root -Recurse -File){
            if($f.FullName -ne $p){$keep += [pscustomobject]@{path=$f.FullName;sha256=(Hash $f.FullName)}}
        }
    }
    foreach($dir in 'stage4_phase_local_blend_20260928_20cycle','stage4_single_target_contract_20260929_20cycle_progress_contract'){
        foreach($f in Get-ChildItem -LiteralPath (Join-Path $repo "outputs_storage_audit\$dir") -File){
            $keep += [pscustomobject]@{path=$f.FullName;sha256=(Hash $f.FullName)}
        }
    }
    New-Item -ItemType Directory -Path $archive | Out-Null
    Write-Json $planPath ([pscustomobject]@{
        schema='heatdrive_ecc_obsolete_stage4_arm_retirement_v1';files=$files;protected_files=$keep;
        retire_bytes=($files | Measure-Object bytes -Sum).Sum;
        classification='superseded_rejected_conservative_arm_raw_only';
        reason='No downstream JSON or verification-source dependency found; retain native raw and both-arm compact diagnostics.';
        arrays_claimed_identical=$false;full_historical_dual_arm_raw_reverification_available=$false;
        current_OP_or_physical_gate_changed=$false;production_recovery_allowed=$false})
    [pscustomobject]@{mode='plan';retire_bytes=($files | Measure-Object bytes -Sum).Sum;
        protected_files=$keep.Count;plan_sha256=(Hash $planPath)} | ConvertTo-Json
    exit 0
}
if(-not $ExpectedPlanSha256 -or (Hash $planPath) -ne $ExpectedPlanSha256){throw 'Separately reviewed exact plan SHA required'}
$plan=Read-Json $planPath
if($plan.schema -ne 'heatdrive_ecc_obsolete_stage4_arm_retirement_v1' -or $plan.files.Count -ne 2){throw 'Wrong retirement plan'}
Check-Records $plan.protected_files;Check-Records $plan.files;Assert-NoRun
for($i=0;$i -lt 2;$i++){
    $root=Join-Path $exec $names[$i];$p=Join-Path $root 'conservative\observations.mat'
    Check-Path $p $root
    if($plan.files[$i].path -ne $p -or $plan.files[$i].sha256 -ne $expected[$i]){throw 'Target outside immutable allowlist'}
}
foreach($name in $names){
    Write-Json (Join-Path $exec "$name\HISTORICAL_CONSERVATIVE_RAW_RETIRED.json") ([pscustomobject]@{
        classification=$plan.classification;plan_path=$planPath;plan_sha256=(Hash $planPath);
        native_raw_retained=$true;both_arm_compact_diagnostics_retained=$true;
        full_historical_dual_arm_raw_reverification_available=$false;production_recovery_allowed=$false})
}
foreach($r in $plan.files){Remove-Item -LiteralPath $r.path -ErrorAction Stop}
Check-Records $plan.protected_files
foreach($r in $plan.files){if(Test-Path -LiteralPath $r.path){throw 'Retirement incomplete'}}
$receipt=[pscustomobject]@{schema=$plan.schema;plan_sha256=(Hash $planPath);deleted_files=$plan.files;
    deleted_bytes=$plan.retire_bytes;protected_files_rehashed=$plan.protected_files.Count;
    native_raw_retained=$true;both_arm_compact_diagnostics_retained=$true;recursive_delete_used=$false;
    full_historical_dual_arm_raw_reverification_available=$false;current_OP_or_physical_gate_changed=$false}
Write-Json $receiptPath $receipt
$receipt | Select-Object deleted_bytes,protected_files_rehashed,native_raw_retained,recursive_delete_used | ConvertTo-Json
