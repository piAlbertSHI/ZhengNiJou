import unittest
import numpy as np

from Audit_HeatDriveECC_CoupledEnergyInventory import (
    BUFFER_NAMES, CHAMBER_NAMES, SOURCE_ROLES, buffer_cycle_rows,
    chamber_inventory_projection, latent_decomposition, system_balance,
)


class CoupledEnergyTests(unittest.TestCase):
    def latent(self):
        t=np.arange(21)*.001
        phase=np.vstack((.1+.001*np.arange(21),.5-.0005*np.arange(21)))
        coefficients=np.array([100.,50.])
        q=np.r_[0, coefficients@np.diff(phase,axis=1)/np.diff(t)]
        return t,q,phase,coefficients

    def test_latent_storage_has_negative_phase_sign(self):
        result=latent_decomposition(*self.latent())
        self.assertAlmostEqual(result['latent_storage_change_J'],-1.5)
        self.assertAlmostEqual(result['internal_mechanical_net_J'],0)

    def test_latent_not_counted_twice_as_external_heat(self):
        latent=latent_decomposition(*self.latent())
        source={k:0. for k in SOURCE_ROLES}
        source.update(SHEX_source_in=8.,HHEX_ambient_in=-3.,SMA_constitutive_in=1.5)
        result=system_balance(source,6.5,latent)
        self.assertAlmostEqual(result['external_heat_minus_total_storage_J'],0)
        self.assertTrue(result['model_equation_energy_closure_pass'])
        self.assertFalse(result['engineering_pump_proxy_added_as_heat'])

    def test_missing_or_extra_boundary_rejected(self):
        source={k:0. for k in SOURCE_ROLES}
        del source['external_load_in']
        with self.assertRaises(ValueError):
            system_balance(source,0.,latent_decomposition(*self.latent()))
        source={k:0. for k in SOURCE_ROLES};source['engineering_pump_proxy']=10.
        with self.assertRaises(ValueError):
            system_balance(source,0.,latent_decomposition(*self.latent()))

    def test_nonfinite_or_invalid_phase_rejected(self):
        t,q,x,c=self.latent();x[0,0]=1.1
        with self.assertRaises(ValueError):
            latent_decomposition(t,q,x,c)
        t,q,x,c=self.latent();q[0]=float('nan')
        with self.assertRaises(ValueError):
            latent_decomposition(t,q,x,c)

    def test_internal_work_or_pipeline_error_not_hidden(self):
        latent=latent_decomposition(*self.latent())
        source={k:0. for k in SOURCE_ROLES};source.update(SHEX_source_in=5.,SMA_constitutive_in=1.6)
        self.assertFalse(system_balance(source,6.5,latent)['model_equation_energy_closure_pass'])
        latent['internal_mechanical_cumulative_max_abs_J']=1.
        source['SMA_constitutive_in']=1.5
        self.assertFalse(system_balance(source,6.5,latent)['model_equation_energy_closure_pass'])


class InventoryTests(unittest.TestCase):
    def arrays(self):
        time=np.arange(20001)*.001
        arrays={name:dict(mass=.1+sign*1e-5*time,energy=np.zeros_like(time),
                         temperature=np.full_like(time,300.),mass_flow=np.full_like(time,sign*1e-5))
                for name,sign in zip(BUFFER_NAMES,(1,-1,1,-1))}
        return time,arrays

    def test_closed_mass_equation_does_not_mean_stationary_inventory(self):
        time,arrays=self.arrays();rows=buffer_cycle_rows(time,arrays)
        self.assertEqual(len(rows),8)
        self.assertTrue(all(r['local_mass_conservation_pass'] for r in rows))
        self.assertTrue(all(r['resolved_nonzero_mass_change'] for r in rows))
        self.assertAlmostEqual(sum(r['mass_change_kg'] for r in rows),0)

    def test_missing_buffer_or_wrong_window_rejected(self):
        time,arrays=self.arrays();del arrays[BUFFER_NAMES[0]]
        with self.assertRaises(ValueError):
            buffer_cycle_rows(time,arrays)
        time,arrays=self.arrays()
        with self.assertRaises(ValueError):
            buffer_cycle_rows(time,arrays,cycle_period=20)

    def test_equation_error_detected(self):
        time,arrays=self.arrays();arrays[BUFFER_NAMES[0]]['mass_flow']*=2
        rows=buffer_cycle_rows(time,arrays)
        self.assertFalse(all(r['local_mass_conservation_pass'] for r in rows))

    def test_constant_buffers_are_stationary(self):
        time,arrays=self.arrays()
        for data in arrays.values():
            data['mass'][:]=.1;data['mass_flow'][:]=0
        self.assertFalse(any(r['resolved_nonzero_mass_change'] for r in buffer_cycle_rows(time,arrays)))


class ChamberProjectionTests(unittest.TestCase):
    def inputs(self):
        time=np.arange(20001)*.001;local=np.mod(time,10)
        temperature=300+90*np.where(local<=5,local/5,(10-local)/5)
        pressure=np.full_like(time,8.5e5)
        table=lambda x:1000-.5*(x[:,0]-300)+1e-6*(x[:,1]-8.5e5)
        density=table(np.column_stack((temperature,pressure)));volume=1.6e-6
        mass=density*volume
        chambers={name:dict(mass=mass.copy(),temperature=temperature.copy(),pressure=pressure.copy(),
                           density=density.copy(),volume_m3=volume,density_table=table)
                  for name in CHAMBER_NAMES}
        buffers={name:dict(mass=np.full_like(time,.1)) for name in BUFFER_NAMES}
        buffers[BUFFER_NAMES[0]]['mass']-=2*(mass-mass[0])
        return time,buffers,chambers

    def test_temperature_density_exchange_matches_mass(self):
        result=chamber_inventory_projection(*self.inputs())
        self.assertTrue(result['buffer_plus_chamber_stage_mass_closure_pass'])
        self.assertEqual(len(result['chamber_cycles']),4)
        for r in result['chamber_cycles']:
            self.assertAlmostEqual(r['hot_half_mass_change_kg'],-72e-6)
            self.assertAlmostEqual(r['hot_half_mass_change_from_P_at_final_T_kg'],0)
            self.assertTrue(r['density_decomposition_exact'])

    def test_mass_density_identity_failure_rejected(self):
        time,buffers,chambers=self.inputs();chambers[CHAMBER_NAMES[0]]['mass'][0]+=.01
        with self.assertRaises(ValueError):
            chamber_inventory_projection(time,buffers,chambers)

    def test_missing_chamber_rejected(self):
        time,buffers,chambers=self.inputs();del chambers[CHAMBER_NAMES[0]]
        with self.assertRaises(ValueError):
            chamber_inventory_projection(time,buffers,chambers)

    def test_missing_compensating_mass_is_visible(self):
        time,buffers,chambers=self.inputs();buffers[BUFFER_NAMES[0]]['mass'][:]=.1
        self.assertFalse(chamber_inventory_projection(time,buffers,chambers)[
            'buffer_plus_chamber_stage_mass_closure_pass'])


if __name__=='__main__':
    unittest.main()
