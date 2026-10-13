function options = Resolve_HeatDriveECC_SEReferenceDiagnostic(options, state_mode, cycle_count, duration, arm, endpoint_all_arms)
    assert(isstruct(options) && isscalar(options),'Require scalar SE reference diagnostic options.');
    assert(all(ismember(fieldnames(options),{'mode'})),'Unknown SE reference diagnostic option.');
    if isempty(fieldnames(options)),return;end
    assert(isscalar(string(options.mode)) && strcmp(options.mode,'coherent_envelope'), ...
        'Only the explicit coherent-envelope reference experiment is supported.');
    assert(strcmp(state_mode,'off') && cycle_count==1 && duration==10 && ...
        strcmp(arm,'native') && endpoint_all_arms, ...
        'Reference changes require an independent ten-second cold case without state import.');
end
