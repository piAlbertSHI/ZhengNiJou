function record=Test_HeatDriveECC_RuntimeWarmupPolicy(parent_path,endpoint_path,python)
% Actual typed policy tests without a model simulation or OP import.
    pointer=jsondecode(fileread(endpoint_path));repo=fileparts(fileparts(endpoint_path));
    q=jsondecode(fileread(fullfile(repo,pointer.qualification_relative)));
    state=struct('mode','capture','command_horizon_cycles',200);
    request=struct('mode','runtime_boundary_warmup','python_executable',python, ...
        'source_contract_path',parent_path,'recording_contract_path',endpoint_path, ...
        'collection_root','not-created-policy-test','resume_collection',false, ...
        'collection_stop_s',pointer.snapshot_time_s+200);
    actual=Resolve_HeatDriveECC_ObservationPreflight(request,state,20,200,'native',true,struct());
    assert(isequaln(actual,request));
    rejected=0;
    for target=[pointer.snapshot_time_s+180,pointer.snapshot_time_s+201,2001,NaN]
        bad=request;bad.collection_stop_s=target;
        try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    end
    bad=request;bad.candidate_Tc_K=276.85;
    try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    bad_state=struct('mode','diagnostic_resume','command_horizon_cycles',200);
    try,Resolve_HeatDriveECC_ObservationPreflight(request,bad_state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    assert(rejected==6);
    options=struct('system',struct('Tchex_K',276.95,'cold_boundary_temperature_configurability','runtime'));
    source=Require_HeatDriveECC_RuntimeRecordingSource(pointer,q,options);assert(source.snapshot_s==pointer.snapshot_time_s);
    typed_rejected=0;
    for name={'temperature_configurability','state_history_cap_cycles','old_model_OP_imported'}
        bad=q;
        if strcmp(name{1},'temperature_configurability'),bad.(name{1})='compiletime';
        elseif strcmp(name{1},'state_history_cap_cycles'),bad.(name{1})=2;
        else,bad.(name{1})=true;end
        try,Require_HeatDriveECC_RuntimeRecordingSource(pointer,bad,options);catch,typed_rejected=typed_rejected+1;end
    end
    assert(typed_rejected==3);
    record=struct('valid_same_family_request',true,'unsafe_request_count_rejected',rejected, ...
        'unsafe_family_count_rejected',typed_rejected,'simulation_executed',false,'operating_point_loaded',false);
    fprintf('RUNTIME_WARMUP_POLICY_JSON=%s\n',jsonencode(record));
end
