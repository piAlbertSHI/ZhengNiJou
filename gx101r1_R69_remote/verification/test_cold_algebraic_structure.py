import unittest
from pathlib import Path


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


if __name__ == '__main__':
    unittest.main()
