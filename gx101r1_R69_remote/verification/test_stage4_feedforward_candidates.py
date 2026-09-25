from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "verification" / "Analyze_HeatDriveECC_Stage4FeedforwardCandidates.py"


def test_candidate_analysis_is_diagnostic_only():
    text = SCRIPT.read_text(encoding="utf-8")
    assert '"seed_eligible": False' in text
    assert "geometric_endpoint" in text
    assert "logarithmic_endpoint" in text
    assert '"table4_reproduction_claim": False' in text
