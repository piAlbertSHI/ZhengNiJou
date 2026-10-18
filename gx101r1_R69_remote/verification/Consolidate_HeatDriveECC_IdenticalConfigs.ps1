param([Parameter(Mandatory=$true)][string]$Plan,[Parameter(Mandatory=$true)][string]$ExpectedPlanSha256)
$ErrorActionPreference='Stop'
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function Local([string]$p,[string]$root){
    $p=[IO.Path]::GetFullPath($p);$root=[IO.Path]::GetFullPath($root)
    if(-not $p.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Path escaped exact execution root'}
    if($p -match '\\v71(case3|c1|p1)(\\|\.)'){throw 'Active case excluded'}
    $a=$p
    while($a.Length -ge $root.Length){
        if((Get-Item -LiteralPath $a).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point forbidden'}
        if($a -eq $root){break};$a=Split-Path -Parent $a
    }
}
if((Hash $Plan) -ne $ExpectedPlanSha256){throw 'Reviewed plan SHA required'}
$q=Get-Content -LiteralPath $Plan -Raw -Encoding utf8 | ConvertFrom-Json
$root='C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合\gx101r1_R69_remote\outputs'
if($q.schema -ne 'heatdrive_ecc_identical_config_consolidation_v1' -or $q.execution_root -ne $root){throw 'Wrong plan scope'}
$receipt=Join-Path (Split-Path -Parent $Plan) 'configuration_receipt.json'
if(Test-Path -LiteralPath $receipt){throw 'Already completed; do not repeat'}
foreach($g in $q.groups){
    foreach($p in @($g.canonical)+@($g.copies)){
        Local $p $root
        if((Split-Path -Leaf $p) -ne 'configuration.mat' -or (Hash $p) -ne $g.sha256){throw 'Not an identical configuration'}
    }
}
$done=@()
foreach($g in $q.groups){foreach($p in $g.copies){
    $link=$p+'.relief_link';$backup=$p+'.relief_original'
    if((Test-Path -LiteralPath $link) -or (Test-Path -LiteralPath $backup)){throw 'Review incomplete previous operation'}
    New-Item -ItemType HardLink -Path $link -Target $g.canonical | Out-Null
    if((Hash $link) -ne $g.sha256){throw 'Staged link differs'}
    Move-Item -LiteralPath $p -Destination $backup
    try{
        Move-Item -LiteralPath $link -Destination $p
        if((Hash $p) -ne $g.sha256){throw 'Replacement bytes differ'}
    }catch{
        if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p}
        Move-Item -LiteralPath $backup -Destination $p
        throw
    }
    Remove-Item -LiteralPath $backup
    $done += [pscustomobject]@{path=$p;canonical=$g.canonical;sha256=$g.sha256;independent_copy_bytes_removed=$g.each_bytes}
}}
foreach($g in $q.groups){foreach($p in @($g.canonical)+@($g.copies)){if((Hash $p) -ne $g.sha256){throw 'Post-consolidation hash mismatch'}}}
$r=[pscustomobject]@{schema=$q.schema;plan_sha256=$ExpectedPlanSha256;replacements=$done;
    independent_copy_bytes_removed=($done | Measure-Object independent_copy_bytes_removed -Sum).Sum;
    all_original_paths_and_bytes_preserved=$true;active_case_untouched=$true;recursive_delete_used=$false}
[IO.File]::WriteAllText($receipt,($r | ConvertTo-Json -Depth 12)+"`n",[Text.UTF8Encoding]::new($false))
$r | Select-Object independent_copy_bytes_removed,all_original_paths_and_bytes_preserved,active_case_untouched | ConvertTo-Json
