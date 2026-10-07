function record=Export_HeatDriveECC_FailedColdObservations(output,model,metadata,destination)
% Serialize public signals/leaves before a live Simscape logging Node is lost.
    assert(~isfile(destination),'Do not overwrite failed evidence.');
    record=struct('schema','heatdrive_ecc_failed_cold_public_observations_v1', ...
        'production_recovery_allowed',false,'valid_simulation',false, ...
        'error_message',output.ErrorMessage,'native_read_errors',{{}}, ...
        'signals_count',0,'native_leaf_count',0);
    started=tic;signals=struct(); native={}; names=output.who;
    for k=1:numel(names)
        if any(strcmp(names{k},{'simlog','states'})),continue;end
        v=output.get(names{k});
        if isa(v,'timeseries')
            signals.(names{k})=struct('time_s',v.Time,'values',v.Data);
        elseif isstruct(v) && isscalar(v) && isfield(v,'time') && isfield(v,'signals') && ...
                isscalar(v.signals) && isfield(v.signals,'values')
            signals.(names{k})=struct('time_s',v.time,'values',v.signals.values);
        end
    end
    try
        log=output.get('simlog');
    catch ME
        log=[];record.simlog_read_error=ME.message;
    end
    for k=1:numel(metadata.storage_blocks)
        block=metadata.storage_blocks{k};
        try
            node=Find_HeatDriveECC_NativeLogNode(log,block.block_path);
            assert(~isempty(node),'No node in failed log.'); leaves=node.childIds;
            for j=1:numel(leaves)
                series=node.child(leaves{j}).series;
                if isempty(series) || series.points==0,continue;end
                t=double(time(series)); data=reshape(double(values(series)),numel(t),[]);
                native{end+1}=struct('block_path',block.block_path,'state_name',leaves{j}, ...
                    'unit',series.unit,'time_s',t(:),'values',data, ...
                    'finite',all(isfinite(t)) && all(isfinite(data),'all')); %#ok<AGROW>
            end
        catch ME
            record.native_read_errors{end+1}=struct('block_path',block.block_path,'message',ME.message);
        end
    end
    record.model=model; record.signals_count=numel(fieldnames(signals));record.native_leaf_count=numel(native);
    record.collection_seconds=toc(started);
    save(destination,'signals','native','record','-v7.3');
    fprintf('FAILED_PUBLIC_OBSERVATIONS signals=%d native=%d valid=0\n',record.signals_count,record.native_leaf_count);
end
