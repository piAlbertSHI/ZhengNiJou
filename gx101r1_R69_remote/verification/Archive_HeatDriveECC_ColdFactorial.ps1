[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceRoot,
      [Parameter(Mandatory=$true)][string]$AuditFile,
      [Parameter(Mandatory=$true)][string]$ArchiveRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$audit = Get-Content -LiteralPath $AuditFile -Raw | ConvertFrom-Json
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$destination = [IO.Path]::GetFullPath($ArchiveRoot)
$studyFile = Join-Path $source 'factorial_execution.json'
$study = Get-Content -LiteralPath $studyFile -Raw | ConvertFrom-Json
$names = @('baseline_legacy','baseline_tight','sma_pipe_legacy','sma_pipe_tight')
if ($audit.schema -ne 'heatdrive_ecc_cold_buffer_factorial_audit_v1' -or
    $audit.source_root -ne $source -or
    (Get-FileHash -LiteralPath $studyFile).Hash -ne $audit.input_sha256.factorial_execution -or
    -not $study.collection_pass -or $study.coupled_start_time_s -ne 0 -or $study.coupled_stop_time_s -ne 10 -or
    $study.C200_state_loaded -or $study.C62_state_loaded -or $study.source_state_edited -or
    @($study.cases).Count -ne 4 -or (Compare-Object $names @($study.cases.name)) -or
    (Split-Path -Leaf (Split-Path -Parent $source)) -ne 'outputs' -or
    -not $destination.StartsWith((Join-Path $repo 'outputs_storage_audit')+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $destination)) { throw 'Require a complete independent cold matrix and new bounded archive.' }

function Write-Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
}
function Assert-NoReparse([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    $entries = @($item)
    if ($item.PSIsContainer) { $entries += @(Get-ChildItem -LiteralPath $Path -Force -Recurse) }
    if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
        throw "Reparse point is not eligible for cleanup: $Path"
    }
}
function Assert-C62 {
    $contract = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'current_storage_warmup_contract.json') -Raw | ConvertFrom-Json
    $root = Join-Path $contract.execution_repo $contract.source_root_relative
    $rows = foreach ($kind in @('operating_point','history')) {
        $path = Join-Path $root $contract."${kind}_relative"
        $hash = (Get-FileHash -LiteralPath $path).Hash
        if ($hash -ne $contract."${kind}_sha256") { throw "C62 changed: $kind" }
        [ordered]@{kind=$kind;path=$path;sha256=$hash}
    }
    return @($rows)
}
$before = Assert-C62
Assert-NoReparse $source
$plan = @()
$retained = @()
$compact = @($studyFile,(Join-Path $source 'factorial_progress.json'),$AuditFile,
             ($source+'.matlab_stdout.log'),($source+'.matlab_stderr.log'))
foreach ($name in $names) {
    $case = Join-Path $source $name
    $arm = Join-Path $case 'native'
    $entry = @($study.cases | Where-Object name -eq $name)[0]
    if ($entry.source_root -ne $case -or (Get-FileHash -LiteralPath $entry.config_path).Hash -ne $entry.config_sha256 -or
        (Get-FileHash -LiteralPath (Join-Path $case 'cold_chamber_execution.json')).Hash -ne $entry.execution_sha256) {
        throw "Changed case contract: $name"
    }
    foreach ($property in $audit.cases.$name.input_sha256.PSObject.Properties) {
        if ((Get-FileHash -LiteralPath (Join-Path $arm $property.Name)).Hash -ne $property.Value) {
            throw "Changed evidence: $name/$($property.Name)"
        }
    }
    $mechanism = Get-Content -LiteralPath (Join-Path $arm 'cold_mechanism_audit.json') -Raw | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath (Join-Path $arm 'cold_mechanism_observation.mat')).Hash -ne $mechanism.observation_sha256) {
        throw "Changed original mechanism view: $name"
    }
    $compact += $entry.config_path
    $compact += @(Get-ChildItem -LiteralPath $case -File | Where-Object Extension -in '.json','.log','.txt' | ForEach-Object FullName)
    $compact += @(Get-ChildItem -LiteralPath $arm -File | Where-Object Extension -in '.json','.txt','.csv' | ForEach-Object FullName)
    foreach ($cacheName in @('cache','codegen')) {
        $target = [IO.Path]::GetFullPath((Join-Path $case $cacheName))
        if ((Split-Path -Parent $target) -ne $case) { throw 'Cache path escaped exact case.' }
        if (Test-Path -LiteralPath $target) {
            Assert-NoReparse $target
            $files = @(Get-ChildItem -LiteralPath $target -Recurse -File -Force)
            $bytes = 0L
            foreach ($file in $files) { $bytes += $file.Length }
            $plan += [ordered]@{path=$target;bytes=$bytes;file_count=$files.Count}
        }
    }
    foreach ($item in Get-ChildItem -LiteralPath $case -Recurse -File -Force) {
        if ($item.FullName.StartsWith($case+'\cache\',[StringComparison]::OrdinalIgnoreCase) -or
            $item.FullName.StartsWith($case+'\codegen\',[StringComparison]::OrdinalIgnoreCase)) { continue }
        $retained += [ordered]@{path=$item.FullName;bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $item.FullName).Hash}
    }
}
New-Item -ItemType Directory -Path $destination | Out-Null
Write-Json (Join-Path $destination 'cache_retirement_plan.json') $plan
$copies = @()
foreach ($file in $compact | Select-Object -Unique) {
    $item = Get-Item -LiteralPath $file
    if ($item.Length -gt 8MB) { throw 'Compact archive cannot duplicate large raw.' }
    $relative = if ($file.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)) {
        $file.Substring($source.Length+1)
    } else { $item.Name }
    $target = Join-Path $destination $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $file -Destination $target
    $hash = (Get-FileHash -LiteralPath $file).Hash
    if ((Get-FileHash -LiteralPath $target).Hash -ne $hash) { throw 'Compact copy changed bytes.' }
    $copies += [ordered]@{source=$file;archive_relative=$relative;bytes=$item.Length;sha256=$hash}
}
foreach ($row in $plan) {
    Assert-NoReparse $row.path
    Remove-Item -LiteralPath $row.path -Recurse -Force
}
$after = Assert-C62
$retiredBytes = 0L
foreach ($row in $plan) { $retiredBytes += $row.bytes }
$receipt = [ordered]@{schema='heatdrive_ecc_cold_factorial_compact_archive_v1';source_root=$source;
    compact_copies=$copies;retained_single_execution_copy=$retained;deleted_cache=$plan;
    retired_cache_bytes=$retiredBytes;retired_raw_bytes=0;
    C62_before=$before;C62_after=$after;C62_unchanged=$true;C200_untouched=$true;Agent6_untouched=$true;
    original_rejection_markers_retained=$true;simulation_rerun=$false;production_recovery_allowed=$false}
Write-Json (Join-Path $destination 'storage_receipt.json') $receipt
[ordered]@{compact_copies=$copies.Count;retained_files=$retained.Count;retired_cache_bytes=$receipt.retired_cache_bytes;
    retired_raw_bytes=0;C62_unchanged=$true} | ConvertTo-Json
