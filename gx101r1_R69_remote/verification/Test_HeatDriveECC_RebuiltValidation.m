function Test_HeatDriveECC_RebuiltValidation(metadata_path)
    saved=load(metadata_path,'original','refreshed');
    a=saved.original.validation;b=saved.refreshed.validation;
    for field={'article_component_pipe_UA_audit','article_component_pipe_UA_implemented'}
        a=rmfield(a,field{1});b=rmfield(b,field{1});
    end
    branch=saved.original.branch;
    assert(Compare_HeatDriveECC_RebuiltValidation(a,b,branch));
    bad=b;bad.pressure_command_domain_contract.minimum_absolute_MPa=0.44;
    assert(~Compare_HeatDriveECC_RebuiltValidation(a,bad,branch));
    bad=b;bad.pressure_command_domain_contract.fallback_interval_MPa(1)=-0.4;
    assert(~Compare_HeatDriveECC_RebuiltValidation(a,bad,branch));
    bad=b;bad.pressure_command_domain_contract.requested.fallback_min_MPa=-0.5;
    assert(~Compare_HeatDriveECC_RebuiltValidation(a,bad,branch));
    bad=b;bad.minimum_valid_liquid_pressure_MPa=0.44;
    assert(~Compare_HeatDriveECC_RebuiltValidation(a,bad,branch));
    bad=branch;bad.pressure_pi_min_MPa=-0.4;
    assert(~Compare_HeatDriveECC_RebuiltValidation(a,b,bad));
    fprintf('REBUILD_VALIDATION_TEST_JSON=%s\n',jsonencode(struct('cases',6,'pass',true)));
end
