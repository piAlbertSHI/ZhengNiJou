param([switch]$Apply,[string]$ExpectedPlanSha256)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$archive=Join-Path $repo 'outputs_storage_audit\v65_Tc273p85_phase_rejection_20261017\middle_raw_retirement'
$planPath=Join-Path $archive 'retirement_plan.json'
$receiptPath=Join-Path $archive 'retirement_receipt.json'
function Read-Json([string]$Path){Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Write-Json([string]$Path,$Value){
    if(Test-Path -LiteralPath $Path){throw "Never overwrite evidence: $Path"}
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 30)+"`n",[Text.UTF8Encoding]::new($false))
}
function File-Record([string]$Path){
    $item=Get-Item -LiteralPath $Path
    if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked evidence is not allowed'}
    [pscustomobject]@{path=$item.FullName;bytes=$item.Length;sha256=(Hash $item.FullName)}
}
function Check-Records($Rows){
    foreach($row in $Rows){
        if((Hash $row.path) -ne $row.sha256){throw "Changed protected/planned file: $($row.path)"}
    }
}
if(Test-Path -LiteralPath $receiptPath){throw 'Retirement already completed; do not blindly repeat'}
if(-not $Apply){
    if(Test-Path -LiteralPath $archive){throw 'Use the existing plan only after reviewing it'}
    $qPath=Join-Path $repo 'outputs_storage_audit\v61_runtime_Tc274p85_C108_snapshot_20261016\endpoint_qualification.json'
    if((Hash $qPath) -ne '72227BFA412079E695B98BD1F87CC6F5EE04F196E5EDD62413533873E7609525'){throw 'Changed C108 source'}
    $q=Read-Json $qPath
    $exec=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $q.source_packet_root))
    $expected='C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote'
    if($exec -ne $expected){throw 'Unexpected execution repository'}
    $budgetPath=Join-Path $repo 'outputs_storage_audit\v65_Tc273p85_phase_rejection_20261017\common_source_drive_budget.json'
    if((Hash $budgetPath) -ne 'C33B3909D5314C509DD383D8F80D56AA8E314979ABA9929B4FC7A9E576FFBEEF'){throw 'Changed matched-time evidence'}
    $budget=Read-Json $budgetPath
    if($budget.root_interpolation_allowed -or $budget.failed_OP_propagation_allowed){throw 'Unexpected scientific authority'}
    $protected=@{}; $candidates=@(); $collections=@()
    foreach($row in @($q.files)+@($budget.files)){$protected[$row.path]=$row.sha256}
    $protected[$qPath]=Hash $qPath; $protected[$budgetPath]=Hash $budgetPath
    foreach($name in @('v64c1','v65c1')){
        $root=(Resolve-Path -LiteralPath (Join-Path $exec "outputs\$name")).Path
        $resultPath=Join-Path $root 'collection_result.json';$result=Read-Json $resultPath
        if($result.pass -or -not $result.error_message -or -not (Test-Path -LiteralPath (Join-Path $result.current_attempt_root 'REJECTED_DO_NOT_RESUME.json'))){throw 'Only terminal explicitly rejected branches may retire middle raw'}
        if(Get-CimInstance Win32_Process -Filter "Name = 'MATLAB.exe'" | Where-Object {$_.CommandLine -like "*$name*"}){throw 'A candidate process is still alive'}
        $protected[$resultPath]=Hash $resultPath
        $collections+= [pscustomobject]@{root=$root;collection_result_sha256=(Hash $resultPath);last_verified_snapshot_s=$result.last_verified_snapshot_time_s;failed_attempt_root=$result.current_attempt_root}
        $retained=@('packet_C110_attempt01')
        if($name -eq 'v64c1'){$retained+=@('packet_C116_attempt01','packet_C118_attempt01')}
        else{$retained+=@('packet_C116_attempt01','packet_C118_attempt01','packet_C120_attempt01','packet_C122_attempt01','packet_C124_attempt01','packet_C126_attempt01')}
        foreach($packet in $retained){
            foreach($relative in @('native\observations.mat','observed_states.mat')){
                $p=Join-Path $root "$packet\$relative";$protected[$p]=Hash $p
            }
        }
        foreach($row in $result.completed_packets){$p=Join-Path $row.packet_root 'comparison_only_complete_op.mat';$protected[$p]=Hash $p}
        $p=Join-Path $result.current_attempt_root 'comparison_only_complete_op.mat';$protected[$p]=Hash $p
        foreach($packet in @('packet_C112_attempt01','packet_C114_attempt01')){
            $folder=Join-Path $root $packet;$gate=Read-Json (Join-Path $folder 'packet_gate.json')
            if(-not $gate.gate_pass -or -not $gate.original_mechanism_pass){throw 'Middle packet was not originally gate-verified'}
            foreach($relative in @('native\observations.mat','observed_states.mat')){
                $p=(Resolve-Path -LiteralPath (Join-Path $folder $relative)).Path
                if(-not $p.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or $protected.ContainsKey($p)){throw 'Escaped or protected deletion target'}
                $ancestor=Split-Path -Parent $p
                while($ancestor.Length -ge $root.Length){
                    if((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse ancestor is forbidden'}
                    if($ancestor -eq $root){break};$ancestor=Split-Path -Parent $ancestor
                }
                $candidates+=File-Record $p
            }
        }
    }
    $keep=@($protected.GetEnumerator() | Sort-Object Key | ForEach-Object {[pscustomobject]@{path=$_.Key;sha256=$_.Value}})
    Check-Records $keep
    if($candidates.Count -ne 8){throw 'Expected exactly eight explicitly named historical arrays'}
    New-Item -ItemType Directory -Path $archive | Out-Null
    $plan=[pscustomobject]@{schema='heatdrive_ecc_rejected_middle_raw_retirement_v1';collections=$collections;files=$candidates;protected_files=$keep;retire_bytes=($candidates | Measure-Object bytes -Sum).Sum;complete_OPs_retired=0;retained_current_C108_source=$true;retained_current_window_and_matched_first_last_packets=$true;failed_state_propagation_allowed=$false}
    Write-Json $planPath $plan
    [pscustomobject]@{mode='plan';files=$candidates.Count;retire_bytes=$plan.retire_bytes;protected_files=$keep.Count;plan_sha256=(Hash $planPath)} | ConvertTo-Json
    exit 0
}
$plan=Read-Json $planPath
if(-not $ExpectedPlanSha256 -or (Hash $planPath) -ne $ExpectedPlanSha256){throw 'Apply requires the separately reviewed exact plan SHA-256'}
if($plan.schema -ne 'heatdrive_ecc_rejected_middle_raw_retirement_v1' -or $plan.files.Count -ne 8 -or $plan.failed_state_propagation_allowed){throw 'Wrong retirement plan'}
Check-Records $plan.protected_files;Check-Records $plan.files
foreach($collection in $plan.collections){
    $name=Split-Path -Leaf $collection.root
    if(Get-CimInstance Win32_Process -Filter "Name = 'MATLAB.exe'" | Where-Object {$_.CommandLine -like "*$name*"}){throw 'A collection process appeared after plan creation'}
    if((Hash (Join-Path $collection.root 'collection_result.json')) -ne $collection.collection_result_sha256){throw 'Collection changed after plan'}
    Write-Json (Join-Path $collection.root 'HISTORICAL_RAW_RETIRED.json') ([pscustomobject]@{classification='terminal_rejected_branch_middle_raw_retired';plan_path=$planPath;plan_sha256=(Hash $planPath);inplace_resume_allowed=$false;failed_state_propagation_allowed=$false;full_historical_raw_reverification_available=$false})
}
foreach($row in $plan.files){
    $p=(Resolve-Path -LiteralPath $row.path).Path
    $allowed=$false;$allowedRoot=''
    foreach($collection in $plan.collections){
        foreach($packet in @('packet_C112_attempt01','packet_C114_attempt01')){
            foreach($relative in @('native\observations.mat','observed_states.mat')){
                if($p -eq (Join-Path $collection.root "$packet\$relative")){$allowed=$true;$allowedRoot=$collection.root}
            }
        }
    }
    if(-not $allowed -or (Get-Item -LiteralPath $p).Length -ne $row.bytes -or (Hash $p) -ne $row.sha256){throw 'Unverified exact removal target'}
    $ancestor=Split-Path -Parent $p
    while($ancestor.Length -ge $allowedRoot.Length){
        if((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse ancestor changed before removal'}
        if($ancestor -eq $allowedRoot){break};$ancestor=Split-Path -Parent $ancestor
    }
    Remove-Item -LiteralPath $p
}
Check-Records $plan.protected_files
$receipt=[pscustomobject]@{schema='heatdrive_ecc_rejected_middle_raw_retirement_receipt_v1';plan_sha256=(Hash $planPath);deleted_files=$plan.files.Count;deleted_bytes=$plan.retire_bytes;protected_files_rehashed_after=$plan.protected_files.Count;all_complete_OPs_retained=$true;all_current_C108_dependencies_retained=$true;raw_copied_bytes=0;failed_state_propagation_allowed=$false;completed=$true}
Write-Json $receiptPath $receipt
$receipt | ConvertTo-Json
