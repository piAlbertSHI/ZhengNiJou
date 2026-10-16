[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputRoot,[switch]$Apply)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$out=[IO.Path]::GetFullPath($OutputRoot)
if ((Split-Path -Parent $out) -ne (Join-Path $repo 'outputs_storage_audit')) { throw 'Require a local audit destination.' }
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Require-Hash([string]$Path,[string]$Hash) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Hash) { throw "Changed source: $Path" }
}
$study=Read-Json (Join-Path $PSScriptRoot 'current_runtime_metric_study.json')
$current=Join-Path $repo $study.point_qualification_relative
$reference=Join-Path $repo 'outputs_storage_audit/v59_runtime_Tc274p85_C98_snapshot_20261016/endpoint_qualification.json'
Require-Hash $current $study.point_qualification_sha256
Require-Hash $reference 'A2BD2A6C97806F3C9EA6B61B722BB902D7681C99943A2FE3B6A8DA601A90D91A'
$comparison=Join-Path $repo $study.repeatability_relative
Require-Hash $comparison $study.repeatability_sha256
$repeat=Read-Json $comparison
if (-not $repeat.disjoint_metric_repeatability_pass -or
    $repeat.candidate_qualification_sha256 -ne $study.point_qualification_sha256) { throw 'Require the actual repeated current endpoint.' }
$cq=Read-Json $current; $rq=Read-Json $reference
if ($cq.snapshot_time_s -ne 1080 -or $rq.snapshot_time_s -ne 980 -or
    -not $cq.original_public_thermal_periodic_pass -or -not $rq.original_public_thermal_periodic_pass) { throw 'This release is scoped to C108 and its C98 reference.' }
$execRepo=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $cq.source_packet_root))
$roots=@((Join-Path $execRepo 'outputs/v57_runtime_Tc274p85_fromC52_r1'),(Join-Path $execRepo 'outputs/v58c3'))
$live=@(Get-CimInstance Win32_Process -Filter "Name='MATLAB.exe'" | Where-Object {
    $_.CommandLine -and ($_.CommandLine.Contains($execRepo) -or $_.CommandLine -match 'Run_HeatDriveECC_Runtime|Load_HeatDriveECC_GatedObservationPacket') })
