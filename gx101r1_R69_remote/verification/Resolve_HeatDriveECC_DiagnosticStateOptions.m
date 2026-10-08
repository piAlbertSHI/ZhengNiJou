function options = Resolve_HeatDriveECC_DiagnosticStateOptions(options, cycle_count)
% State-capture policy is separate from physical mechanism or recovery eligibility.
    assert(isstruct(options) && isscalar(options),'Require scalar diagnostic state options.');
    assert(all(ismember(fieldnames(options),{'mode','command_horizon_cycles'})), ...
        'Unknown diagnostic state option.');
    if ~isfield(options,'mode'),options.mode='off';end
    if ~isfield(options,'command_horizon_cycles'),options.command_horizon_cycles=cycle_count;end
    options.mode=char(string(options.mode));
    assert(ismember(options.mode,{'off','capture','restore_preflight'}),'Unknown state capture mode.');
    validateattributes(options.command_horizon_cycles,{'numeric'}, ...
        {'scalar','finite','integer','>=',cycle_count,'<=',200});
    assert(~strcmp(options.mode,'off') || options.command_horizon_cycles==cycle_count, ...
        'Default cold diagnostics cannot silently change command horizon.');
    assert(strcmp(options.mode,'off') || cycle_count>=2, ...
        'State capture is not a new ten-second initialization seed.');
    assert(~strcmp(options.mode,'restore_preflight') || cycle_count==2, ...
        'Restore preflight is explicitly scoped to two cycles.');
end
