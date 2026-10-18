param([Parameter(Mandatory=$true)][string]$Plan,[Parameter(Mandatory=$true)][string]$ExpectedPlanSha256)
$ErrorActionPreference='Stop'
function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function Write-Json([string]$p,$v){
    if(Test-Path -LiteralPath $p){throw 'Never overwrite evidence'}
    [IO.File]::WriteAllText($p,($v | ConvertTo-Json -Depth 25)+"`n",[Text.UTF8Encoding]::new($false))
}
if((Hash $Plan) -ne $ExpectedPlanSha256){throw 'Reviewed plan SHA required'}
$q=Get-Content -LiteralPath $Plan -Raw -Encoding utf8 | ConvertFrom-Json
$rows=@();$retired=@()
for($i=0;$i -lt $q.arms.Count;$i++){
    $a=$q.arms[$i];$root=[IO.Path]::GetFullPath($a.root)
    foreach($p in @($a.old_key_archive,$a.key_archive)){
        if([IO.Path]::GetFullPath($p) -ne (Join-Path $root ('conservative\'+(Split-Path -Leaf $p)))){throw 'Archive path escaped reviewed old trial'}
    }
    if((Split-Path -Leaf $a.old_key_archive) -ne 'retained_key_evidence_20261018.h5' -or
       (Split-Path -Leaf $a.key_archive) -ne 'retained_key_evidence_shared_20261018.h5'){throw 'Not the exact generated intermediate'}
    $ancestor=[IO.Path]::GetFullPath($a.old_key_archive)
    while($ancestor.Length -ge $root.Length){
        if((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Reparse point forbidden'}
        if($ancestor -eq $root){break};$ancestor=Split-Path -Parent $ancestor
    }
    & $q.python -B -X utf8 (Join-Path $PSScriptRoot 'Share_HeatDriveECC_ArchivedKeyEvidence.py') --plan $Plan --expected-sha256 $ExpectedPlanSha256 --index $i | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Diagnose sharing failure; do not retry or remove intermediate'}
    $r=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $Plan) ('key_sharing_{0:D2}.json' -f $i)) -Raw -Encoding utf8 | ConvertFrom-Json
    if(-not $r.all_retained_datasets_bitwise_equal -or (Hash $a.key_archive) -ne $r.archive_sha256 -or
       (Hash $a.old_key_archive) -ne $a.old_key_archive_sha256 -or (Hash $a.native_path) -ne $a.native_sha256){throw 'Evidence verification failed'}
    Remove-Item -LiteralPath $a.old_key_archive -ErrorAction Stop
    $rows+=$r;$retired+=[pscustomobject]@{path=$a.old_key_archive;sha256=$a.old_key_archive_sha256;bytes=$r.old_archive_bytes}
}
Write-Json (Join-Path (Split-Path -Parent $Plan) 'arm_key_evidence_receipt.json') ([pscustomobject]@{plan_sha256=$ExpectedPlanSha256;arms=$rows;retired_generated_intermediates=$retired;raw_deleted_bytes=0})
[pscustomobject]@{arms=$rows.Count;retired_generated_bytes=($retired | Measure-Object bytes -Sum).Sum;retained_shared_archive_bytes=($rows | Measure-Object archive_bytes -Sum).Sum;all_retained_arrays_bitwise_equal=$true} | ConvertTo-Json
