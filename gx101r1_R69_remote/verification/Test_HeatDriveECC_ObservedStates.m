function Test_HeatDriveECC_ObservedStates()
% Exercise trace shape, bounded retention, finite values and incomplete windows.
    t = (0:0.1:12)';
    data = [t, 2*t];
    state = Simulink.SimulationData.State;
    state.Name = 'test';
    state.BlockPath = Simulink.SimulationData.BlockPath('test_model/state');
    state.Values = timeseries(data, t);
    states = Simulink.SimulationData.Dataset;
    states = states.addElement(state);
    observed = Extract_HeatDriveECC_ObservedStates(states, 1, 11);
    row = observed.states{1};
    assert(row.channel_count == 2 && abs(row.time_s(1) - 1) < 1e-12);
    assert(isequal(row.values, data(11:end, :)));
    assert(row.complete_requested_window);
    assert(~observed.complete_internal_state_periodicity_verified);
    observed = Extract_HeatDriveECC_ObservedStates(states, 2, 11);
    assert(~observed.states{1}.complete_requested_window);
    state.Values = timeseries(permute(data, [2 3 1]), t);
    states = Simulink.SimulationData.Dataset;
    states = states.addElement(state);
    observed = Extract_HeatDriveECC_ObservedStates(states, 1, 11);
    assert(isequal(observed.states{1}.values, data(11:end, :)));
    data(end, 2) = NaN;
    state.Values = timeseries(data, t);
    states = Simulink.SimulationData.Dataset;
    states = states.addElement(state);
    assert_rejected(@() Extract_HeatDriveECC_ObservedStates(states, 1, 11), ...
        'HeatDriveECC:NonfiniteObservedState');
    assert_rejected(@() Extract_HeatDriveECC_ObservedStates( ...
        Simulink.SimulationData.Dataset, 1, 11), 'HeatDriveECC:EmptyObservedStates');
    fprintf('OBSERVED_STATES_REGRESSION_PASS=1\n');
end

function assert_rejected(callback, expected)
    rejected = false;
    try
        callback();
    catch e
        rejected = strcmp(e.identifier, expected);
    end
    assert(rejected);
end
