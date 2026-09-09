import unittest
from Audit_HeatDriveECC_ColdPSControllerRejection import reject_state_promotion, check_connections, check_constant_derivative_inputs


def converter_fixture():
    prefix = 'heatdrive_ecc_coupled_se21/'
    commands, rows = [], []
    for name, unit in zip(('bias', 'target', 'enable', 'reset'), ('MPa', 'kg/s', '1', '1')):
        c = dict(block=prefix+name, variable=name, time_s=[0., 1.], values=[0., 0.], interpolate='on')
        commands.append(c)
        value = dict(path=c['block'], type='FromWorkspace', sample_time='0', **{k: c[k] for k in ('variable', 'time_s', 'values', 'interpolate')})
        derivative = dict(path=prefix+'ColdSMA_'+name+'_PS_Derivative', type='FromWorkspace',
                          interpolate='off', time_s=[0., 1.], values=[0., 0.])
        if name == 'bias':
            derivative = dict(path=derivative['path'], type='Constant', sample_time='inf', value='0')
        rows.append(dict(path=prefix+'ColdSMA_'+name+'_PS', Unit=unit, FilteringAndDerivatives='provide',
                         UdotUserProvided='1', inputs=[value, derivative]))
    rows.append(dict(path=prefix+'ColdSMA_InitialMdot_PS', Unit='kg/s', FilteringAndDerivatives='provide',
                     UdotUserProvided='1', inputs=[dict(path=prefix+'ColdSMA_InitialMdot', type='Constant', value='-1e-9'),
                     dict(path=prefix+'ColdSMA_InitialMdot_Derivative', type='Constant', value='0')]))
    return rows, commands


class ColdPSRejectionTests(unittest.TestCase):
    def test_explicit_derivative_inputs(self):
        rows, commands = converter_fixture()
        self.assertTrue(check_constant_derivative_inputs(rows, commands, -1e-9))

    def test_connected_but_disabled_derivative_rejected(self):
        rows, commands = converter_fixture()
        rows[0]['FilteringAndDerivatives'] = 'filter'
        with self.assertRaises(ValueError):
            check_constant_derivative_inputs(rows, commands, -1e-9)

    def test_wrong_constant_sample_time_rejected(self):
        rows, commands = converter_fixture()
        rows[0]['inputs'][1]['sample_time'] = '0'
        with self.assertRaises(ValueError):
            check_constant_derivative_inputs(rows, commands, -1e-9)

    def test_nonfinite_derivative_rejected(self):
        rows, commands = converter_fixture()
        rows[1]['inputs'][1]['values'][0] = float('nan')
        with self.assertRaises(ValueError):
            check_constant_derivative_inputs(rows, commands, -1e-9)

    def test_frozen_flow_has_distinct_failure_signature(self):
        r = dict(inspection_pass=False, stage='initialization_state_logging', states=[],
                 c200_state_imported=False, failed_terminal_state_imported=False,
                 checkpoint_saved=False, production_recovery_allowed=False,
                 error_message=' '.join(f'SMA_Pump{side}ConnectingPipeVolume.stored_{state}'
                                        for side in ('Inlet', 'Outlet') for state in ('mass', 'energy')))
        self.assertEqual(len(reject_state_promotion(r, True)), 4)
        with self.assertRaises(ValueError):
            reject_state_promotion(r)
        r['error_message'] += ' ColdSMAPSController.error_lag.Y'
        with self.assertRaises(ValueError):
            reject_state_promotion(r, True)

    def test_wrong_error_is_not_an_accepted_rejection(self):
        r = dict(inspection_pass=False, stage='initialization_state_logging', states=[],
                 c200_state_imported=False, failed_terminal_state_imported=False,
                 checkpoint_saved=False, production_recovery_allowed=False, error_message='unrelated failure')
        with self.assertRaises(ValueError):
            reject_state_promotion(r)

    def test_failed_states_cannot_be_promoted(self):
        with self.assertRaises(ValueError):
            reject_state_promotion(dict(inspection_pass=True))

    def test_boundary_differences_and_duplicates_rejected(self):
        rows = [dict(block='b', port=str(k), domain='thermal') for k in range(1183)]
        c = dict(physical_connections_before=rows, physical_connections_after=rows,
                 physical_connections_unchanged=True)
        self.assertEqual(check_connections(c), 1183)
        c['physical_connections_after'] = rows[:-1]
        with self.assertRaises(ValueError):
            check_connections(c)
        c['physical_connections_before'] = [rows[0]] * 1183
        c['physical_connections_after'] = c['physical_connections_before']
        with self.assertRaises(ValueError):
            check_connections(c)


if __name__ == '__main__':
    unittest.main()
