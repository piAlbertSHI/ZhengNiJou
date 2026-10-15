[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ExecutionOutputs,
    [Parameter(Mandatory=$true)][string]$EndpointContract,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$outputs=(Resolve-Path -LiteralPath $ExecutionOutputs).Path
if ((Split-Path -Leaf $outputs) -ne 'outputs') { throw 'Require the explicit execution outputs directory.' }
$archive=[IO.Path]::GetFullPath($OutputRoot)
$repo=Split-Path -Parent $PSScriptRoot
if ((Split-Path -Parent $archive) -ne (Join-Path $repo 'outputs_storage_audit')) { throw 'Archive must be local.' }
if (Test-Path -LiteralPath $archive) { throw 'Never overwrite a probe archive.' }
$point=Get-Content -LiteralPath $EndpointContract -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $point.operating_point_path -Algorithm SHA256).Hash -ne $point.operating_point_sha256) { throw 'C72 changed.' }
$executionRepo=Split-Path -Parent $outputs
$live=@(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match '(?i)^matlab(?:\.exe)?$' -and $_.CommandLine -and $_.CommandLine.Contains($executionRepo)
})
if ($live.Count) { throw 'An execution-checkout MATLAB process is still alive.' }
New-Item -ItemType Directory -Path $archive | Out-Null
$copies=@();$retire=@();$targets=@();$studies=@()
foreach ($name in @('v49_C72_boundary_parameter_r1','v49_C72_boundary_parameter_r2')) {
    $root=(Resolve-Path -LiteralPath (Join-Path $outputs $name)).Path
    if ((Split-Path -Parent $root) -ne $outputs) { throw 'Escaped experiment root.' }
    $probeRoot=Join-Path $root 'native\boundary_parameter_probe'
    $probe=Get-Content -LiteralPath (Join-Path $probeRoot 'boundary_parameter_probe.json') -Raw | ConvertFrom-Json
    $execution=Get-Content -LiteralPath (Join-Path $root 'cold_chamber_execution.json') -Raw | ConvertFrom-Json
    if ($probe.schema -ne 'heatdrive_ecc_C72_boundary_parameter_probe_v1' -or
        $probe.source_OP_sha256 -ne $point.operating_point_sha256 -or $probe.new_OP_saved -or
        (-not $probe.experiment_completed -and [string]::IsNullOrWhiteSpace($execution.error_message))) { throw 'Not a terminal C72 interface probe.' }
    $studies += [ordered]@{root=$root;experiment_completed=$probe.experiment_completed;
        execution_sha256=(Get-FileHash -LiteralPath (Join-Path $root 'cold_chamber_execution.json') -Algorithm SHA256).Hash}
    $files=@(Get-ChildItem -LiteralPath $probeRoot -Recurse -File | Where-Object { $_.Extension -eq '.json' })
    foreach ($suffix in @('.stdout.log','.stderr.log','.preflight_config.json')) {
        $sidecar=$root+$suffix
        if (Test-Path -LiteralPath $sidecar) { $files += Get-Item -LiteralPath $sidecar }
    }
    foreach ($file in $files) {
        if ($file.Length -gt 1MB) { throw 'Unexpected noncompact probe record.' }
        $relative=$file.FullName.Substring($root.Length).TrimStart('\')
        if (-not $relative -or $file.FullName.StartsWith($root+'.')) { $relative=$file.Name }
        $destination=Join-Path (Join-Path $archive $name) $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination
        $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $hash) { throw 'Copy mismatch.' }
        $copies += [ordered]@{path=$file.FullName;archive_path=$destination;bytes=$file.Length;sha256=$hash}
    }
    foreach ($leaf in @('cache','codegen','component_build','buffer_component_build')) {
        $target=[IO.Path]::GetFullPath((Join-Path $root $leaf))
        if ((Split-Path -Parent $target) -ne $root -or -not $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cache target.' }
        if (-not (Test-Path -LiteralPath $target)) { continue }
        $entries=@(Get-Item -LiteralPath $target -Force)+@(Get-ChildItem -LiteralPath $target -Recurse -Force)
        if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'No junction traversal.' }
        foreach ($file in $entries | Where-Object { -not $_.PSIsContainer }) {
            if ($file.Name -in @('observations.mat','observed_states.mat','comparison_only_complete_op.mat','physical_simscape_result.mat')) { throw 'Unexpected scientific raw in build cache.' }
            $retire += [ordered]@{path=$file.FullName;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
        }
        $targets += $target
    }
}
$bytes=0L;foreach($row in $retire){$bytes += $row.bytes}
$receipt=[ordered]@{schema='heatdrive_ecc_boundary_probe_archive_and_cache_retirement_v1';status='planned';
    studies=$studies;compact_copies=$copies;retired_build_cache_files=$retire;targets=$targets;
    retired_build_cache_bytes=$bytes;raw_deleted_bytes=0;complete_OP_deleted_bytes=0;
    C72_sha256=$point.operating_point_sha256;Agent6_untouched=$true}
$receiptPath=Join-Path $archive 'storage_receipt.json'
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
foreach($target in $targets){Remove-Item -LiteralPath $target -Recurse -Force}
if ((Get-FileHash -LiteralPath $point.operating_point_path -Algorithm SHA256).Hash -ne $point.operating_point_sha256) { throw 'C72 changed during archival.' }
$receipt.status='completed';$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8
[ordered]@{status='completed';compact_files=$copies.Count;retired_build_cache_bytes=$bytes;raw_deleted_bytes=0} | ConvertTo-Json
