$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$out=Join-Path $repo 'outputs_storage_audit\shared_endpoint_inventory_C20_20261026_r2'
$receipt=Join-Path $out 'generated_retirement_receipt.json'
if (Test-Path -LiteralPath $receipt) { throw 'Do not repeat a retirement with an existing receipt.' }
$m=Get-Content -LiteralPath (Join-Path $out 'generated_intermediate_candidates.json') -Raw | ConvertFrom-Json
$roots=@('C:\tmp\se21_shared_endpoint_inventory_C20_r1_20261026','C:\tmp\se21_shared_endpoint_tail_equivalence_C2_r1_20261026')
function Assert-Hash($r) {
    if ((Get-FileHash -LiteralPath $r.path -Algorithm SHA256).Hash -ne $r.sha256) { throw "Hash changed: $($r.path)" }
}
$running=@(Get-CimInstance Win32_Process -Filter "Name = 'MATLAB.exe'")
foreach($p in $running) { foreach($root in $roots) {
    if ($p.CommandLine -and $p.CommandLine.Replace('/','\').Contains($root)) { throw 'Experiment is live.' }
} }
$protected=@($m.expected_raw_before_after)+@($m.frozen_C200)
$protected += [pscustomobject]@{path=(Join-Path $repo 'heatdrive_ecc_coupled_se21.slx');sha256=$m.protected_model_sha256}
foreach($r in $protected) { Assert-Hash $r }
foreach($c in $m.candidates) {
    $root=[IO.Path]::GetFullPath($c.workspace_root);$target=[IO.Path]::GetFullPath($c.path)
    if ($root -notin $roots) { throw 'Unknown experiment root.' }
    $allowed=@('cache','codegen','shared\seed') | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $root $_)) }
    if ($c.kind -eq 'file') {
        if ($root -ne $roots[1] -or -not $c.full_content_subset_proved) { throw 'No raw-subset retirement authority.' }
        $allowed=@('native_CV_observations.mat','workspace_CV_observations.mat','source_CV_observations.mat') |
            ForEach-Object { [IO.Path]::GetFullPath((Join-Path $root "shared\$_")) }
    }
    if ($target -notin $allowed -or -not $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Target escaped exact workspace boundary.' }
    $ancestor=Get-Item -LiteralPath $target -Force
    while($null -ne $ancestor) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked ancestor.' }
        $ancestor=if($ancestor.PSIsContainer) { $ancestor.Parent } else { $ancestor.Directory }
    }
    $all=if($c.kind -eq 'file') { @(Get-Item -LiteralPath $target) } else { @(Get-ChildItem -LiteralPath $target -Recurse -Force) }
    if (@($all | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Linked descendant.' }
    if (@($all | Where-Object { -not $_.PSIsContainer }).Count -ne @($c.files).Count) { throw 'Candidate file set changed.' }
    foreach($r in $c.files) {
        $path=[IO.Path]::GetFullPath($r.path)
        if ($path -ne $target -and -not $path.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest escaped target.' }
        if ((Get-Item -LiteralPath $path).Length -ne $r.bytes) { throw 'Candidate size changed.' }
        Assert-Hash $r
    }
}
$deleted=@();$freed=[int64]0;$failure=$null
try {
    foreach($c in $m.candidates) {
        Remove-Item -LiteralPath $c.path -Recurse -Force
        if(Test-Path -LiteralPath $c.path) { throw 'Candidate remains.' }
        $deleted += $c.path;$freed += [int64]$c.bytes
    }
    foreach($r in $protected) { Assert-Hash $r }
} catch { $failure=$_.Exception.Message } finally {
    $result=[ordered]@{schema='heatdrive_ecc_shared_C20_retirement_v1';complete=($null -eq $failure);
        deleted_targets=$deleted;reclaimed_bytes=$freed;failure=$failure;
        retained_raw_C200_protected_model_hashes_verified_after=($null -eq $failure);
        retained_C20_raw_deleted=$false;different_physical_variants_deleted=$false;
        protected_files=$protected;previously_denied_paths_retried=$false}
    [IO.File]::WriteAllText($receipt,($result | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}
if($failure) { throw $failure }
[pscustomobject]$result | Select-Object complete,reclaimed_bytes,deleted_targets | ConvertTo-Json -Depth 4
