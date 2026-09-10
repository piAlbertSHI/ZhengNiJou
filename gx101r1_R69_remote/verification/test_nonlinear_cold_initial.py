from copy import deepcopy
from pathlib import Path
import unittest
from Audit_HeatDriveECC_NonlinearColdInitial import target_translation,unchanged_runtime_context


def fixture():
    physical=[];components=[]
    for i in range(192):
        physical.append(dict(path=f'Other{i}/T',block_path=f'model/Other{i}',state_name='T',
            unit='K',value=300.,priority='High' if i<113 else 'Low',source_time_s=0))
    for i in range(6):
        mass=.1+i*.001;energy=10000.+i;kind='chamber' if i<2 else 'buffer'
        mn=mass if kind=='chamber' else 1.;en=energy if kind=='chamber' else 1.
        c=dict(block_path=f'model/Inventory{i}',kind=kind,mass_reference_kg=mass,mass_scale_kg=mass,
               energy_reference_J=energy,mass_nominal_kg=mn,energy_nominal_J=en,mass_coordinate_nominal=mn/mass)
        components.append(c)
        for name,unit,val in [('stored_mass','kg',mass),('stored_energy','J',energy)]:
            physical.append(dict(path=f'Inventory{i}/{name}',block_path=c['block_path'],state_name=name,
                                 unit=unit,value=val,priority='High',source_time_s=0))
    runtime=deepcopy(physical)
    for t in runtime[192:]:
        mass=t['state_name']=='stored_mass';t['state_name']='mass_coordinate' if mass else 'energy_delta'
        t['path']=t['path'].rsplit('/',1)[0]+'/'+t['state_name'];t['unit']='1' if mass else 'J';t['value']=0
    return physical,runtime,components


class NonlinearColdInitialTests(unittest.TestCase):
    def test_held_entry_requires_frozen_strict_initial_evidence(self):
        source=(Path(__file__).parent/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn('nonlinear_held=nonlinear_inventory && external_lag && (duration==.04 || pre_feedback);',source)
        self.assertIn('B78B380C37F30077A9189F8EFBBB3E9CB4B85C2413B1C07D21C9D15B591F2E66',source)
        self.assertIn('initial_proof.strict_matching_count==204',source)
        self.assertIn('~initial_proof.production_recovery_allowed',source)
        self.assertIn('record.nonlinear_initial_qualification_sha256=file_hash(initial_audit)',source)

    def test_204_targets_map_without_physical_changes(self):
        r=target_translation(*fixture())
        self.assertEqual((r['translated'],r['unchanged']),(12,192))
        self.assertFalse(r['full_solver_error_weights_verified'])

    def test_nonzero_coordinate_target_rejected(self):
        p,r,c=fixture();r[192]['value']=1e-6
        with self.assertRaises(ValueError):target_translation(p,r,c)

    def test_noninventory_priority_change_rejected(self):
        p,r,c=fixture();r[0]['priority']='Low'
        with self.assertRaises(ValueError):target_translation(p,r,c)

    def test_wrong_mass_nominal_rejected(self):
        p,r,c=fixture();c[-1]['mass_coordinate_nominal']*=1.1
        with self.assertRaises(ValueError):target_translation(p,r,c)

    def test_duplicate_component_rejected(self):
        p,r,c=fixture();c[-1]=c[0]
        with self.assertRaises(ValueError):target_translation(p,r,c)

    def test_controller_changes_not_hidden_by_target_mapping(self):
        reference=dict(pressure_converter=dict(StopTime='.04',derivative_source='held'),
                       targets=[],buffer_nominals=[],chamber_nominals=[],held_interval_contract={},lag=0.)
        current=deepcopy(reference);current.pop('held_interval_contract');current['AutoScaleAbsTol']='on'
        current['pressure_converter']=dict(StopTime='0',derivative_source='heatdrive_ecc_coupled_se21/ColdInitialPressureDerivativeOnly')
        unchanged_runtime_context(current,reference)
        current['lag']=1.
        with self.assertRaises(ValueError):unchanged_runtime_context(current,reference)


if __name__=='__main__':unittest.main()
