import unittest
from pathlib import Path

from Close_HeatDriveECC_SplitObservation import compact_evidence, validate_comparison, validate_gate


class SplitObservationCloseoutTests(unittest.TestCase):
    def comparison(self):
        value={'pass':True}
        for name,count in (('states',74),('native',1262),('sources',162),('public',201)):
            value[name]=dict(pass_=True,bitwise_values_equal=True,trace_count=count,max_tolerance_ratio=0,channel_count=1414)
            value[name]['pass']=value[name].pop('pass_')
        return value

    def gate(self):
        return dict(gate_pass=True,original_mechanism_count=73,original_mechanism_pass=True,
            six_local_inventory_gates=[True]*6,storage_count=119,source_count=49,
            modeled_energy_balance=dict(model_equation_energy_closure_pass=True,energy_tolerance_J=1e-8,
                external_heat_minus_total_storage_J=5e-10,numerical_terms_retained_residual_J=5e-10),
            flow_gates=[{'selected_flow_gate':True} for _ in range(6)],
            production_recovery_allowed=False,outer_solve_eligible=False)

    def test_complete_exact_comparison_accepted(self):validate_comparison(self.comparison())

    def test_tolerance_only_pass_does_not_grant_exact_endpoint_qualification(self):
        value=self.comparison();value['states']['bitwise_values_equal']=False
        with self.assertRaises(ValueError):validate_comparison(value)

    def test_missing_state_coordinate_rejected(self):
        value=self.comparison();value['states']['channel_count']=1413
        with self.assertRaises(ValueError):validate_comparison(value)

    def test_complete_energy_gate_accepted(self):validate_gate(self.gate())

    def test_vacuous_flow_gate_rejected(self):
        value=self.gate();value['flow_gates']=[]
        with self.assertRaises(ValueError):validate_gate(value)

    def test_loosened_energy_tolerance_rejected(self):
        value=self.gate();value['modeled_energy_balance']['energy_tolerance_J']=1e-6
        with self.assertRaises(ValueError):validate_gate(value)

    def test_false_energy_pass_label_cannot_hide_actual_residual(self):
        value=self.gate();value['modeled_energy_balance']['external_heat_minus_total_storage_J']=1e-5
        with self.assertRaises(ValueError):validate_gate(value)

    def test_outer_authority_not_inherited_from_packet(self):
        value=self.gate();value['outer_solve_eligible']=True
        with self.assertRaises(ValueError):validate_gate(value)

    def test_generated_full_arrays_are_not_compact_because_they_are_JSON(self):
        self.assertFalse(compact_evidence(Path('distributed_pressure_ff_contract.json'),100))
        self.assertFalse(compact_evidence(Path('thermal_connectivity.json'),100))
        self.assertTrue(compact_evidence(Path('packet_gate.json'),100))


if __name__=='__main__':unittest.main()
