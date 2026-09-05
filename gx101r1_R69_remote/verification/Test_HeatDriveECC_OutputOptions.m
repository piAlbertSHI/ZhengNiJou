function Test_HeatDriveECC_OutputOptions()
% Plot suppression must not change any checksum-sensitive model options.
    quiet = struct('output', struct('generate_figures', false));
    loud = struct('output', struct('generate_figures', true));
    assert(Resolve_HeatDriveECC_FigurePolicy(struct()));
    assert(~Resolve_HeatDriveECC_FigurePolicy(quiet));
    assert(Resolve_HeatDriveECC_FigurePolicy(loud));
    assert(isequaln(Build_HeatDriveECC_EighthRound_Defaults(quiet), ...
        Build_HeatDriveECC_EighthRound_Defaults(loud)));
    rejected = false;
    try
        Resolve_HeatDriveECC_FigurePolicy(struct('output', struct('generate_figures', NaN)));
    catch e
        rejected = strcmp(e.identifier, 'HeatDriveECC:InvalidFigurePolicy');
    end
    assert(rejected);
    assert(~Resolve_HeatDriveECC_StateLoggingPolicy(struct()));
    observed = struct('output', struct('capture_internal_states', true));
    assert(Resolve_HeatDriveECC_StateLoggingPolicy(observed));
    assert(isequaln(Build_HeatDriveECC_EighthRound_Defaults(observed), ...
        Build_HeatDriveECC_EighthRound_Defaults(struct())));
    for value = {NaN, Inf, -1, 2, [], [true false], 'on'}
        rejected = false;
        try
            Resolve_HeatDriveECC_StateLoggingPolicy(struct('output', ...
                struct('capture_internal_states', value{1})));
        catch e
            rejected = strcmp(e.identifier, 'HeatDriveECC:InvalidStateLoggingPolicy');
        end
        assert(rejected);
    end
    fprintf('OUTPUT_OPTIONS_REGRESSION_PASS=1\n');
end
