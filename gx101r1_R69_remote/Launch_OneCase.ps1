param(
    [string]$RepoRoot = "",
    [string]$RunId = "",
    [double]$VStar = 1.0,
    [double]$StageTime = 0.40,
    [int]$NCycles = 15,
    [switch]$SavePlots
)

$ErrorActionPreference = "Stop"

function New-Dir([string]$PathValue) {
    New-Item -ItemType Directory -Force -Path $PathValue | Out-Null
}

function Write-Utf8NoBom([string]$PathValue, [string]$TextValue) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($PathValue, $TextValue, $encoding)
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if ([string]::IsNullOrWhiteSpace($RunId)) {
    $RunId = "single_" + (Get-Date -Format "MMdd_HHmm")
}

$tag = ("v{0:000}_t{1:000}_{2}c" -f [int]($VStar * 100), [int]($StageTime * 100), $NCycles)
$batchRoot = Join-Path $RepoRoot (Join-Path "Output" $RunId)
$caseRoot = Join-Path $batchRoot $tag
$logDir = Join-Path $caseRoot "logs"
$prefDir = Join-Path $caseRoot "pref"
$tmpDir = Join-Path $caseRoot "tmp"
foreach ($dir in @($batchRoot, $caseRoot, $logDir, $prefDir, $tmpDir)) {
    New-Dir $dir
}

$repoM = $RepoRoot -replace "\\", "/"
$outM = $caseRoot -replace "\\", "/"
$savePlotsText = if ($SavePlots) { "true" } else { "false" }
$matlabScript = @"
try
    diary('$outM/matlab_diary.txt');
    fprintf('Single case start tag=%s V=%g t=%g nCycles=%d at %s\n', '$tag', $VStar, $StageTime, $NCycles, datestr(now, 31));
    restoredefaultpath;
    repo = '$repoM';
    addpath(repo, '-begin');
    addpath(fullfile(repo, 'Tools', 'validation'), '-begin');
    Remote_RunCase(repo, '$outM', '$tag', $NCycles, $VStar, $savePlotsText, $StageTime);
    fprintf('Single case finished tag=%s at %s\n', '$tag', datestr(now, 31));
    diary off;
catch ME
    try
        fid = fopen('$outM/matlab_error.txt', 'w');
        fprintf(fid, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
        fclose(fid);
    catch
    end
    try, diary off; catch, end
    rethrow(ME);
end
"@

$caseM = Join-Path $caseRoot "run_case.m"
Write-Utf8NoBom $caseM $matlabScript

$casePs1 = Join-Path $caseRoot "run_case.ps1"
$wrapper = @"
`$ErrorActionPreference = "Stop"
`$env:MATLAB_PREFDIR = "$prefDir"
`$env:TEMP = "$tmpDir"
`$env:TMP = "$tmpDir"
Set-Location -LiteralPath "$RepoRoot"
matlab -batch "run('$($caseM -replace "\\", "/")')"
"@
Write-Utf8NoBom $casePs1 $wrapper

$stdout = Join-Path $logDir "powershell_stdout.log"
$stderr = Join-Path $logDir "powershell_stderr.log"
$proc = Start-Process -FilePath "powershell.exe" `
    -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $casePs1) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$launchRow = [pscustomobject]@{
    tag = $tag
    V_star = $VStar
    stage_time_s = $StageTime
    nCycles = $NCycles
    save_plots = [bool]$SavePlots
    process_id = $proc.Id
    case_dir = $caseRoot
    summary_json = Join-Path $caseRoot "summary.json"
    stderr = $stderr
    stdout = $stdout
}

$launchRow | Export-Csv -LiteralPath (Join-Path $batchRoot "launch_status.csv") -NoTypeInformation -Encoding UTF8
$launchRow | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $batchRoot "launch_status.json") -Encoding UTF8
[ordered]@{
    run_id = $RunId
    repo_root = $RepoRoot
    batch_root = $batchRoot
    started_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    worker_count = 1
    case = $launchRow
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $batchRoot "batch_info.json") -Encoding UTF8

Write-Host "Started case: $caseRoot"
$launchRow | Format-List
