[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EndpointContract)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$pointer=Get-Content -LiteralPath $EndpointContract -Raw | ConvertFrom-Json
$repo=Split-Path -Parent $PSScriptRoot
$qpath=[IO.Path]::GetFullPath((Join-Path $repo $pointer.qualification_relative))
if ((Get-FileHash -LiteralPath $qpath -Algorithm SHA256).Hash -ne $pointer.qualification_sha256) { throw 'Qualification changed.' }
$q=Get-Content -LiteralPath $qpath -Raw | ConvertFrom-Json
if ($q.schema -ne 'heatdrive_ecc_runtime_boundary_warmup_endpoint_v1' -or -not $q.transient_continuation_allowed -or
    -not $q.all_original_packet_gates_pass -or -not $q.all_recorded_boundaries_pass) { throw 'Not a completed gated warmup.' }
foreach($row in $q.files) {
    if ((Get-FileHash -LiteralPath $row.path -Algorithm SHA256).Hash -ne $row.sha256) { throw 'Current qualification dependency changed.' }
}
$archive=Split-Path -Parent $qpath
$planPath=Join-Path $archive 'raw_prefix_retirement_plan.json'
if ((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash -ne $q.obsolete_prefix_raw_retirement_plan_sha256) { throw 'Plan changed.' }
$plan=Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$root=(Resolve-Path -LiteralPath $plan.collection_root).Path
if ((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'No reparse experiment root.' }
if ((Split-Path -Leaf (Split-Path -Parent $root)) -ne 'outputs' -or
    (Get-FileHash -LiteralPath (Join-Path $root 'collection_result.json') -Algorithm SHA256).Hash -ne $plan.collection_result_sha256) { throw 'Collection mismatch.' }
$executionRepo=Split-Path -Parent (Split-Path -Parent $root)
$live=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '(?i)^matlab(?:\.exe)?$' -and $_.CommandLine -and $_.CommandLine.Contains($executionRepo) })
if ($live.Count) { throw 'A checkout MATLAB process is alive.' }
$targets=@()
foreach($row in $plan.files) {
    $file=(Resolve-Path -LiteralPath $row.path).Path
    if (-not $file.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $file) -notin @('observations.mat','observed_states.mat','mechanism_view.mat') -or
        @($q.files | Where-Object path -eq $file).Count) { throw 'Unsafe or qualified target.' }
    $item=Get-Item -LiteralPath $file -Force
    $parent=Get-Item -LiteralPath (Split-Path -Parent $file) -Force
    $packetParent=$parent
    if ($parent.Name -eq 'native') { $packetParent=Get-Item -LiteralPath $parent.Parent.FullName -Force }
    if ($packetParent.Name -notmatch '^packet_C\d+_attempt\d+$' -or $packetParent.Parent.FullName -ne $root -or
        @($item,$parent,$packetParent | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'No directory escape or junction traversal.' }
    $m=Get-Content -LiteralPath (Join-Path $packetParent.FullName 'packet_manifest.json') -Raw | ConvertFrom-Json
    if ($m.window_s[1] -gt $plan.retained_native_window_s[0] -or
        (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $row.sha256) { throw 'Not an obsolete verified raw prefix.' }
    $targets += $file
}
$receiptPath=Join-Path $archive 'raw_prefix_retirement_receipt.json'
if (Test-Path -LiteralPath $receiptPath) { throw 'Never overwrite a retirement receipt.' }
$marker=Join-Path $root 'COMPLETED_RAW_PREFIX_RETIRED.json'
if (Test-Path -LiteralPath $marker) { throw 'Retirement already started; diagnose its receipt.' }
$receipt=[ordered]@{schema='heatdrive_ecc_runtime_raw_prefix_retirement_receipt_v1';status='planned';
    plan_sha256=$q.obsolete_prefix_raw_retirement_plan_sha256;qualification_sha256=$pointer.qualification_sha256;
    retired_bytes=$plan.retire_bytes;retired_files=$targets;retained_native_window_s=$plan.retained_native_window_s;
    complete_OP_deleted_bytes=0;current_raw_deleted_bytes=0;inplace_job_resume_allowed=$false}
$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding utf8
[ordered]@{status='retirement_started';receipt_path=$receiptPath;use_latest_qualified_endpoint=$true;inplace_resume_allowed=$false} |
    ConvertTo-Json | Set-Content -LiteralPath $marker -Encoding utf8
foreach($file in $targets) { Remove-Item -LiteralPath $file -Force }
if ((Get-FileHash -LiteralPath $pointer.operating_point_path -Algorithm SHA256).Hash -ne $pointer.operating_point_sha256) { throw 'Latest OP changed.' }
$receipt.status='completed';$receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding utf8
[ordered]@{status='completed';retired_bytes=$plan.retire_bytes;files=$targets.Count;current_raw_deleted_bytes=0;OP_deleted_bytes=0} | ConvertTo-Json
