function record=Verify_HeatDriveECC_SensitivityColdCase(input,options,folder,chambers,buffers,request,producer)
% An initialization probe cannot qualify a steady sensitivity response.
    root=fullfile(folder,'sensitivity_cold_case');assert(~isfolder(root));mkdir(root);
    contract=jsondecode(fileread(fullfile(folder,'sensitivity_case_contract.json')));
    declared=contract.parameters;if isstruct(declared),declared=num2cell(declared);end
    for k=1:numel(declared)
        parts=strsplit(declared{k}.field,'.');value=options;
        for j=1:numel(parts),value=value.(parts{j});end
        assert(isequaln(value,declared{k}.after),'A sensitivity override did not reach the actual constructor.');
    end
    assert(strcmp(get_param(input.ModelName,'LoadInitialState'),'off'));
    output=sim(input.setModelParameter('StopTime','.001','SaveFinalState','off','SaveOperatingPoint','off'));
    if ~isempty(output.ErrorMessage)
        metadata=jsondecode(fileread(fullfile(folder,'inventory_metadata.json')));
        Export_HeatDriveECC_FailedColdObservations(output,input.ModelName,metadata,fullfile(root,'failed_initial_probe.mat'));
    end
    assert(isempty(output.ErrorMessage),'HeatDriveECC:SensitivityInitialProbeFailed','%s',output.ErrorMessage);
    native=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,input.ModelName,false,chambers,buffers);
    save(fullfile(root,'initial_native_observations.mat'),'native','-v7.3');clear output
    physical=jsondecode(fileread(fullfile(folder,'public_inventory_targets.json')));targets=physical.targets;
    if isstruct(targets),targets=num2cell(targets);end
    comparisons=cell(size(targets));
    for k=1:numel(targets)
        target=targets{k};selected=native(cellfun(@(r) strcmp(r.block_path,target.block_path) && ...
            strcmp(r.state_name,target.state_name),native));assert(isscalar(selected));row=selected{1};
        assert(row.time_s(1)==0);
        actual=value_in_unit(row.values(1),row.unit,target.unit);limit=1e-10+1e-11*abs(target.value);
        comparisons{k}=struct('path',target.path,'priority',target.priority,'expected',target.value, ...
            'actual',actual,'unit',target.unit,'limit',limit,'pass',abs(actual-target.value)<=limit);
    end
    record=struct('schema','heatdrive_ecc_runtime_sensitivity_cold_result_v1','producer',producer, ...
        'case_index',request.case_index,'probe_only',request.probe_only,'coordinate_count',numel(targets), ...
        'coordinate_comparisons',{comparisons},'coordinate_match_pass', ...
        numel(targets)==204 && all(cellfun(@(r) r.pass,comparisons)), ...
        'full_cycle_gates_evaluated',false,'all_original_packet_gates_pass',false, ...
        'periodic_steady_state',false,'orthogonal_effects_evaluated',false, ...
        'complete_state_may_propagate_outside_case',false,'case_local_gated_continuation_allowed',true, ...
        'last_verified_snapshot_time_s',0,'completed_cold_cycles',0, ...
        'experiment_completed',false,'error_message','', ...
        'source_state_imported',false,'production_recovery_allowed',false);
    write_json(fullfile(root,'case_result.json'),record);
    try
        assert(record.coordinate_match_pass,'HeatDriveECC:SensitivityColdCoordinatesFailed','New case t0 coordinates do not match the original strict comparison.');
        if ~request.probe_only
            initial=[];parent='';previous='';completed={};case_hash=file_hash(fullfile(folder,'sensitivity_case_contract.json'));
            for finish=20:20:200
                start=finish-20;destination=fullfile(root,sprintf('packet_C%03d',finish/10));
                role='runtime_sensitivity_cold';if start>0,role='runtime_sensitivity_transient';end
                record.current_attempt_root=destination;record.current_attempt_window_s=[start finish];
                write_json(fullfile(root,'case_result.json'),record);
                Collect_HeatDriveECC_ObservationPacket(input,initial,start,finish,destination,options,folder,chambers,buffers, ...
                    producer,request.python_executable,role,parent);
                if start>0,Verify_HeatDriveECC_ObservationBoundary(previous,destination);end
                [initial,m]=Load_HeatDriveECC_GatedObservationPacket(destination,start>0,case_hash);
                parent=m.complete_OP_sha256;previous=destination;
                completed{end+1}=struct('packet_root',destination,'start_time_s',start,'stop_time_s',finish,'operating_point_sha256',parent); %#ok<AGROW>
                record.completed_packets=completed;record.last_verified_snapshot_time_s=finish;
                record.completed_cold_cycles=finish/10;
                record.last_verified_packet_root=destination;write_json(fullfile(root,'case_result.json'),record);
            end
            check=Check_HeatDriveECC_RuntimeRollingPeriodicity(root,[],completed,276.95);
            record.current_public_periodicity=check;record.periodic_steady_state=check.periodic_steady_state;
            script=fullfile(fileparts(mfilename('fullpath')),'Measure_HeatDriveECC_TargetWindow.py');
            precision=fullfile(fileparts(check.measured_window_path),'target_window_stability.json');
            [status,message]=system(sprintf('"%s" "%s" --index "%s" --output "%s" --Tc 276.95', ...
                request.python_executable,script,check.measured_window_path,precision));
            assert(status==0,'Target precision evaluation failed: %s',message);
            record.current_target_precision=jsondecode(fileread(precision));
            record.full_cycle_gates_evaluated=true;record.all_original_packet_gates_pass=true;
            record.completed_cold_cycles=20;
        end
        record.experiment_completed=true;
    catch ME
        record.error_message=ME.message;record.error_identifier=ME.identifier;
        record.error_report=getReport(ME,'extended','hyperlinks','off');
        write_json(fullfile(root,'REJECTED_DO_NOT_RESUME.json'),struct('reason',ME.message,'failed_state_may_propagate',false));
        if isfield(record,'current_attempt_root') && isfolder(record.current_attempt_root)
            write_json(fullfile(record.current_attempt_root,'REJECTED_DO_NOT_RESUME.json'), ...
                struct('reason',ME.message,'failed_state_may_propagate',false));
        end
    end
    write_json(fullfile(root,'case_result.json'),record);
    assert(record.experiment_completed,'HeatDriveECC:SensitivityColdCaseFailed','Diagnose the preserved initialization or original cycle gate failure.');
end
function hash=file_hash(path)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
function v=value_in_unit(v,from,to),v=value(simscape.Value(v,from),to);end
function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
