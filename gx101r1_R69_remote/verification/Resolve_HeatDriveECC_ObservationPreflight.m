function options=Resolve_HeatDriveECC_ObservationPreflight(options,state,cycles,duration,arm,endpoint_all,factors)
% Execution-only comparison; the configured model and native history stay unchanged.
    assert(isstruct(options) && isscalar(options),'Require scalar observation options.');
    if isempty(fieldnames(options)),return;end
    assert(isequal(sort(fieldnames(options)),sort({'mode';'python_executable';'source_contract_path'})) && ...
        strcmp(options.mode,'split_preflight') && strcmp(state.mode,'diagnostic_resume') && ...
        cycles==20 && duration==200 && strcmp(arm,'native') && endpoint_all && ...
        isempty(fieldnames(factors)) && ~isfield(state,'native_inventory_window_cycles'), ...
        'Observation preflight requires the unchanged qualified native resume recipe, no geometry or log-cap override.');
    for key={'python_executable','source_contract_path'}
        options.(key{1})=char(string(options.(key{1})));
        assert(isfile(options.(key{1})),'Missing observation prerequisite: %s',key{1});
    end
end
