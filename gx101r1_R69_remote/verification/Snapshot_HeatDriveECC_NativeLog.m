function [native_log,record]=Snapshot_HeatDriveECC_NativeLog(log,folder,inventory_paths)
% Public vendor MAT persistence; fail closed instead of silently losing raw evidence.
    assert(isa(log,'simscape.logging.Node') && (log.savable || log.exportable), ...
        'No supported public vendor persistence method for this actual Node.');
    if log.savable
        target=fullfile(folder,'native_logging_node.mat');assert(~isfile(target));
        clock=tic;native_log=log;save(target,'native_log','-v7.3');save_s=toc(clock);
        clock=tic;saved=load(target,'native_log');native_log=saved.native_log;load_s=toc(clock);
        method='savable Node public MATLAB MAT save/load';
    else
        % Vendor export does not support cross-locale filenames. Bind the exact
        % ASCII sidecar in the receipt; never change shared logging preferences.
        ancestor=folder;
        while any(double(ancestor)>127)
            parent=fileparts(ancestor);assert(~strcmp(parent,ancestor));ancestor=parent;
        end
        [~,experiment]=fileparts(fileparts(folder));
        [~,arm]=fileparts(folder);
        assert(~isempty(regexp(experiment,'^[A-Za-z0-9_-]+$','once')));
        destination=fullfile(ancestor,'native_log_archives',experiment,arm);
        if ~isfolder(destination),mkdir(destination);end
        target=fullfile(destination,'native_logging_node.mldatx');assert(~isfile(target));
        clock=tic;simscape.logging.export(log,target);save_s=toc(clock);
        clock=tic;native_log=simscape.logging.import(target);load_s=toc(clock);
        method='exportable Node public MLDATX export/import';
    end
    assert(isa(native_log,'simscape.logging.Node') && ...
        strcmp(native_log.id,log.id) && isequal(native_log.childIds,log.childIds), ...
        'Vendor Node MAT roundtrip changed root identity.');
    assert(numel(inventory_paths)==6,'Require both chambers and all four buffers.');
    comparisons={};
    for k=1:numel(inventory_paths)
        original=simscape.logging.findNode(log,inventory_paths{k});
        loaded=simscape.logging.findNode(native_log,inventory_paths{k});
        assert(isequal(original.childIds,loaded.childIds),'Inventory node children changed.');
        names=original.childIds;
        selected=names(ismember(names,{'stored_mass','mass_offset','stored_energy'}));
        assert(ismember('stored_energy',selected) && ismember('stored_mass',selected) && ...
            ismember(numel(selected),[2 3]),'Missing independent inventory ledger coordinates.');
        for j=1:numel(selected)
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
        'method',method,'actual_savable',logical(log.savable), ...
        'actual_exportable',logical(log.exportable),'root_identity_equal',true, ...
        'save_s',save_s,'load_s',load_s,'file',target, ...
        'inventory_roundtrip_comparisons',{comparisons},'all_six_inventory_roundtrip_pass',true, ...
        'full_leaf_value_equivalence_verified',false,'production_recovery_allowed',false);
end
