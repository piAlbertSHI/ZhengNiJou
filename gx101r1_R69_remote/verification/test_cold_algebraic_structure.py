import unittest
import copy
from pathlib import Path
from Audit_HeatDriveECC_CompiledAlgebraicStructure import check_structure


ROOT = Path(__file__).parent


class ColdAlgebraicStructureTests(unittest.TestCase):
    def test_compilation_only_and_no_solver_relaxation(self):
        source = (ROOT/'Inspect_HeatDriveECC_CompiledAlgebraicStructure.m').read_text(encoding='utf-8')
        self.assertIn("set_param(model,'SimulationCommand','update')", source)
        self.assertIn('Simulink.BlockDiagram.getAlgebraicLoops(model)', source)
        for forbidden in ('sim(', 'save_system(', 'add_block(', 'delete_block(', "'AlgebraicLoopMsg','none'"):
            self.assertNotIn(forbidden, source)

    def test_record_classification_and_variable_blocks(self):
        source = (ROOT/'Inspect_HeatDriveECC_CompiledAlgebraicStructure.m').read_text(encoding='utf-8')
        for expected in ('item.IsArtificial', 'item.VariableBlockHandles', 'item.BlockHandles',
                         "'simulation_run',false", "'production_recovery_allowed',false"):
            self.assertIn(expected, source)

    def test_declared_branch_skips_simulation(self):
        source = (ROOT/'Inspect_HeatDriveECC_ColdCompiledStates.m').read_text(encoding='utf-8')
        self.assertIn('if nargin<31,algebraic_structure_only=false;end', source)
        self.assertIn('actuate_ps_output && ~tighten_global && duration==0 && capture_runtime', source)
        branch = source.index("record.stage='compiled_algebraic_structure'")
        simulation = source.index('output=sim(input)')
        self.assertIn('else', source[branch:simulation])
        self.assertNotIn('record.simulation_run=true', source[branch:source.index('else', branch)])

    def fixture(self):
        r = dict(inspection_pass=True, algebraic_structure_only=True, stage='complete', initialization_only=True,
                 diagnostic_stop_time_s=0, states=[], simulation_run=False, production_recovery_allowed=False,
                 checkpoint_saved=False, c200_state_imported=False, failed_terminal_state_imported=False)
        keys = ('inventory_formulation', 'global_solver_configuration', 'global_tolerances_after',
                'consistency_settings_after', 'runtime_solver_options_after', 'source_native_sha256',
                'global_tolerance_override', 'initial_pressure_derivative_contract', 'pressure_value_path_contract',
                'inactive_controller_removal_contract', 'passive_ps_observer_contract', 'ps_initial_actuation_contract')
        r.update({k: k for k in keys})
        c = dict(stage='InitFcn', simulation_status='updating', targets=[dict(path=str(i)) for i in range(204)])
        c.update({k: k for k in ('solver_settings', 'global_solver_configuration', 'RelTol', 'AbsTol',
                                'runtime_solver_options', 'LoadInitialState', 'has_private_data', 'pressure_converter',
                                'passive_observer_solver', 'passive_observer_flow_input')})
        r['runtime_callbacks'] = [copy.deepcopy(c), copy.deepcopy(c)]
        blocks = []
        for group, names in [('Solver\nConfiguration', ['STATE_1','OUTPUT_1_0','INPUT_47_1_1']),
                             ('ColdObserver_Solver', ['INPUT_3_1_1','STATE_1','OUTPUT_1_1'])]:
            for name in names:
                variable = name.startswith('INPUT')
                blocks.append(dict(path='heatdrive_ecc_coupled_se21/'+group+'/EVAL_KEY/'+name,
                    is_algebraic_variable=variable, block_type='SimscapeInputBlock' if variable else 'SimscapeExecutionBlock',
                    inputs=[dict(port='1', source_block='compiled_source', source_port=0)]))
        r['algebraic_structure'] = dict(matlab_release='2025b', loop_count=1,
            loops=[dict(is_artificial=False, blocks=blocks)], simulation_run=False,
            trajectory_verified=False, production_recovery_allowed=False)
        return r, copy.deepcopy(r)

    def test_valid_collection_does_not_qualify_initialization(self):
        r,b = self.fixture(); result = check_structure(r,b)
        self.assertTrue(result['evidence_audit_pass'])
        self.assertFalse(result['initial_coordinate_gate_verified'])
        self.assertFalse(result['production_recovery_allowed'])

    def test_promotion_or_configuration_change_rejected(self):
        for key,value in [('simulation_run',True), ('production_recovery_allowed',True),
                          ('checkpoint_saved',True), ('initial_coordinates',[]),
                          ('global_tolerances_after','changed')]:
            r,b=self.fixture();r[key]=value
            with self.assertRaises(ValueError):check_structure(r,b)

    def test_loop_classification_and_nodes_cannot_be_relabelled(self):
        r,b=self.fixture();r['algebraic_structure']['loops'][0]['is_artificial']=True
        with self.assertRaises(ValueError):check_structure(r,b)
        r,b=self.fixture();r['algebraic_structure']['loops'][0]['blocks'].pop()
        with self.assertRaises(ValueError):check_structure(r,b)

    def test_callback_and_targets_cannot_be_omitted(self):
        r,b=self.fixture();r['runtime_callbacks'].pop()
        with self.assertRaises(ValueError):check_structure(r,b)
        r,b=self.fixture();r['runtime_callbacks'][0]['targets'].pop()
        with self.assertRaises(ValueError):check_structure(r,b)
        r,b=self.fixture();b['runtime_callbacks'][0]['targets'].pop()
        with self.assertRaises(ValueError):check_structure(r,b)


if __name__ == '__main__':
    unittest.main()