if ($live.Count) { throw 'A related MATLAB process remains alive.' }
$protected=@{}
$catalog=Read-Json (Join-Path $PSScriptRoot 'runtime_Tc_trial_catalog.json')
$baseline=Read-Json (Join-Path $PSScriptRoot 'current_runtime_boundary_warmup.json')
$points=@($catalog.latest_same_Tc_continuations)+@($catalog.latest_bounded_search_continuation)+@($baseline)
foreach($point in $points) {
    $path=Join-Path $repo $point.qualification_relative
    Require-Hash $path $point.qualification_sha256
    $q=Read-Json $path
    $protected[$path]=$point.qualification_sha256
    $protected[$q.operating_point_path]=$q.operating_point_sha256
    foreach($row in $q.files) { $protected[$row.path]=$row.sha256 }
}
$protected[$reference]=(Get-FileHash -LiteralPath $reference).Hash
$protected[$rq.operating_point_path]=$rq.operating_point_sha256
foreach($row in $rq.files) { $protected[$row.path]=$row.sha256 }
foreach($path in $protected.Keys) { Require-Hash $path $protected[$path] }
$planPath=Join-Path $out 'retirement_plan.json'
if (-not $Apply) {
    if (Test-Path -LiteralPath $out) { throw 'Never overwrite a release plan.' }
    $targets=@(); $oldpoints=@()
    foreach($name in @('v57_runtime_Tc274p85_C72_snapshot_20261016','v58_runtime_Tc274p85_C92_snapshot_20261016')) {
        $qp=Join-Path $repo "outputs_storage_audit/$name/endpoint_qualification.json"
        $expected=if($name -like 'v57_*'){'17D22F868FDD09749E8A77DCD8B8D4D2AF0F9070B675A3AEADC590022C0A9B34'}else{'0AD43426F00E979201CAF8528DDD6F4F8199911B04430D71302D7CEB666AD53B'}
        Require-Hash $qp $expected
        $q=Read-Json $qp
        if (-not $q.all_original_packet_mechanism_flow_phase_energy_gates_pass -or
            $q.source_state_edited -or $q.temperature_K -ne $cq.temperature_K) { throw 'Not a superseded same-Tc physical transient.' }
        $collection=Split-Path -Parent $q.source_packet_root
        if ($collection -notin $roots) { throw 'Unrecognized historical collection.' }
        foreach($row in $q.files) { Require-Hash $row.path $row.sha256 }
        $oldpoints += [pscustomobject]@{qualification_path=$qp;qualification_sha256=(Get-FileHash -LiteralPath $qp).Hash;
            collection_root=$collection;status='historical_not_full_raw_reverifiable_after_retirement';resume_allowed=$false}
        foreach($row in $q.files) {
            $file=[IO.Path]::GetFullPath($row.path); $leaf=Split-Path -Leaf $file
            if (-not $file.StartsWith($collection+'\',[StringComparison]::OrdinalIgnoreCase) -or
                $leaf -notin @('observations.mat','observed_states.mat') -or $protected.ContainsKey($file)) { continue }
            $packet=Split-Path -Parent $file
            if ($leaf -eq 'observations.mat') { $packet=Split-Path -Parent $packet }
            if ((Split-Path -Parent $packet) -ne $collection -or (Split-Path -Leaf $packet) -eq 'packet_C054_attempt01') { continue }
            $m=Read-Json (Join-Path $packet 'packet_manifest.json')
            if ($m.window_s[1] -gt $rq.current_window_s[0]) { continue }
            $g=Read-Json (Join-Path $packet 'packet_gate.json')
            if (-not $g.gate_pass -or -not $g.original_mechanism_pass) { throw 'Unverified historical packet.' }
            $targets += [pscustomobject]@{path=$file;bytes=(Get-Item -LiteralPath $file).Length;sha256=$row.sha256;collection_root=$collection}
        }
    }
    if (@($targets.path | Select-Object -Unique).Count -ne $targets.Count) { throw 'Duplicate target.' }
    $bytes=0L;foreach($target in $targets){$bytes+=[long]$target.bytes}
    New-Item -ItemType Directory -Path $out | Out-Null
    [ordered]@{schema='heatdrive_ecc_superseded_transient_raw_release_v1';current_qualification_sha256=$study.point_qualification_sha256;
        reference_qualification_sha256=$repeat.reference_qualification_sha256;repeatability_sha256=$study.repeatability_sha256;
        targets=$targets;retire_bytes=$bytes;historical_points=$oldpoints;protected_files=$protected;
        complete_OP_deleted_bytes=0;current_window_deleted_bytes=0;Tc_transition_C54_retained=$true} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding utf8
    [pscustomobject]@{status='planned';files=$targets.Count;retire_bytes=$bytes;targets=$targets.path} | ConvertTo-Json -Depth 4
    return
}
$plan=Read-Json $planPath
if ($plan.current_qualification_sha256 -ne $study.point_qualification_sha256 -or
    $plan.repeatability_sha256 -ne $study.repeatability_sha256) { throw 'Current release authority changed.' }
$receiptPath=Join-Path $out 'retirement_receipt.json'
if (Test-Path -LiteralPath $receiptPath) { throw 'Existing receipt requires diagnosis, not a blind retry.' }
foreach($target in $plan.targets) {
    $file=(Resolve-Path -LiteralPath $target.path).Path
    if ($target.collection_root -notin $roots -or -not $file.StartsWith($target.collection_root+'\',[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $file) -notin @('observations.mat','observed_states.mat') -or $protected.ContainsKey($file)) { throw 'Unsafe retirement target.' }
    $item=Get-Item -LiteralPath $file -Force
    while ($null -ne $item -and $item.FullName.StartsWith($execRepo,[StringComparison]::OrdinalIgnoreCase)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'No junction traversal.' }
        $item=if($item -is [IO.FileInfo]){$item.Directory}else{$item.Parent}
    }
    Require-Hash $file $target.sha256
    if ((Get-Item -LiteralPath $file).Length -ne $target.bytes) { throw 'Target length changed.' }
}
$receipt=[ordered]@{status='retirement_started';plan_sha256=(Get-FileHash -LiteralPath $planPath).Hash;
    retired_files=@();retired_bytes=0L;complete_OP_deleted_bytes=0;current_window_deleted_bytes=0;historical_points=$plan.historical_points}
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
foreach($root in $roots) {
    $marker=Join-Path $root 'HISTORICAL_RAW_RETIRED.json'
    if(Test-Path -LiteralPath $marker){throw 'Historical marker already exists.'}
    [ordered]@{status='retirement_started';receipt_path=$receiptPath;resume_allowed=$false} |
        ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding utf8
}
foreach($target in $plan.targets) {
    Remove-Item -LiteralPath $target.path -Force
    $receipt.retired_files+= $target.path; $receipt.retired_bytes+=[long]$target.bytes
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
}
foreach($path in $protected.Keys) { Require-Hash $path $protected[$path] }
$receipt.status='completed'
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
foreach($root in $roots) {
    [ordered]@{status='completed';receipt_path=$receiptPath;resume_allowed=$false;complete_OP_retained=$true} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'HISTORICAL_RAW_RETIRED.json') -Encoding utf8
}
[pscustomobject]@{status='completed';files=$receipt.retired_files.Count;retired_bytes=$receipt.retired_bytes;
    complete_OP_deleted_bytes=0;current_window_deleted_bytes=0;protected_files_verified=$protected.Count} | ConvertTo-Json
