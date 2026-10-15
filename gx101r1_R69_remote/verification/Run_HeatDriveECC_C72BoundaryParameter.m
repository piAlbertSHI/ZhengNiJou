function record=Run_HeatDriveECC_C72BoundaryParameter(prepared_root,parent_path,endpoint_path,python,candidate_Tc_K)
% One unchanged positive control and one declared boundary perturbation, not an outer candidate.
    config=Prepare_HeatDriveECC_ObservationRecipe(prepared_root,parent_path,python);
    config.diagnostic_observation_options=struct('mode','boundary_parameter_probe','python_executable',python, ...
        'source_contract_path',parent_path,'endpoint_contract_path',endpoint_path,'candidate_Tc_K',candidate_Tc_K);
    file=[prepared_root,'.preflight_config.json'];fid=fopen(file,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    execution=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(file);
    assert(execution.boundary_parameter_probe_completed && ~execution.checkpoint_saved && ...
        ~execution.requested_arm_collection_pass && ~execution.production_recovery_allowed);
    record=execution.boundary_parameter_probe;
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end
