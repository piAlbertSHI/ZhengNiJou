$ErrorActionPreference='Stop'
$repo='C:\Users\86182\Desktop\正逆耦合'
$auditRoot=Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_20261115_r1'
$receipt=Join-Path $auditRoot 'cache_retirement_receipt.json'
if(Test-Path -LiteralPath $receipt){throw 'Cache retirement receipt already exists; refusing a second deletion.'}
$roots=@(
    'C:\Users\86182\.codex\worktrees\fixed-stage4-kp237-endpoint\正逆耦合',
    'C:\Users\86182\.codex\worktrees\stage4-default-cold-diagnostic\正逆耦合',
    'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合'
)
$names=@('cache','codegen','slprj','simulink_cache')
$all=@(); foreach($root in $roots){$all += @(Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -ErrorAction SilentlyContinue | Where-Object {$_.Name -in $names -and ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0})}
$paths=@($all | Select-Object -ExpandProperty FullName -Unique)
$top=@(); foreach($p in $paths){$ancestor=$false;$parent=(Get-Item -LiteralPath $p).Parent;while($null -ne $parent){if($paths -contains $parent.FullName){$ancestor=$true;break};$parent=$parent.Parent};if(-not $ancestor){$top += $p}}
$procs=@(Get-CimInstance Win32_Process | Select-Object ProcessId,Name,CommandLine)
foreach($p in $procs){foreach($root in $roots){if($p.CommandLine -and $p.CommandLine.Replace('/','\').Contains($root)){throw "Live process references cleanup scope: $($p.ProcessId)"}}}
$files=@(); foreach($d in $top){foreach($f in @(Get-ChildItem -LiteralPath $d -Recurse -File -Force -ErrorAction SilentlyContinue)){if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "Reparse-point cache file: $($f.FullName)"};$files += [ordered]@{path=$f.FullName;bytes=[int64]$f.Length;sha256=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash}}}
$freed=[int64](($files|ForEach-Object {[int64]$_.bytes}|Measure-Object -Sum).Sum)
foreach($d in $top){Remove-Item -LiteralPath $d -Recurse -Force;if(Test-Path -LiteralPath $d){throw "Cache directory remained: $d"}}
$r=[ordered]@{schema='agent5_workspace_cache_retirement_v1';status='completed';generated_utc=(Get-Date).ToUniversalTime().ToString('o');recursive_delete_used=$true;scope_roots=$roots;deleted_directories=$top;deleted_file_count=$files.Count;deleted_files=$files;reclaimed_bytes=$freed;runtime_cv_json_contract_touched=$false;external_or_unconfirmed_paths_touched=$false;scientific_gates_changed=$false;protected_results_deleted=$false;live_process_reference_count=0}
$r|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $receipt -Encoding utf8
[pscustomobject]@{status=$r.status;directories=$top.Count;files=$files.Count;reclaimed_bytes=$freed;reclaimed_gib=[math]::Round($freed/1GB,6)}|ConvertTo-Json
