import unittest
from pathlib import Path

from Audit_HeatDriveECC_ColdChamberRejection import check_topology, check_targets


class ColdChamberTests(unittest.TestCase):
    def test_changed_edge_rejected(self):
        a=dict(vertices=[{'key':'a'},{'key':'b'}],edges=[])
        b=dict(vertices=a['vertices'],edges=[dict(kind='physical_wire_net',a=1,b=2)])
        with self.assertRaisesRegex(ValueError,'edges changed'): check_topology(a,b)

    def test_empty_target_set_rejected(self):
        with self.assertRaisesRegex(ValueError,'coverage'): check_targets([],{},1,'hash')

    def test_cold_runner_does_not_import_checkpoint(self):
        source=(Path(__file__).parent/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text()
        self.assertIn("overrides.simulation.resume_checkpoint_path='';",source)
        self.assertIn("'LoadInitialState','off','SimscapeUseOperatingPoints','off'",source)
        self.assertNotIn('.setInitialState(',source)
        self.assertIn("'SaveFinalState','off','SaveOperatingPoint','off'",source)

    def test_library_hook_cannot_write_mainline(self):
        source=(Path(__file__).parent.parent/'Integrate_HeatDriveECC_Constitutive21_Interface.m').read_text(encoding='utf-8')
        self.assertIn('assert(isempty(options.simulation.resume_checkpoint_path)',source)
        self.assertIn('assert(~options.simulation.persist_model_configuration',source)

    def test_endpoint_variant_is_equation_identical_and_explicitly_gated(self):
        root=Path(__file__).parent
        endpoint=(root/'simscape_inventory_endpoint/+ecc_inventory_endpoint/conservative_chamber.ssc').read_text()
        specific=(root/'simscape_inventory_specific/+ecc_inventory_specific/conservative_chamber.ssc').read_text()
        self.assertEqual(endpoint,specific.replace(
            '% Conservative Inventory Chamber (TL)\n% Diagnostic alternative: differentiate stored mass and energy themselves.',
            '% Endpoint-contract chamber diagnostic.\n% This isolated variant exposes stored mass and energy as explicit states so\n% endpoint inventories use the same state variables as the differential ledger.'))
        runner=(root/'Run_HeatDriveECC_ColdChamberDiagnostic.m').read_text()
        self.assertIn('endpoint_chamber_diagnostic',runner)
        self.assertIn('endpoint_chamber_diagnostic && cycle_count == 1',runner)
        target_builder=(root/'Build_HeatDriveECC_ColdInventoryTargets.m').read_text()
        self.assertIn('ecc_inventory_endpoint.conservative_chamber',target_builder)


if __name__=='__main__': unittest.main()
