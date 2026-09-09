import copy
import unittest
from pathlib import Path
from Audit_HeatDriveECC_ColdInitializationPhases import check_callbacks, check_phases, target_map, check_buffer_nominals, check_momentum_rows, check_regularization, check_half_step, RUNTIME_BASE, BASE, audit


class ColdInitializationPhasesTests(unittest.TestCase):
    def targets(self):
        return [dict(path='p/T', unit='K', priority='High', value=300.)]

    def callbacks(self):
        return [dict(stage=s, simulation_status='terminating' if s == 'StopFcn' else 'initializing',
                     solver_settings={}, RelTol='1e-2', AbsTol='1e-3', SimscapeUseOperatingPoints='on',
                     LoadInitialState='off', has_private_data=False, mode='accelerator', targets=self.targets())
                for s in ('InitFcn', 'StartFcn', 'StopFcn')]

    def test_callback_targets_and_settings(self):
        rows = self.callbacks(); tol = dict(RelTol='1e-2', AbsTol='1e-3')
        check_callbacks(rows, self.targets(), {}, tol)
        rows[1]['targets'][0]['value'] = 301.
        with self.assertRaises(ValueError): check_callbacks(rows, self.targets(), {}, tol)

    def test_callback_order_or_private_source_rejected(self):
        tol = dict(RelTol='1e-2', AbsTol='1e-3')
        with self.assertRaises(ValueError): check_callbacks(self.callbacks()[::-1], self.targets(), {}, tol)
        rows = self.callbacks(); rows[0]['has_private_data'] = True
        with self.assertRaises(ValueError): check_callbacks(rows, self.targets(), {}, tol)

    def test_prestart_matching_does_not_imply_start_matching(self):
        start = copy.deepcopy(self.targets()); start[0]['value'] = 300.00001
        phases = [dict(phase=s, cache_requested=True, private_payload_exported=False, public_targets=t)
                  for s, t in [('Prestart', self.targets()), ('Start', start)]]
        measured = [dict(path='p/T', unit='K', priority='High', actual=300.00001)]
        check_phases(phases, self.targets(), measured)
        measured[0]['actual'] = 300.
        with self.assertRaises(ValueError): check_phases(phases, self.targets(), measured)

    def test_duplicate_phase_targets_rejected(self):
        with self.assertRaises(ValueError): target_map(self.targets()*2)

    def test_callback_is_read_only_for_model(self):
        source = (Path(__file__).parent/'Capture_HeatDriveECC_ColdInitializationContext.m').read_text(encoding='utf-8')
        for forbidden in ('set_param(', 'sim(', 'save_system(', 'simscape.op.create(', 'set(point,'):
            self.assertNotIn(forbidden, source)

    def test_explicit_normal_mode_does_not_accept_accelerator(self):
        rows = self.callbacks(); tol = dict(RelTol='1e-2', AbsTol='1e-3')
        with self.assertRaises(ValueError): check_callbacks(rows, self.targets(), {}, tol, 'normal')
        for row in rows: row['mode'] = 'normal'
        check_callbacks(rows, self.targets(), {}, tol, 'normal')
        with self.assertRaises(ValueError): check_callbacks(rows, self.targets(), {}, tol, 'rapid-accelerator')

    def nominal_fixture(self):
        targets = []; changes = []; active = []
        for name in ('ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer'):
            for state, unit, v in [('stored_mass', 'kg', .1), ('stored_energy', 'J', 8000.)]:
                targets.append(dict(path=name+'/'+state, unit=unit, value=v))
                changes.append(dict(block_path='model/'+name, state_name=state, source_time_s=0,
                    nominal_value=v, unit=unit, before=dict(specify='off', value='1', unit=unit)))
                active.append(dict(block_path='model/'+name, state_name=state, specify='on', value=str(v), unit=unit))
        return targets, dict(buffer_nominal_changes=changes, buffer_nominal_scaling_requested=True,
            runtime_callbacks=[dict(normalize_using_nominal_values='on', buffer_nominals=active)])

    def test_nominals_derive_from_unchanged_targets(self):
        targets, r = self.nominal_fixture(); check_buffer_nominals(r, targets)
        r['buffer_nominal_changes'][0]['nominal_value'] *= 2
        with self.assertRaises(ValueError): check_buffer_nominals(r, targets)

    def test_nominal_runtime_or_coverage_mismatch_rejected(self):
        targets, r = self.nominal_fixture(); r['runtime_callbacks'][0]['buffer_nominals'][0]['value'] = '2'
        with self.assertRaises(ValueError): check_buffer_nominals(r, targets)
        targets, r = self.nominal_fixture(); r['buffer_nominal_changes'].pop()
        with self.assertRaises(ValueError): check_buffer_nominals(r, targets)

    def momentum_fixture(self):
        contracts = []; rows = []
        for name in ('ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer'):
            path = 'model/'+name
            contracts.append(dict(block_path=path, candidate_source_file='ecc_buffer_momentum.conservative_buffer',
                initial_source_time_s=0, tank_area_m2=.001, port_area_m2=.01, inlet_height_m=0,
                gravity_m_s2=9.81, p_environment_Pa=1e6, mainline_recovery_allowed=False,
                original_conserving_ports=[dict(name='A', interface_type='Domain', side='LConn', index=1,
                    domain='foundation.thermal_liquid.thermal_liquid', connected=True),
                    dict(name='H', interface_type='Domain', side='RConn', index=1, domain='foundation.thermal.thermal', connected=False)],
                removed_unconnected_outputs=[dict(name=n, interface_type='Output', domain='', connected=False) for n in ('L_out','T_out','V_out')]))
            rows.append(dict(block_path=path, source_time_s=0, mdot_A=-.1, rho_port=1000.,
                             dynamic_pressure=.05, p_A=1000980.95, rho_I=1000., level=.1))
        return contracts, rows

    def test_momentum_initial_contract(self):
        c, rows = self.momentum_fixture()
        self.assertEqual(len(check_momentum_rows(c, rows)), 4)
        rows[0]['dynamic_pressure'] = 0
        with self.assertRaises(ValueError): check_momentum_rows(c, rows)

    def test_momentum_duplicates_and_changed_geometry_rejected(self):
        c, rows = self.momentum_fixture(); rows[1] = rows[0]
        with self.assertRaises(ValueError): check_momentum_rows(c, rows)
        c, rows = self.momentum_fixture(); c[0]['port_area_m2'] = .0001
        with self.assertRaises(ValueError): check_momentum_rows(c, rows)
        with self.assertRaises(ValueError): audit(None, scaling_mode=True, momentum=True)

    def regularization_fixture(self):
        return dict(disable_regularization_requested=True,runtime_solver_options_before=RUNTIME_BASE,
            runtime_solver_options_after=dict(RUNTIME_BASE,ResolveIndetEquations='off'),
            runtime_callbacks=[dict(runtime_solver_options=dict(RUNTIME_BASE,ResolveIndetEquations='off')) for _ in range(3)],
            momentum_buffers_requested=False,normal_mode_requested=False,buffer_nominal_scaling_requested=False,
            global_tolerance_override=False,consistency_tolerance_override=[],residual_tolerance_override=[])

    def test_regularization_runtime_visible_and_isolated(self):
        r=self.regularization_fixture();check_regularization(r)
        r['runtime_callbacks'][0]['runtime_solver_options']['ResolveIndetEquations']='on'
        with self.assertRaises(ValueError):check_regularization(r)
        r=self.regularization_fixture();r['runtime_solver_options_after']['DoFixedCost']='on'
        with self.assertRaises(ValueError):check_regularization(r)
        with self.assertRaises(ValueError):audit(None,momentum=True,regularization=True)

    def test_half_step_preserves_tolerances_and_runtime(self):
        r=self.regularization_fixture();r.update(disable_regularization_requested=False,half_step_requested=True,
            fixed_step_before=.001,fixed_step_after=.0005,consistency_settings_before=BASE,
            consistency_settings_after=dict(BASE,LocalSolverSampleTime='0.0005'),runtime_solver_options_after=RUNTIME_BASE,
            runtime_callbacks=[dict(global_fixed_step='0.0005',runtime_solver_options=RUNTIME_BASE) for _ in range(3)])
        check_half_step(r)
        r['fixed_step_after']=.0001
        with self.assertRaises(ValueError):check_half_step(r)
        with self.assertRaises(ValueError):audit(None,half_step=True,regularization=True)


if __name__ == '__main__': unittest.main()
