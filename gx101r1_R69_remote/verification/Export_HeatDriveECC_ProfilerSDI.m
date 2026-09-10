function record=Export_HeatDriveECC_ProfilerSDI(model,output_root,ids_before)
% Export only runs newly created by this profiling call and owned by this model.
    ids_after=Simulink.sdi.getAllRunIDs;
    created=setdiff(ids_after,ids_before,'stable');
    record=struct('export_pass',false,'prior_run_ids',{id_strings(ids_before)}, ...
        'after_run_ids',{id_strings(ids_after)},'prior_runs_preserved',all(ismember(ids_before,ids_after)), ...
        'runs',{{}},'scalar_signal_count',0,'full_native_coverage_verified',false, ...
        'science_gate_pass',false,'production_recovery_allowed',false);
    assert(record.prior_runs_preserved,'Existing SDI runs disappeared during profiling.');
    signals={};owned_count=0;
    for i=1:numel(created)
        run=Simulink.sdi.getRun(created(i));
        row=struct('run_id',sprintf('%d',created(i)),'name',run.Name,'model',run.Model, ...
            'signal_count',run.SignalCount,'ownership_verified',false,'exported',false, ...
            'scalar_count',0,'non_scalar_or_empty_count',0,'unreadable_signals',{{}});
        metadata=cell(1,run.SignalCount);
        for j=1:run.SignalCount
            sig=run.getSignalByIndex(j);
            metadata{j}=struct('index',j,'name',sig.Name,'model',sig.Model,'block_path',sig.BlockPath, ...
                'full_block_path',{sig.FullBlockPath},'unit',sig.Units,'description',sig.Description);
        end
        % Model-labelled runs are authoritative; unlabelled runs need unanimous signal provenance.
        named=cellfun(@(s) ~isempty(s.model),metadata);
        row.ownership_verified=strcmp(run.Model,model) || (isempty(run.Model) && any(named) && ...
            all(cellfun(@(s) strcmp(s.model,model),metadata(named))));
        if ~row.ownership_verified
            row.skip_reason='New run is not verified as belonging to the profiled model.';
            record.runs{end+1}=row;continue
        end
        assert(all(cellfun(@(s) isempty(s.model) || strcmp(s.model,model),metadata)), ...
            'Mixed-model signals in candidate SDI run.');
        owned_count=owned_count+1;
        archive=fullfile(output_root,sprintf('sdi_run_%d.mldatx',owned_count));
        assert(~isfile(archive),'Do not overwrite SDI evidence.');
        Simulink.sdi.exportRun(created(i),'to','file','filename',archive);
        row.archive_file=archive;row.archive_sha256=file_hash(archive);info=dir(archive);row.archive_bytes=info.bytes;
        row.exported=true;
        run_signals=cell(1,run.SignalCount);
        for j=1:run.SignalCount
            sig=run.getSignalByIndex(j);meta=metadata{j};
            try
                v=sig.Values;
                if isa(v,'timeseries') && isnumeric(v.Data) && isreal(v.Data) && ~isempty(v.Time) && ...
                        numel(v.Data)==numel(v.Time)
                    meta.run_id=row.run_id;meta.time_s=double(v.Time(:));meta.values=double(v.Data(:));
                    row.scalar_count=row.scalar_count+1;
                    meta.value_class=class(v.Data);run_signals{row.scalar_count}=meta;
                else
                    row.non_scalar_or_empty_count=row.non_scalar_or_empty_count+1;
                end
            catch ME
                row.unreadable_signals{end+1}=struct('index',j,'name',meta.name,'error',ME.message);
            end
        end
        signals=[signals run_signals(1:row.scalar_count)]; %#ok<AGROW>
        row.signal_metadata=metadata;record.runs{end+1}=row;
    end
    record.scalar_signal_count=numel(signals);record.owned_run_count=owned_count;
    destination=fullfile(output_root,'sdi_scalar_observations.mat');
    assert(~isfile(destination),'Do not overwrite scalar evidence.');
    save(destination,'signals','-v7.3');
    record.scalar_file=destination;record.scalar_sha256=file_hash(destination);
    owned=record.runs(cellfun(@(r) r.ownership_verified,record.runs));
    record.export_pass=owned_count>0 && ~isempty(signals) && ...
        all(cellfun(@(r) r.exported && isempty(r.unreadable_signals),owned));
end

function strings=id_strings(ids)
    strings=arrayfun(@(id) sprintf('%d',id),ids,'UniformOutput',false);
end

function hash=file_hash(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(path,'rb');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,1048576,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
