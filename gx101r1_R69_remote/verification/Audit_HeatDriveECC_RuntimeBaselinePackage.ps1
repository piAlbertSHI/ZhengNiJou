[CmdletBinding()]
param([string]$AuditRoot = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $AuditRoot) { $AuditRoot = Join-Path $repo 'outputs_storage_audit\runtime_c180_release_20260906' }
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$contractPath = Join-Path $PSScriptRoot 'runtime_c180_recovery_contract.json'
$c = Read-Json $contractPath
$raw = Join-Path $repo $c.result_relative_path
$op = Join-Path $repo $c.checkpoint_relative_path
$strictPath = Join-Path $repo $c.strict_restore_audit_relative_path
$energyPath = Join-Path $repo $c.system_energy_audit_relative_path
$s = Read-Json $strictPath
$e = Read-Json $energyPath
$coveragePath = Join-Path $repo 'outputs_storage_audit\runtime_c180_release_20260906\internal_state_coverage.json'
$coverage = Read-Json $coveragePath
$figureQAPath = Join-Path $repo 'outputs_storage_audit\runtime_c180_release_20260906\figure_qa.json'
$figureQA = Read-Json $figureQAPath
Require ($figureQA.source_result_sha256 -eq $c.result_sha256 -and
    $figureQA.readability_review_pass -and $figureQA.png_reviewed -eq 7 -and
    $figureQA.pdf_poppler_render_reviewed -eq 7 -and
    -not $figureQA.journal_peer_review_claimed) 'Figure visual review is missing or out of scope.'
foreach ($figure in $figureQA.files) {
    $path = Join-Path (Split-Path $raw) "figures_sci\$($figure.name)"
    Require ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $figure.sha256) 'Reviewed figure changed.'
}
Require ($coverage.source_sha256 -eq $c.result_sha256 -and
    -not $coverage.complete_internal_state_periodicity_verified -and
    -not $coverage.steady_parameter_study_allowed -and
    -not $coverage.PI_route_memory_timeseries_recorded) 'Internal-state coverage scope mismatch.'
Require ($c.mechanism_pass -and $c.periodic_steady_state -and -not $c.state_reset -and
    $c.recovery_policy.state_recovery_allowed -and -not $c.steady_parameter_study_allowed -and
    -not $c.complete_internal_state_periodicity_verified -and -not $c.strict_table4_reproduction) 'C180 scope mismatch.'
Require ($s.strict_restore_pass -and $s.complete_operating_point_restore_verified -and
    $s.production_logging_and_final_state_settings_matched -and -not $s.partial_diagnostic_executed -and
    -not $s.contents_checksum_mismatch_detected -and $s.result_cycles -eq 180 -and
    $s.result_end_time_s -eq 1800 -and $s.checkpoint_time_s -eq 1800) 'C180 strict restore failed.'
Require ($e.production_pass -and $e.local_exchanger_kcl_pass -and $e.boundary_direction_pass -and
    $e.modeled_thermal_closure_pass -and $e.fluid_mass_conservation_pass -and
    -not $e.complete_device_first_law_closure) 'C180 modeled energy gates failed.'
Require ((Get-FileHash -LiteralPath $raw -Algorithm SHA256).Hash -eq $c.result_sha256) 'C180 result hash mismatch.'
Require ((Get-FileHash -LiteralPath $op -Algorithm SHA256).Hash -eq $c.checkpoint_sha256) 'C180 OP hash mismatch.'
$run = Split-Path $raw
$chain = Split-Path $run
$progress = @(Import-Csv -LiteralPath (Join-Path $chain 'steady_continuation_progress.csv'))
Require ($progress.Count -eq 6 -and $progress[-1].total_cycles -eq 180 -and
    $progress[-1].periodic_steady_state -eq 1 -and
    @($progress | Where-Object { $_.mechanism_pass -ne 1 }).Count -eq 0) 'Continuation promotion history failed.'
$stop = Select-String -LiteralPath (Join-Path $chain 'matlab_stdout.log') `
    -Pattern '^STEADY_CONTINUATION_STOP status=periodic_steady_state cycles=180 '
Require ($null -ne $stop) 'C180 explicit completion marker missing.'
$retired = $c.retired_diagnostic_raw
$old = Join-Path $repo $retired.result_relative_path
Require ($retired.approved -and $retired.result_sha256 -eq
    'B5FA3DE5C0AB7F386B686A6D3090599696DAFA11EAEAB50AEB7CF628238D291E') 'C246 retirement approval mismatch.'
if (Test-Path -LiteralPath $old -PathType Leaf) {
    Require ((Get-FileHash -LiteralPath $old -Algorithm SHA256).Hash -eq $retired.result_sha256) 'C246 pre-retirement hash mismatch.'
}
$paths = @($contractPath, $raw, $op, $strictPath, $energyPath,
    $coveragePath, $figureQAPath,
    (Join-Path $run 'physical_validation_report.txt'), (Join-Path $run 'cycle_physical_summary.csv'),
    (Join-Path $run 'qian2019_table2_table4_parameter_contract.csv'),
    (Join-Path $chain 'steady_continuation_progress.csv'), (Join-Path $chain 'steady_continuation_state.mat'),
    (Join-Path $chain 'matlab_stdout.log'), (Join-Path $chain 'matlab_stderr.log'))
foreach ($stem in @('Fig01_last_cycle_mechanism','Fig02_last_cycle_axial_fields','Fig03_periodic_convergence',
    'Fig04_control_and_energy','Fig05_table4_boundary_audit','Fig06_direct_SHEX_control_volume','Fig07_modeled_system_energy_ledger')) {
    foreach ($ext in @('png','pdf')) { $paths += Join-Path $run "figures_sci\$stem.$ext" }
}
$paths += Join-Path $run 'figures_sci\figure_manifest.txt'
$figureManifest = Get-Content -LiteralPath (Join-Path $run 'figures_sci\figure_manifest.txt') -Raw
Require ($figureManifest -match 'schema=heatdrive_ecc_sci_figure_set_v3' -and
    $figureManifest -match 'cycle_count=180' -and
    $figureManifest -match 'rejected_points_used_for_fit=0') 'Current figure provenance failed.'
$rows = @($paths | ForEach-Object {
    $file = Get-Item -LiteralPath $_
    [pscustomobject]@{path=$file.FullName; bytes=$file.Length; sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}
})
New-Item -ItemType Directory -Path $AuditRoot -Force | Out-Null
$rows | Export-Csv -LiteralPath (Join-Path $AuditRoot 'manifest_sha256.csv') -NoTypeInformation -Encoding utf8
$summary = [ordered]@{
    schema='heatdrive_ecc_runtime_baseline_package_v1'; generated_at=(Get-Date).ToString('o')
    package_pass=$true; completed_cycles=180; mechanism_pass=$true; declared_periodic_gate_pass=$true
    strict_restore_pass=$true; state_reset=$false; modeled_thermal_closure_pass=$true
    fluid_mass_conservation_pass=$true; complete_device_first_law_closure=$false
    complete_internal_state_periodicity_verified=$false; steady_parameter_study_allowed=$false
    table4_reproduction_claimed=$false; c246_raw_present=(Test-Path -LiteralPath $old -PathType Leaf)
    file_count=$rows.Count; audit_root=$AuditRoot
}
$summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $AuditRoot 'package_audit.json') -Encoding utf8
$summary | ConvertTo-Json
