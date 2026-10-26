"""Endpoint ownership and ledger semantics; compilation is a separate proof."""
import copy
from pathlib import Path
import unittest

import numpy as np

from Analyze_HeatDriveECC_CoupledCVBalance import storage,balance_window
from Review_HeatDriveECC_CoupledCVPacket import expected_storage_types


class EndpointTests(unittest.TestCase):
    def contract(self):
        buffers=['m/'+n for n in ('ColdFluidBuffer','HotFluidBuffer','SHEXFluidBuffer','SMAHotFluidBuffer')]
        chambers=['m/'+n for n in ('SMA_PumpInletConnectingPipeVolume','SMA_PumpOutletConnectingPipeVolume')]
        rows=[dict(block_path=p,mask_type=kind,source_file=source) for paths,kind,source in
              ((buffers,'Endpoint Buffer','ecc_buffer_coupled_offset.conservative_buffer'),
               (chambers,'Endpoint Chamber','ecc_inventory_endpoint.conservative_chamber')) for p in paths]
        return dict(schema='heatdrive_ecc_endpoint_CV_inventory_v1',storage_formulation='endpoint_inventory',
                    storage_paths=buffers+chambers,endpoint_buffer_paths=buffers,endpoint_chamber_paths=chambers,storage_blocks=rows)

    def test_exact_candidate_identities_are_not_native_tank_counts(self):
        c=self.contract();expected=expected_storage_types(c,'shared')
        self.assertEqual(expected,{'Pipe (TL)':46,'Endpoint Buffer':4,'Endpoint Chamber':2,'Thermal Mass':46})
        self.assertNotIn('Tank (TL)',expected)
        for mutation in ('wrong_source','wrong_name','wrong_formulation','wrong_class'):
            x=copy.deepcopy(c)
            if mutation=='wrong_source':x['storage_blocks'][0]['source_file']='ecc_buffer.conservative_buffer'
            if mutation=='wrong_name':x['endpoint_buffer_paths'][0]='m/unknown'
            if mutation=='wrong_formulation':x['storage_formulation']='native'
            if mutation=='wrong_class':x['storage_blocks'][0]['mask_type']='Tank (TL)'
            with self.assertRaises(ValueError):expected_storage_types(x,'shared')
        with self.assertRaises(ValueError):expected_storage_types(c,'dual')

    def test_endpoint_energy_includes_declared_auxiliary_inventory_not_just_Mu(self):
        t=np.array([0.,.001,.002]);path='m/fixture';native={}
        for name,value,unit in (('stored_mass',[1.,1.001,1.003],'kg'),('stored_energy',[100.,100.002,100.005],'J'),
                                ('Phi_A',[99.,2.,3.],'W'),('Q_H',[0.,0.,0.],'W'),('mdot_A',[0.,1.,2.],'kg/s')):
            native[path,name]={'time_s':t,'values':np.array(value)[:,None],'unit':unit}
        data={'time':t,'native':native,'contract':{'storage_blocks':[dict(block_path=path,mask_type='Endpoint Buffer',mask_parameters={})],
                                                 'storage_paths':[path]}}
        components=storage(data);r=balance_window(data,components,[dict(path='source',kind='fixture',role='fixture',sign=1,rule='fixture',power=np.array([99.,2.,3.]))],0.,.002)
        self.assertAlmostEqual(r['BE_identified_native_equation_residual_J'],0.,places=12)
        self.assertAlmostEqual(r['endpoint_energy_change_J'],.005,places=12)
        self.assertEqual(r['BE_tank_extra_thermal_accumulation_J'],0.)
        self.assertEqual(r['BE_tank_pressure_volume_work_out_J'],0.)
        self.assertFalse(r['full_device_first_law_verified'])

    def test_complete_constructor_not_old_empirical_flux_or_a_restart(self):
        root=Path(__file__).resolve().parent
        apply=(root/'Apply_HeatDriveECC_SharedEndpointInventory.m').read_text(encoding='utf-8')
        self.assertIn('Build_HeatDriveECC_ColdInventoryTargets',apply)
        self.assertIn("'zero_based_offset'",apply)
        self.assertIn("'initial_flux_compensation_applied',false",apply)
        self.assertNotIn('Build_HeatDriveECC_ColdInitialFluxCompensation(',apply)
        self.assertNotIn('setInitialState(',apply)
        self.assertNotIn('save_system(',apply)
        self.assertIn('record.physical_target_count==162',apply)
        self.assertIn('sort(string(reference_contract.storage_paths(:)))',apply)
        self.assertIn('sort(string(contract.storage_paths(:)))',apply)
        target=(root/'Build_HeatDriveECC_ColdInventoryTargets.m').read_text(encoding='utf-8')
        self.assertIn('expected_primary=125',target)
        self.assertIn('expected_primary=104',target)
        self.assertIn('sort(inventory.storage_paths)',target)


if __name__=='__main__':unittest.main()
