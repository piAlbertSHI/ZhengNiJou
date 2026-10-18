param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$execution='C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs'
$out=[IO.Path]::GetFullPath($OutputRoot)
$allowed=Join-Path $repo 'outputs_storage_audit'
if(-not $out.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Inventory must stay in storage audit'}
if(Test-Path -LiteralPath $out){throw 'Never overwrite a previous inventory'}
$rows=@(foreach($d in Get-ChildItem -LiteralPath $execution -Directory){
    $files=[Collections.Generic.List[object]]::new()
    $links=[Collections.Generic.List[string]]::new()
    $pending=[Collections.Generic.Stack[string]]::new()
    $pending.Push($d.FullName)
    while($pending.Count){
        $p=$pending.Pop();$item=Get-Item -LiteralPath $p -Force
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){$links.Add($p);continue}
        foreach($child in Get-ChildItem -LiteralPath $p -Force){
            if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){$links.Add($child.FullName);continue}
            if($child.PSIsContainer){$pending.Push($child.FullName)}else{$files.Add($child)}
        }
    }
    $class='historical_diagnostic_pending_dependency_review'
    if($d.Name -in 'v67c1','v68c1','v70c1'){$class='current_C60_full_response_and_restore_chain'}
    elseif($d.Name -in 'v66_sensitivity_nominal_20261017','v68r2','v70case2'){$class='current_C20_origin_all_OPs_and_reduced_cold_history'}
    elseif($d.Name -match '^v69'){$class='candidate_kernel_qualification_evidence'}
    elseif($d.Name -eq 'v61c1'){$class='C108_constructor_reference_and_direct_dependencies'}
    elseif(Test-Path -LiteralPath (Join-Path $d.FullName 'HISTORICAL_CONSERVATIVE_RAW_RETIRED.json')){$class='rejected_old_trial_native_raw_and_compact_dual_arm_evidence'}
    elseif(Test-Path -LiteralPath (Join-Path $d.FullName 'REJECTED_DO_NOT_RESUME.txt')){$class='rejected_diagnostic_pending_dependency_review'}
    if($d.Attributes -band [IO.FileAttributes]::ReparsePoint){$class='mapped_reference_not_counted_again'}
    [pscustomobject]@{name=$d.Name;path=$d.FullName;files=$files.Count;
        bytes=[long](($files | Measure-Object Length -Sum).Sum);classification=$class;
        excluded_reparse_paths=@($links.ToArray());
        automatic_delete_allowed=$false}
})
New-Item -ItemType Directory -Path $out | Out-Null
$rows | Sort-Object bytes -Descending | Export-Csv -LiteralPath (Join-Path $out 'execution_output_inventory.csv') -NoTypeInformation -Encoding utf8
$summary=[pscustomobject]@{schema='heatdrive_ecc_execution_storage_inventory_v1';
    measured_at_utc=[DateTime]::UtcNow.ToString('o');scope=$execution;
    excludes_main_workspace=$true;excludes_Agent6=$true;directories=$rows.Count;
    files=($rows | Measure-Object files -Sum).Sum;bytes=($rows | Measure-Object bytes -Sum).Sum;
    byte_measure='logical_file_lengths_excluding_all_reparse_points_not_allocated_clusters';
    excluded_reparse_paths=@($rows | ForEach-Object {$_.excluded_reparse_paths});
    C_drive_free_bytes=(Get-PSDrive C).Free;
    next_complete_cold_to_C60_capacity_budget_bytes=18000000000L;
    classification_is_not_dependency_clearance=$true;automatic_delete_allowed=$false;
    top_ten=@($rows | Sort-Object bytes -Descending | Select-Object -First 10)}
[IO.File]::WriteAllText((Join-Path $out 'execution_storage_summary.json'),
    ($summary | ConvertTo-Json -Depth 8)+"`n",[Text.UTF8Encoding]::new($false))
$summary | Select-Object directories,files,bytes,C_drive_free_bytes | ConvertTo-Json
