function record = Test_HeatDriveECC_SavedMechanismObservation()
    names = {'probe_pressure_MPa', 'probe_phase_fraction', 'probe_fluid_T_K', ...
        'fluid_temp_out', 'stage4_inlet_temperature_delay', 'probe_flow_kgps'};
    assert(isequal(HeatDriveECC_IsTemperatureSignal(names), [false false true true true false]));
    row = struct('time_s', (0:.001:.004)', 'values', (300:304)');
    saved = struct('signals', struct('fluid_temp_out', row), ...
        'thermal_boundary_signals', struct('extraction_pass', true, ...
            'time_s', row.time_s, 'fields', struct('shex_fluid_heat_flow_W', row)));
    original = saved;
    view = Slice_HeatDriveECC_SavedMechanismObservation(saved, .001, .003, .001);
    assert(isequaln(saved, original) && isequal(view.signals.fluid_temp_out.values, (301:303)'));
    assert(~view.simulation_executed && ~view.production_recovery_allowed && view.read_only);
    invalid = saved; invalid.signals.fluid_temp_out.time_s(3) = .0021;
    expect_failure(@() Slice_HeatDriveECC_SavedMechanismObservation(invalid, .001, .003, .001));
    invalid = saved; invalid.signals.fluid_temp_out.time_s(3) = .001;
    expect_failure(@() Slice_HeatDriveECC_SavedMechanismObservation(invalid, .001, .003, .001));
    invalid = saved; invalid.thermal_boundary_signals.fields.shex_fluid_heat_flow_W.time_s(3) = .0021;
    expect_failure(@() Slice_HeatDriveECC_SavedMechanismObservation(invalid, .001, .003, .001));
    expect_failure(@() Slice_HeatDriveECC_SavedMechanismObservation(saved, .001, .006, .001));
    record = struct('schema', 'heatdrive_ecc_saved_mechanism_observation_test_v1', ...
        'temperature_dimension_filter_pass', true, 'exact_slice_pass', true, ...
        'input_unchanged', true, 'rejected_invalid_windows', 4, 'simulation_executed', false);
    fprintf('%s\n', jsonencode(record));
end

function expect_failure(action)
    rejected = false;
    try, action(); catch, rejected = true; end
    assert(rejected, 'Malformed observation window was accepted.');
end
