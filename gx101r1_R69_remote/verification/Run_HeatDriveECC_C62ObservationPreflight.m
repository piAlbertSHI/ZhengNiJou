function record=Run_HeatDriveECC_C62ObservationPreflight(output_root,contract_path,python,reference_review_path)
% Prepare the original C62 model, then execute only the explicit split comparison.
    config=Prepare_HeatDriveECC_ObservationRecipe(output_root,contract_path,python);
    config.diagnostic_observation_options=struct('mode','split_preflight','python_executable',python, ...
        'source_contract_path',contract_path);
    if nargin==4
        config.diagnostic_observation_options.reference_review_path=reference_review_path;
    end
    path=[output_root,'.preflight_config.json'];fid=fopen(path,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    record=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(path);
    assert(record.observation_preflight_pass && ~record.requested_arm_collection_pass && ...
        ~record.checkpoint_saved && ~record.production_recovery_allowed, ...
        'A comparison must not masquerade as a twenty-cycle continuation.');
    fprintf('FINAL_JSON=%s\n',jsonencode(record.observation_preflight));
end
