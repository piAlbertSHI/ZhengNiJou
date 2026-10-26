$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$out = Join-Path $repo 'outputs_storage_audit\shared_endpoint_inventory_C2_20261026_r2'
$receipt = Join-Path $out 'generated_retirement_receipt.json'
if (Test-Path -LiteralPath $receipt) { throw 'A retirement receipt already exists; do not repeat.' }
$manifest = Get-Content -LiteralPath (Join-Path $out 'generated_intermediate_candidates.json') -Raw | ConvertFrom-Json
$closeout = Get-Content -LiteralPath (Join-Path $out 'closeout_verification.json') -Raw | ConvertFrom-Json
$roots = @('C:\tmp\se21_shared_endpoint_inventory_smoke_r1_20261026',
    'C:\tmp\se21_shared_endpoint_inventory_smoke_r2_20261026',
    'C:\tmp\se21_shared_endpoint_inventory_C2_r1_20261026')

function Assert-Hash($row) {
    if ((Get-FileHash -LiteralPath $row.path -Algorithm SHA256).Hash -ne $row.sha256) {
        throw "Protected or generated file changed: $($row.path)"
    }
}

$running = @(Get-CimInstance Win32_Process -Filter "Name = 'MATLAB.exe'")
foreach ($p in $running) {
    foreach ($root in $roots) {
        if ($p.CommandLine -and $p.CommandLine.Replace('/','\').Contains($root)) {
            throw "An experiment is still live: $($p.ProcessId)"
        }
    }
}
$protected = @($manifest.expected_raw_before_after) + @($closeout.frozen_baseline_dependencies_reverified |
    Where-Object { $_.path -match 'physical_simscape_result\.mat$|final_operating_point\.mat$' })
$protected += [pscustomobject]@{path=(Join-Path $repo 'heatdrive_ecc_coupled_se21.slx');sha256=$closeout.protected_model_sha256}
foreach ($row in $protected) { Assert-Hash $row }

foreach ($candidate in $manifest.candidates) {
    $root = [IO.Path]::GetFullPath($candidate.workspace_root)
    $target = [IO.Path]::GetFullPath($candidate.path)
    if ($root -notin $roots) { throw 'Unknown experiment root.' }
    $allowed = @('cache','codegen','shared\seed') | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $root $_)) }
    if ($target -notin $allowed -or -not $target.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw "Generated target is outside the explicit workspace boundary: $target"
    }
    $ancestor = Get-Item -LiteralPath $target -Force
    while ($null -ne $ancestor) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Do not traverse a junction or symlink.' }
        $ancestor = $ancestor.Parent
    }
    $all = @(Get-ChildItem -LiteralPath $target -Recurse -Force)
    if (@($all | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Linked descendant.' }
    $actual = @($all | Where-Object { -not $_.PSIsContainer })
    if ($actual.Count -ne @($candidate.files).Count) { throw 'Generated file count changed.' }
    foreach ($row in $candidate.files) {
        $path = [IO.Path]::GetFullPath($row.path)
        if (-not $path.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Manifest file escaped target.' }
        if ((Get-Item -LiteralPath $path).Length -ne $row.bytes) { throw 'Generated size changed.' }
        Assert-Hash $row
    }
}

$deleted = @(); $freed = [int64]0; $failure = $null
try {
    foreach ($candidate in $manifest.candidates) {
        Remove-Item -LiteralPath $candidate.path -Recurse -Force
        if (Test-Path -LiteralPath $candidate.path) { throw 'Generated target was not removed.' }
        $deleted += $candidate.path
        $freed += [int64]$candidate.bytes
    }
    foreach ($row in $protected) { Assert-Hash $row }
} catch {
    $failure = $_.Exception.Message
} finally {
    $result = [ordered]@{schema='heatdrive_ecc_shared_endpoint_generated_retirement_v1';
        complete=($null -eq $failure);deleted_directories=$deleted;reclaimed_bytes=$freed;
        protected_files=$protected;protected_hashes_verified_after=($null -eq $failure);failure=$failure;
        raw_result_or_checkpoint_deleted=$false;unrelated_process_or_Agent6_touched=$false}
    [IO.File]::WriteAllText($receipt,($result | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
}
if ($failure) { throw $failure }
$result | ConvertTo-Json -Depth 3
