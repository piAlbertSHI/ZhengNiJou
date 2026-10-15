function Test_HeatDriveECC_RuntimeTcPolicy(parent_path,endpoint_path,python)
% Exercise the request type before building a long candidate model.
    p=jsondecode(fileread(endpoint_path));state=struct('mode','capture','command_horizon_cycles',200);
    r=struct('mode','runtime_boundary_Tc_candidate','python_executable',python, ...
        'source_contract_path',parent_path,'recording_contract_path',endpoint_path, ...
        'collection_root','not-created-policy-test','resume_collection',false, ...
        'collection_stop_s',p.snapshot_time_s+200,'candidate_Tc_K',276.85,'minimum_transition_cycles',12);
    actual=Resolve_HeatDriveECC_ObservationPreflight(r,state,20,200,'native',true,struct());assert(isequaln(r,actual));
    rejected=0;
    for Tc=[276.95,276.7,NaN,Inf]
        bad=r;bad.candidate_Tc_K=Tc;
        try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    end
    for count=[10,11,20]
        bad=r;bad.minimum_transition_cycles=count;
        try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    end
    assert(rejected==7);fprintf('RUNTIME_TC_POLICY_JSON=%s\n',jsonencode(struct('valid_request',true,'rejected',rejected)));
end
