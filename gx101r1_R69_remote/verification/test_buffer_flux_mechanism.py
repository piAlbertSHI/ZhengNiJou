import unittest
import numpy as np

from Analyze_HeatDriveECC_BufferFluxMechanism import (
    convection_bounds,interval_partition,symmetric_inventory_split,smoothing_power,source_conductivity)


class BufferFluxMechanismTests(unittest.TestCase):
    def test_zero_mass_flow_does_not_mean_zero_conduction(self):
        result=convection_bounds([0.],[1e6],[400000.],[100000.],[3.],900.,1100.)
        np.testing.assert_array_equal(result['smoothing_low_W'],[3.])
        np.testing.assert_array_equal(result['smoothing_high_W'],[3.])

    def test_exact_smoothed_equation_is_inside_bounds_for_both_flow_signs(self):
        m=np.array([-.01,0.,.01]);p=np.full(3,1e6);uin=np.full(3,4e5);uout=np.full(3,1e5)
        G=.001;smooth=np.sqrt(m*m+4*G*G)
        power=.5*m*(uin+uout)+.5*smooth*(uin-uout)+m*p/1000
        exact=.5*(smooth-abs(m))*(uin-uout)
        result=convection_bounds(m,p,uin,uout,power,900,1100)
        self.assertTrue(np.all(result['smoothing_low_W']<=exact))
        self.assertTrue(np.all(result['smoothing_high_W']>=exact))

    def test_conduction_bounds_are_invariant_to_energy_datum(self):
        m=np.array([-.01,.02]);p=np.full(2,1e6);u=np.array([4e5,5e5]);v=np.full(2,1e5);q=np.array([30.,40.])
        first=convection_bounds(m,p,u,v,q,900,1100)
        shifted=convection_bounds(m,p,u+1e5,v+1e5,q+m*1e5,900,1100)
        for key in ('smoothing_low_W','smoothing_high_W'):
            np.testing.assert_allclose(first[key],shifted[key],rtol=0,atol=1e-10)

    def test_symmetric_split_exact_with_mass_temperature_interaction(self):
        energy=lambda T,M:M*T*T+2*M*M+3*T
        result=symmetric_inventory_split(energy,[300.,301.],[.1,.11])
        self.assertAlmostEqual(result['temperature_change_energy_J']+result['mass_change_energy_J'],
                               result['total_change_J'])

    def test_midpoint_stage_partition_covers_cycle_boundary_once(self):
        time=np.array([0,3.5,5.,8.5,10.])
        np.testing.assert_array_equal(interval_partition(time),[1,2,3,4])

    def test_invalid_physical_inputs_rejected(self):
        with self.assertRaises(ValueError):convection_bounds([0.],[1e6],[1.],[1.],[0.],0.,1000.)
        with self.assertRaises(ValueError):symmetric_inventory_split(lambda T,M:T*M,[1.,2.],[0.,1.])
        with self.assertRaises(ValueError):interval_partition([0.,0.])

    def test_zero_flow_smoothing_scales_with_conduction_parameter(self):
        self.assertAlmostEqual(smoothing_power(np.array([0.]),np.array([3e5]),1e-5)[0],3.)

    def test_conductivity_comes_from_unique_literal_not_fit(self):
        source='k_water_mW_per_mK = [500; ...\n600];'
        self.assertAlmostEqual(source_conductivity(source,'model/SMA_ThermalLiquidSettings',np.array([283.15,303.15])),.55)
        with self.assertRaises(ValueError):source_conductivity(source+source,'model/SMA_ThermalLiquidSettings',np.array([283.15,303.15]))


if __name__=='__main__':
    unittest.main()
