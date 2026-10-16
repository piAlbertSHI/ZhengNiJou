function record=Verify_HeatDriveECC_SensitivityContinuation(input,options,folder,chambers,buffers,request,producer)
% Same immutable case: a real split test precedes a bounded unchanged-state continuation.
    source=Read_HeatDriveECC_SensitivityColdSource(request.source_closeout_path,request.case_index);
    root=request.collection_root;path=fullfile(root,'continuation_result.json');
    assert(strcmp(file_hash(fullfile(folder,'sensitivity_case_contract.json')),source.case_contract_sha256));
    origin=jsondecode(fileread(source.origin_measured_window_path));
    if request.resume_collection
        assert(isfile(path) && ~isfile(fullfile(root,'REJECTED_DO_NOT_RESUME.json')));
        record=jsondecode(fileread(path));
        assert(strcmp(record.source_closeout_sha256,source.source_closeout_sha256) && ...
            strcmp(record.case_contract_sha256,source.case_contract_sha256) && ~record.source_state_edited);
        alive=false;
        try,p=System.Diagnostics.Process.GetProcessById(record.process_pid);alive=~p.HasExited;catch,end
        assert(~alive || record.process_pid==feature('getpid'),'The original continuation process is still alive.');
        if isstruct(record.completed_packets),record.completed_packets=num2cell(record.completed_packets);end
        if record.experiment_completed
            assert(request.collection_stop_s>record.last_verified_snapshot_time_s && ...
                request.collection_stop_s<=record.last_verified_snapshot_time_s+200, ...
                'An explicit bounded extension must follow the finished endpoint.');
            archived=fullfile(root,['completed_to_' num2str(record.last_verified_snapshot_time_s) '_' file_hash(path) '.json']);
            assert(~isfile(archived));copyfile(path,archived);
            record.previous_completed_record_path=archived;record.previous_completed_record_sha256=file_hash(archived);
            record.planned_window_s(2)=request.collection_stop_s;record.experiment_completed=false;
        else
            assert(request.collection_stop_s==record.planned_window_s(2),'Do not silently change an interrupted run budget.');
        end
    else
        assert(~isfolder(root),'Never overwrite a continuation collection.');mkdir(root);
        record=struct('schema','heatdrive_ecc_sensitivity_continuation_v1','producer',producer, ...
            'process_pid',feature('getpid'),'case_index',request.case_index,'case_contract_sha256',source.case_contract_sha256, ...
            'source_closeout_sha256',source.source_closeout_sha256,'source_packet_root',source.packet_root, ...
            'source_operating_point_sha256',source.operating_point_sha256,'planned_window_s',[200 request.collection_stop_s], ...
            'last_verified_snapshot_time_s',200,'completed_packets',{{}},'completed_continuation_cycles',0, ...
            'split_trajectory_comparison_pass',false,'experiment_completed',false,'error_message','', ...
            'source_state_edited',false,'state_reconstructed_or_reset',false, ...
            'full_internal_state_periodicity_verified',false,'orthogonal_effects_evaluated',false, ...
            'production_recovery_allowed',false,'outer_solve_eligible',false);
    end
    record.process_pid=feature('getpid');record.latest_execution_producer=producer;write_json(path,record);
    try
        workspace=fileparts(fileparts(fileparts(mfilename('fullpath'))));
        [status,~]=system(sprintf(['git -c core.longpaths=true -C "%s" diff --quiet "%s" HEAD -- ' ...
            '":(top,glob)gx101r1_R69_remote/*.m" "gx101r1_R69_remote/verification/Integrate_HeatDriveECC_StableConstitutiveSample.m" ' ...
            '"gx101r1_R69_remote/verification/HeatDriveECC_ConstitutiveStabilityBound.m"'],workspace,source.producer));
        assert(status==0,'Physical constructor or constitutive source changed since the actual C20 producer.');
        record.physical_constructor_and_constitutive_sources_unchanged=true;
        recipe=Compare_HeatDriveECC_RuntimeBoundaryRecipe(fullfile(source.packet_root,'native','configuration.mat'), ...
            fullfile(folder,'configuration.mat'),fullfile(folder,'same_case_recipe_comparison.json'));
        assert(recipe.only_declared_change && recipe.numeric_validation_thresholds_equal && ...
            strcmp(recipe.reference_configurability,recipe.candidate_configurability));
        [initial,m]=Load_HeatDriveECC_GatedObservationPacket(source.packet_root,true,source.case_contract_sha256);
        assert(initial.snapshotTime==200 && strcmp(m.complete_OP_sha256,source.operating_point_sha256));
        if ~record.split_trajectory_comparison_pass
            compare_root=fullfile(root,'split_comparison');attempt=1;
            while isfolder(sprintf('%s_attempt%02d',compare_root,attempt)),attempt=attempt+1;end
            compare_root=sprintf('%s_attempt%02d',compare_root,attempt);mkdir(compare_root);
            reference=collect(initial,200,220,fullfile(compare_root,'reference'), ...
                'runtime_sensitivity_split_comparison',source.operating_point_sha256);
            prefix=collect(initial,200,210,fullfile(compare_root,'prefix'), ...
                'runtime_sensitivity_split_comparison',source.operating_point_sha256);
            first=Compare_HeatDriveECC_ObservationPackets(reference,prefix,fullfile(compare_root,'prefix_comparison.json'));
            assert(first.pass);
            manifest=jsondecode(fileread(fullfile(prefix,'packet_manifest.json')));
            assert(strcmp(file_hash(fullfile(prefix,'comparison_only_complete_op.mat')),manifest.complete_OP_sha256) && ...
                strcmp(manifest.sensitivity_case_contract_sha256,source.case_contract_sha256));
            saved=load(fullfile(prefix,'comparison_only_complete_op.mat'),'diagnostic_operating_point','production_recovery_allowed');
            assert(~saved.production_recovery_allowed && saved.diagnostic_operating_point.snapshotTime==210);
            suffix=collect(saved.diagnostic_operating_point,210,220,fullfile(compare_root,'suffix'), ...
                'runtime_sensitivity_split_comparison',manifest.complete_OP_sha256);clear saved
            Verify_HeatDriveECC_ObservationBoundary(prefix,suffix);
            second=Compare_HeatDriveECC_ObservationPackets(reference,suffix,fullfile(compare_root,'suffix_comparison.json'));
            assert(second.pass);
            record.split_trajectory_comparison_pass=true;
            record.split_trajectory_comparison_bitwise=first.states.bitwise_values_equal && first.native.bitwise_values_equal && ...
                first.sources.bitwise_values_equal && first.public.bitwise_values_equal && second.states.bitwise_values_equal && ...
                second.native.bitwise_values_equal && second.sources.bitwise_values_equal && second.public.bitwise_values_equal;
            record.split_comparison_root=compare_root;
            record.prefix_comparison_sha256=file_hash(fullfile(compare_root,'prefix_comparison.json'));
            record.suffix_comparison_sha256=file_hash(fullfile(compare_root,'suffix_comparison.json'));
            record.split_comparison_scope='200-220 s continuous versus disk split at 210 s; bounded trajectory evidence, not a universal serialization proof';
            record.comparison_states_may_propagate=false;write_json(path,record);
        else
            for name={'prefix','suffix'}
                comparison_path=fullfile(record.split_comparison_root,[name{1} '_comparison.json']);
                assert(strcmp(file_hash(comparison_path),record.([name{1} '_comparison_sha256'])));
                comparison=jsondecode(fileread(comparison_path));
                assert(comparison.pass);
            end
        end
        previous=source.packet_root;parent=source.operating_point_sha256;
        for k=1:numel(record.completed_packets)
            row=record.completed_packets{k};assert(row.start_time_s==200+20*(k-1) && row.stop_time_s==200+20*k);
            m=jsondecode(fileread(fullfile(row.packet_root,'packet_manifest.json')));
            assert(strcmp(m.parent_complete_OP_sha256,parent));
            [initial,m]=Load_HeatDriveECC_GatedObservationPacket(row.packet_root,true,source.case_contract_sha256);
            parent=m.complete_OP_sha256;previous=row.packet_root;
        end
        assert(initial.snapshotTime==record.last_verified_snapshot_time_s);
        for finish=initial.snapshotTime+20:20:request.collection_stop_s
            start=finish-20;base=fullfile(root,sprintf('packet_C%03d',finish/10));attempt=1;
            while isfolder(sprintf('%s_attempt%02d',base,attempt)),attempt=attempt+1;end
            destination=sprintf('%s_attempt%02d',base,attempt);
            record.current_attempt_root=destination;record.current_attempt_window_s=[start finish];write_json(path,record);
            collect(initial,start,finish,destination,'runtime_sensitivity_continuation',parent);
            Verify_HeatDriveECC_ObservationBoundary(previous,destination);
            [initial,m]=Load_HeatDriveECC_GatedObservationPacket(destination,true,source.case_contract_sha256);
            parent=m.complete_OP_sha256;previous=destination;
            record.completed_packets{end+1}=struct('packet_root',destination,'start_time_s',start, ...
                'stop_time_s',finish,'operating_point_sha256',parent);
            record.last_verified_snapshot_time_s=finish;record.completed_continuation_cycles=(finish-200)/10;
            record.last_verified_packet_root=destination;write_json(path,record);
            check=Check_HeatDriveECC_RuntimeRollingPeriodicity(root,origin,record.completed_packets,276.95);
            precision=fullfile(fileparts(check.measured_window_path),'target_window_stability.json');
            script=fullfile(fileparts(mfilename('fullpath')),'Measure_HeatDriveECC_TargetWindow.py');
            [status,message]=system(sprintf('"%s" "%s" --index "%s" --output "%s" --Tc 276.95', ...
                request.python_executable,script,check.measured_window_path,precision));
            assert(status==0,'Target precision read failed: %s',message);
            record.latest_public_periodicity=check;record.latest_target_precision=jsondecode(fileread(precision));
            write_json(path,record);
        end
        record.experiment_completed=true;record.total_cycles=record.last_verified_snapshot_time_s/10;
    catch ME
        record.error_message=ME.message;record.error_identifier=ME.identifier;
        record.error_report=getReport(ME,'extended','hyperlinks','off');
        write_json(fullfile(root,'REJECTED_DO_NOT_RESUME.json'),struct('reason',ME.message,'failed_state_may_propagate',false));
        if isfield(record,'current_attempt_root') && isfolder(record.current_attempt_root)
            write_json(fullfile(record.current_attempt_root,'REJECTED_DO_NOT_RESUME.json'), ...
                struct('reason',ME.message,'failed_state_may_propagate',false));
        end
    end
    write_json(path,record);fprintf('SENSITIVITY_CONTINUATION_JSON=%s\n',jsonencode(record));
    assert(record.experiment_completed,'HeatDriveECC:SensitivityContinuationFailed','Diagnose the preserved comparison or physical rejection.');

    function destination=collect(op,a,b,destination,role,parent_hash)
        Collect_HeatDriveECC_ObservationPacket(input,op,a,b,destination,options,folder,chambers,buffers, ...
            producer,request.python_executable,role,parent_hash);
    end
end
function write_json(path,value)
    temp=[path '.tmp'];fid=fopen(temp,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));fclose(fid);
    [ok,message]=movefile(temp,path,'f');assert(ok,'%s',message);
end
function h=file_hash(path)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
