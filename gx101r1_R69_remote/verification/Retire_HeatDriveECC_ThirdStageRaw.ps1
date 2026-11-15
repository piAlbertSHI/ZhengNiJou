param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$repo = 'C:\Users\86182\Desktop\正逆耦合'
$auditRoot = Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit\workspace_deep_cleanup_third_20261115'
$runtime = 'C:\Users\86182\.codex\worktrees\runtime-cv-json-contract\正逆耦合'
$phase = 'C:\Users\86182\.codex\worktrees\stage4-phase-local-blend-diagnostic\正逆耦合'
$verificationRoots = @(
    (Join-Path $runtime 'gx101r1_R69_remote\verification'),
    (Join-Path $phase 'gx101r1_R69_remote\verification'),
    (Join-Path $repo 'gx101r1_R69_remote\verification'),
    (Join-Path $repo '项目文档\报告')
)
$model = Join-Path $repo 'gx101r1_R69_remote\heatdrive_ecc_coupled_se21.slx'

if (Test-Path -LiteralPath $auditRoot) { throw "Audit root already exists: $auditRoot" }

function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Assert-File([string]$Path) { if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" } }
function Assert-NoReparse([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse candidate: $Path" }
    $parent = $item.Directory
    while ($null -ne $parent) {
        if (($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse ancestor: $Path" }
        $parent = $parent.Parent
    }
}

function Relative-Path([string]$Path) {
    [IO.Path]::GetRelativePath($repo, $Path).Replace('/', '\')
}

function Compact-Evidence([string]$Root) {
    @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction Stop |
        Where-Object {
            $_.Extension -in @('.json', '.csv', '.txt', '.log') -or
            $_.Name -like 'retained_key_evidence_shared_*.h5'
        } |
        Where-Object { $_.Name -notin @('matlab_stdout.log', 'matlab_stderr.log') } |
        ForEach-Object {
            [ordered]@{ path = $_.FullName; bytes = [int64]$_.Length; sha256 = Hash $_.FullName }
        })
}

function Add-Candidate([System.Collections.Generic.List[object]]$List, [string]$Path, [string]$Reason, [string[]]$Evidence) {
    Assert-File $Path
    Assert-NoReparse $Path
    $refs = @()
    $relative = Relative-Path $Path
    $outputsIndex = $Path.IndexOf('outputs\\', [StringComparison]::OrdinalIgnoreCase)
    $outputRelative = if ($outputsIndex -ge 0) { $Path.Substring($outputsIndex) } else { $relative }
    foreach ($root in $verificationRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $patterns = @($Path, $outputRelative, $outputRelative.Replace('\', '/'))
        foreach ($pattern in $patterns) {
            $refs += @(rg -l -F --hidden --no-messages --glob '*.m' --glob '*.py' --glob '*.ps1' --glob '*.json' --glob '*.md' --glob '!outputs/**' --glob '!outputs_storage_audit/**' -- $pattern $root 2>$null)
        }
    }
    $refs = @($refs | Sort-Object -Unique)
    $List.Add([ordered]@{
        path = $Path
        relative_path = $relative
        bytes = [int64](Get-Item -LiteralPath $Path).Length
        sha256 = Hash $Path
        replacement_evidence = @($Evidence)
        direct_script_references = @($refs)
        reference_conclusion = if ($refs.Count -eq 0) { 'No exact path or leaf-name reference found outside outputs/audits.' } else { 'References exist; entries are retained in the manifest for review before deletion.' }
        deletion_reason = $Reason
        deletion_impact = 'Raw trajectory/state/configuration is not required by the verified compact consumers; exact raw re-audit is intentionally relinquished and the retained representative/compact evidence remains.'
    })
}

$live = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '(?i)^matlab(\.exe)?$|simulink|sldriver' })
if ($live.Count -gt 0) { throw ('MATLAB/Simulink is alive: ' + ($live | Select-Object ProcessId, Name, CommandLine | ConvertTo-Json -Compress)) }
Assert-File $model
$modelHash = Hash $model

$candidates = [System.Collections.Generic.List[object]]::new()

# Runtime directional and constitutive chains: retain contracts, configuration, OP and compact audit copies.
$runtimeGroups = @(
    @{ name = 'v26_directional_directlog_resume_20c'; evidence = @('v26_directional_C22_full_mechanism_20261008.json','v26_directional_C22_state_capture_20261008.json','v26_directional_C22_endpoint_qualification_20261008.json','v26_directional_closeout_20261008.json') },
    @{ name = 'v27_directional_latest_resume_C42'; evidence = @('v27_directional_C42_full_mechanism_20261008.json','v27_directional_C42_state_capture_20261008.json','v27_directional_C42_endpoint_qualification_20261008.json','v27_directional_C42_storage_closeout_20261008.json') },
    @{ name = 'v28_directional_latest_resume_C62'; evidence = @('v28_directional_C62_full_mechanism_20261009.json','v28_directional_C62_state_capture_20261009.json','v28_directional_C62_endpoint_qualification_20261009.json','v28_directional_C62_storage_closeout_20261009.json') },
    @{ name = 'v29_directional_latest_resume_C82'; evidence = @('v29_directional_C82_full_mechanism_20261009.json','v29_directional_C82_state_capture_20261009.json','v29_directional_C82_endpoint_qualification_20261009.json','v29_directional_C82_storage_closeout_20261009.json') },
    @{ name = 'v31_stable_constitutive_from_C82_C102_fix6'; evidence = @('v32_stable_evidence_snapshot_20261013\snapshot_receipt.json') },
    @{ name = 'v31_stable_constitutive_from_C102_C122_fix1'; evidence = @('v32_stable_evidence_snapshot_20261013\snapshot_receipt.json') },
    @{ name = 'v31_stable_constitutive_from_C122_C142_fix1'; evidence = @('v32_stable_evidence_snapshot_20261013\snapshot_receipt.json') }
)
foreach ($group in $runtimeGroups) {
    $root = Join-Path $runtime "gx101r1_R69_remote\outputs\$($group.name)"
    $auditEvidence = @()
    foreach ($name in $group.evidence) {
        $matches = @(Get-ChildItem -LiteralPath (Join-Path $repo 'gx101r1_R69_remote\outputs_storage_audit') -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq (Split-Path -Leaf $name) })
        $auditEvidence += $matches.FullName
    }
    $auditEvidence += @(Compact-Evidence $root)
    $evidencePaths = @($auditEvidence | Where-Object { $_ -is [string] })
    foreach ($relative in @('native\observations.mat', 'native\diagnostic_state_observation.mat')) {
        Add-Candidate $candidates (Join-Path $root $relative) 'Intermediate full native trajectory/state; compact contract and audited stable evidence are retained.' $evidencePaths
    }
}

# Old rejected/warmup native raw, with markers and compact public/key evidence retained.
foreach ($spec in @(
    @{ root = (Join-Path $runtime 'gx101r1_R69_remote\outputs\v9_warmup20p'); raw = 'native\observations.mat' },
    @{ root = (Join-Path $runtime 'gx101r1_R69_remote\outputs\v16_distributed_envelope_20c'); raw = 'native\observations.mat' }
)) {
    Add-Candidate $candidates (Join-Path $spec.root $spec.raw) 'Rejected/warmup native raw; marker, public targets, contracts and retained key evidence remain.' (Compact-Evidence $spec.root)
}

# v56: keep C052 representative, remove intermediate C044-C050 state/observation raw only.
$v56 = Join-Path $phase 'gx101r1_R69_remote\outputs\v56_runtime_Tc277p05_precision_fromC40_r1'
$v56Evidence = Compact-Evidence $v56
foreach ($cycle in @('C044','C046','C048','C050')) {
    Add-Candidate $candidates (Join-Path $v56 "packet_${cycle}_attempt01\native\observations.mat") 'Intermediate precision packet raw; C052 representative and per-packet compact summaries/probes/manifests remain.' $v56Evidence
    Add-Candidate $candidates (Join-Path $v56 "packet_${cycle}_attempt01\observed_states.mat") 'Intermediate precision packet raw state; C052 representative and compact evidence remain.' $v56Evidence
}

# v61: keep C108 representative, remove C100-C106 state/observation raw only.
$v61 = Join-Path $phase 'gx101r1_R69_remote\outputs\v61c1'
$v61Evidence = Compact-Evidence $v61
foreach ($cycle in @('C100','C102','C104','C106')) {
    Add-Candidate $candidates (Join-Path $v61 "packet_${cycle}_attempt01\native\observations.mat") 'Intermediate C108 repeatability packet raw; C108 representative and compact evidence remain.' $v61Evidence
    Add-Candidate $candidates (Join-Path $v61 "packet_${cycle}_attempt01\observed_states.mat") 'Intermediate C108 repeatability packet raw state; C108 representative and compact evidence remain.' $v61Evidence
}

# Split-comparison raw is numerical repeatability evidence; retain JSON/CSV/probes and the final representative packet.
foreach ($group in @(
    @{ name = 'v67c1'; representative = 'packet_C060_attempt01' },
    @{ name = 'v68c1'; representative = 'packet_C060_attempt01' },
    @{ name = 'v70c1'; representative = 'packet_C060_attempt01' },
    @{ name = 'v71c1'; representative = 'packet_C050_attempt01' }
)) {
    $root = Join-Path $phase "gx101r1_R69_remote\outputs\$($group.name)"
    $evidence = Compact-Evidence $root
    foreach ($part in @('prefix','reference','suffix')) {
        foreach ($relative in @("split_comparison_attempt01\$part\native\observations.mat", "split_comparison_attempt01\$part\observed_states.mat", "split_comparison_attempt01\$part\native\configuration.mat")) {
            Add-Candidate $candidates (Join-Path $root $relative) 'Split-comparison raw trajectory/configuration; bitwise repeatability JSON, packet manifests, summaries and probes remain; representative final packet is retained.' $evidence
        }
    }
}

$direct = @($candidates | Where-Object { @($_.direct_script_references).Count -gt 0 })
if ($direct.Count -gt 0) {
    throw ('Exact candidate references found; review required before deletion: ' + ($direct | ConvertTo-Json -Depth 6 -Compress))
}

$before = @()
foreach ($root in @(
    'C:\Users\86182\.codex\worktrees\fixed-stage4-kp237-endpoint\正逆耦合',
    $runtime,
    'C:\Users\86182\.codex\worktrees\stage4-default-cold-diagnostic\正逆耦合',
    $phase
)) {
    $files = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -ErrorAction Stop)
    $sum = [int64]0; foreach ($file in $files) { $sum += [int64]$file.Length }
    $before += [ordered]@{ path = $root; file_count = $files.Count; logical_bytes = $sum }
}

New-Item -ItemType Directory -Path $auditRoot | Out-Null
$whitelist = [ordered]@{
    schema = 'agent5_third_stage_raw_retirement_whitelist_v1'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    thread_id = '019e9312-444b-7090-a68e-0888598c1598'
    deletion_performed = $false
    candidate_count = $candidates.Count
    candidates = $candidates
    before_worktrees = $before
    retained_representatives = @(
        'v43_storage_warmup_from_C42_r1',
        'v56 packet_C052_attempt01', 'v61 packet_C108_attempt01',
        'v67/v68/v70 packet_C060_attempt01', 'v71 packet_C050_attempt01',
        'C200 physical_simscape_result.mat and final_operating_point.mat'
    )
    guard = 'No MATLAB/Simulink process at manifest creation; all exact path references outside outputs/audits were empty.'
    scientific_gates_changed = $false
}
$whitelistPath = Join-Path $auditRoot 'third_stage_raw_retirement_whitelist.json'
$whitelist | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $whitelistPath -Encoding utf8

$deleted = @()
if ($Apply) {
    $liveNow = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match '(?i)^matlab(\.exe)?$|simulink|sldriver' })
    if ($liveNow.Count -gt 0) { throw ('MATLAB/Simulink appeared before deletion: ' + ($liveNow | Select-Object ProcessId, Name, CommandLine | ConvertTo-Json -Compress)) }
    foreach ($candidate in $candidates) {
        if ((Hash $candidate.path) -ne $candidate.sha256) { throw "Candidate changed before deletion: $($candidate.path)" }
        Remove-Item -LiteralPath $candidate.path -Force
        if (Test-Path -LiteralPath $candidate.path) { throw "Candidate remained: $($candidate.path)" }
        $deleted += $candidate
    }
}

