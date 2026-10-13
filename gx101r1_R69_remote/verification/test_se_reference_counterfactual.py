import copy
import unittest
import numpy as np

from Analyze_HeatDriveECC_SEReferenceCounterfactual import config_contract,controller_contract


class ReferenceContractTests(unittest.TestCase):
    def configs(self):
        baseline=dict(output_root='baseline',stage2_kp=-126,volume=1.6e-6)
        candidate=copy.deepcopy(baseline)
        candidate.update(output_root='candidate',diagnostic_se_reference_options={'mode':'coherent_envelope'})
        return baseline,candidate

    def test_only_reference_mode_change(self):
        config_contract(*self.configs())

    def test_hidden_gain_change_rejected(self):
        a,b=self.configs();b['stage2_kp']=-127
        with self.assertRaises(ValueError):config_contract(a,b)

    def test_hidden_geometry_change_rejected(self):
        a,b=self.configs();b['volume']*=.1
        with self.assertRaises(ValueError):config_contract(a,b)

    def references(self):
        time=np.arange(101)*.001;alpha=np.linspace(1,0,101);state=np.ones_like(time)*.01
        signals=dict(distributed_pressure_envelope=alpha,distributed_target_flow_kg_s=alpha*.0032,
            stage4_target_flow_command=alpha*.0032,stage4_integrator_state=state,
            stage4_integrator_output_gate=state*alpha)
        contract=dict(time_s=time,stroke_envelope=alpha,nominal_mass_flow_kgps=.0032,
            route_output_gates=[dict(stage=4,time_s=time,coherent_output_enable=alpha)])
        return time,signals,contract

    def test_common_reference_and_memory_output(self):
        result=controller_contract(*self.references())
        self.assertEqual(result['route_I_output_equation_max_error_MPa'],0)

    def test_legacy_full_PI_target_rejected(self):
        time,signals,contract=self.references();signals['stage4_target_flow_command'][:]=.0032
        with self.assertRaises(ValueError):controller_contract(time,signals,contract)

    def test_unscaled_memory_output_rejected(self):
        time,signals,contract=self.references();signals['stage4_integrator_output_gate']=signals['stage4_integrator_state']
        with self.assertRaises(ValueError):controller_contract(time,signals,contract)


if __name__=='__main__':unittest.main()
