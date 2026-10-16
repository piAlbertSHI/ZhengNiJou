function record=Run_HeatDriveECC_RuntimeHorizonPreflight(prepared_root,parent_path,qualification_path,python)
% Capacity preflight, never a new cold family or a C200 state conversion.
    config=Prepare_HeatDriveECC_RuntimeFamilyRecipe(prepared_root,parent_path);
    config.diagnostic_observation_options=struct('mode','runtime_boundary_horizon_preflight', ...
        'python_executable',python,'source_contract_path',parent_path,'candidate_qualification_path',qualification_path);
    file=[prepared_root,'.preflight_config.json'];fid=fopen(file,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    execution=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(file);
    record=execution.runtime_horizon_preflight;
    assert(record.pass && ~record.comparison_states_may_propagate && ~execution.production_recovery_allowed);
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end
