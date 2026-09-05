function Test_HeatDriveECC_ObservationGates()
% Nonperiodic physical passes must not be mislabeled as energy/mass failures.
    energy = struct('mechanism_pass', true, 'periodic_steady_state', false, ...
        'local_exchanger_kcl_pass', true, 'boundary_direction_pass', true, ...
        'fluid_mass_conservation_pass', true, 'modeled_thermal_closure_pass', true, ...
        'production_pass', false);
    c = Classify_HeatDriveECC_ObservationGates(energy);
    assert(c.physical_gates_pass && ~c.production_pass && ...
        strcmp(c.status, 'transient_observation_complete'));
    energy.periodic_steady_state = true;
    energy.production_pass = true;
    c = Classify_HeatDriveECC_ObservationGates(energy);
    assert(c.production_pass && ~c.steady_parameter_study_allowed && ...
        ~c.complete_internal_state_periodicity_verified);
    names = {'mechanism_pass','local_exchanger_kcl_pass', ...
        'boundary_direction_pass','fluid_mass_conservation_pass','modeled_thermal_closure_pass'};
    for k = 1:numel(names)
        failed = energy;
        failed.(names{k}) = false;
        failed.production_pass = false;
        c = Classify_HeatDriveECC_ObservationGates(failed);
        assert(~c.physical_gates_pass && strcmp(c.status, 'physical_gate_failure'));
    end
    energy.production_pass = false;
    caught = false;
    try
        Classify_HeatDriveECC_ObservationGates(energy);
    catch e
        caught = strcmp(e.identifier, 'HeatDriveECC:InconsistentObservationGate');
    end
    assert(caught);
    fprintf('OBSERVATION_GATE_CLASSIFICATION_PASS=1\n');
end
