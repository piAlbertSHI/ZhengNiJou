import unittest
import numpy as np
from Analyze_HeatDriveECC_Stage4DistributedResistance import distributed_pressure
from Analyze_HeatDriveECC_Stage4FeedforwardCandidates import controller_mu


class DistributedResistanceTests(unittest.TestCase):
    def test_uniform_field_matches_laminar_reference(self):
        t = np.full((21, 3), 303.15)
        rho = np.full_like(t, 1045.)
        flow = np.full_like(t, .0032)
        value = distributed_pressure(t, rho, flow, np.full(21, .4/21), 7.14e-6, .00042)
        expected = 32*.4*controller_mu(np.array([303.15]))[0]*.0032/(1045*7.14e-6*.00042**2)/1e6
        np.testing.assert_allclose(value, expected)

    def test_nonuniform_field_is_not_endpoint_average(self):
        t = np.full((21, 3), 303.15)
        t[-1] = 263.15
        rho, flow = np.full_like(t, 1045.), np.full_like(t, .0032)
        actual = distributed_pressure(t, rho, flow, np.full(21, .4/21), 7.14e-6, .00042)
        endpoint = np.mean(controller_mu(t[[0,-1]]), axis=0)
        endpoint_drop = 32*.4*endpoint*.0032/(1045*7.14e-6*.00042**2)/1e6
        self.assertTrue(np.all(endpoint_drop > actual))

    def test_bad_coordinates_are_rejected(self):
        with self.assertRaises(ValueError):
            distributed_pressure(np.ones((21,3))*300, np.zeros((21,3)), np.ones((21,3)),
                                 np.ones(21), 1, 1)
