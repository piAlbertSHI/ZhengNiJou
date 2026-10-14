param([Parameter(Mandatory=$true)][string]$ExecutionRepo,
      [Parameter(Mandatory=$true)][string]$ArchiveRoot)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $ExecutionRepo).Path
$audit=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\outputs_storage_audit')).Path
$dest=[IO.Path]::GetFullPath($ArchiveRoot)
if (-not $dest.StartsWith($audit+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $dest)) { throw 'Require new bounded archive' }
$run=Join-Path $repo 'outputs\v41_storage_warmup_from_C22_r1'
$gate=Get-Content -LiteralPath (Join-Path $repo 'outputs\v41_storage_mechanism_r1\saved_mechanism_audit.json') -Raw | ConvertFrom-Json
if (-not $gate.mechanism_pass -or @($gate.checks.PSObject.Properties).Count -ne 73 -or
    @($gate.checks.PSObject.Properties | Where-Object Value -ne $true).Count) { throw 'Current mechanism failed' }
New-Item -ItemType Directory -Path $dest | Out-Null
$relative=@('cold_chamber_execution.json','native\diagnostic_state_capture.json','native\arm_completion.json',
    'native\compiled_inventory_tags.json','native\inventory_metadata.json','native\buffer_replacement_contract.json',
    'native\pressure_only_inverse_density_map_1.json','native\pressure_only_inverse_density_map_2.json')
$files=@($relative | ForEach-Object { Join-Path $run $_ })
$files+=@(($run+'.resumed_config.json'),($run+'.matlab_stdout.log'),($run+'.matlab_stderr.log'))
$files+=@(Join-Path $repo 'outputs\v41_storage_mechanism_r1\saved_mechanism_audit.json')
$files+=@(Join-Path $repo 'outputs\v41_storage_periodicity_r1\saved_periodicity_audit.json')
$files+=@(Join-Path $repo 'outputs\v41_storage_thermal_r1\ten_cycle_thermal_periodicity_audit.json')
$copies=@()
foreach ($file in $files) {
    $target=Join-Path $dest (Split-Path $file -Leaf)
    if (Test-Path -LiteralPath $target) { throw 'Archive name collision' }
    Copy-Item -LiteralPath $file -Destination $target
    $hash=(Get-FileHash -LiteralPath $file).Hash
    if ((Get-FileHash -LiteralPath $target).Hash -ne $hash) { throw 'Archive bytes changed' }
    $copies+=[ordered]@{source=$file;archive=$target;sha256=$hash;bytes=(Get-Item -LiteralPath $file).Length}
}
$keep=@()
foreach ($relative in @('native\observations.mat','native\configuration.mat',
    'native\diagnostic_complete_operating_point.mat','native\diagnostic_state_observation.mat')) {
    $path=Join-Path $run $relative;$keep+=[ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash}
}
$retire=@()
foreach ($name in @('v42_storage_native10_from_C42_r1','v42_storage_native10_from_C42_r2')) {
    $failed=Join-Path $repo ('outputs\'+$name)
    if (-not (Test-Path -LiteralPath (Join-Path $failed 'REJECTED_DO_NOT_RESUME.json'))) { throw 'Missing rejection marker' }
    foreach ($relative in @('native\configuration.mat','native\cold_public_targets.mat','native\se_reference_contract.json')) {
        $path=[IO.Path]::GetFullPath((Join-Path $failed $relative));$item=Get-Item -LiteralPath $path
        if ((Split-Path -Parent $path) -ne (Join-Path $failed 'native') -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Escaped or reparse retirement file' }
        $retire+=[ordered]@{path=$path;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $path).Hash}
    }
}
$encoding=New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $dest 'storage_plan.json'),(@{copies=$copies;retain=$keep;retire=$retire}|ConvertTo-Json -Depth 7),$encoding)
foreach ($row in $retire) {
    if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Retirement changed input' }
    Remove-Item -LiteralPath $row.path -Force
}
foreach ($row in $keep) { if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Current raw changed' } }
$bytes=0L;foreach ($row in $retire) { $bytes+=[long]$row.bytes }
$receipt=[ordered]@{schema='heatdrive_ecc_mapped_observation_storage_closeout_v1';current_cycles=42;
    copied_compact_files=$copies;retained_current_raw=$keep;retired_failed_setup=$retire;retired_raw_bytes=$bytes;
    C22_independent_mapping_reference_untouched=$true;C2_C3_untouched=$true;current_raw_single_copy=$true;
    Agent6_untouched=$true;protected_SLX_untouched=$true;production_recovery_allowed=$false}
[IO.File]::WriteAllText((Join-Path $dest 'storage_receipt.json'),($receipt|ConvertTo-Json -Depth 7),$encoding)
[ordered]@{copied_files=$copies.Count;retired_failed_setup_bytes=$bytes;current_cycles=42}|ConvertTo-Json
