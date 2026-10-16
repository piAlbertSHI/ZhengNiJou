[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$catalogPath=Join-Path $PSScriptRoot 'runtime_Tc_trial_catalog.json'
$catalog=Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$out=[IO.Path]::GetFullPath($OutputRoot)
if ((Split-Path -Parent $out) -ne (Join-Path $repo 'outputs_storage_audit') -or (Test-Path -LiteralPath $out)) {
    throw 'Require a fresh local retirement archive.'
}
$protected=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$points=@($catalog.latest_same_Tc_continuations)+@($catalog.bounded_search_candidates)
$p=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'current_runtime_boundary_warmup.json') -Raw | ConvertFrom-Json
$points+= $p
foreach($point in $points) {
    $path=Join-Path $repo $point.qualification_relative
    if ((Get-FileHash -LiteralPath $path).Hash -ne $point.qualification_sha256) { throw 'Changed current qualification.' }
    $q=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($q.source_state_edited -or (Get-FileHash -LiteralPath $q.operating_point_path).Hash -ne $q.operating_point_sha256) {
        throw 'Changed current complete state.'
    }
    [void]$protected.Add([IO.Path]::GetFullPath($path))
    [void]$protected.Add([IO.Path]::GetFullPath($q.operating_point_path))
    foreach($row in $q.files) {
        if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Changed current dependency.' }
        [void]$protected.Add([IO.Path]::GetFullPath($row.path))
    }
}
$live=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '(?i)^matlab\.exe$' -and
    $_.CommandLine -and $_.CommandLine -match 'Run_HeatDriveECC_Runtime|Load_HeatDriveECC_GatedObservationPacket' })
if ($live.Count) { throw 'A related runtime command is alive; do not retire source observations.' }
$targets=@();$jobs=@()
foreach($point in $catalog.trials) {
    $oldPath=Join-Path $repo $point.qualification_relative
    if ((Get-FileHash -LiteralPath $oldPath).Hash -ne $point.qualification_sha256) { throw 'Changed historical qualification.' }
    $old=Get-Content -LiteralPath $oldPath -Raw | ConvertFrom-Json
    $new=@($catalog.latest_same_Tc_continuations | Where-Object temperature_K -eq $old.temperature_K)
    if ($new.Count -ne 1 -or $new[0].snapshot_time_s -le $old.snapshot_time_s) { throw 'No later same-Tc replacement.' }
    $current=Get-Content -LiteralPath (Join-Path $repo $new[0].qualification_relative) -Raw | ConvertFrom-Json
    if (-not $current.same_Tc_continuation -or -not $current.original_public_thermal_periodic_pass -or
        -not $current.bounded_outer_metric_sampling_allowed -or
        $current.boundary_trial.source_complete_OP_sha256 -ne $old.boundary_trial.source_complete_OP_sha256 -or
        @($current.files | Where-Object sha256 -eq $point.qualification_sha256).Count -eq 0) {
        throw 'The later qualified endpoint must retain the exact old source ancestry.'
    }
    foreach($row in $old.files) {
        if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Historical raw already changed; inspect old receipts.' }
    }
    $records=@($old.files | Where-Object { (Split-Path -Leaf $_.path) -eq 'collection_result.json' })
    if ($records.Count -ne 1) { throw 'Ambiguous historical collection.' }
    $root=(Resolve-Path -LiteralPath (Split-Path -Parent $records[0].path)).Path
    $record=Get-Content -LiteralPath $records[0].path -Raw | ConvertFrom-Json
    $marker=Join-Path $root 'COMPLETED_RAW_PREFIX_RETIRED.json'
    if ((Split-Path -Leaf (Split-Path -Parent $root)) -ne 'outputs' -or -not $record.pass -or
        $record.last_verified_snapshot_time_s -ne $old.snapshot_time_s -or (Test-Path -LiteralPath $marker)) {
        throw 'Not an intact completed superseded collection.'
    }
    # Keep the first full packet: it is the unique external temperature event.
    foreach($packet in @($record.completed_packets | Select-Object -Skip 1)) {
        foreach($name in @('native\observations.mat','observed_states.mat')) {
            $path=[IO.Path]::GetFullPath((Join-Path $packet.packet_root $name))
            if (-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase) -or $protected.Contains($path)) {
                throw 'Escaped target or current qualified dependency.'
            }
            $ancestor=$path
            while ($ancestor -and $ancestor.Length -ge $root.Length) {
                $item=Get-Item -LiteralPath $ancestor
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'No reparse traversal.' }
                $ancestor=Split-Path -Parent $ancestor
            }
            $expected=@($old.files | Where-Object path -eq $path)
            if ($expected.Count -ne 1 -or (Get-FileHash -LiteralPath $path).Hash -ne $expected[0].sha256) {
                throw 'Only exact old qualified raw may be retired.'
            }
            $targets+= [ordered]@{path=$path;bytes=(Get-Item -LiteralPath $path).Length;sha256=$expected[0].sha256}
        }
    }
    $jobs+= [ordered]@{collection=$root;historical_qualification=$oldPath;historical_qualification_sha256=$point.qualification_sha256;
        replacement_qualification=(Join-Path $repo $new[0].qualification_relative);marker=$marker}
}
if (-not $targets.Count) { throw 'No reviewed superseded raw.' }
New-Item -ItemType Directory -Path $out | Out-Null
Copy-Item -LiteralPath $catalogPath -Destination (Join-Path $out 'catalog_at_retirement.json')
$receiptPath=Join-Path $out 'retirement_receipt.json'
$receipt=[ordered]@{schema='heatdrive_ecc_runtime_Tc_superseded_raw_retirement_v1';status='planned';
    catalog_sha256=(Get-FileHash -LiteralPath $catalogPath).Hash;files=$targets;jobs=$jobs;deleted_files=0;retired_bytes=0;
    first_temperature_event_packets_retained=$true;all_complete_OPs_retained=$true;all_compact_results_retained=$true;
    old_qualifications_now_historical_not_full_raw_reverifiable=$true;current_qualified_raw_deleted_bytes=0}
$receipt | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $receiptPath -Encoding utf8
foreach($job in $jobs) {
    [ordered]@{status='superseded_raw_retirement_started';receipt=$receiptPath;use_latest_qualified_endpoint=$true;
        inplace_resume_allowed=$false;historical_raw_reverification_available=$false} |
        ConvertTo-Json | Set-Content -LiteralPath $job.marker -Encoding utf8
}
foreach($target in $targets) {
    if ((Get-FileHash -LiteralPath $target.path).Hash -ne $target.sha256) { throw 'Target changed after planning.' }
    Remove-Item -LiteralPath $target.path
    $receipt.deleted_files++;$receipt.retired_bytes+=$target.bytes
    $receipt | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $receiptPath -Encoding utf8
}
foreach($point in $points) {
    $q=Get-Content -LiteralPath (Join-Path $repo $point.qualification_relative) -Raw | ConvertFrom-Json
    foreach($row in $q.files) {
        if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Post-retirement current dependency changed.' }
    }
}
$receipt.status='completed'
$receipt | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $receiptPath -Encoding utf8
[ordered]@{status='completed';retired_bytes=$receipt.retired_bytes;deleted_files=$receipt.deleted_files;
    first_events_retained=$true;OP_deleted_bytes=0;current_raw_deleted_bytes=0} | ConvertTo-Json
