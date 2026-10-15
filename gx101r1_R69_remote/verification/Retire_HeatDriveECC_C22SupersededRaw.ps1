[CmdletBinding()]
param([Parameter(Mandatory=$true)][string[]]$CandidateQualifications,
      [Parameter(Mandatory=$true)][string]$OutputRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pointerPath=Join-Path $PSScriptRoot 'current_runtime_boundary_warmup.json'
$p=Get-Content -LiteralPath $pointerPath -Raw | ConvertFrom-Json
$currentQ=Join-Path $repo $p.qualification_relative
if ($p.snapshot_time_s -ne 280 -or (Get-FileHash -LiteralPath $currentQ).Hash -ne $p.qualification_sha256) {
    throw 'This retirement is scoped to the sealed C28 baseline only.'
}
if ($CandidateQualifications.Count -ne 2) { throw 'Require both matched Tc qualifications.' }
$qualified=@($currentQ)+@($CandidateQualifications)
$temperatures=@()
$protected=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($path in $qualified) {
    $q=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if (-not $q.original_public_thermal_periodic_pass -or $q.source_state_edited) { throw 'Unqualified current endpoint.' }
    if ($path -ne $currentQ -and ($q.snapshot_time_s -ne 400 -or
        $q.boundary_trial.source_complete_OP_sha256 -ne $p.operating_point_sha256)) {
        throw 'Trial does not share the complete C28 origin.'
    }
    if ($path -ne $currentQ) { $temperatures+= $q.temperature_K }
    [void]$protected.Add([IO.Path]::GetFullPath($path))
    [void]$protected.Add([IO.Path]::GetFullPath($q.operating_point_path))
    if ((Get-FileHash -LiteralPath $q.operating_point_path).Hash -ne $q.operating_point_sha256) { throw 'Changed state.' }
    foreach ($f in $q.files) {
        if ((Get-FileHash -LiteralPath $f.path).Hash -ne $f.sha256) { throw ('Changed dependency: '+$f.path) }
        [void]$protected.Add([IO.Path]::GetFullPath($f.path))
    }
}
if (($temperatures | Sort-Object -Unique).Count -ne 2 -or
    $temperatures -notcontains 276.85 -or $temperatures -notcontains 277.05) { throw 'Require the two distinct declared Tc arms.' }
$outputs=Split-Path (Split-Path (Split-Path $p.operating_point_path -Parent) -Parent) -Parent
$collection=[IO.Path]::GetFullPath((Join-Path $outputs 'v51_runtime_warmup_C2_C22_r1'))
$marker=Join-Path $collection 'ADDITIONAL_SUPERSEDED_RAW_RETIRED.json'
if (Test-Path -LiteralPath $marker) { throw 'Do not overwrite an older retirement marker.' }
if (-not (Test-Path -LiteralPath (Join-Path $collection 'COMPLETED_RAW_PREFIX_RETIRED.json'))) {
    throw 'Require the already completed, in-place-resume-prohibited old C22 job.'
}
$live=@(Get-CimInstance Win32_Process -Filter "Name='MATLAB.exe'" | Where-Object {
    $_.CommandLine -match 'v51_runtime_warmup|v52_runtime_convergence|v53_runtime_Tc276p85|v54_runtime_Tc277p05'
})
if ($live.Count) { throw 'A related program is still alive; do not retire its observations.' }
$out=[IO.Path]::GetFullPath($OutputRoot)
if ((Split-Path $out -Parent) -ne (Join-Path $repo 'outputs_storage_audit') -or (Test-Path -LiteralPath $out)) {
    throw 'Use a fresh local audit directory.'
}
$targets=@(foreach ($cycle in @(14,16,18)) {
    foreach ($name in @('native\observations.mat','observed_states.mat')) {
        $path=[IO.Path]::GetFullPath((Join-Path $collection ('packet_C{0:D3}_attempt01\{1}' -f $cycle,$name)))
        if (-not $path.StartsWith($collection+'\',[StringComparison]::OrdinalIgnoreCase) -or $protected.Contains($path)) {
            throw 'Target escapes the retired collection or is a current qualified dependency.'
        }
        $ancestor=$path
        while ($ancestor -and $ancestor.Length -ge $collection.Length) {
            $item=Get-Item -LiteralPath $ancestor
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'No reparse paths.' }
            $ancestor=Split-Path $ancestor -Parent
        }
        $file=Get-Item -LiteralPath $path
        [pscustomobject]@{path=$path;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $path).Hash;
            classification='superseded_C22_window_outside_current_C28_180_to_280_and_both_C40_trials'}
    }
})
New-Item -ItemType Directory -Path $out | Out-Null
$receipt=[ordered]@{schema='heatdrive_ecc_superseded_C22_raw_retirement_v1';status='planned';
    collection_root=$collection;current_baseline_snapshot_s=280;matched_trials_snapshot_s=400;
    all_complete_OPs_preserved=$true;current_qualified_raw_deleted=0;old_C22_raw_reverification_available=$false;
    old_C22_qualification_now_historical_not_a_recovery_source=$true;
    qualification_files=$qualified;files=$targets;retired_bytes=0}
$receiptPath=Join-Path $out 'retirement_receipt.json'
$receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding utf8
foreach ($target in $targets) { Remove-Item -LiteralPath $target.path }
$receipt.status='completed';$receipt.retired_bytes=[long](($targets | Measure-Object bytes -Sum).Sum)
$receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding utf8
[ordered]@{retirement_receipt=$receiptPath;receipt_sha256=(Get-FileHash -LiteralPath $receiptPath).Hash;
    old_C22_raw_reverification_available=$false;old_C22_recovery_allowed=$false;
    use_current_sealed_C28_or_declared_same_Tc_C40_diagnostic_only=$true} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $marker -Encoding utf8
foreach ($path in $qualified) {
    $q=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    foreach ($f in $q.files) {
        if ((Get-FileHash -LiteralPath $f.path).Hash -ne $f.sha256) { throw ('Post-retirement dependency changed: '+$f.path) }
    }
}
[ordered]@{status=$receipt.status;retired_bytes=$receipt.retired_bytes;retired_file_count=$targets.Count;
    current_qualified_raw_deleted=0;complete_OPs_deleted=0;all_current_direct_dependencies_rehashed=$true} | ConvertTo-Json
