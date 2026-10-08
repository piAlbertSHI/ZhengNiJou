function Verify_HeatDriveECC_SavedDirectionalPressure(root)
% Read-only extraction parity test on actual completed cold evidence.
    folder=fullfile(root,'native');stored=load(fullfile(folder,'configuration.mat'),'options');
    saved=load(fullfile(folder,'observations.mat'),'signals','thermal_boundary_signals');
    view=Slice_HeatDriveECC_SavedMechanismObservation(saved,0,20,stored.options.simulation.fixed_step_s);
    physical=Extract_HeatDriveECC_PhysicalLogs(view,stored.options,'',false);
    pressure=Audit_HeatDriveECC_DirectionalPressureObservation(physical,stored.options);assert(pressure.pass);
    prefixes={'sma','se_stage2','se_stage4'};
    for k=1:3
        assert(isequaln(physical.pump_pressure_port_A_MPa(:,k), ...
            view.signals.(sprintf('pump_pressure_%s_port_a_MPa',prefixes{k})).values));
        assert(isequaln(physical.pump_pressure_port_B_MPa(:,k), ...
            view.signals.(sprintf('pump_pressure_%s_port_b_MPa',prefixes{k})).values));
    end
    fprintf('%s\n',jsonencode(struct('saved_six_pressure_faces_exact',true, ...
        'actual_pressure_domain_pass',true,'simulation_executed',false,'production_recovery_allowed',false)));
end
