function options = Resolve_HeatDriveECC_DiagnosticStateOptions(options, cycle_count)
% State-capture policy is separate from physical mechanism or recovery eligibility.
    assert(isstruct(options) && isscalar(options),'Require scalar diagnostic state options.');
    assert(all(ismember(fieldnames(options),{'mode','command_horizon_cycles','restore_source_root','restore_verification_root', ...
        'storage_state_audit_path','storage_complete_cycle_audit_path','native_inventory_window_cycles'})), ...
        'Unknown diagnostic state option.');
    if ~isfield(options,'mode'),options.mode='off';end
    if ~isfield(options,'command_horizon_cycles'),options.command_horizon_cycles=cycle_count;end
    options.mode=char(string(options.mode));
    assert(ismember(options.mode,{'off','capture','restore_preflight','rebuilt_cycle_preflight','diagnostic_resume'}),'Unknown state capture mode.');
    rebuilding=strcmp(options.mode,'rebuilt_cycle_preflight');
    resuming=strcmp(options.mode,'diagnostic_resume');
    storage_fields={'storage_state_audit_path','storage_complete_cycle_audit_path'};
    if isfield(options,'native_inventory_window_cycles')
        assert(resuming && all(isfield(options,storage_fields)) && ...
            isequal(options.native_inventory_window_cycles,10), 'Only typed ten-cycle native recording is supported.');
    end
    if any(isfield(options,storage_fields))
        assert(resuming && all(isfield(options,storage_fields)), ...
            'Storage warmup requires both typed audits, only in diagnostic resume.');
        for field=storage_fields
            value=string(options.(field{1}));
            assert(isscalar(value) && strlength(value)>0,'Require nonempty storage evidence path.');
            options.(field{1})=char(value);
        end
    end
    assert(~isfield(options,'restore_source_root') || rebuilding || resuming, ...
        'A restore source is forbidden outside the rebuilt-cycle experiment.');
    if rebuilding
        assert(cycle_count==2 && isfield(options,'restore_source_root') && ...
            isscalar(string(options.restore_source_root)) && strlength(string(options.restore_source_root))>0, ...
            'Rebuilt-cycle preflight requires the two-cycle source root.');
        options.restore_source_root=char(string(options.restore_source_root));
    end
    assert(~isfield(options,'restore_verification_root') || resuming, ...
        'A complete-cycle receipt is only consumed by diagnostic resume.');
    if resuming
        assert(cycle_count==20 && options.command_horizon_cycles==200 && ...
            all(isfield(options,{'restore_source_root','restore_verification_root'})), ...
            'Diagnostic resume requires twenty cycles, fixed horizon, and complete-cycle evidence.');
        for field={'restore_source_root','restore_verification_root'}
            value=string(options.(field{1}));
            assert(isscalar(value) && strlength(value)>0,'Require a nonempty diagnostic source path.');
            options.(field{1})=char(value);
        end
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
