import unittest
import numpy as np
from Analyze_HeatDriveECC_InventoryRoundoffReplay import replay
from Audit_HeatDriveECC_TRBDF2InterfaceFailure import derivative_requirements, MODEL


class RoundoffReplayTests(unittest.TestCase):
    def test_offset_loses_individual_sub_ulp_increments(self):
        t=np.arange(101,dtype=float)
        a,s,r,_=replay(t,1.,np.full(101,2.**-55),[],1.)
        self.assertTrue(np.all(a==1.))
        np.testing.assert_array_equal(s,r)
        self.assertGreater(s[-1],a[-1])

    def test_reset_uses_right_endpoint_only_on_declared_interval(self):
        a,s,r,tr=replay([0,1,2,3],0.,[0,1,2,3],[1],1.)
        np.testing.assert_array_equal(a,[0,.5,2.5,5.])
        np.testing.assert_array_equal(s,r)
        np.testing.assert_array_equal(tr,[.5,1.5,2.5])

    def test_reject_invalid_inputs(self):
        cases=[([0,0],[1,1],[],1.),([0,1],[1],[],1.),
               ([0,1],[1,np.nan],[],1.),([0,1],[1,1],[1,1],1.),
               ([0,1],[1,1],[],0.),([0,1],[1,1],[],np.inf)]
        for t,f,resets,scale in cases:
            with self.subTest(case=(t,f,resets,scale)), self.assertRaises(ValueError):
                replay(t,1.,f,resets,scale)


class DerivativeFailureTests(unittest.TestCase):
    def message(self,path=None):
        path=path or MODEL+'/Heat'
        return (f"...'{path}' (\u9700\u8981 1 \u4e2a\uff0c\u63d0\u4f9b\u4e86 0 \u4e2a)\n"
                '\u4ee5\u4e0b Simulink-PS Converter \u6a21\u5757\u5177\u6709\u8fde\u7eed\u8f93\u5165\n'
                f"...'{MODEL}/Controller' (\u9700\u8981 2 \u4e2a\uff0c\u63d0\u4f9b\u4e86 1 \u4e2a)")

    def test_two_input_classes(self):
        rows=derivative_requirements(self.message())
        self.assertEqual([x['input_kind'] for x in rows],['piecewise_constant','continuous'])
        self.assertEqual(rows[1]['provided_derivatives'],1)

    def test_reject_duplicate_and_foreign_blocks(self):
        for path in (MODEL+'/Controller','other/Heat'):
            with self.subTest(path=path),self.assertRaises(ValueError):
                derivative_requirements(self.message(path))

    def test_reject_unknown_localization(self):
        with self.assertRaises(ValueError):derivative_requirements('Unknown failure')


if __name__=='__main__':unittest.main()
