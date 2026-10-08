function options = Resolve_HeatDriveECC_DiagnosticStateOptions(options, cycle_count)
% State-capture policy is separate from physical mechanism or recovery eligibility.
    assert(isstruct(options) && isscalar(options),'Require scalar diagnostic state options.');
    assert(all(ismember(fieldnames(options),{'mode','command_horizon_cycles','restore_source_root'})), ...
        'Unknown diagnostic state option.');
    if ~isfield(options,'mode'),options.mode='off';end
    if ~isfield(options,'command_horizon_cycles'),options.command_horizon_cycles=cycle_count;end
    options.mode=char(string(options.mode));
    assert(ismember(options.mode,{'off','capture','restore_preflight','rebuilt_cycle_preflight'}),'Unknown state capture mode.');
    rebuilding=strcmp(options.mode,'rebuilt_cycle_preflight');
    assert(~isfield(options,'restore_source_root') || rebuilding, ...
        'A restore source is forbidden outside the rebuilt-cycle experiment.');
    if rebuilding
        assert(cycle_count==2 && isfield(options,'restore_source_root') && ...
            isscalar(string(options.restore_source_root)) && strlength(string(options.restore_source_root))>0, ...
            'Rebuilt-cycle preflight requires the two-cycle source root.');
        options.restore_source_root=char(string(options.restore_source_root));
    end
    validateattributes(options.command_horizon_cycles,{'numeric'}, ...
        {'scalar','finite','integer','>=',cycle_count,'<=',200});
    assert(~strcmp(options.mode,'off') || options.command_horizon_cycles==cycle_count, ...
        'Default cold diagnostics cannot silently change command horizon.');
    assert(strcmp(options.mode,'off') || cycle_count>=2, ...
        'State capture is not a new ten-second initialization seed.');
    assert(~strcmp(options.mode,'restore_preflight') || cycle_count==2, ...
        'Restore preflight is explicitly scoped to two cycles.');
end
