function record=Run_HeatDriveECC_SensitivityContinuation(prepared,collection,parent,qualification,closeout,python,resume,stop)
% Rebuild the identical constructor and resume only the sealed case's complete state.
    if nargin<7,resume=false;end
    if nargin<8,stop=400;end
    q=jsondecode(fileread(closeout));Read_HeatDriveECC_SensitivityColdSource(closeout,q.case_index);
    config=Prepare_HeatDriveECC_RuntimeFamilyRecipe(prepared,parent);
    config.diagnostic_observation_options=struct('mode','runtime_sensitivity_continuation', ...
        'source_contract_path',parent,'candidate_qualification_path',qualification, ...
        'python_executable',python,'case_index',q.case_index,'probe_only',false, ...
        'source_closeout_path',closeout,'collection_root',collection,'resume_collection',resume,'collection_stop_s',stop);
    file=[prepared '.preflight_config.json'];fid=fopen(file,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    execution=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(file);
    record=execution.sensitivity_continuation_result;
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end
