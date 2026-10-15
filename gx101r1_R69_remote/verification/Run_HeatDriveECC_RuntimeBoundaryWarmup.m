function record=Run_HeatDriveECC_RuntimeBoundaryWarmup(prepared_root,collection_root,parent_path,endpoint_path,python,stop,resume,converge)
% Twenty-cycle transient continuation in the same runtime family, never a cold rerun.
    if nargin<7,resume=false;end
    if nargin<8,converge=false;end
    Test_HeatDriveECC_RuntimeWarmupPolicy(parent_path,endpoint_path,python);
    config=Prepare_HeatDriveECC_RuntimeFamilyRecipe(prepared_root,parent_path);
    config.diagnostic_observation_options=struct('mode','runtime_boundary_warmup','python_executable',python, ...
        'source_contract_path',parent_path,'recording_contract_path',endpoint_path, ...
        'collection_root',collection_root,'resume_collection',resume,'collection_stop_s',stop);
    if converge,config.diagnostic_observation_options.stop_on_public_periodicity=true;end
    file=[prepared_root,'.preflight_config.json'];fid=fopen(file,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    execution=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(file);
    assert(execution.runtime_boundary_warmup_pass && ~execution.requested_arm_collection_pass && ...
        ~execution.production_recovery_allowed);
    record=execution.runtime_boundary_warmup;
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end
