function record = Verify_HeatDriveECC_PassiveLoggingWindow(input, source_op, source_root, folder, chambers, buffers)
% Compare one strict restored step under 2/10-cycle log caps, then reuse the original OP.
    assert(~isfile(fullfile(folder,'native_logging_step_equivalence.json')),'Never overwrite logging evidence.');
    model=input.ModelName;start=source_op.snapshotTime;stop=start+.001;
    assert(strcmp(get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'SimscapeLogLimitData'),'on'),'Require strict unchanged vendor restoration.');
    capture=jsondecode(fileread(fullfile(source_root,'native','diagnostic_state_capture.json')));
    op_file=fullfile(source_root,'native','diagnostic_complete_operating_point.mat');
    assert(strcmp(file_hash(op_file),capture.operating_point_sha256) && capture.snapshot_time_s==start);
    state_sets=cell(1,2);signals=cell(1,2);native=cell(1,2);sources=cell(1,2);
    for k=1:2
        cycles=[2 10];
        trial=input.setModelParameter('StopTime',num2str(stop,'%.17g'), ...
            'SimscapeLogDataHistory',cycles(k)*10000+2).setInitialState(source_op);
        output=sim(trial);assert(isempty(output.ErrorMessage),'Strict logging trial failed: %s',output.ErrorMessage);
        state_sets{k}=Extract_HeatDriveECC_ObservedStates(output.diagnostic_state_log,10,1);
        signals{k}=public_signals(output,start,stop);
        [native{k},~]=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model,false,chambers,buffers);
        [sources{k},~]=Extract_HeatDriveECC_BoundaryTraces(output.simlog,model);
        clear output
    end
    save(fullfile(folder,'native_logging_step_comparison.mat'),'state_sets','signals','native','sources','-v7.3');
    a=state_sets{1}.states;b=state_sets{2}.states;
    assert(numel(a)==74 && numel(b)==74,'Incomplete state comparison.');
    for k=1:numel(a)
        assert(strcmp(a{k}.block_path,b{k}.block_path) && strcmp(a{k}.state_name,b{k}.state_name));
        check_pair(a{k},b{k},start,stop);
    end
    names=fieldnames(signals{1});
    assert(numel(names)==201 && isequal(sort(names),sort(fieldnames(signals{2}))));
    for k=1:numel(names),check_pair(signals{1}.(names{k}),signals{2}.(names{k}),start,stop);end
    assert(numel(native{1})==1262 && isequaln(native{1},native{2}) && ...
        isequaln(sources{1},sources{2}),'Logging changed native inventories or source leaves.');
    assert(strcmp(file_hash(op_file),capture.operating_point_sha256),'Source complete OP changed.');
    record=struct('schema','heatdrive_ecc_passive_native_logging_step_equivalence_v1', ...
        'source_root',source_root,'source_operating_point_sha256',capture.operating_point_sha256, ...
        'actual_comparison_window_s',[start stop],'native_history_caps_cycles',[2 10], ...
        'state_groups_exact',74,'signals_exact',201,'samples_per_comparison',2, ...
        'native_traces_exact',1262,'native_source_leaves_exact',true,'checksum_policy','error/error', ...
        'logging_step_equivalence_pass',true,'verification_sim_calls',2,'long_segment_sim_calls',1, ...
        'source_state_edited',false,'comparison_OP_used_for_long_segment',false, ...
        'complete_cycle_equivalence_claim',false,'ten_cycle_native_window_already_observed',false, ...
        'production_recovery_allowed',false);
    save(fullfile(folder,'native_logging_step_comparison.mat'),'state_sets','signals','native','sources','record','-v7.3');
    fid=fopen(fullfile(folder,'native_logging_step_equivalence.json'),'w','n','UTF-8');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
end

function check_pair(a,b,start,stop)
    expected=[start;stop];
    assert(numel(a.time_s)==2 && numel(b.time_s)==2 && all(abs(a.time_s-expected)<=1e-9) && ...
        all(abs(b.time_s-expected)<=1e-9) && all(isfinite(a.values),'all') && all(isfinite(b.values),'all') && ...
        isequal(a.time_s,b.time_s) && isequal(a.values,b.values), ...
        'Native recording caps changed a state or public trajectory.');
end

function signals=public_signals(output,start,stop)
    signals=struct();names=output.who;
    for k=1:numel(names)
        v=output.get(names{k});
        if isa(v,'timeseries')
            t=double(v.Time(:));data=v.Data;
            if ~v.IsTimeFirst,data=permute(data,[ndims(data),1:ndims(data)-1]);end
        elseif isstruct(v) && isscalar(v) && isfield(v,'time') && isfield(v,'signals') && ...
                isscalar(v.signals) && isfield(v.signals,'values')
            t=double(v.time(:));data=v.signals.values;
        else,continue;end
        data=reshape(double(data),numel(t),[]);selected=t>=start-1e-9 & t<=stop+1e-9;
        signals.(names{k})=struct('time_s',t(selected),'values',data(selected,:));
    end
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
