function record=Run_HeatDriveECC_RuntimeBoundaryColdFamily(prepared_root,parent_path,probe_path,python)
% Construct a separate tunable family. No C200/C62/C72 complete OP enters this simulation.
    config=Prepare_HeatDriveECC_RuntimeFamilyRecipe(prepared_root,parent_path);
    config.diagnostic_observation_options=struct('mode','runtime_boundary_cold_family', ...
        'python_executable',python,'source_contract_path',parent_path,'boundary_probe_path',probe_path);
    file=[prepared_root,'.preflight_config.json'];fid=fopen(file,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    execution=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(file);
    assert(execution.runtime_boundary_family_completed && ~execution.requested_arm_collection_pass && ...
        ~execution.production_recovery_allowed);
    record=execution.runtime_boundary_family_result;
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end
