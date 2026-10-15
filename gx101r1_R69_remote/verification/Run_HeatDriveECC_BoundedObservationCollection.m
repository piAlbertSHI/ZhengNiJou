function record=Run_HeatDriveECC_BoundedObservationCollection(prepared_root,collection_root,parent_path,recording_path,python,resume)
% Prepare the identical model once; actual execution is limited by the sealed recording contract.
    if nargin<6,resume=false;end
    config=Prepare_HeatDriveECC_ObservationRecipe(prepared_root,parent_path,python);
    config.diagnostic_observation_options=struct('mode','packet_collection','python_executable',python, ...
        'source_contract_path',parent_path,'recording_contract_path',recording_path, ...
        'collection_root',collection_root,'resume_collection',resume);
    path=[prepared_root,'.preflight_config.json'];fid=fopen(path,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    record=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(path);
    assert(record.observation_collection_pass && ~record.requested_arm_collection_pass && ...
        ~record.checkpoint_saved && ~record.production_recovery_allowed);
    fprintf('FINAL_JSON=%s\n',jsonencode(record.observation_collection));
end
