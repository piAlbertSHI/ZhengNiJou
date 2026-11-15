param([switch]$Apply)
$ErrorActionPreference='Stop'
$repo='C:\Users\86182\Desktop\正逆耦合'
$audit=Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_fourth_20261115'
$runtime='C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合'
$phase='C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合'
$verificationRoots=@((Join-Path $runtime 'gx101r1_R69_remote\verification'),(Join-Path $phase 'gx101r1_R69_remote\verification'),(Join-Path $repo 'gx101r1_R69_remote\verification'),(Join-Path $repo '项目文档\报告'))
$model=Join-Path $repo 'gx101r1_R69_remote\heatdrive_ecc_coupled_se21.slx'
if(Test-Path $audit){throw "Audit root exists: $audit"}
function Hash([string]$p){(Get-FileHash $p -Algorithm SHA256).Hash}
function AssertFile([string]$p){if(-not(Test-Path $p -PathType Leaf)){throw "Missing $p"}}
function AddCandidate([Collections.Generic.List[object]]$list,[string]$p,[string]$root,[string]$why){
  AssertFile $p
  $idx=$p.IndexOf('outputs\',[StringComparison]::OrdinalIgnoreCase)
  $tail=if($idx-ge 0){$p.Substring($idx)}else{$p}
  $refs=@()
  foreach($vr in $verificationRoots){
    foreach($pat in @($p,$tail,$tail.Replace('\','/'))){
      $refs+=@(rg -l -F --hidden --no-messages --glob '*.m' --glob '*.py' --glob '*.ps1' --glob '*.json' --glob '*.md' --glob '!outputs/**' --glob '!outputs_storage_audit/**' -- $pat $vr 2>$null)
    }
  }
  $refs=@($refs|Sort-Object -Unique)
  if($refs.Count){throw "Exact raw reference $p => $($refs -join ';')"}
  $ev=@(Get-ChildItem $root -File -Recurse|Where-Object {$_.Extension -in @('.json','.csv','.txt','.h5') -or $_.Name -in @('configuration.mat','cold_public_targets.mat','runtime_evidence_contract.mat','diagnostic_complete_operating_point.mat','cold_mechanism_observation.mat','restore_preflight_comparison.mat','comparison_only_complete_op.mat')}|Select-Object -ExpandProperty FullName)
  $list.Add([ordered]@{path=$p;group=$root;bytes=[int64](Get-Item $p).Length;sha256=(Hash $p);replacement_evidence=$ev;direct_script_references=@();reason=$why})
}
$live=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -match '(?i)^matlab(\.exe)?$|simulink|sldriver'})
if($live.Count){throw 'MATLAB/Simulink is alive'}
AssertFile $model
$modelHash=Hash $model
$c=[Collections.Generic.List[object]]::new()
$runtimeSpecs=@(
  @{r=(Join-Path $runtime 'gx101r1_R69_remote\outputs\v19_intact_diagnostic_resume_20c');f=@('native\observations.mat','native\diagnostic_state_observation.mat');w='Warmup candidate raw replaced by compact contract and public targets'},
  @{r=(Join-Path $runtime 'gx101r1_R69_remote\outputs\v36_se_ref2_r1');f=@('baseline\native\observations.mat','baseline\native\diagnostic_state_observation.mat','coherent\native\observations.mat','coherent\native\diagnostic_state_observation.mat');w='SE reference trajectory replaced by mechanism/OP/restore/cycle evidence'},
  @{r=(Join-Path $runtime 'gx101r1_R69_remote\outputs\v39_density_c2_r1');f=@('candidate\native\observations.mat','candidate\native\diagnostic_state_observation.mat');w='Density candidate trajectory replaced by mechanism/OP/restore/cycle evidence'},
  @{r=(Join-Path $runtime 'gx101r1_R69_remote\outputs\v24_directional_directlog_cold_2c');f=@('native\observations.mat','native\diagnostic_state_observation.mat');w='Directional C2 trajectory replaced by mechanism/OP/restore/cycle evidence'},
  @{r=(Join-Path $runtime 'gx101r1_R69_remote\outputs\v14_distributed_ff20c');f=@('native\failed_public_observations.mat');w='Rejected public raw replaced by rejection marker and compact targets'}
)
foreach($s in $runtimeSpecs){foreach($f in $s.f){AddCandidate $c (Join-Path $s.r $f) $s.r $s.w}}
$packetSpecs=@(
  @{r=(Join-Path $phase 'gx101r1_R69_remote\outputs\v48_native_recording_C64_C72_r1');d=@('C066','C068','C070');keep='C072'},
  @{r=(Join-Path $phase 'gx101r1_R69_remote\outputs\v52_runtime_convergence_C22_r1');d=@('C024','C026');keep='C028'},
  @{r=(Join-Path $phase 'gx101r1_R69_remote\outputs\v59c1');d=@('C094','C096');keep='C098'},
  @{r=(Join-Path $phase 'gx101r1_R69_remote\outputs\v58c3');d=@('C090');keep='C092'},
  @{r=(Join-Path $phase 'gx101r1_R69_remote\outputs\v51_runtime_warmup_C2_C22_r1');d=@('C020');keep='C022'}
)
foreach($s in $packetSpecs){
  foreach($cy in $s.d){
    $files=@(('packet_' + $cy + '_attempt01\observed_states.mat'),('packet_' + $cy + '_attempt01\native\observations.mat'),('packet_' + $cy + '_attempt01\native\configuration.mat'))
    foreach($f in $files){AddCandidate $c (Join-Path $s.r $f) $s.r ('Intermediate packet raw; ' + $s.keep + ' representative and compact evidence retained')}
  }
}
$h=Join-Path $phase 'gx101r1_R69_remote\outputs\v63p2'
foreach($f in @('native\horizon_preflight\reference\native\observations.mat','native\horizon_preflight\reference\observed_states.mat','native\horizon_preflight\reference\native\configuration.mat','native\horizon_preflight\short_reference\native\observations.mat','native\horizon_preflight\short_reference\observed_states.mat')){AddCandidate $c (Join-Path $h $f) $h 'Bitwise-equal horizon reference raw replaced by extended representative and compact preflight evidence'}
New-Item -ItemType Directory -Path $audit|Out-Null
$blocked=@('v37_ref_restore_r1','v15_distributed_envelope_10s','v5t','v4','qian_cold_stage4_p_continuous_kp70_20261005_v3','qian_cold_stage4_p_path_kp70_20261005','qian_cold_runtime_cv_contract_20261005_json_v2','qian_coupled_stage4_phase_local_blend_20260928_20cycle_warmup','qian_coupled_stage4_single_target_contract_20260929_20cycle_progress_contract','qian_coupled_stage4_single_target_contract_20260928_20cycle','v64c1','v65c1')
$wl=[ordered]@{schema='agent5_fourth_stage_raw_retirement_whitelist_v1';generated_utc=[DateTime]::UtcNow.ToString('o');candidate_count=$c.Count;candidates=$c;blocked_groups=$blocked;blocked_reason='No complete compact replacement or unique restore/failure evidence verified in this pass.';model_hash_before=$modelHash;deletion_performed=$false}
$wp=Join-Path $audit 'fourth_stage_raw_retirement_whitelist.json'
$wl|ConvertTo-Json -Depth 25|Set-Content $wp -Encoding utf8
$del=@()
if($Apply){
  $live=@(Get-CimInstance Win32_Process|Where-Object {$_.Name -match '(?i)^matlab(\.exe)?$|simulink|sldriver'})
  if($live.Count){throw 'MATLAB appeared before deletion'}
  foreach($x in $c){if((Hash $x.path)-ne $x.sha256){throw "Changed $($x.path)"};Remove-Item $x.path -Force;if(Test-Path $x.path){throw "Remaining $($x.path)"};$del+=$x}
}
$freed=[int64]0
foreach($x in $del){$freed+=$x.bytes}
$wl.deletion_performed=$Apply.IsPresent
$wl.deleted_file_count=$del.Count
$wl.deleted_files=$del
$wl.reclaimed_bytes=$freed
$wl.reclaimed_gib=[math]::Round($freed/1GB,6)
$wl.model_hash_after=Hash $model
$wl|ConvertTo-Json -Depth 25|Set-Content $wp -Encoding utf8
$rp=Join-Path $audit 'fourth_stage_raw_retirement_receipt.json'
[ordered]@{schema='agent5_fourth_stage_raw_retirement_receipt_v1';status='completed';generated_utc=[DateTime]::UtcNow.ToString('o');whitelist=$wp;deleted_file_count=$del.Count;deleted_files=$del;reclaimed_bytes=$freed;reclaimed_gib=[math]::Round($freed/1GB,6);blocked_groups=$blocked;model_hash_before=$modelHash;model_hash_after=(Hash $model);scientific_gates_changed=$false;matlab_simulink_started_or_interrupted=$false;Agent6_touched=$false;main_model_touched=$false}|ConvertTo-Json -Depth 25|Set-Content $rp -Encoding utf8
[pscustomobject]@{candidate_count=$c.Count;deleted_count=$del.Count;reclaimed_bytes=$freed;reclaimed_gib=[math]::Round($freed/1GB,6);whitelist=$wp;receipt=$rp}|ConvertTo-Json
