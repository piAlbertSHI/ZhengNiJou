import unittest

from Audit_HeatDriveECC_StateTargetMapping import match_targets


class StateTargetMappingTests(unittest.TestCase):
    def sample(self):
        return ([dict(path='pipe/T_I',unit='K',priority='High',value=300)],
                {'pipe/T_I':dict(unit='K',time_s=[2000,2000.001],values=[342,341.9])})

    def test_first_sample_not_default_or_endpoint(self):
        targets, native = self.sample()
        rows, missing = match_targets(targets,native)
        self.assertEqual(rows[0]['c200_value'],342)
        self.assertEqual(rows[0]['difference_from_declared'],42)
        self.assertEqual(missing,[])

    def test_low_priority_not_silently_promoted(self):
        targets,native=self.sample()
        targets[0]['priority']='Low'
        self.assertEqual(match_targets(targets,native)[0][0]['priority'],'Low')

    def test_missing_active_rejected(self):
        targets,_=self.sample()
        with self.assertRaisesRegex(ValueError,'lacks'):
            match_targets(targets,{})

    def test_unknown_algebraic_not_filled(self):
        targets,_=self.sample()
        targets[0]['priority']='None'
        self.assertEqual(match_targets(targets,{}),([],['pipe/T_I']))

    def test_unit_mismatch_rejected(self):
        targets,native=self.sample()
        native['pipe/T_I']['unit']='degC'
        with self.assertRaisesRegex(ValueError,'Unit mismatch'):
            match_targets(targets,native)

    def test_duplicate_identity_rejected(self):
        targets,native=self.sample()
        with self.assertRaisesRegex(ValueError,'Duplicate'):
            match_targets(targets*2,native)

    def test_bad_grid_and_nonfinite_rejected(self):
        for field,value in [('time_s',[2000.001,2000.002]),('values',[float('nan'),342]),('values',[342])]:
            with self.subTest(field=field,value=value):
                targets,native=self.sample()
                native['pipe/T_I'][field]=value
                with self.assertRaises(ValueError):
                    match_targets(targets,native)

    def test_unknown_priority_rejected(self):
        targets,native=self.sample()
        targets[0]['priority']='Required'
        with self.assertRaisesRegex(ValueError,'priority'):
            match_targets(targets,native)


if __name__ == '__main__':
    unittest.main()
