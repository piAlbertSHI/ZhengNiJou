[CmdletBinding()]
param(
    [string]$RecoveryContractPath = '',
    [string]$OutputRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($RecoveryContractPath)) {
    $RecoveryContractPath = Join-Path $repoRoot `
        'verification\source_heatflow_c240_recovery_contract.json'
}
$RecoveryContractPath = [IO.Path]::GetFullPath($RecoveryContractPath)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repoRoot `
        'outputs_storage_audit\shex_control_volume_c240_20260903'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot `
    'outputs_storage_audit')) + [IO.Path]::DirectorySeparatorChar
if (-not $OutputRoot.StartsWith($allowedRoot, `
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "OutputRoot must remain under outputs_storage_audit: $OutputRoot"
}

$contract = Get-Content -LiteralPath $RecoveryContractPath -Raw |
    ConvertFrom-Json
if ([int]$contract.completed_cycles -ne 240 -or
        -not [bool]$contract.mechanism_pass -or
        -not [bool]$contract.periodic_steady_state -or
        -not [bool]$contract.source_heat_flow_direction_pass) {
    throw 'C240 recovery contract does not satisfy the required gates.'
}
function Resolve-RepoPath([string]$RelativePath) {
    $path = [IO.Path]::GetFullPath((Join-Path $repoRoot `
        ($RelativePath -replace '/', '\')))
    $prefix = $repoRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($prefix, `
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Contract path escaped repository: $path"
    }
    return $path
}
$resultPath = Resolve-RepoPath $contract.result_relative_path
$checkpointPath = Resolve-RepoPath $contract.checkpoint_relative_path
$resultHash = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash
$checkpointHash = (Get-FileHash -LiteralPath $checkpointPath `
    -Algorithm SHA256).Hash
if ($resultHash -ne [string]$contract.result_sha256 -or
        $checkpointHash -ne [string]$contract.checkpoint_sha256) {
    throw 'Frozen C240 SHA-256 verification failed.'
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$stdoutPath = Join-Path $OutputRoot 'matlab_stdout.log'
$stderrPath = Join-Path $OutputRoot 'matlab_stderr.log'
$matlab = 'C:\Program Files\MATLAB\R2025b\bin\matlab.exe'
function Matlab-Escape([string]$Value) { return $Value.Replace("'", "''") }
$repoForMatlab = Matlab-Escape $repoRoot
$resultForMatlab = Matlab-Escape $resultPath
$outputForMatlab = Matlab-Escape $OutputRoot
$batch = "cd('$repoForMatlab'); addpath(pwd); addpath(fullfile(pwd,'verification')); audit=Audit_HeatDriveECC_FrozenSHEXControlVolume('$resultForMatlab','$outputForMatlab'); assert(audit.production_pass,'FROZEN_SHEX_CONTROL_VOLUME_FAILED');"
$process = Start-Process -FilePath $matlab `
    -ArgumentList @('-batch', ('"' + $batch.Replace('"', '\"') + '"')) `
    -WorkingDirectory $repoRoot -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru -Wait
if ($process.ExitCode -ne 0) {
    throw "MATLAB SHEX control-volume audit failed; see $stderrPath"
}

$required = @(
    'shex_control_volume_audit.mat',
    'shex_control_volume_summary.json',
    'shex_control_volume_sample.csv',
    'Fig06_frozen_C240_SHEX_control_volume.png',
    'Fig06_frozen_C240_SHEX_control_volume.pdf',
    'matlab_stdout.log',
    'matlab_stderr.log'
)
$manifest = foreach ($name in $required) {
    $path = Join-Path $OutputRoot $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required SHEX artifact is missing: $path"
    }
    $item = Get-Item -LiteralPath $path
    [pscustomobject]@{
        role = 'C240 frozen SHEX control-volume evidence'
        file = $name
        bytes = $item.Length
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
}
$manifestPath = Join-Path $OutputRoot 'artifact_manifest_sha256.csv'
$manifest | Export-Csv -LiteralPath $manifestPath -NoTypeInformation `
    -Encoding UTF8
$package = [ordered]@{
    schema = 'heatdrive_ecc_frozen_shex_package_v1'
    generated_at = (Get-Date).ToString('o')
    recovery_contract = $RecoveryContractPath
    frozen_result = $resultPath
    frozen_result_sha256 = $resultHash
    frozen_checkpoint = $checkpointPath
    frozen_checkpoint_sha256 = $checkpointHash
    frozen_files_modified = $false
    artifact_count = $manifest.Count
    artifact_manifest = $manifestPath
}
$packagePath = Join-Path $OutputRoot 'package_contract.json'
$package | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $packagePath `
    -Encoding UTF8
$package | ConvertTo-Json -Depth 6
