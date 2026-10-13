function options = Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(options, state_mode, cycle_count, duration, arm, endpoint_all_arms)
% Explicit geometry/closure experiments; never arbitrary state import.
    assert(isstruct(options) && isscalar(options), 'Require scalar inventory diagnostic options.');
    assert(all(ismember(fieldnames(options), {'volume_factor','storage_closure','cold_followup_audit_path','rebuilt_state_audit_path','warmup_restore_audit_path'})), 'Unknown inventory diagnostic option.');
    if isempty(fieldnames(options)), return; end
    if isfield(options,'storage_closure')
        assert(strcmp(options.storage_closure,'pressure_only_density') && ...
            ~isfield(options,'volume_factor'), 'Never combine geometry and inventory-density interventions.');
        cold_two=strcmp(state_mode,'restore_preflight') && cycle_count==2 && duration==20;
        cold_one=strcmp(state_mode,'off') && cycle_count==1 && duration==10;
        rebuilding=strcmp(state_mode,'rebuilt_cycle_preflight') && cycle_count==2 && duration==20;
        warming=strcmp(state_mode,'diagnostic_resume') && cycle_count==20 && duration==200;
        assert((cold_one || cold_two || rebuilding || warming) && strcmp(arm,'native') && endpoint_all_arms, ...
            'Pressure-only closure requires its cold C1/C2 or qualified complete-cycle test.');
        assert(isfield(options,'cold_followup_audit_path')==(cold_two || rebuilding || warming) && ...
            isfield(options,'rebuilt_state_audit_path')==(rebuilding || warming) && ...
            isfield(options,'warmup_restore_audit_path')==warming, ...
            'Only C2 must carry qualified storage-closure C1 authority.');
        if cold_two || rebuilding || warming,Require_HeatDriveECC_StorageClosureColdSource(options.cold_followup_audit_path);end
        if rebuilding || warming
            audit=jsondecode(fileread(options.rebuilt_state_audit_path));
            Require_HeatDriveECC_StorageClosureCheckpoint(audit.source_root,options.rebuilt_state_audit_path);
            if warming
                Require_HeatDriveECC_StorageClosureWarmupSource(audit.source_root, ...
                    options.rebuilt_state_audit_path,options.warmup_restore_audit_path);
            end
        end
        return;
    else
        assert(~isfield(options,'cold_followup_audit_path') && ~isfield(options,'rebuilt_state_audit_path') && ...
            ~isfield(options,'warmup_restore_audit_path'), ...
            'A volume intervention cannot consume closure authority.');
        validateattributes(options.volume_factor, {'numeric'}, {'scalar','real','finite','positive','<=',1});
        assert(ismember(options.volume_factor, [1 0.1]), 'Only the declared baseline and ten-percent counterfactual are supported.');
    end
    assert(strcmp(state_mode,'off') && cycle_count==1 && duration==10 && ...
        strcmp(arm,'native') && endpoint_all_arms, ...
        'Inventory intervention requires an independent ten-second endpoint-native cold experiment without state loading.');
end