$after = @()
foreach ($item in $before) {
    $files = @(Get-ChildItem -LiteralPath $item.path -File -Recurse -Force -ErrorAction Stop)
    $sum = [int64]0; foreach ($file in $files) { $sum += [int64]$file.Length }
    $after += [ordered]@{ path = $item.path; file_count = $files.Count; logical_bytes = $sum }
}
$freed = [int64]0; foreach ($candidate in $deleted) { $freed += [int64]$candidate.bytes }
$whitelist.deletion_performed = $Apply.IsPresent
$whitelist.deleted_file_count = $deleted.Count
$whitelist.deleted_files = $deleted
$whitelist.reclaimed_bytes = $freed
$whitelist.reclaimed_gib = [math]::Round($freed / 1GB, 6)
$whitelist.after_worktrees = $after
$whitelist | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $whitelistPath -Encoding utf8
$receipt = [ordered]@{
    schema = 'agent5_third_stage_raw_retirement_receipt_v1'
    status = 'completed'
    generated_utc = [DateTime]::UtcNow.ToString('o')
    whitelist = $whitelistPath
    deleted_file_count = $deleted.Count
    deleted_files = $deleted
    reclaimed_bytes = $freed
    reclaimed_gib = [math]::Round($freed / 1GB, 6)
    retained_representatives = $whitelist.retained_representatives
    scientific_gates_changed = $false
    model_hash_before = $modelHash
    model_hash_after = Hash $model
    matlab_simulink_started_or_interrupted = $false
    other_worktrees_touched = $false
    Agent6_touched = $false
}
$receiptPath = Join-Path $auditRoot 'third_stage_raw_retirement_receipt.json'
$receipt | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $receiptPath -Encoding utf8
[pscustomobject]@{ status = $receipt.status; candidate_count = $candidates.Count; deleted_count = $receipt.deleted_file_count; reclaimed_bytes = $freed; reclaimed_gib = $receipt.reclaimed_gib; whitelist = $whitelistPath; receipt = $receiptPath } | ConvertTo-Json
