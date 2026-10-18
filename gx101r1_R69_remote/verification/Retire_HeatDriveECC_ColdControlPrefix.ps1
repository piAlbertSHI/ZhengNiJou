param([switch]$Apply,[string]$ExpectedPlanSha256,[switch]$L8CaseOne,[switch]$L8CaseTwo)
$ErrorActionPreference='Stop'
if($L8CaseOne -and $L8CaseTwo){throw 'Select exactly one sealed factor case'}
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$archive=Join-Path $repo 'outputs_storage_audit\v67_C60_same_case_continuation_20261017\cold_prefix_retirement'
if($L8CaseOne){$archive=Join-Path $repo 'outputs_storage_audit\v68_L8case01_C60_20261017\cold_prefix_retirement'}
if($L8CaseTwo){$archive=Join-Path $repo 'outputs_storage_audit\v70_L8case02_C60_20261018\cold_prefix_retirement'}
$planPath=Join-Path $archive 'retirement_plan.json';$receiptPath=Join-Path $archive 'retirement_receipt.json'
function Read-Json([string]$Path){Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Write-Json([string]$Path,$Value){
    if(Test-Path -LiteralPath $Path){throw "Never overwrite evidence: $Path"}
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 35)+"`n",[Text.UTF8Encoding]::new($false))
}
function Check-Records($Rows){foreach($r in $Rows){if((Hash $r.path) -ne $r.sha256){throw "Changed protected input: $($r.path)"}}}
function Check-LocalPath([string]$Path,[string]$Root){
    $p=[IO.Path]::GetFullPath($Path);$base=[IO.Path]::GetFullPath($Root)
    if(-not $p.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Deletion escaped the exact cold root'}
    $ancestor=$p
    while($ancestor.Length -ge $base.Length){
        if((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse points forbidden'}
        if($ancestor -eq $base){break};$ancestor=Split-Path -Parent $ancestor
    }
    return $p
}
function Assert-NoRun {
    $pattern=if($L8CaseTwo){'v70p1|v70c1|v70case2'}elseif($L8CaseOne){'v68p[12]|v68c1|v68r2'}else{'v67p[12]|v67c1|v66_sensitivity_nominal_20261017'}
    if(Get-CimInstance Win32_Process -Filter "Name = 'MATLAB.exe'" | Where-Object {$_.CommandLine -match $pattern}){
        throw 'The exact diagnostic has a live MATLAB process'
    }
}
if(Test-Path -LiteralPath $receiptPath){throw 'Retirement already completed; do not repeat'}
Assert-NoRun
if(-not $Apply){
    if(Test-Path -LiteralPath $archive){throw 'Review the existing plan rather than regenerating it'}
    $coldPath=Join-Path $repo 'outputs_storage_audit\v66_nominal_cold_20cycle_20261017\case_closeout.json'
    $latestPath=Join-Path $repo 'outputs_storage_audit\v67_C60_same_case_continuation_20261017\continuation_closeout.json'
    $decisionPath=Join-Path $repo 'outputs_storage_audit\v67_C60_same_case_continuation_20261017\disjoint_control_windows.json'
    $coldHash='98BEC1478F7949F533B3BD707836D69668396CF650ED053A4A24A114BB8C3D05'
    $latestHash='C75450A51A90AA58C698084F88EBF05837659153973D07BCDAE2AA607F246467'
    if($L8CaseOne){
        $coldPath=Join-Path $repo 'outputs_storage_audit\v68_L8case01_C20_20261017\case_closeout.json'
        $latestPath=Join-Path $repo 'outputs_storage_audit\v68_L8case01_C60_20261017\continuation_closeout.json'
        $decisionPath=Join-Path $repo 'outputs_storage_audit\v68_L8case01_C60_20261017\disjoint_case_windows.json'
        $coldHash='9EE8AAA8794A7A29E14B8F98A3E8A01F9B227CD13C6A18040057D4952FFFD767'
        $latestHash='F4F0D244DC5192A450CAABE253C104CE38686C7477FD41A2651EE497E4E35532'
        if((Hash $decisionPath) -ne '0BC0D026D675C492371FFE084D2F7C4B6D90F3C56EAD06F70AD082BB3F4398E1'){throw 'Changed case window decision'}
    }
    if($L8CaseTwo){
        $coldPath=Join-Path $repo 'outputs_storage_audit\v70_L8case02_C20_20261018\case_closeout.json'
        $latestPath=Join-Path $repo 'outputs_storage_audit\v70_L8case02_C60_20261018\continuation_closeout.json'
        $decisionPath=Join-Path $repo 'outputs_storage_audit\v70_L8case02_C60_20261018\disjoint_case_windows.json'
        $coldHash='C9785F29C64B8DE15EC33E0B9D145651F0CF7139C32E2B9A4E9EE9756A7C53D3'
        $latestHash='BDE1CA5CF871255C1DCB86FA2E24EA022C2A31764C2C380375FD439D24D6FB01'
        if((Hash $decisionPath) -ne 'AF40ABDE7B8FA1FFF529859164290C555D5195386E2F5269CF74DA8FF0EE00E8'){throw 'Changed case two window decision'}
    }
    if((Hash $coldPath) -ne $coldHash -or (Hash $latestPath) -ne $latestHash){throw 'Changed sealed source'}
    $cold=Read-Json $coldPath;$latest=Read-Json $latestPath;$decision=Read-Json $decisionPath
    $qualified=$decision.finite_precision_nominal_control_qualified
    if($L8CaseOne){
        $qualified=$decision.finite_precision_case_response_qualified
        if($cold.case_index -ne 1 -or $latest.case_index -ne 1 -or $decision.case_index -ne 1 -or
           $cold.case_contract_sha256 -ne $latest.case_contract_sha256 -or
           $decision.case_contract_sha256 -ne $latest.case_contract_sha256){throw 'Wrong exact L8 case'}
    }
    if($L8CaseTwo){
        $qualified=$decision.finite_precision_case_response_qualified
        if($cold.case_index -ne 2 -or $latest.case_index -ne 2 -or $decision.case_index -ne 2 -or
           $cold.case_contract_sha256 -ne $latest.case_contract_sha256 -or
           $decision.case_contract_sha256 -ne $latest.case_contract_sha256){throw 'Wrong exact L8 case two'}
    }
    if(-not $qualified -or $latest.completed_cycles -ne 60 -or
       -not $latest.public_periodicity.periodic_steady_state -or -not $latest.target_precision.precision_pass){throw 'Current control not qualified'}
    $root=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $cold.source_result_path))
    $expected='C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v66_sensitivity_nominal_20261017'
    if($L8CaseOne){$expected='C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v68r2'}
    if($L8CaseTwo){$expected='C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v70case2'}
    if($root -ne $expected){throw 'Unexpected cold execution root'}
    $marker=Join-Path $root 'HISTORICAL_COLD_PREFIX_RAW_RETIRED.json'
    if(Test-Path -LiteralPath $marker){throw 'Cold prefix was already classified retired'}
    $candidates=@()
    foreach($cycle in 4,6,8,10){
        $packet=Join-Path $root ('native\sensitivity_cold_case\packet_C{0:D3}' -f $cycle)
        $manifest=Read-Json (Join-Path $packet 'packet_manifest.json');$gate=Read-Json (Join-Path $packet 'packet_gate.json')
        if(-not $gate.gate_pass -or -not $gate.original_mechanism_pass -or $manifest.window_s[1] -gt 100){throw 'Wrong historical cold packet'}
        foreach($relative in 'native/observations.mat','observed_states.mat'){
            $p=Check-LocalPath (Join-Path $packet $relative) $root
            $entry=@($manifest.input_files | Where-Object {$_.path -eq $relative})
            if($entry.Count -ne 1 -or (Hash $p) -ne $entry[0].sha256){throw 'Changed retired array'}
            $candidates+= [pscustomobject]@{path=$p;bytes=(Get-Item -LiteralPath $p).Length;sha256=$entry[0].sha256}
        }
    }
    $protected=@{}
    foreach($f in Get-ChildItem -LiteralPath $root -Recurse -File){
        if($f.FullName -notin $candidates.path){$protected[$f.FullName]=Hash $f.FullName}
    }
    foreach($p in @($coldPath,$latestPath,$decisionPath,$latest.frozen_result_path)){$protected[$p]=Hash $p}
    foreach($row in $latest.packet_chain){
        foreach($name in 'comparison_only_complete_op.mat','packet_manifest.json','packet_gate.json','boundary_comparison.json'){
            $p=Join-Path $row.packet_root $name;$protected[$p]=Hash $p
        }
    }
    $qPath=Join-Path $repo 'outputs_storage_audit\v61_runtime_Tc274p85_C108_snapshot_20261016\endpoint_qualification.json'
    $q=Read-Json $qPath;$protected[$qPath]=Hash $qPath
    $p=Join-Path $q.source_packet_root 'comparison_only_complete_op.mat';$protected[$p]=Hash $p
    $keep=@($protected.GetEnumerator() | Sort-Object Key | ForEach-Object {[pscustomobject]@{path=$_.Key;sha256=$_.Value}})
    Check-Records $keep
    if($candidates.Count -ne 8 -or @($candidates.path | Select-Object -Unique).Count -ne 8){throw 'Require exactly eight historical arrays'}
    New-Item -ItemType Directory -Path $archive | Out-Null
    $plan=[pscustomobject]@{schema='heatdrive_ecc_cold_control_prefix_retirement_v1';case_index=$cold.case_index;cold_root=$root;files=$candidates;protected_files=$keep;
        retire_bytes=($candidates | Measure-Object bytes -Sum).Sum;retained_cold_origin_window_s=@(100,200);retained_first_cold_packet=$true;
        all_complete_OPs_retained=$true;current_C60_continuation_untouched=$true;current_C108_untouched=$true;
        production_recovery_allowed=$false;full_historical_cold_raw_reverification_after_retirement=$false}
    Write-Json $planPath $plan
    [pscustomobject]@{mode='plan';files=$candidates.Count;retire_bytes=$plan.retire_bytes;protected_files=$keep.Count;plan_sha256=(Hash $planPath)} | ConvertTo-Json
    exit 0
}
if(-not $ExpectedPlanSha256 -or (Hash $planPath) -ne $ExpectedPlanSha256){throw 'Exact separately reviewed plan SHA required'}
$plan=Read-Json $planPath
if($plan.schema -ne 'heatdrive_ecc_cold_control_prefix_retirement_v1' -or $plan.files.Count -ne 8 -or -not $plan.all_complete_OPs_retained){throw 'Wrong plan'}
if($L8CaseOne -and ($plan.case_index -ne 1 -or $plan.cold_root -ne 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v68r2')){throw 'Wrong exact case root'}
if($L8CaseTwo -and ($plan.case_index -ne 2 -or $plan.cold_root -ne 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs\v70case2')){throw 'Wrong exact case two root'}
Check-Records $plan.protected_files;Check-Records $plan.files;Assert-NoRun
$allowed=@()
foreach($cycle in 4,6,8,10){foreach($relative in 'native\observations.mat','observed_states.mat'){
    $allowed+=[IO.Path]::GetFullPath((Join-Path $plan.cold_root ('native\sensitivity_cold_case\packet_C{0:D3}\{1}' -f $cycle,$relative)))
}}
foreach($row in $plan.files){$p=Check-LocalPath $row.path $plan.cold_root;if($p -notin $allowed){throw 'Target outside reviewed allowlist'}}
Write-Json (Join-Path $plan.cold_root 'HISTORICAL_COLD_PREFIX_RAW_RETIRED.json') ([pscustomobject]@{
    classification='C4_C6_C8_C10_cold_history_only_raw_retired';plan_path=$planPath;plan_sha256=(Hash $planPath);
    full_historical_raw_reverification_available=$false;C20_complete_OP_and_origin_window_retained=$true;C60_collection_untouched=$true})
foreach($row in $plan.files){Remove-Item -LiteralPath $row.path -ErrorAction Stop}
Check-Records $plan.protected_files
foreach($row in $plan.files){if(Test-Path -LiteralPath $row.path){throw 'Deletion did not complete'}}
$receipt=[pscustomobject]@{schema=$plan.schema;plan_sha256=(Hash $planPath);deleted_files=$plan.files;
    deleted_bytes=($plan.files | Measure-Object bytes -Sum).Sum;protected_files_rehashed=$plan.protected_files.Count;
    all_complete_OPs_retained=$true;current_C60_continuation_untouched=$true;current_C108_untouched=$true;recursive_delete_used=$false}
Write-Json $receiptPath $receipt
$receipt | Select-Object deleted_bytes,protected_files_rehashed,all_complete_OPs_retained,current_C60_continuation_untouched,recursive_delete_used | ConvertTo-Json
