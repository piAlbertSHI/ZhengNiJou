function Test_HeatDriveECC_RuntimeTcStepPolicy(parent,path,python,Tc)
% Exercise actual JSON source and typed request before building the model.
    Test_HeatDriveECC_RuntimeTcSource(path);
    q=jsondecode(fileread(path));state=struct('mode','capture','command_horizon_cycles',200);
    r=struct('mode','runtime_boundary_Tc_step','python_executable',python,'source_contract_path',parent, ...
        'candidate_qualification_path',path,'collection_root','not-created-step-policy-test', ...
        'resume_collection',false,'collection_stop_s',q.snapshot_time_s+200,'candidate_Tc_K',Tc, ...
        'target_lift_span_K',.1,'target_SCP_span_W_per_g',.01);
    actual=Resolve_HeatDriveECC_ObservationPreflight(r,state,20,200,'native',true,struct());assert(isequaln(r,actual));
    rejected=0;
    for value=[q.temperature_K,q.temperature_K-2.01,NaN,Inf,254,394]
        bad=r;bad.candidate_Tc_K=value;
        try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    end
    for name={'target_lift_span_K','target_SCP_span_W_per_g'}
        bad=r;bad.(name{1})=bad.(name{1})*2;
        try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    end
    t=struct('schema','heatdrive_ecc_runtime_Tc_intervention_v2','source_Tc_K',q.temperature_K, ...
        'candidate_Tc_K',Tc,'transition_time_s',q.snapshot_time_s,'minimum_transition_cycles',12, ...
        'only_runtime_temperature_variable_changed',true,'source_state_edited',false,'old_model_OP_imported',false, ...
        'search_policy',struct('schema','heatdrive_ecc_runtime_Tc_bounded_search_v1','minimum_Tc_K',255.05, ...
        'maximum_Tc_K',393.15,'maximum_step_K',2,'fluid_minimum_K',255.05,'fluid_maximum_K',393.15, ...
        'source_public_periodic_pass',true,'source_target_precision_pass',true));
    Require_HeatDriveECC_RuntimeTcTrial(t);
    for name={'schema','maximum_step_K','source_target_precision_pass'}
        bad=t;
        switch name{1}
            case 'schema',bad.schema='heatdrive_ecc_runtime_Tc_intervention_v1';
            case 'maximum_step_K',bad.search_policy.maximum_step_K=10;
            otherwise,bad.search_policy.source_target_precision_pass=false;
        end
        try,Require_HeatDriveECC_RuntimeTcTrial(bad);catch,rejected=rejected+1;end
    end
    assert(rejected==11);
    fprintf('RUNTIME_TC_STEP_POLICY_JSON=%s\n',jsonencode(struct('valid_source_request_and_trial',true,'rejected',rejected)));
end
