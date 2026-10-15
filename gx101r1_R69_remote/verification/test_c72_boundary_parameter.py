from pathlib import Path
import unittest


class C72BoundaryParameterTests(unittest.TestCase):
    def setUp(self):
        self.root=Path(__file__).parent
        self.probe=(self.root/'Verify_HeatDriveECC_C72BoundaryParameter.m').read_text()

    def test_unchanged_control_precedes_single_declared_perturbation(self):
        self.assertIn("values=[276.95 request.candidate_Tc_K]",self.probe)
        self.assertIn("'unchanged_control','candidate'",self.probe)
        self.assertIn('BoundaryPositiveControlFailed',self.probe)

    def test_no_op_reconstruction_or_cold_reset(self):
        for forbidden in ('loggedStates=', 'SimscapeOperatingPoint', "set_param(source", 'setBlockParameter(', 'SaveFinalState'):
            self.assertNotIn(forbidden,self.probe)
        self.assertIn("candidate=input.setVariable('cold_sink_T_init',values(k)).setInitialState(initial)",self.probe)
        self.assertIn("Load_HeatDriveECC_GatedObservationPacket(q.source_packet_root,true)",self.probe)

    def test_does_not_change_compiletime_to_runtime_or_checksum_policy(self):
        self.assertIn("get_param(source,'temperature_conf'),'compiletime'",self.probe)
        self.assertIn("get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error'",self.probe)
        self.assertIn("get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error'",self.probe)

    def test_short_probe_cannot_be_promoted(self):
        self.assertIn("'complete_cycle_mechanism_gates_evaluated',false",self.probe)
        self.assertIn("'outer_solve_eligible',false",self.probe)
        self.assertIn("'new_OP_saved',false",self.probe)
        self.assertIn('NOT_A_RESUME_OR_OUTER_POINT',self.probe)

    def test_all_four_retained_memories_checked(self):
        for name in ('ECC_Constitutive21_StateDelay','SMAPressurePI_Integrator',
                     'SEStage2PressurePI_Integrator','SEStage4PressurePI_Integrator'):
            self.assertIn(name,self.probe)
        self.assertIn('nnz(selected)==4',self.probe)

    def test_resolver_keeps_probe_local_and_rejects_collection_mix(self):
        source=(self.root/'Resolve_HeatDriveECC_ObservationPreflight.m').read_text()
        self.assertIn('abs(options.candidate_Tc_K-276.95)<=.1+1e-12',source)
        self.assertIn("~any(isfield(options,[extra,{'reference_review_path'}]))",source)
        self.assertIn('Only a source-bound C72 boundary probe',source)

    def test_actual_snapshot_recorded_with_existing_ulp_clock_rule(self):
        self.assertIn('row.actual_final_snapshot_s=output.diagnostic_final_op.snapshotTime',self.probe)
        self.assertIn('row.clock_representation_allowance_s=16*eps(720.002)',self.probe)
        self.assertNotIn('snapshotTime==720.002',self.probe)


if __name__=='__main__':unittest.main()
