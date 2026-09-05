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
    fprintf('OUTPUT_OPTIONS_REGRESSION_PASS=1\n');
end
