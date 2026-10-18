function record=Run_HeatDriveECC_RuntimeSensitivityColdCase(root,parent,qualification,python,index,probe_only,kernel_admission)
% New independent factor case; the qualified source supplies parameters, never state.
    config=Prepare_HeatDriveECC_RuntimeFamilyRecipe(root,parent);
    config.diagnostic_observation_options=struct('mode','runtime_sensitivity_cold', ...
        'source_contract_path',parent,'candidate_qualification_path',qualification, ...
        'python_executable',python,'case_index',index,'probe_only',probe_only);
    if nargin>=7 && ~isempty(kernel_admission)
        backend=Read_HeatDriveECC_KernelColdAdmission(kernel_admission);
        config.diagnostic_constitutive_step_function=backend.wrapper_name;
        config.diagnostic_observation_options.kernel_admission_path=kernel_admission;
    end
    file=[root '.preflight_config.json'];fid=fopen(file,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    execution=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(file);
    record=execution.sensitivity_cold_result;
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end
