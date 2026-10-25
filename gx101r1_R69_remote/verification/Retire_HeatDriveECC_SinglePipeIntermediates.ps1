[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ReviewDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$review = (Resolve-Path -LiteralPath $ReviewDirectory).Path
$auditPath = Join-Path $review 'single_pipe_runtime_review.json'
$audit = Get-Content -LiteralPath $auditPath -Raw | ConvertFrom-Json
if ($audit.schema -ne 'heatdrive_ecc_single_pipe_runtime_review_v1' -or
    -not $audit.passive_probe_comparison_verified -or $audit.cases.Count -ne 12) {
    throw 'Require the completed independently checked single-pipe fixture.'
}
$receipt = Join-Path $review 'intermediate_retirement_receipt.json'
if (Test-Path -LiteralPath $receipt) { throw 'Never overwrite a retirement receipt.' }
$current = (Resolve-Path -LiteralPath 'C:\tmp\se21_single_pipe_heat_step_r3_20261025').Path
$failed = (Resolve-Path -LiteralPath 'C:\tmp\se21_single_pipe_heat_step_r2_20261025').Path
$oldReview = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $review) 'single_pipe_heat_step_20261025_r3'))
if ((Split-Path -Leaf $review) -ne 'single_pipe_heat_step_20261025_r3_review2') {
    throw 'Only the explicitly superseding review is accepted.'
}
$executionPath = Join-Path $current 'single_pipe_execution.json'
$execution = Get-Content -LiteralPath $executionPath -Raw | ConvertFrom-Json
if (-not $execution.collection_pass -or $execution.cases.Count -ne 12 -or
    (Get-FileHash -LiteralPath $executionPath).Hash -ne $audit.execution_sha256) {
    throw 'Completed execution identity mismatch.'
}
$running = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -ieq 'MATLAB.exe' -and $_.CommandLine -and
    $_.CommandLine.Contains('se21_single_pipe_heat_step_')
})
if ($running.Count) { throw 'A single-pipe MATLAB process is still running.' }
$protected = @($executionPath, $auditPath,
    (Join-Path $failed 'single_pipe_execution.json'),
    'C:\tmp\se21_single_pipe_heat_step_r1_20261025\single_pipe_execution.json',
    (Join-Path $review 'Fig01_single_pipe_heat_steps.png'),
    (Join-Path $review 'Fig01_single_pipe_heat_steps.svg'))
foreach ($case in $execution.cases) {
    $path = [IO.Path]::GetFullPath((Join-Path $current $case.file))
    if ((Split-Path -Parent $path) -ne $current -or
        (Get-FileHash -LiteralPath $path).Hash -ne $case.sha256) { throw 'Raw case changed.' }
    $protected += $path
}
$protectedHashes = @($protected | ForEach-Object {
    [ordered]@{path=$_;sha256=(Get-FileHash -LiteralPath $_).Hash}
})
$targets = @()
foreach ($root in @($current,$failed)) {
    $info = Get-Content -LiteralPath (Join-Path $root 'single_pipe_execution.json') -Raw | ConvertFrom-Json
    $ssc = Join-Path $root 'component_build\+ecc_pipe_probe\observed_pipe.ssc'
    if ((Get-FileHash -LiteralPath $ssc).Hash -ne $info.probe_source_sha256) { throw 'Generated source changed.' }
    $targets += $ssc
    $targets += Join-Path $root 'component_build\ecc_pipe_probe_lib.slx'
}
foreach ($name in @('single_pipe_runtime_review.json','Fig01_single_pipe_heat_steps.png','Fig01_single_pipe_heat_steps.svg')) {
    $targets += Join-Path $oldReview $name
}
if ((Get-FileHash -LiteralPath (Join-Path $oldReview 'Fig01_single_pipe_heat_steps.png')).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $review 'Fig01_single_pipe_heat_steps.png')).Hash) {
    throw 'Superseded PNG is not the already reviewed identical image.'
}
$manifest = @()
foreach ($target in $targets) {
    $absolute = [IO.Path]::GetFullPath($target)
    $allowed = @($current,$failed,$oldReview) | Where-Object {
        $absolute.StartsWith($_+'\',[StringComparison]::OrdinalIgnoreCase)
    }
    if (@($allowed).Count -ne 1 -or $protected -contains $absolute) { throw 'Unsafe exact file target.' }
    $file = Get-Item -LiteralPath $absolute
    if ($file.PSIsContainer) { throw 'Directories must not be deleted by this tool.' }
    $parent = $file.Directory
    while ($null -ne $parent) {
        if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse ancestor.' }
        $parent = $parent.Parent
    }
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse target.' }
    $manifest += [ordered]@{path=$absolute;bytes=$file.Length;sha256=(Get-FileHash -LiteralPath $absolute).Hash}
}
$bytes = 0L
foreach ($row in $manifest) { $bytes += [long]$row.bytes }
$record = [ordered]@{
    schema='heatdrive_ecc_single_pipe_intermediate_retirement_v1'
    created_at=(Get-Date).ToString('o');status='planned';files=$manifest;protected_files=$protectedHashes
    retired_bytes=$bytes
    basis='Reproducible generated component/library and superseded derived review; not checkpoint or raw result retirement.'
    superseded_review_change='Port A/B labels made direction neutral; prior numerical equality separately verified; retained PNG byte-identical.'
    different_generated_library_bytes_not_claimed_duplicate=$true
    production_recovery_allowed=$false
}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receipt -Encoding utf8
foreach ($row in $manifest) {
    if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Target changed before retirement.' }
    Remove-Item -LiteralPath $row.path -Force
    if (Test-Path -LiteralPath $row.path) { throw 'Retirement incomplete.' }
}
foreach ($row in $protectedHashes) {
    if ((Get-FileHash -LiteralPath $row.path).Hash -ne $row.sha256) { throw 'Protected evidence changed.' }
}
$record.status='completed'
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receipt -Encoding utf8
[ordered]@{status='completed';retired_bytes=$record.retired_bytes;protected_count=$protectedHashes.Count;receipt=$receipt} | ConvertTo-Json
