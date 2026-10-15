function record=Verify_HeatDriveECC_SplitObservation(input,source_op,options,folder,chambers,buffers,settings,request,producer)
% Compare a real two-cycle run with a qualified disk split, keeping all model settings.
    root=fullfile(folder,'split_observation');assert(~isfolder(root),'Never overwrite split evidence.');mkdir(root);
    model=input.ModelName;start=source_op.snapshotTime;middle=start+10;stop=start+20;
    contract=jsondecode(fileread(request.source_contract_path));
    source=fullfile(contract.execution_repo,contract.source_root_relative);
    source_file=fullfile(source,contract.operating_point_relative);
    history_file=fullfile(source,contract.history_relative);
    assert(start==contract.snapshot_time_s && start==620 && ...
        strcmp(file_hash(source_file),contract.operating_point_sha256) && ...
        strcmp(file_hash(history_file),contract.history_sha256),'Require intact current C62.');
    native_history=get_param(model,'SimscapeLogDataHistory');
    state_history=get_param(model,'MaxDataPoints');
    write_json(fullfile(root,'actual_observation_settings.json'),struct( ...
        'native_history_raw',native_history,'native_history_class',class(native_history), ...
        'state_history_raw',state_history,'state_history_class',class(state_history), ...
        'native_history_points',Resolve_HeatDriveECC_ObservationCount(native_history), ...
        'state_history_points',Resolve_HeatDriveECC_ObservationCount(state_history), ...
        'settings_changed',false));
    assert(strcmp(get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'SimscapeLogLimitData'),'on') && ...
        Resolve_HeatDriveECC_ObservationCount(native_history)==20002 && ...
        Resolve_HeatDriveECC_ObservationCount(state_history)==110002 && settings.history_cycles==11 && ...
        strcmp(get_param(model,'SaveOperatingPoint'),'on'),'Do not alter checkpoint-bound observation settings.');
    record=struct('schema','heatdrive_ecc_split_observation_preflight_v1','producer',producer, ...
        'source_root',source,'source_operating_point_sha256',contract.operating_point_sha256, ...
        'source_history_sha256',contract.history_sha256,'full_window_s',[start stop], ...
        'split_time_s',middle,'history_cap_cycles',2,'state_history_cap_cycles',11, ...
        'checksum_policy','error/error','pass',false,'completed_packets',{{}}, ...
        'source_state_edited',false,'partial_state_restore_used',false, ...
        'physical_parameters_changed',false,'production_recovery_allowed',false, ...
        'outer_solve_eligible',false,'error_message','');
    write_json(fullfile(root,'progress.json'),record);
    try
        if isfield(request,'reference_review_path')
            reference=load_reference_review(request.reference_review_path,folder,contract);
            record.reference_reused_without_simulation=true;
        else
            reference=packet('reference',source_op,start,stop);
            record.reference_reused_without_simulation=false;
        end
        record.completed_packets{end+1}='reference';write_json(fullfile(root,'progress.json'),record);
        prefix=packet('prefix',source_op,start,middle);
        record.completed_packets{end+1}='prefix';write_json(fullfile(root,'progress.json'),record);
        compare_packet(reference,prefix,fullfile(root,'prefix_comparison.json'));
        prefix_manifest=jsondecode(fileread(fullfile(prefix,'packet_manifest.json')));
        assert(strcmp(file_hash(fullfile(prefix,'comparison_only_complete_op.mat')),prefix_manifest.complete_OP_sha256));
        restored=load(fullfile(root,'prefix','comparison_only_complete_op.mat'), ...
            'diagnostic_operating_point','production_recovery_allowed');
        assert(~restored.production_recovery_allowed && restored.diagnostic_operating_point.snapshotTime==middle);
        suffix=packet('suffix',restored.diagnostic_operating_point,middle,stop);
        record.completed_packets{end+1}='suffix';write_json(fullfile(root,'progress.json'),record);
        compare_packet(reference,suffix,fullfile(root,'suffix_comparison.json'));
        record.pass=true;
        record.complete_two_cycle_split_comparison_pass=true;
        record.final_reference_OP_is_comparison_only=true;
    catch ME
        record.error_message=ME.message;record.error_identifier=ME.identifier;
        record.error_report=getReport(ME,'extended','hyperlinks','off');
        write_json(fullfile(root,'REJECTED_DO_NOT_RESUME.json'),struct( ...
            'reason',ME.message,'failed_comparison_state_may_propagate',false,'production_recovery_allowed',false));
    end
    assert(strcmp(file_hash(source_file),contract.operating_point_sha256) && ...
        strcmp(file_hash(history_file),contract.history_sha256),'Original C62 evidence changed.');
    write_json(fullfile(root,'split_observation_preflight.json'),record);
    fprintf('SPLIT_PREFLIGHT_JSON=%s\n',jsonencode(record));
    assert(record.pass,'HeatDriveECC:SplitObservationFailed', ...
        'Preserve split evidence and diagnose: %s',record.error_message);

    function result=packet(name,initial,a,b)
        result=Collect_HeatDriveECC_ObservationPacket(input,initial,a,b,fullfile(root,name), ...
            options,folder,chambers,buffers,producer,request.python_executable);
    end
