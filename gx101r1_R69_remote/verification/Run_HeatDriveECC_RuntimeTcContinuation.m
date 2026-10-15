function record=Run_HeatDriveECC_RuntimeTcContinuation(prepared_root,collection_root,parent_path,qualification_path,python,resume)
% Continue the already qualified candidate, not its original C28 ancestor.
    if nargin<6,resume=false;end
    Test_HeatDriveECC_RuntimeTcSource(qualification_path);
    config=Prepare_HeatDriveECC_RuntimeFamilyRecipe(prepared_root,parent_path);
    q=jsondecode(fileread(qualification_path));
    config.diagnostic_observation_options=struct('mode','runtime_boundary_Tc_continuation', ...
        'python_executable',python,'source_contract_path',parent_path,'candidate_qualification_path',qualification_path, ...
        'collection_root',collection_root,'resume_collection',resume,'collection_stop_s',q.snapshot_time_s+200, ...
        'candidate_Tc_K',q.temperature_K,'target_lift_span_K',.1,'target_SCP_span_W_per_g',.01);
    file=[prepared_root,'.preflight_config.json'];fid=fopen(file,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    execution=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(file);
    assert(execution.runtime_boundary_warmup_pass && ~execution.requested_arm_collection_pass && ...
        ~execution.production_recovery_allowed);
    record=execution.runtime_Tc_candidate;
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end
