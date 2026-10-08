function [native_log,record]=Snapshot_HeatDriveECC_NativeLog(log,folder,inventory_paths)
% Public vendor MAT persistence; fail closed instead of silently losing raw evidence.
    assert(isa(log,'simscape.logging.Node') && log.savable, ...
        'The actual Node does not support regular MAT save/load.');
    target=fullfile(folder,'native_logging_node.mat');
    assert(~isfile(target),'Never overwrite the native log.');
    clock=tic;native_log=log;save(target,'native_log','-v7.3');save_s=toc(clock);
    clock=tic;saved=load(target,'native_log');load_s=toc(clock);
    assert(isa(saved.native_log,'simscape.logging.Node') && ...
        strcmp(saved.native_log.id,log.id) && isequal(saved.native_log.childIds,log.childIds), ...
        'Vendor Node MAT roundtrip changed root identity.');
    assert(numel(inventory_paths)==6,'Require both chambers and all four buffers.');
    comparisons={};
    for k=1:numel(inventory_paths)
        original=simscape.logging.findNode(log,inventory_paths{k});
        loaded=simscape.logging.findNode(saved.native_log,inventory_paths{k});
        assert(isequal(original.childIds,loaded.childIds),'Inventory node children changed.');
        names=original.childIds;
        selected=names(ismember(names,{'stored_mass','mass_offset','stored_energy'}));
        assert(numel(selected)==2,'Missing independent inventory ledger coordinates.');
        for j=1:2
            [t,a,u]=Read_HeatDriveECC_NativeSeries(original.child(selected{j}));
            [s,b,v]=Read_HeatDriveECC_NativeSeries(loaded.child(selected{j}));
            equal=isequaln(t,s) && isequaln(a,b) && strcmp(u,v);
            assert(equal,'Saved inventory leaf differs from actual trajectory.');
            comparisons{end+1}=struct('block_path',inventory_paths{k}, ...
                'leaf',selected{j},'samples',numel(t),'channels',size(a,2), ...
                'unit',u,'values_clock_unit_exact',equal); %#ok<AGROW>
        end
    end
    record=struct('schema','heatdrive_ecc_native_log_snapshot_v1', ...
        'method','savable Node public MATLAB MAT save/load', ...
        'actual_savable',logical(log.savable),'root_identity_equal',true, ...
        'save_s',save_s,'load_s',load_s,'file',target, ...
        'inventory_roundtrip_comparisons',{comparisons},'all_six_inventory_roundtrip_pass',true, ...
        'full_leaf_value_equivalence_verified',false,'production_recovery_allowed',false);
    native_log=saved.native_log;
end
