function record=Run_HeatDriveECC_RuntimeTcPackets(input,options,folder,chambers,buffers,settings,request,producer)
% Gate intact same-family candidate packets; exclude the transition from statistics.
    repo=fileparts(fileparts(mfilename('fullpath')));model=input.ModelName;
    continuing=strcmp(request.mode,'runtime_boundary_Tc_continuation');
    stepping=strcmp(request.mode,'runtime_boundary_Tc_step');qualified=continuing || stepping;
    root=canonical(request.collection_root);assert(strcmp(fileparts(root),canonical(fullfile(repo,'outputs'))));
    assert(~isfile(fullfile(root,'HISTORICAL_RAW_RETIRED.json')), ...
        'Historical/rejected raw retirement disables in-place resume; use a separately qualified complete source.');
    assert(~isfile(fullfile(root,'COMPLETED_RAW_PREFIX_RETIRED.json')), ...
        'A sealed archived collection cannot resume in place; use its latest qualified same-Tc endpoint.');
    assert((qualified || strcmp(request.mode,'runtime_boundary_Tc_candidate')) && settings.history_cycles==11 && ...
        strcmp(get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error') && ...
        Resolve_HeatDriveECC_ObservationCount(get_param(model,'SimscapeLogDataHistory'))==20002 && ...
        Resolve_HeatDriveECC_ObservationCount(get_param(model,'MaxDataPoints'))==110002);
    existed=isfolder(root);assert(~existed || request.resume_collection,'Explicit resume only.');
    if ~existed,mkdir(root);end
    handle=java.io.RandomAccessFile(fullfile(root,'collection.lock'),'rw');channel=handle.getChannel();lock=channel.tryLock();
    if isempty(lock),channel.close();handle.close();error('Candidate already running.');end
    cleanup=onCleanup(@() release_lock(lock,channel,handle));
    snapshot=fullfile(root,'initial_recording_contract.json');recipe=fullfile(root,'initial_prepared_recipe.json');
    actual_recipe=[fileparts(folder),'.preflight_config.json'];progress=fullfile(root,'collection_progress.json');
    if qualified,contract=request.candidate_qualification_path;else,contract=request.recording_contract_path;end
    if ~existed
        copyfile(contract,snapshot);copyfile(actual_recipe,recipe);
    else
        old=jsondecode(fileread(recipe));current=jsondecode(fileread(actual_recipe));
        for key={'output_root','diagnostic_observation_options'},old=rmfield(old,key{1});current=rmfield(current,key{1});end
        assert(isequaln(old,current),'Candidate resume cannot change physics, controls or source recipe.');
    end
    pointer=jsondecode(fileread(snapshot));
    if qualified
        qpath=contract;assert(strcmp(file_hash(qpath),file_hash(snapshot)));q=pointer;
        source=Require_HeatDriveECC_RuntimeTcSource(q,options);reference_field='plant_build_options';
        origin_index=[];source_window='';
        for k=1:numel(q.files)
            row=q.files(k);[~,name,ext]=fileparts(row.path);
            if strcmp([name ext],'measured_window.json')
                candidate_index=jsondecode(fileread(row.path));
                if strcmp(candidate_index.schema,'heatdrive_ecc_measured_ten_cycle_collection_v1') && ...
                        isequal(candidate_index.window_s(:),[source.snapshot_s-100;source.snapshot_s])
                    assert(isempty(origin_index));origin_index=candidate_index;source_window=row.path;
                end
            end
        end
        assert(~isempty(origin_index) && origin_index.fixed_Tc_candidate && ...
            origin_index.candidate_Tc_K==source.Tc_K && origin_index.sample_count==100001 && ...
            isequal(origin_index.window_s(:),[source.snapshot_s-100;source.snapshot_s]));
    else
        main_repo=fileparts(fileparts(request.recording_contract_path));
        qpath=fullfile(main_repo,pointer.qualification_relative);assert(strcmp(file_hash(qpath),pointer.qualification_sha256));
        q=jsondecode(fileread(qpath));source=Require_HeatDriveECC_RuntimeRecordingSource(pointer,q,options);reference_field='options';
        assert(q.original_public_thermal_periodic_pass,'The baseline must first pass its original current thermal criteria.');
    end
    for k=1:numel(q.files),assert(strcmp(file_hash(q.files(k).path),q.files(k).sha256));end
    comparison=Compare_HeatDriveECC_RuntimeBoundaryRecipe(fullfile(source.packet_root,'native','configuration.mat'), ...
        fullfile(folder,'configuration.mat'),fullfile(folder,'runtime_Tc_recipe_comparison.json'),reference_field);
    assert(comparison.only_declared_change && comparison.numeric_validation_thresholds_equal && ...
        strcmp(comparison.reference_configurability,'runtime') && strcmp(comparison.candidate_configurability,'runtime'));
    origin=source.snapshot_s;target=request.collection_stop_s;Tc=request.candidate_Tc_K;
    minimum_stop=origin+20;
    if continuing && isfield(request,'minimum_stop_time_s'),minimum_stop=request.minimum_stop_time_s;end
    assert(target==origin+200 && target<=2000);
    if continuing
        assert(Tc==source.Tc_K);trial=q.boundary_trial;
        continuation=struct('source_snapshot_s',origin,'source_OP_sha256',q.operating_point_sha256, ...
            'source_qualification_sha256',file_hash(qpath),'budget_stop_s',target,'temperature_unchanged',true);
    elseif stepping
        assert(q.original_public_thermal_periodic_pass && q.bounded_outer_metric_sampling_allowed && ...
            q.current_target_window_stability.precision_pass);
        fluid=options.fluid.SE;
        assert(fluid.minimum_operating_temperature_K==255.05 && fluid.maximum_tabulated_temperature_K==393.15);
        policy=struct('schema','heatdrive_ecc_runtime_Tc_bounded_search_v1', ...
            'minimum_Tc_K',255.05,'maximum_Tc_K',393.15,'maximum_step_K',2, ...
            'fluid_minimum_K',fluid.minimum_operating_temperature_K,'fluid_maximum_K',fluid.maximum_tabulated_temperature_K, ...
            'source_public_periodic_pass',true,'source_target_precision_pass',true);
        trial=struct('schema','heatdrive_ecc_runtime_Tc_intervention_v2','source_Tc_K',source.Tc_K, ...
            'candidate_Tc_K',Tc,'transition_time_s',origin,'minimum_transition_cycles',12, ...
            'source_complete_OP_sha256',q.operating_point_sha256,'source_qualification_sha256',file_hash(qpath), ...
            'plant_recipe_sha256',file_hash(recipe),'only_runtime_temperature_variable_changed',true, ...
            'source_state_edited',false,'old_model_OP_imported',false,'search_policy',policy);
        Require_HeatDriveECC_RuntimeTcTrial(trial);
    else
        assert(request.minimum_transition_cycles==12);
        trial=struct('schema','heatdrive_ecc_runtime_Tc_intervention_v1','source_Tc_K',276.95, ...
        'candidate_Tc_K',Tc,'transition_time_s',origin,'minimum_transition_cycles',12, ...
        'source_complete_OP_sha256',pointer.operating_point_sha256, ...
        'source_qualification_sha256',pointer.qualification_sha256, ...
        'plant_recipe_sha256',file_hash(recipe),'only_runtime_temperature_variable_changed',true, ...
        'source_state_edited',false,'old_model_OP_imported',false);
    end
    if isfile(progress)
        record=jsondecode(fileread(progress));
        assert(strcmp(record.origin_snapshot_sha256,file_hash(snapshot)) && ...
            strcmp(record.origin_recipe_sha256,file_hash(recipe)) && isequaln(record.boundary_trial,trial) && ...
            isequal(record.planned_collection_window_s(:),[origin;target]));
        completed=record.completed_packets;
        if isempty(completed),completed={};elseif isstruct(completed),completed=num2cell(completed);end
    else
        assert(~existed || isempty(dir(fullfile(root,'packet_C*'))),'Missing progress requires forensic recovery.');
        schema='heatdrive_ecc_runtime_Tc_candidate_collection_v1';
        if continuing,schema='heatdrive_ecc_runtime_Tc_continuation_collection_v1';end
        completed={};record=struct('schema',schema,'producer',producer, ...
            'origin_snapshot_sha256',file_hash(snapshot),'origin_recipe_sha256',file_hash(recipe), ...
            'boundary_trial',trial,'candidate_Tc_K',Tc,'planned_collection_window_s',[origin target], ...
            'collection_window_s',[origin origin],'completed_packets',{{}}, ...
            'last_verified_snapshot_time_s',origin,'last_verified_packet_root',source.packet_root, ...
            'pass',false,'source_state_edited',false,'partial_state_restore_used',false, ...
            'production_recovery_allowed',false,'outer_solve_eligible',false,'error_message','');
    end
    if continuing
        if isfield(record,'continuation'),assert(isequaln(record.continuation,continuation));end
        record.continuation=continuation;record.origin_measured_window_path=source_window;
        record.origin_measured_window_sha256=file_hash(source_window);
        record.target_lift_span_K=request.target_lift_span_K;record.target_SCP_span_W_per_g=request.target_SCP_span_W_per_g;
        if isfield(record,'minimum_stop_time_s'),assert(record.minimum_stop_time_s==minimum_stop);end
        record.minimum_stop_time_s=minimum_stop;
    end
    if stepping
        record.target_precision_required=true;
        record.target_lift_span_K=request.target_lift_span_K;record.target_SCP_span_W_per_g=request.target_SCP_span_W_per_g;
    end
    [op,m]=Load_HeatDriveECC_GatedObservationPacket(source.packet_root,false);previous=source.packet_root;
    assert(strcmp(m.complete_OP_sha256,pointer.operating_point_sha256));
    for k=1:numel(completed)
        row=completed{k};parent=m.complete_OP_sha256;
        [op,m]=Load_HeatDriveECC_GatedObservationPacket(row.packet_root,true);
        assert(row.start_time_s==origin+20*(k-1) && row.stop_time_s==origin+20*k && ...
            strcmp(row.operating_point_sha256,m.complete_OP_sha256) && strcmp(m.parent_complete_OP_sha256,parent) && ...
            isequaln(m.boundary_trial,trial));previous=row.packet_root;
    end
    candidate_input=input.setVariable('cold_sink_T_init',Tc);
    analysis_options=options;analysis_options.system.Tchex_K=Tc;
    analysis_options.validation.cold_boundary_audit.prescribed_Tchex_K=Tc;
    record.process_pid=feature('getpid');record.current_producer=producer;record.error_message='';
    record.completed_packets=completed;write_json(progress,record);
    try
        periodic=false;precision=false;
        if ~isempty(completed) && (continuing || numel(completed)>=6)
            if continuing,history=origin_index;else,history=[];end
            record.latest_periodicity=Check_HeatDriveECC_RuntimeRollingPeriodicity(root,history,completed,Tc);
            periodic=record.latest_periodicity.periodic_steady_state;
            if qualified
                record.latest_target_stability=target_precision(record.latest_periodicity,request);precision=record.latest_target_stability.precision_pass;
            end
            write_json(progress,record);
        end
        for finish=origin+20+20*numel(completed):20:target
            if periodic && (~qualified || precision) && op.snapshotTime>=minimum_stop,break;end
            start=op.snapshotTime;assert(finish-start==20);attempt=1;
            destination=fullfile(root,sprintf('packet_C%03d_attempt%02d',finish/10,attempt));
            while isfolder(destination),attempt=attempt+1;destination=fullfile(root,sprintf('packet_C%03d_attempt%02d',finish/10,attempt));end
            record.current_attempt_root=destination;record.current_attempt_window_s=[start finish];write_json(progress,record);
            role='runtime_boundary_Tc_candidate';packet_trial=trial;
            if continuing,role='runtime_boundary_Tc_continuation';packet_trial.continuation=continuation;end
            Collect_HeatDriveECC_ObservationPacket(candidate_input,op,start,finish,destination,analysis_options,folder, ...
                chambers,buffers,producer,request.python_executable,role,m.complete_OP_sha256,packet_trial);
            if isempty(completed) && ~continuing,boundary=Verify_HeatDriveECC_ObservationBoundary(previous,destination,trial);
            else,boundary=Verify_HeatDriveECC_ObservationBoundary(previous,destination);end
            assert(boundary.pass);[next,m]=Load_HeatDriveECC_GatedObservationPacket(destination,true);
            completed{end+1}=struct('packet_root',destination,'start_time_s',start,'stop_time_s',finish, ...
                'operating_point_sha256',m.complete_OP_sha256); %#ok<AGROW>
            op=next;previous=destination;record.completed_packets=completed;
            record.last_verified_snapshot_time_s=finish;record.last_verified_packet_root=destination;write_json(progress,record);
            if continuing || numel(completed)>=6
                if continuing,history=origin_index;else,history=[];end
                record.latest_periodicity=Check_HeatDriveECC_RuntimeRollingPeriodicity(root,history,completed,Tc);
                periodic=record.latest_periodicity.periodic_steady_state;
                if qualified
                    record.latest_target_stability=target_precision(record.latest_periodicity,request);precision=record.latest_target_stability.precision_pass;
                end
                write_json(progress,record);
            end
        end
        if continuing,assert(~isempty(completed) && (((periodic && precision) && op.snapshotTime>=minimum_stop) || op.snapshotTime==target));
        else,assert(numel(completed)>=6 && ((periodic && (~stepping || precision)) || op.snapshotTime==target));end
        record.pass=true;record.collection_window_s=[origin op.snapshotTime];record.total_cycles=op.snapshotTime/10;
        record.periodic_steady_state=periodic;record.transition_excluded_from_current_window=true;
        record.completed_additional_cycles=2*numel(completed);
        if qualified,record.target_window_precision_pass=precision;end
    catch ME
        record.error_message=ME.message;record.error_identifier=ME.identifier;record.error_report=getReport(ME,'extended','hyperlinks','off');
        if isfield(record,'current_attempt_root') && isfolder(record.current_attempt_root) && ...
                ~strcmp(record.current_attempt_root,record.last_verified_packet_root)
            write_json(fullfile(record.current_attempt_root,'REJECTED_DO_NOT_RESUME.json'), ...
                struct('reason',ME.message,'failed_packet_may_propagate',false,'production_recovery_allowed',false));
        end
    end
    write_json(progress,record);write_json(fullfile(root,'collection_result.json'),record);
    fprintf('TC_CANDIDATE_JSON=%s\n',jsonencode(record));
    assert(record.pass,'HeatDriveECC:RuntimeTcCandidateFailed','Inspect preserved diagnostic: %s',record.error_message);
end

function report=target_precision(check,request)
    index=check.measured_window_path;output=fullfile(fileparts(index),'target_window_stability.json');
    script=fullfile(fileparts(mfilename('fullpath')),'Measure_HeatDriveECC_TargetWindow.py');
    [status,message]=system(sprintf('"%s" "%s" --index "%s" --output "%s" --Tc %.17g', ...
        request.python_executable,script,index,output,request.candidate_Tc_K));
    assert(status==0 && isfile(output),'Target-window analysis failed: %s',message);
    report=jsondecode(fileread(output));report.path=output;report.sha256=file_hash(output);
    assert(report.lift_limit_K==request.target_lift_span_K && report.SCP_limit_W_per_g==request.target_SCP_span_W_per_g);
end

function p=canonical(p),p=char(java.io.File(char(p)).getCanonicalPath());end
function release_lock(lock,channel,handle),lock.release();channel.close();handle.close();end
function write_json(path,value)
    temporary=[path,'.writing'];fid=fopen(temporary,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));fclose(fid);movefile(temporary,path,'f');
end
function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
