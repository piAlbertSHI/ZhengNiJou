param(
    [Parameter(Mandatory=$true)][string]$ExecutionRepo,
    [Parameter(Mandatory=$true)][string]$ArchiveRoot
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath $ExecutionRepo).Path
$root = Join-Path $repo 'outputs\v40_storage_warmup_r1'
$source = Join-Path $repo 'outputs\v39_density_c2_r1\candidate'
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Missing interrupted experiment' }
if (Test-Path -LiteralPath $ArchiveRoot) { throw 'Never overwrite a closeout' }
foreach ($relative in @('native\diagnostic_complete_operating_point.mat','cold_chamber_execution.json','native\observations.mat')) {
    if (Test-Path -LiteralPath (Join-Path $root $relative)) { throw 'Unexpected completed evidence; reassess rather than classify incomplete' }
}
$capture = Get-Content -LiteralPath (Join-Path $source 'native\diagnostic_state_capture.json') -Raw | ConvertFrom-Json
$op = Join-Path $source 'native\diagnostic_complete_operating_point.mat'
$history = Join-Path $source 'native\diagnostic_state_observation.mat'
if ((Get-FileHash -LiteralPath $op -Algorithm SHA256).Hash -ne $capture.operating_point_sha256 -or
    (Get-FileHash -LiteralPath $history -Algorithm SHA256).Hash -ne $capture.history_sha256) { throw 'Recovery source changed' }
$events = @(Get-WinEvent -FilterHashtable @{
    LogName='System'; StartTime=[datetime]'2026-10-14 05:20:00'; EndTime=[datetime]'2026-10-14 06:05:00'
} | Where-Object { $_.Id -eq 1074 } | Select-Object TimeCreated, Id, ProviderName, Message)
if ($events.Count -lt 1) { throw 'No authoritative system restart event' }
$receipt = [ordered]@{
    schema='heatdrive_ecc_external_restart_interruption_v1'
    experiment_root=$root; execution_commit='8d499b0'; session_id=23338
    terminal_exit_code=1073807364; interrupted_by_windows_update_restart=$true
    system_restart_events=$events; stderr_bytes=(Get-Item -LiteralPath ($root + '.matlab_stderr.log')).Length
    requested_window_s=@(20,220); new_complete_checkpoint_saved=$false
    scientific_mechanism_failure_demonstrated=$false; failed_state_propagated=$false
    safe_source_root=$source; safe_source_time_s=20
    safe_operating_point_sha256=$capture.operating_point_sha256; safe_history_sha256=$capture.history_sha256
    source_state_edited=$false; production_recovery_allowed=$false
    classification='incomplete setup evidence, not a continuation source'
    raw_retired_bytes=0; completed_results_claimed=$false
}
New-Item -ItemType Directory -Path $ArchiveRoot | Out-Null
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $root 'INCOMPLETE_DO_NOT_RESUME.json'), ($receipt | ConvertTo-Json -Depth 8), $encoding)
$files = @(
    (Join-Path $root 'INCOMPLETE_DO_NOT_RESUME.json'),
    ($root + '.resumed_config.json'), ($root + '.matlab_stdout.log'), ($root + '.matlab_stderr.log'),
    (Join-Path $root 'native\simulation_start.json'), (Join-Path $root 'native\pressure_only_inverse_density_map_1.json'),
    (Join-Path $root 'native\pressure_only_inverse_density_map_2.json')
)
$archived = @()
foreach ($file in $files) {
    $target = Join-Path $ArchiveRoot (Split-Path $file -Leaf)
    Copy-Item -LiteralPath $file -Destination $target
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash) { throw 'Archive changed bytes' }
    $archived += [ordered]@{source=$file; archive=$target; sha256=$hash; bytes=(Get-Item -LiteralPath $file).Length}
}
$receipt.archived_files=$archived
[System.IO.File]::WriteAllText((Join-Path $ArchiveRoot 'interruption_receipt.json'), ($receipt | ConvertTo-Json -Depth 8), $encoding)
$receipt | ConvertTo-Json -Depth 8
