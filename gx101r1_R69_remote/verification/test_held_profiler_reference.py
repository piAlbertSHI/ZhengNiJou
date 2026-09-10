import unittest
from Audit_HeatDriveECC_HeldProfilerReference import check_summary


class HeldProfilerReferenceTests(unittest.TestCase):
    def test_summary_is_only_qualified_for_observed_case(self):
        s=dict(solver='ode23t',tStart=0,tStop=.04,absTol=1e-8,relTol=1e-6,hMax=.00025,hAverage=.00025,
            steps=160,zcNumber=0,resetNumber=40,jacobianNumber=40,exceptionNumber=0,profileTime=8)
        check_summary(s)
        for k,v in [('exceptionNumber',1),('steps',0),('tStop',.03),('jacobianNumber',0),('profileTime',float('nan'))]:
            with self.assertRaises(ValueError):check_summary(dict(s,**{k:v}))
