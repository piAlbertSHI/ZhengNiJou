param([Parameter(Mandatory=$true)][string]$ExecutionRepo,
      [Parameter(Mandatory=$true)][string]$ArchiveRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $ExecutionRepo).Path
$outputs=Join-Path $repo 'outputs'
$audit=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\outputs_storage_audit')).Path
$destination=[IO.Path]::GetFullPath($ArchiveRoot)
if (-not $destination.StartsWith($audit+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $destination)) { throw 'Require new bounded main archive.' }
$proof=Get-Content -LiteralPath (Join-Path $audit 'v44_buffer_geometry_fixture_verified_20261015.json') -Raw | ConvertFrom-Json
$latest=Join-Path $outputs 'v44_buffer_geometry_fixture_r4'
if (-not $proof.isolated_component_equations_pass -or $proof.cases.Count -ne 8 -or
    $proof.source_root -ne $latest -or
    $proof.input_sha256.fixture_execution -ne (Get-FileHash -LiteralPath (Join-Path $latest 'fixture_execution.json')).Hash) {
    throw 'Require the verified eight-case component result.'
}
$pointer=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'current_storage_warmup_contract.json') -Raw | ConvertFrom-Json
$source=Join-Path $repo $pointer.source_root_relative
$protected=@()
foreach ($pair in @(@('operating_point_relative','operating_point_sha256'),@('history_relative','history_sha256'))) {
    $path=Join-Path $source $pointer.($pair[0]);$hash=(Get-FileHash -LiteralPath $path).Hash
    if ($hash -ne $pointer.($pair[1])) { throw 'Current complete state changed.' }
    $protected+=[ordered]@{path=$path;sha256=$hash}
}
New-Item -ItemType Directory -Path $destination | Out-Null
$classes=@('compile_failure_no_sim','weak_flux_energy_failure','global_only_precision_control_failed','local_precision_component_pass')
$copies=@();$keep=@();$retire=@()
for ($i=1;$i -le 4;$i++) {
    $root=[IO.Path]::GetFullPath((Join-Path $outputs ('v44_buffer_geometry_fixture_r'+$i)))
    if ((Split-Path -Parent $root) -ne $outputs -or
        ((Get-Item -LiteralPath $root).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Escaped or reparse root.' }
    if ($i -lt 4 -and -not (Test-Path -LiteralPath (Join-Path $root 'REJECTED_DO_NOT_RESUME.json'))) { throw 'Missing failed-case marker.' }
    $target=Join-Path $destination ('r'+$i);New-Item -ItemType Directory -Path $target | Out-Null
    $files=@((Join-Path $root 'fixture_execution.json'),(Join-Path $root 'matlab_diary.log'),
        ($root+'.matlab_stdout.log'),($root+'.matlab_stderr.log'))
    if ($i -lt 4) { $files+=Join-Path $root 'REJECTED_DO_NOT_RESUME.json' }
    foreach ($file in $files) {
        $copy=Join-Path $target (Split-Path $file -Leaf);Copy-Item -LiteralPath $file -Destination $copy
        $hash=(Get-FileHash -LiteralPath $file).Hash
        if ((Get-FileHash -LiteralPath $copy).Hash -ne $hash) { throw 'Copied evidence changed.' }
        $copies+=[ordered]@{source=$file;archive=$copy;sha256=$hash;classification=$classes[$i-1]}
    }
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object { $_.FullName -notmatch '\\(cache|codegen)\\' }) {
        $keep+=[ordered]@{path=$file.FullName;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash}
    }
    foreach ($name in @('cache','codegen')) {
        $path=[IO.Path]::GetFullPath((Join-Path $root $name))
        if ((Split-Path -Parent $path) -ne $root -or $path -notin @((Join-Path $root 'cache'),(Join-Path $root 'codegen'))) {
            throw 'Escaped exact cache target.'
        }
        if (Test-Path -LiteralPath $path -PathType Container) {
            if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse cache rejected.' }
            $size=0L;foreach ($file in Get-ChildItem -LiteralPath $path -File -Recurse -Force) { $size+=$file.Length }
            $retire+=[ordered]@{path=$path;bytes=$size;classification='regenerable_fixture_cache_only'}
        }
    }
}
$encoding=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $destination 'cleanup_plan.json'),
    (@{copies=$copies;retain=$keep;protected=$protected;retire=$retire}|ConvertTo-Json -Depth 7),$encoding)
foreach ($row in $retire) { Remove-Item -LiteralPath $row.path -Recurse -Force }
foreach ($row in @($keep)+@($protected)) {
    if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Retained evidence changed.' }
}
$bytes=0L;foreach ($row in $retire) { $bytes+=[long]$row.bytes }
$receipt=[ordered]@{schema='heatdrive_ecc_buffer_geometry_round_closeout_v1';copies=$copies;retained_single_execution_copy=$keep;
    protected_C62_state=$protected;retired_cache=$retire;retired_cache_bytes=$bytes;retired_raw_bytes=0;
    coupled_checkpoint_unchanged=$true;failed_cases_not_propagated=$true;Agent6_untouched=$true;production_recovery_allowed=$false}
[IO.File]::WriteAllText((Join-Path $destination 'storage_receipt.json'),($receipt|ConvertTo-Json -Depth 8),$encoding)
[ordered]@{compact_copies=$copies.Count;retired_cache_bytes=$bytes;retired_raw_bytes=0;retained_files=$keep.Count}|ConvertTo-Json
