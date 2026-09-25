import importlib.util
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "verification" / "Audit_HeatDriveECC_Stage4ControllerProbes.py"
sys.path.insert(0, str(ROOT / "verification"))


def module():
    spec = importlib.util.spec_from_file_location("stage4_probe_audit", SCRIPT)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def test_probe_audit_is_diagnostic_only():
    audit = module()
    assert len(audit.EXPECTED) == 17
    assert audit.EXPECTED[-1] == "stage4_pressure_command"


def test_probe_audit_rejects_missing_contract():
    audit = module()
    assert audit.EXPECTED[9] == "stage4_dynamic_feedforward"