end


function source=load_reference_review(path,folder,contract)
    proof=jsondecode(fileread(path));source=char(java.io.File(proof.source_packet_root).getCanonicalPath());
    assert(strcmp(proof.schema,'heatdrive_ecc_qualified_observation_reference_v1') && ...
        proof.mechanism_pass && proof.other_72_predicates_unchanged && ~proof.simulation_executed && ...
        ~proof.operating_point_loaded && ~proof.source_state_edited && ...
        ~proof.production_recovery_allowed && proof.reference_comparison_only, ...
        'No failed physical state may be promoted by a provenance review.');
    manifest_file=fullfile(source,'packet_manifest.json');manifest=jsondecode(fileread(manifest_file));
    assert(isequal(manifest.window_s(:),[620;640]) && manifest.source_snapshot_s==620 && ...
        strcmp(file_hash(manifest_file),proof.input_sha256.original_manifest));
    for k=1:numel(manifest.input_files)
        row=manifest.input_files(k);assert(strcmp(file_hash(fullfile(source,row.path)),row.sha256));
    end
    gate=jsondecode(fileread(proof.packet_gate_path));
    assert(gate.gate_pass && strcmp(file_hash(proof.packet_gate_path),proof.packet_gate_sha256) && ...
        strcmp(file_hash(proof.mechanism_review_path),proof.mechanism_review_sha256) && ...
        strcmp(gate.input_sha256.mechanism_review,proof.mechanism_review_sha256), ...
        'Reference needs all original predicates and current native energy gates.');
    old_root=fileparts(fileparts(fileparts(source)));new_root=fileparts(folder);
    old=jsondecode(fileread([old_root,'.preflight_config.json']));
    current=jsondecode(fileread([new_root,'.preflight_config.json']));
    for name={'output_root','diagnostic_observation_options'}
        old=rmfield(old,name{1});current=rmfield(current,name{1});
    end
    assert(isequaln(old,current) && strcmp(current.diagnostic_state_options.restore_source_root, ...
        fullfile(contract.execution_repo,contract.source_root_relative)), ...
        'Reused reference must have the identical prepared recipe and C62 parent.');
end

function compare_packet(reference,candidate,path)
    a=load(fullfile(reference,'observed_states.mat'),'observation');
    b=load(fullfile(candidate,'observed_states.mat'),'observation');
    states=Compare_HeatDriveECC_DiagnosticTraces(a.observation.states,b.observation.states);clear a b
    a=load(fullfile(reference,'native','observations.mat'),'native','source_traces','signals');
    b=load(fullfile(candidate,'native','observations.mat'),'native','source_traces','signals');
    native=Compare_HeatDriveECC_DiagnosticTraces(a.native,b.native);
    sources=Compare_HeatDriveECC_DiagnosticTraces(a.source_traces,b.source_traces);
    public=Compare_HeatDriveECC_DiagnosticTraces(public_traces(a.signals),public_traces(b.signals));
    record=struct('states',states,'native',native,'sources',sources,'public',public, ...
        'pass',states.pass && native.pass && sources.pass && public.pass, ...
        'comparison_scope','same samples; original numerical comparison tolerances, not physical steady tolerances');
    write_json(path,record);assert(record.pass,'HeatDriveECC:SplitTrajectoryMismatch','Actual split trajectory differs.');
end

function traces=public_traces(signals)
    names=fieldnames(signals);traces=cell(size(names));
    for k=1:numel(names)
        row=signals.(names{k});traces{k}=struct('block_path',names{k},'state_name','', ...
            'unit','','time_s',row.time_s,'values',row.values,'channel_count',size(row.values,2));
    end
end


function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
