function options = Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(options, state_mode, cycle_count, duration, arm, endpoint_all_arms)
% Explicit geometry/closure experiments; never arbitrary state import.
    assert(isstruct(options) && isscalar(options), 'Require scalar inventory diagnostic options.');
    assert(all(ismember(fieldnames(options), {'volume_factor','storage_closure','cold_followup_audit_path'})), 'Unknown inventory diagnostic option.');
    if isempty(fieldnames(options)), return; end
    if isfield(options,'storage_closure')
        assert(strcmp(options.storage_closure,'pressure_only_density') && ...
            ~isfield(options,'volume_factor'), 'Never combine geometry and inventory-density interventions.');
        cold_two=strcmp(state_mode,'restore_preflight') && cycle_count==2 && duration==20;
        cold_one=strcmp(state_mode,'off') && cycle_count==1 && duration==10;
        assert((cold_one || cold_two) && strcmp(arm,'native') && endpoint_all_arms, ...
            'Pressure-only closure requires its cold C1 or qualified cold C2 experiment.');
        assert(isfield(options,'cold_followup_audit_path')==cold_two, ...
            'Only C2 must carry qualified storage-closure C1 authority.');
        if cold_two,Require_HeatDriveECC_StorageClosureColdSource(options.cold_followup_audit_path);end
        return;
    else
        assert(~isfield(options,'cold_followup_audit_path'),'A volume intervention cannot consume closure authority.');
        validateattributes(options.volume_factor, {'numeric'}, {'scalar','real','finite','positive','<=',1});
        assert(ismember(options.volume_factor, [1 0.1]), 'Only the declared baseline and ten-percent counterfactual are supported.');
    end
    assert(strcmp(state_mode,'off') && cycle_count==1 && duration==10 && ...
        strcmp(arm,'native') && endpoint_all_arms, ...
        'Inventory intervention requires an independent ten-second endpoint-native cold experiment without state loading.');
end
