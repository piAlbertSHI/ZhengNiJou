param([Parameter(Mandatory=$true)][string]$ExecutionRepo,
      [Parameter(Mandatory=$true)][string]$ArchiveRoot)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $ExecutionRepo).Path
$run=Join-Path $repo 'outputs\v40_storage_warmup_r2'
$old=Join-Path $repo 'outputs\v40_storage_warmup_r1'
$audit=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\outputs_storage_audit')).Path
$destination=[IO.Path]::GetFullPath($ArchiveRoot)
if (-not $destination.StartsWith($audit+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $destination)) { throw 'Require a new bounded archive' }
$science=Get-Content -LiteralPath (Join-Path $audit 'v40_storage_warmup_science_20261014.json') -Raw | ConvertFrom-Json
$mechanism=Get-Content -LiteralPath (Join-Path $repo 'outputs\v40_storage_mechanism_r1\saved_mechanism_audit.json') -Raw | ConvertFrom-Json
if ($science.source_root -ne $run -or -not $science.modeled_energy_balance.model_equation_energy_closure_pass -or
    -not $mechanism.mechanism_pass -or @($mechanism.checks.PSObject.Properties).Count -ne 73 -or
    @($mechanism.checks.PSObject.Properties | Where-Object Value -ne $true).Count) { throw 'Incomplete current scientific closeout' }
New-Item -ItemType Directory -Path $destination | Out-Null
$relative=@('cold_chamber_execution.json','native\diagnostic_state_capture.json','native\arm_completion.json',
    'native\compiled_inventory_tags.json','native\pressure_only_inverse_density_map_1.json',
    'native\pressure_only_inverse_density_map_2.json','native\pump_pressure_probe_contract.json',
    'native\stage4_controller_probe_contract.json','native\native_transport_configuration.json',
    'native\postprocessing_profile.json','native\diagnostic_state_type_validation.json')
$files=@($relative | ForEach-Object { Join-Path $run $_ })
$files+=@(($run+'.resumed_config.json'),($run+'.matlab_stdout.log'),($run+'.matlab_stderr.log'))
$files+=@(Join-Path $repo 'outputs\v40_storage_mechanism_r1\saved_mechanism_audit.json')
$files+=@(Join-Path $repo 'outputs\v40_storage_mechanism_r1\physical_validation_report.txt')
$files+=@(Join-Path $repo 'outputs\v40_storage_periodicity_r1\saved_periodicity_audit.json')
$files+=@(Join-Path $repo 'outputs\v40_storage_thermal_r1\ten_cycle_thermal_periodicity_audit.json')
$files+=@(Join-Path $repo 'outputs\v40_storage_endpoint_guard_r1\actual_endpoint_guard.json')
$copies=@()
foreach ($file in $files) {
    $target=Join-Path $destination (Split-Path $file -Leaf)
    if (Test-Path -LiteralPath $target) { throw 'Archive basename collision' }
    Copy-Item -LiteralPath $file -Destination $target
    $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $hash) { throw 'Archive bytes changed' }
    $copies += [ordered]@{source=$file;archive=$target;sha256=$hash;bytes=(Get-Item -LiteralPath $file).Length}
}
$retired=@()
if (-not (Test-Path -LiteralPath (Join-Path $old 'INCOMPLETE_DO_NOT_RESUME.json'))) { throw 'Missing interrupted marker' }
foreach ($relative in @('native\configuration.mat','native\cold_public_targets.mat','native\se_reference_contract.json')) {
    $path=[IO.Path]::GetFullPath((Join-Path $old $relative))
    if ((Split-Path -Parent $path) -ne (Join-Path $old 'native')) { throw 'Escaped exact obsolete file' }
    $item=Get-Item -LiteralPath $path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse file rejected' }
    $retired += [ordered]@{path=$path;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $path).Hash;
        reason='Reboot-interrupted setup only; no observations or OP; config recipe and exact completed C22 setup retained'}
}
$keep=@()
foreach ($file in @('native\observations.mat','native\configuration.mat',
    'native\diagnostic_complete_operating_point.mat','native\diagnostic_state_observation.mat')) {
    $path=Join-Path $run $file
    $keep += [ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash;bytes=(Get-Item -LiteralPath $path).Length}
}
$encoding=New-Object System.Text.UTF8Encoding($false)
$plan=[ordered]@{copies=$copies;retire=$retired;retain_current=$keep;source_state_edited=$false}
[IO.File]::WriteAllText((Join-Path $destination 'storage_plan.json'),($plan | ConvertTo-Json -Depth 7),$encoding)
foreach ($row in $retired) {
    if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Retirement input changed' }
    Remove-Item -LiteralPath $row.path -Force
    if (Test-Path -LiteralPath $row.path) { throw 'File retirement incomplete' }
}
foreach ($row in $keep) {
    if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Retained current raw changed' }
}
$bytes=0L;foreach ($row in $retired) { $bytes+=[long]$row.bytes }
$receipt=[ordered]@{schema='heatdrive_ecc_storage_warmup_closeout_v1';total_cycles=22;
    copied_compact_files=$copies;retired_interrupted_setup=$retired;retired_raw_bytes=$bytes;
    retained_current_raw=$keep;current_raw_single_execution_copy=$true;
    C2_C3_dependencies_untouched=$true;Agent6_untouched=$true;protected_SLX_untouched=$true;
    periodic_steady_state_claim=$false;production_recovery_allowed=$false;outer_solve_eligible=$false}
[IO.File]::WriteAllText((Join-Path $destination 'storage_receipt.json'),($receipt | ConvertTo-Json -Depth 7),$encoding)
[ordered]@{compact_files=$copies.Count;retired_raw_bytes=$bytes;current_raw_preserved=$true} | ConvertTo-Json
