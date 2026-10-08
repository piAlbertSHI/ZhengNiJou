import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class DirectionalPressureContractTests(unittest.TestCase):
    def test_direction_is_bound_to_named_actual_wires_and_vendor_equation(self):
        text = (ROOT / 'Audit_HeatDriveECC_PressureReferenceTopology.m').read_text()
        self.assertIn("'SE_Stage2_PistonPressureSource','B','SE_ColdChamberJunction','C'", text)
        self.assertIn("'SMA Pressure Source (TL)','A','SMA_PumpInletConnectingPipeVolume','B'", text)
        self.assertIn('B.p - A.p == p_diff;', text)
        self.assertIn('p_diff = P;', text)
        self.assertIn('get_param(block,\'tank_pressure_unit\')', text)
        self.assertIn("get_param(block,'pressure_spec')", text)

    def test_runtime_pressure_is_not_approved_by_static_configuration(self):
        text = (ROOT / 'Audit_HeatDriveECC_DirectionalPressureObservation.m').read_text()
        self.assertIn('size(a,2)~=3', text)
        self.assertIn('head_error<=c.reference_head_budget_MPa+tolerance', text)
        self.assertIn('record.pass=domain && head && interval', text)
        self.assertIn("'entire_network_pressure_proven',false", text)
        validator = (ROOT / 'Validate_HeatDriveECC_EighthRound_Physics.m').read_text()
        self.assertIn('checks.named_source_pressure_domain_and_reference_head=directional_pressure.pass', validator)

    def test_probe_faces_cannot_be_replaced_by_a_generic_pressure_difference(self):
        text = (ROOT / 'Extract_HeatDriveECC_PhysicalLogs.m').read_text()
        self.assertNotIn("{'p_A', 'P_A', 'p'}", text)
        self.assertNotIn("{'p_B', 'P_B', 'p'}", text)
        self.assertIn('if probe_available', text)

    def test_final_limits_do_not_reinitialize_the_integrated_controller(self):
        text = (ROOT / 'Build_HeatDriveECC_EighthRound_Simulink_Model.m').read_text()
        boundary = text.split('options = Configure_HeatDriveECC_PressureCommandDomain(model_name, options);')[1]
        boundary = boundary.split('pipe_ua_audit =')[0]
        self.assertNotIn('assign_mature_exchange_workspace(', boundary)
        self.assertIn("assignin('base',limits{k},options.branch.(limits{k}))", boundary)


if __name__ == '__main__':
    unittest.main()
