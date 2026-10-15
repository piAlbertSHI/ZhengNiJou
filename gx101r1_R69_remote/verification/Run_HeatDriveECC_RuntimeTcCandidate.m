function record=Run_HeatDriveECC_RuntimeTcCandidate(prepared_root,collection_root,parent_path,endpoint_path,python,Tc,resume)
% A candidate is not a C200 mainline point; never migrate old-family state.
    if nargin<7,resume=false;end
    Test_HeatDriveECC_RuntimeTcPolicy(parent_path,endpoint_path,python);
    config=Prepare_HeatDriveECC_RuntimeFamilyRecipe(prepared_root,parent_path);
    p=jsondecode(fileread(endpoint_path));
    config.diagnostic_observation_options=struct('mode','runtime_boundary_Tc_candidate', ...
        'python_executable',python,'source_contract_path',parent_path,'recording_contract_path',endpoint_path, ...
        'collection_root',collection_root,'resume_collection',resume,'collection_stop_s',p.snapshot_time_s+200, ...
        'candidate_Tc_K',Tc,'minimum_transition_cycles',12);
    file=[prepared_root,'.preflight_config.json'];fid=fopen(file,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    execution=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(file);
    assert(execution.runtime_boundary_warmup_pass && ~execution.requested_arm_collection_pass && ...
        ~execution.production_recovery_allowed);
    record=execution.runtime_Tc_candidate;
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end
