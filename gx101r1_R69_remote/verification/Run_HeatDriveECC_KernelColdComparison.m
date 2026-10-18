function record=Run_HeatDriveECC_KernelColdComparison(prepared,parent,closeout,kernel,python)
% Two independent cold cycles against the same case's retained original C2.
    q=jsondecode(fileread(closeout));assert(ismember(q.case_index,[0 1]));
    source=Read_HeatDriveECC_SensitivityColdSource(closeout,q.case_index);
    Read_HeatDriveECC_KernelQualification(kernel);
    config=Prepare_HeatDriveECC_RuntimeFamilyRecipe(prepared,parent);
    config.diagnostic_constitutive_step_function='HeatDriveECC_ConstitutiveStateVectorStep21_KernelCandidate';
    config.diagnostic_observation_options=struct('mode','runtime_sensitivity_kernel_cold_comparison', ...
        'source_contract_path',parent,'candidate_qualification_path',source.case_contract.source_qualification_path, ...
        'python_executable',python,'case_index',q.case_index,'probe_only',true, ...
        'source_closeout_path',closeout,'kernel_qualification_path',kernel);
    path=[prepared '.preflight_config.json'];fid=fopen(path,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    execution=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(path);
    record=execution.kernel_cold_comparison_result;
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end
