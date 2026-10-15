[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ExecutionRepo,
      [Parameter(Mandatory=$true)][string]$SourceRoot,
      [Parameter(Mandatory=$true)][string]$MechanismRoot,
      [Parameter(Mandatory=$true)][string]$PairRoot,
      [Parameter(Mandatory=$true)][string]$ThermalRoot,
      [Parameter(Mandatory=$true)][string]$QualificationFile,
      [Parameter(Mandatory=$true)][string]$TypedGuardFile,
      [Parameter(Mandatory=$true)][string]$ArchiveRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath $ExecutionRepo).Path
$source=(Resolve-Path -LiteralPath $SourceRoot).Path
$audit=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\outputs_storage_audit')).Path
$destination=[IO.Path]::GetFullPath($ArchiveRoot)
if ((Split-Path -Parent $source) -ne (Join-Path $repo 'outputs') -or
    -not $destination.StartsWith($audit+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $destination)) { throw 'Require exact existing source and new bounded archive.' }
$qualification=Get-Content -LiteralPath $QualificationFile -Raw | ConvertFrom-Json
$typed=Get-Content -LiteralPath $TypedGuardFile -Raw | ConvertFrom-Json
$mechanism=Get-Content -LiteralPath (Join-Path $MechanismRoot 'saved_mechanism_audit.json') -Raw | ConvertFrom-Json
if ($qualification.source_root -ne $source -or -not $qualification.qualification_pass -or
    -not $typed.actual_vendor_OP_loaded -or $typed.total_cycles -ne $qualification.total_cycles -or
    $typed.simulation_executed -or $typed.source_state_edited -or
    -not $mechanism.mechanism_pass -or @($mechanism.checks.PSObject.Properties).Count -ne 73 -or
    @($mechanism.checks.PSObject.Properties | Where-Object Value -ne $true).Count) {
    throw 'Current complete state and mechanism evidence required.'
}
$relative=@('cold_chamber_execution.json','native\diagnostic_state_capture.json','native\arm_completion.json',
    'native\compiled_inventory_tags.json','native\buffer_replacement_contract.json',
    'native\pressure_only_inverse_density_map_1.json','native\pressure_only_inverse_density_map_2.json',
    'native\native_transport_configuration.json','native\postprocessing_profile.json')
$files=@($relative | ForEach-Object { Join-Path $source $_ })
$files+=@(($source+'.resumed_config.json'),($source+'.matlab_stdout.log'),($source+'.matlab_stderr.log'))
$files+=@(Join-Path $MechanismRoot 'saved_mechanism_audit.json')
$files+=@(Join-Path $MechanismRoot 'physical_validation_report.txt')
$files+=@(Join-Path $PairRoot 'saved_periodicity_audit.json')
$files+=@(Join-Path $ThermalRoot 'ten_cycle_thermal_periodicity_audit.json')
$files+=@($QualificationFile,$TypedGuardFile)
New-Item -ItemType Directory -Path $destination | Out-Null
$copies=@()
foreach ($file in $files) {
    $item=Get-Item -LiteralPath $file
    if ($item.Length -gt 8MB) { throw 'Compact archive must not duplicate raw matrices.' }
    $target=Join-Path $destination $item.Name
    if (Test-Path -LiteralPath $target) { throw 'Archive name collision.' }
    Copy-Item -LiteralPath $file -Destination $target
    $hash=(Get-FileHash -LiteralPath $file).Hash
    if ((Get-FileHash -LiteralPath $target).Hash -ne $hash) { throw 'Copied bytes changed.' }
    $copies+=[ordered]@{source=$file;archive=$target;bytes=$item.Length;sha256=$hash}
}
$raw=@()
foreach ($name in @('observations.mat','configuration.mat','diagnostic_state_observation.mat',
                   'diagnostic_complete_operating_point.mat')) {
    $file=Join-Path $source ('native\'+$name)
    $raw+=[ordered]@{path=$file;bytes=(Get-Item -LiteralPath $file).Length;
        sha256=(Get-FileHash -LiteralPath $file).Hash;classification='retained_single_execution_copy'}
}
if (($raw | Where-Object { $_.path.EndsWith('diagnostic_complete_operating_point.mat') }).sha256 -ne $typed.operating_point_sha256 -or
    ($raw | Where-Object { $_.path.EndsWith('diagnostic_state_observation.mat') }).sha256 -ne $typed.history_sha256) {
    throw 'Typed source hashes changed.'
}
$receipt=[ordered]@{schema='heatdrive_ecc_qualified_segment_compact_archive_v1';source_root=$source;
    total_cycles=$typed.total_cycles;copies=$copies;retained_raw=$raw;deleted_files=@();
    C200_untouched=$true;ancestor_dependencies_untouched=$true;Agent6_untouched=$true;
    production_recovery_allowed=$false;outer_solve_eligible=$false}
[IO.File]::WriteAllText((Join-Path $destination 'storage_receipt.json'),
    ($receipt|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
[ordered]@{compact_copies=$copies.Count;retained_raw_files=$raw.Count;total_cycles=$typed.total_cycles}|ConvertTo-Json
