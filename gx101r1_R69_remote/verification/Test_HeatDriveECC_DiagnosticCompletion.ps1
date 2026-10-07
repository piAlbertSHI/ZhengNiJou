function Test-HeatDriveECCDiagnosticCompletion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Execution,
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][string[]]$RequestedArms,
        [Parameter(Mandatory)][bool]$DistributedController
    )
    $cases = @($Execution.cases)
    $actual = @($cases | ForEach-Object { [string]$_.arm })
    $scopePass = ($Execution.requested_arm_collection_pass -eq $true) -and
        ($actual.Count -eq $RequestedArms.Count) -and
        (($actual -join ',') -eq ($RequestedArms -join ',')) -and
        ($Execution.c200_state_imported -eq $false) -and
        ($Execution.checkpoint_saved -eq $false) -and
        ($Execution.production_recovery_allowed -eq $false)
    $controllerPass = $true
    foreach ($arm in $RequestedArms) {
        $folder = Join-Path $OutputRoot $arm
        $completion = Get-Content -LiteralPath (Join-Path $folder 'arm_completion.json') -Raw | ConvertFrom-Json
        $case = @($cases | Where-Object { $_.arm -eq $arm })
        $hash = (Get-FileHash -LiteralPath (Join-Path $folder 'observations.mat') -Algorithm SHA256).Hash
        $scopePass = $scopePass -and ($case.Count -eq 1) -and
            ($completion.arm -eq $arm) -and
            ($completion.observation_sha256 -eq $hash) -and
            ($case[0].observation_sha256 -eq $hash)
        if ($DistributedController) {
            $ff = Get-Content -LiteralPath (Join-Path $folder 'distributed_pressure_ff_contract.json') -Raw | ConvertFrom-Json
            $controllerPass = $controllerPass -and ($ff.simulation_run -eq $true) -and
                (@($ff.sources).Count -eq 21) -and
                ($ff.legacy_reference_multiplier_used -eq $false)
        }
    }
    [pscustomobject]@{
        requested_arm_collection_pass = [bool]$scopePass
        requested_controller_executed = [bool]$controllerPass
        physical_collection_pass = [bool](($Execution.collection_pass -eq $true) -and
            $scopePass -and (($actual -join ',') -eq 'native,conservative'))
        production_recovery_allowed = $false
    }
}
