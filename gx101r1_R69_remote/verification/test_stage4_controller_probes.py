from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "Instrument_HeatDriveECC_Stage4ControllerProbes.m"
RUNNER = ROOT / "verification" / "Run_HeatDriveECC_ColdChamberDiagnostic.m"


def test_stage4_probe_contract_is_in_memory_and_complete():
    text = PROBE.read_text(encoding="utf-8")
    assert "heatdrive_ecc_stage4_controller_probe_contract_v1" in text
    assert "heatdrive_ecc_stage4_controller_probe_contract_v3" in text
    assert "heatdrive_ecc_stage4_controller_probe_contract_v4" in text
    assert "stage4_target_flow_command" in text
    assert "stage4_pressure_bias_command" in text
    assert "SaveFormat', 'Structure With Time'" in text
    assert "save_system" not in text
    for block in (
        "SEStage4InletViscosityExp",
        "SEStage4OutletViscosityExp",
        "SEStage4PressureFFActivityFromWorkspace",
        "SEStage4ViscosityMean",
        "SEPressureDynamicFeedforward",
        "PressurePI_ErrorSum",
        "SEStage4PressurePI_Integrator",
        "PressurePI_Saturation",
    ):
        assert block in text


def test_cold_runner_persists_stage4_probe_observations():
    text = RUNNER.read_text(encoding="utf-8")
    assert "Instrument_HeatDriveECC_Stage4ControllerProbes" in text
    assert "stage4_controller_probe_contract.json" in text
    assert "stage4_controller_probe_signals" in text
    assert "stage4_controller_probe_count" in text
