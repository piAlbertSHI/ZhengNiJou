function Test_HeatDriveECC_DirectionalPressureObservation(options)
% Synthetic counterexamples test the predicate, never qualify a trajectory.
    c=options.validation.pressure_command_domain_contract;
    physical.pump_pressure_port_names=c.named_reference_topology.source_names;
    physical.pump_pressure_port_A_MPa=repmat([.851,1.35,1.35],4,1);
    physical.pump_pressure_port_B_MPa=repmat([.501,.85,.85],4,1);
    record=Audit_HeatDriveECC_DirectionalPressureObservation(physical,options);assert(record.pass);
    bad=physical;bad.pump_pressure_port_B_MPa(1,2)=.87;
    record=Audit_HeatDriveECC_DirectionalPressureObservation(bad,options);assert(~record.pass);
    bad=physical;bad.pump_pressure_port_B_MPa(1,1)=.449;
    record=Audit_HeatDriveECC_DirectionalPressureObservation(bad,options);assert(~record.pass);
    bad=physical;bad.pump_pressure_port_A_MPa(1,2)=1.36;
    record=Audit_HeatDriveECC_DirectionalPressureObservation(bad,options);assert(~record.pass);
    bad=physical;bad.pump_pressure_port_names{2}=bad.pump_pressure_port_names{1};
    record=Audit_HeatDriveECC_DirectionalPressureObservation(bad,options);assert(~record.pass);
    bad=physical;bad.pump_pressure_port_A_MPa(1,3)=NaN;
    record=Audit_HeatDriveECC_DirectionalPressureObservation(bad,options);assert(~record.pass);
end
