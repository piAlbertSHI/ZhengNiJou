function receipt = Verify_HeatDriveECC_NativeLogLookup(log, paths)
% Compare actual leaf data with the official resolver, not guessed node names.
    rows=cell(size(paths));
    for k=1:numel(paths)
        [fast,row]=Find_HeatDriveECC_NativeLogNode(log,paths{k});
        started=tic; original=simscape.logging.findNode(log,paths{k});
        row.official_lookup_seconds=toc(started);
        assert(~isempty(original) && isequal(fast.childIds,original.childIds), ...
            'HeatDriveECC:NativeLookupIdentity','Official leaf identities differ.');
        names=original.childIds; count=0;
        for j=1:numel(names)
            a=original.child(names{j}); b=fast.child(names{j});
            assert(isequal(a.tags,b.tags),'Native tags differ.');
            x=a.series; y=b.series;
            if isempty(x),assert(isempty(y));continue;end
            assert(x.points==y.points && strcmp(x.unit,y.unit));
            if x.points>0
                assert(isequal(time(x),time(y)) && isequal(values(x),values(y)), ...
                    'HeatDriveECC:NativeLookupValues','Native observations differ.');
                count=count+1;
            end
        end
        row.exact_leaf_data_match=true; row.leaf_count=count; rows{k}=row;
    end
    receipt=struct('schema','heatdrive_ecc_exact_native_lookup_comparison_v1', ...
        'pass',true,'comparisons',{rows},'physical_model_modified',false, ...
        'production_recovery_allowed',false);
end
