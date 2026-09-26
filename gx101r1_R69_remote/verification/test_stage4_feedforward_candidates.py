from pathlib import Path

import numpy as np

from Analyze_HeatDriveECC_Stage4FeedforwardCandidates import (
    finite_correlation,
    harmonic_log_mean,
)


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "verification" / "Analyze_HeatDriveECC_Stage4FeedforwardCandidates.py"


def test_candidate_analysis_is_diagnostic_only():
    text = SCRIPT.read_text(encoding="utf-8")
    assert '"seed_eligible": False' in text
    assert "geometric_endpoint" in text
    assert "logarithmic_endpoint" in text
    assert '"table4_reproduction_claim": False' in text


def test_logarithmic_mean_equal_endpoint_fallback():
    a = np.array([0.01, 0.02])
    b = np.array([0.01, 0.03])
    actual = harmonic_log_mean(a, b)
    assert actual[0] == 0.01
    assert np.isclose(actual[1], 0.01 / np.log(1.5))


def test_constant_signal_correlation_is_undefined():
    assert finite_correlation(np.array([1.0, 2.0]), np.array([0.0, 0.0])) is None
