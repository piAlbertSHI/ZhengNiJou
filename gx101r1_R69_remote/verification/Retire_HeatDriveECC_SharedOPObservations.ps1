$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$out=Join-Path $repo 'outputs_storage_audit\shared_endpoint_OP_bounded_cycle_20261026_r2'
$receipt=Join-Path $out 'retirement_receipt.json'
if(Test-Path -LiteralPath $receipt) { throw 'Do not repeat this retirement.' }
$m=Get-Content -LiteralPath (Join-Path $out 'retirement_candidates.json') -Raw | ConvertFrom-Json
$roots=@('C:\tmp\se21_shared_endpoint_OP_cycle_r1_20261026',
    'C:\tmp\se21_shared_endpoint_OP_new_process_r1_20261026',
    'C:\tmp\se21_shared_endpoint_OP_bounded_step_r1_20261026',
    'C:\tmp\se21_shared_endpoint_OP_bounded_cycle_r1_20261026',
    'C:\tmp\se21_shared_endpoint_OP_bounded_new_process_r1_20261026')
function Assert-Hash($r) {
    if((Get-FileHash -LiteralPath $r.path -Algorithm SHA256).Hash -ne $r.sha256) { throw "Hash changed: $($r.path)" }
}
foreach($p in @(Get-CimInstance Win32_Process -Filter "Name = 'MATLAB.exe'")) {
    foreach($root in $roots) { if($p.CommandLine -and $p.CommandLine.Replace('/','\').Contains($root)) { throw 'Experiment is live.' } }
}
foreach($r in $m.protected) { Assert-Hash $r }
$raw=@((Join-Path $roots[0] 'shared\continuous_reference_observations.mat'),
    (Join-Path $roots[0] 'shared\same_model_restored_observations.mat'),
    (Join-Path $roots[1] 'new_process_restored_observations.mat'),
    (Join-Path $roots[4] 'new_process_restored_observations.mat'))
foreach($c in $m.candidates) {
    $root=[IO.Path]::GetFullPath($c.workspace_root);$target=[IO.Path]::GetFullPath($c.path)
    if($root -notin $roots) { throw 'Unknown bounded root.' }
    $allowed=@((Join-Path $root 'cache'),(Join-Path $root 'codegen'))
    if($c.kind -eq 'file') {
        if(-not $c.full_content_subset_proved) { throw 'No exact observation coverage proof.' }
        $allowed=$raw
    }
    if($target -notin $allowed -or -not $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Target escaped exact boundary.' }
    $ancestor=Get-Item -LiteralPath $target -Force
    while($null -ne $ancestor) {
        if($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked ancestor.' }
        $ancestor=if($ancestor.PSIsContainer) { $ancestor.Parent } else { $ancestor.Directory }
    }
    $all=if($c.kind -eq 'file') { @(Get-Item -LiteralPath $target) } else { @(Get-ChildItem -LiteralPath $target -Recurse -Force) }
    if(@($all | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Linked descendant.' }
    if(@($all | Where-Object { -not $_.PSIsContainer }).Count -ne @($c.files).Count) { throw 'File set changed.' }
    foreach($r in $c.files) {
        $path=[IO.Path]::GetFullPath($r.path)
        if($path -ne $target -and -not $path.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Candidate escaped target.' }
        if((Get-Item -LiteralPath $path).Length -ne $r.bytes) { throw 'Size changed.' }
        Assert-Hash $r
    }
}
$deleted=@();$freed=[int64]0;$failure=$null
try {
    foreach($c in $m.candidates) {
        Remove-Item -LiteralPath $c.path -Recurse -Force
        if(Test-Path -LiteralPath $c.path) { throw 'Candidate remains.' }
        $deleted+=$c.path;$freed += [int64]$c.bytes
    }
    foreach($r in $m.protected) { Assert-Hash $r }
} catch { $failure=$_.Exception.Message } finally {
    $r=[ordered]@{schema='heatdrive_ecc_shared_OP_retirement_v1';complete=($null -eq $failure);failure=$failure;
        deleted_targets=$deleted;reclaimed_bytes=$freed;protected_hashes_verified_after=($null -eq $failure);
        runtime_model_OP_or_base_archive_deleted=$false;different_physical_trials_deleted=$false;
        previously_denied_paths_retried=$false;protected=$m.protected}
    [IO.File]::WriteAllText($receipt,($r | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}
if($failure) { throw $failure }
[pscustomobject]$r | Select-Object complete,reclaimed_bytes,deleted_targets | ConvertTo-Json -Depth 4
