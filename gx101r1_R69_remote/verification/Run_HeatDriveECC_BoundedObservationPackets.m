function record=Run_HeatDriveECC_BoundedObservationPackets(input,options,folder,chambers,buffers,settings,request,producer)
% Gate every measured packet before propagating its untouched complete vendor OP.
    repo=fileparts(fileparts(mfilename('fullpath')));model=input.ModelName;
    runtime=strcmp(request.mode,'runtime_boundary_warmup');
    converge=runtime && isfield(request,'stop_on_public_periodicity') && request.stop_on_public_periodicity;
    root=canonical(request.collection_root);
    assert(strcmp(fileparts(root),canonical(fullfile(repo,'outputs'))),'Collection must stay in execution outputs.');
    assert(~isfile(fullfile(root,'COMPLETED_RAW_PREFIX_RETIRED.json')), ...
        'A completed archived job cannot resume in place; use its latest qualified runtime endpoint in a new collection.');
    existed=isfolder(root);
    assert(~existed || request.resume_collection,'Explicit diagnosis/resume is required for an existing collection.');
    if ~existed,mkdir(root);end
    handle=java.io.RandomAccessFile(fullfile(root,'collection.lock'),'rw');channel=handle.getChannel();lock=channel.tryLock();
    if isempty(lock),channel.close();handle.close();error('The real collection is already open in another process.');end
    cleanup=onCleanup(@() release_lock(lock,channel,handle));
    assert(strcmp(get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error') && ...
        Resolve_HeatDriveECC_ObservationCount(get_param(model,'SimscapeLogDataHistory'))==20002 && ...
        Resolve_HeatDriveECC_ObservationCount(get_param(model,'MaxDataPoints'))==110002 && settings.history_cycles==11);
    prepared_config=[fileparts(folder),'.preflight_config.json'];
    snapshot=fullfile(root,'initial_recording_contract.json');recipe=fullfile(root,'initial_prepared_recipe.json');
    progress=fullfile(root,'collection_progress.json');
    if ~existed
        copyfile(request.recording_contract_path,snapshot);copyfile(prepared_config,recipe);
    else
        old=jsondecode(fileread(recipe));current=jsondecode(fileread(prepared_config));
        for key={'output_root','diagnostic_observation_options'}
            old=rmfield(old,key{1});current=rmfield(current,key{1});
        end
        assert(isequaln(old,current),'Resuming cannot change physical, control or initial recipes.');
    end
    pointer=jsondecode(fileread(snapshot));
    main_repo=fileparts(fileparts(request.recording_contract_path));
    qualification_path=fullfile(main_repo,pointer.qualification_relative);
    qualification=jsondecode(fileread(qualification_path));
    assert(strcmp(file_hash(qualification_path),pointer.qualification_sha256));
    if runtime
        source=Require_HeatDriveECC_RuntimeRecordingSource(pointer,qualification,options);
        origin_stop=source.snapshot_s;target=request.collection_stop_s;
        source_packet=source.packet_root;role='runtime_boundary_transient';
        assert(target-origin_stop==200 && target<=2000);
        schema='heatdrive_ecc_runtime_boundary_transient_collection_v1';
        recipe_comparison=Compare_HeatDriveECC_RuntimeBoundaryRecipe( ...
            fullfile(source_packet,'native','configuration.mat'),fullfile(folder,'configuration.mat'), ...
            fullfile(folder,'runtime_warmup_recipe_comparison.json'));
        assert(strcmp(recipe_comparison.reference_configurability,'runtime') && ...
            strcmp(recipe_comparison.candidate_configurability,'runtime') && ...
            recipe_comparison.only_declared_change && recipe_comparison.numeric_validation_thresholds_equal, ...
            'Warmup cannot change physics, controls or numerical validation limits.');
    else
        assert(pointer.snapshot_time_s==640 && pointer.total_cycles==64 && pointer.next_collection_stop_s==720 && ...
        pointer.native_history_cap_cycles==2 && pointer.state_history_cap_cycles==11 && ...
        pointer.command_horizon_cycles==200 && strcmp(pointer.checksum_policy,'error/error') && ...
        pointer.bounded_transient_observation_collection_allowed && ~pointer.production_recovery_allowed && ...
        ~pointer.steady_outer_solve_allowed && qualification.all_three_packets_mechanism_and_energy_pass && ...
        qualification.split_states_and_native_bitwise_equal && qualification.complete_vendor_OP_independently_loaded, ...
        'Require the sealed C64 bounded-recording source, not a failed or production state.');
        origin=fullfile(main_repo,pointer.origin_endpoint_comparison_relative);
        assert(strcmp(file_hash(origin),pointer.origin_endpoint_comparison_sha256));
        origin_stop=640;target=720;source_packet=pointer.source_packet_root;
        role='bounded_transient_observation';schema='heatdrive_ecc_bounded_native_collection_v1';
    end
    for k=1:numel(qualification.files)
        row=qualification.files(k);assert(strcmp(file_hash(row.path),row.sha256));
    end
    if converge
        source_window='';
        for k=1:numel(qualification.files)
            row=qualification.files(k);[~,name,extension]=fileparts(row.path);
            if strcmp([name extension],'measured_window.json')
                assert(isempty(source_window),'Ambiguous origin observation window.');source_window=row.path;
            end
        end
        assert(~isempty(source_window),'Early stopping requires a sealed ten-cycle origin window.');
        origin_index=jsondecode(fileread(source_window));
        assert(origin_index.runtime_family && isequal(origin_index.window_s(:),[origin_stop-100;origin_stop]) && ...
            numel(origin_index.packets)==5 && ~origin_index.source_state_edited);
    end
    has_progress=isfile(progress);
    if existed && ~has_progress
        assert(isempty(dir(fullfile(root,'packet_C*'))), ...
            'Missing progress with actual packets requires forensic recovery, not an assumed initial state.');
    end
    if has_progress
        record=jsondecode(fileread(progress));
        if converge && isfield(record,'planned_collection_window_s')
            expected_window=record.planned_collection_window_s;
            assert(strcmp(record.origin_measured_window_path,source_window) && ...
                strcmp(record.origin_measured_window_sha256,file_hash(source_window)));
        else
            expected_window=record.collection_window_s;
        end
        assert(strcmp(record.origin_snapshot_sha256,file_hash(snapshot)) && ...
            strcmp(record.origin_recipe_sha256,file_hash(recipe)) && ...
            isequal(expected_window(:),[origin_stop;target]) && ~record.source_state_edited);
        completed=record.completed_packets;
        if isempty(completed),completed={};elseif isstruct(completed),completed=num2cell(completed);end
    else
        completed={};
        record=struct('schema',schema,'producer',producer, ...
            'origin_snapshot_sha256',file_hash(snapshot),'collection_window_s',[origin_stop target], ...
            'origin_recipe_sha256',file_hash(recipe), ...
            'native_observation_window_after_join_s',[target-100 target],'completed_packets',{{}}, ...
            'last_verified_snapshot_time_s',origin_stop,'last_verified_packet_root',source_packet, ...
            'pass',false,'source_state_edited',false,'partial_state_restore_used',false, ...
            'history_cap_cycles',2,'state_history_cap_cycles',11,'command_horizon_cycles',200, ...
            'production_recovery_allowed',false,'outer_solve_eligible',false,'error_message','');
    end
    previous=source_packet;
    [op,manifest]=Load_HeatDriveECC_GatedObservationPacket(previous,false);
    assert(strcmp(manifest.complete_OP_sha256,pointer.operating_point_sha256));
    for k=1:numel(completed)
        row=completed{k};assert(row.stop_time_s==origin_stop+20*k);
        parent_hash=manifest.complete_OP_sha256;parent_time=op.snapshotTime;
        [op,manifest]=Load_HeatDriveECC_GatedObservationPacket(row.packet_root,true);
        assert(strcmp(manifest.complete_OP_sha256,row.operating_point_sha256) && ...
            strcmp(manifest.parent_complete_OP_sha256,parent_hash) && ...
            manifest.source_snapshot_s==parent_time && row.start_time_s==parent_time);previous=row.packet_root;
    end
    record.completed_packets=completed;record.process_pid=feature('getpid');record.error_message='';
    record.current_producer=producer;
    if converge
        record.stop_on_public_periodicity=true;
        record.planned_collection_window_s=[origin_stop target];
        record.origin_measured_window_path=source_window;
        record.origin_measured_window_sha256=file_hash(source_window);
    end
    write_json(progress,record);
    try
        periodic=false;
        if converge && ~isempty(completed)
            check=Check_HeatDriveECC_RuntimeRollingPeriodicity(root,origin_index,completed);
            record.latest_periodicity=check;periodic=check.periodic_steady_state;write_json(progress,record);
        end
        for finish=origin_stop+20+20*numel(completed):20:target
            if periodic,break;end
            start=op.snapshotTime;assert(finish-start==20);
            attempt=1;
            while isfolder(fullfile(root,sprintf('packet_C%03d_attempt%02d',finish/10,attempt))),attempt=attempt+1;end
            destination=fullfile(root,sprintf('packet_C%03d_attempt%02d',finish/10,attempt));
            record.current_attempt_root=destination;record.current_attempt_window_s=[start finish];write_json(progress,record);
            Collect_HeatDriveECC_ObservationPacket(input,op,start,finish,destination,options,folder, ...
                chambers,buffers,producer,request.python_executable,role,manifest.complete_OP_sha256);
            boundary=Verify_HeatDriveECC_ObservationBoundary(previous,destination);assert(boundary.pass);
            [next,manifest]=Load_HeatDriveECC_GatedObservationPacket(destination,true);
            completed{end+1}=struct('packet_root',destination,'start_time_s',start,'stop_time_s',finish, ...
                'operating_point_sha256',manifest.complete_OP_sha256); %#ok<AGROW>
            op=next;previous=destination;record.completed_packets=completed;
            record.last_verified_snapshot_time_s=finish;record.last_verified_packet_root=destination;write_json(progress,record);
            if converge
                check=Check_HeatDriveECC_RuntimeRollingPeriodicity(root,origin_index,completed);
                record.latest_periodicity=check;periodic=check.periodic_steady_state;write_json(progress,record);
            end
        end
        if converge
            assert((periodic || op.snapshotTime==target) && op.snapshotTime==origin_stop+20*numel(completed));
            record.collection_window_s=[origin_stop op.snapshotTime];
            record.native_observation_window_after_join_s=[op.snapshotTime-100 op.snapshotTime];
            record.early_stopped_on_original_public_periodicity=periodic && op.snapshotTime<target;
        else
            assert(numel(completed)==(target-origin_stop)/20 && op.snapshotTime==target);
        end
        record.pass=true;record.total_cycles=op.snapshotTime/10;
    catch ME
        record.error_message=ME.message;record.error_identifier=ME.identifier;
        record.error_report=getReport(ME,'extended','hyperlinks','off');
        if isfield(record,'current_attempt_root') && isfolder(record.current_attempt_root) && ...
                ~strcmp(record.current_attempt_root,record.last_verified_packet_root)
            write_json(fullfile(record.current_attempt_root,'REJECTED_DO_NOT_RESUME.json'), ...
                struct('reason',ME.message,'failed_packet_may_propagate',false,'production_recovery_allowed',false));
        end
    end
    write_json(progress,record);write_json(fullfile(root,'collection_result.json'),record);
    fprintf('COLLECTION_JSON=%s\n',jsonencode(record));
    assert(record.pass,'HeatDriveECC:BoundedCollectionIncomplete', ...
        'Inspect the preserved error; resume only from last_verified_packet_root: %s',record.error_message);
end

function path=canonical(path)
    path=char(java.io.File(char(path)).getCanonicalPath());
end

function release_lock(lock,channel,handle)
    lock.release();channel.close();handle.close();
end

function write_json(path,value)
    temporary=[path,'.writing'];fid=fopen(temporary,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));fclose(fid);
    movefile(temporary,path,'f');
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
