function options = Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(options, state_mode, cycle_count, duration, arm, endpoint_all_arms)
% An explicit cold-only geometry intervention, never an intact-state continuation.
    assert(isstruct(options) && isscalar(options), 'Require scalar inventory diagnostic options.');
    assert(all(ismember(fieldnames(options), {'volume_factor'})), 'Unknown inventory diagnostic option.');
    if isempty(fieldnames(options)), return; end
    validateattributes(options.volume_factor, {'numeric'}, {'scalar','real','finite','positive','<=',1});
    assert(ismember(options.volume_factor, [1 0.1]), 'Only the declared baseline and ten-percent counterfactual are supported.');
    assert(strcmp(state_mode,'off') && cycle_count==1 && duration==10 && ...
        strcmp(arm,'native') && endpoint_all_arms, ...
        'Inventory intervention requires an independent ten-second endpoint-native cold experiment without state loading.');
end
