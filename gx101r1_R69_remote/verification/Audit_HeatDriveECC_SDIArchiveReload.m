function record=Audit_HeatDriveECC_SDIArchiveReload(repo,output_file)
% Verify persisted physical data in a fresh process without loading/simulating the model.
    assert(~isfile(output_file),'Do not overwrite reload evidence.');
    root=fullfile(repo,'outputs_storage_audit','specific_inventory_hybrid_held_sdi_profiler_20260910');
    manifest=jsondecode(fileread(fullfile(root,'compiled_states_inspection.json')));
    audited=jsondecode(fileread(fullfile(repo,'outputs_storage_audit','hybrid_held_profiler_sdi_audit_20260910','profiler_sdi_audit.json')));
    assert(audited.evidence_audit_pass && audited.mapped_native_leaf_count==1258 && audited.mapped_source_leaf_count==162);
    archive=fullfile(root,'sdi_run_1.mldatx');raw=fullfile(root,'sdi_scalar_observations.mat');
    assert(strcmp(file_hash(archive),manifest.profiler.sdi.runs(1).archive_sha256) && ...
        strcmp(file_hash(raw),manifest.profiler.sdi.scalar_sha256),'Stored evidence changed.');
    model='heatdrive_ecc_coupled_se21';
    assert(~bdIsLoaded(model),'Run reload inspection in a fresh MATLAB process.');
    before=Simulink.sdi.getAllRunIDs;
    assert(isempty(before),'Do not replace an existing SDI session.');
    valid=Simulink.sdi.load(archive);assert(valid,'SDI archive is not loadable.');
    ids=Simulink.sdi.getAllRunIDs;assert(isscalar(ids),'Expected one archived run.');
    run=Simulink.sdi.getRun(ids(1));assert(strcmp(run.Model,model) && run.SignalCount==5414);
    stored=load(raw,'signals');signals=stored.signals;
    indices=cellfun(@(s) s.index,signals);assert(numel(unique(indices))==5409);
    required=unique([audited.mapping.sdi_index]);assert(numel(required)==1420);
    for index=required
        matched=signals(indices==index);assert(isscalar(matched));old=matched{1};
        signal=run.getSignalByIndex(index);v=signal.Values;
        assert(strcmp(signal.Name,old.name) && isequal(signal.FullBlockPath,old.full_block_path) && ...
            strcmp(signal.Units,old.unit),'Reloaded signal identity changed.');
        assert(isa(v,'timeseries') && isequal(double(v.Time(:)),old.time_s) && ...
            isequal(double(v.Data(:)),old.values),'Reloaded physical time/data differs.');
    end
    remaining=setdiff(1:run.SignalCount,indices);details=cell(size(remaining));
    for k=1:numel(remaining)
        signal=run.getSignalByIndex(remaining(k));v=signal.Values;
        details{k}=struct('index',remaining(k),'name',signal.Name,'values_class',class(v));
        if isa(v,'timeseries')
            details{k}.time_count=numel(v.Time);details{k}.data_size=size(v.Data);
        elseif isstruct(v)
            details{k}.fields=fieldnames(v);
        end
    end
    assert(~bdIsLoaded(model),'Reload must not load the simulation model.');
    record=struct('archive_reload_pass',true,'simulation_run',false,'model_loaded',false, ...
        'empty_sdi_session_required',true,'run_count',numel(ids),'signal_count',run.SignalCount, ...
        'physical_signals_checked',numel(required),'physical_arrays_exactly_equal',true, ...
        'non_scalar_or_empty_signal_details',{details},'archive_sha256',file_hash(archive), ...
        'scalar_sha256',file_hash(raw),'all_model_states_verified',false, ...
        'individual_jacobian_matrices_analyzed',false,'production_recovery_allowed',false);
    fid=fopen(output_file,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));clear cleanup
    fprintf('%s\n',jsonencode(record));
end

function hash=file_hash(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(path,'rb');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,1048576,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
