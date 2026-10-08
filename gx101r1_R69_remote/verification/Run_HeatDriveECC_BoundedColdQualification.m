function record=Run_HeatDriveECC_BoundedColdQualification(template_path,static_root,output_root)
% Fresh cold branch with changed command saturation, never an old endpoint resume.
    assert(~isfolder(output_root),'Never overwrite a cold qualification.');
    config=jsondecode(fileread(template_path));repo=char(config.repo_root);
    static=jsondecode(fileread(fullfile(static_root,'domain_component_preflight.json')));
    assert(static.bounded_article_audit.ok && static.protected_configuration_unchanged && ...
        static.route_memory_contract.pass && ~static.operating_point_loaded && ...
        ~static.production_recovery_allowed,'Require actual domain/component model preflight.');
    baseline=jsondecode(fileread(fullfile(static.source_root,'cold_chamber_execution.json')));
    assert(isequaln(Build_HeatDriveECC_IndependentColdBranchOverrides(config), ...
        baseline.diagnostic_branch_overrides),'The prepared controller differs from the inspected baseline.');
    targets=jsondecode(fileread(fullfile(static.source_root,'native','public_inventory_targets.json')));
    assert(targets.source_time_s==0 && numel(targets.targets)==204 && ...
        strcmp(file_hash(fullfile(config.initial_observation_root,'native','observations.mat')), ...
        targets.source_sha256),'Cold initialization differs from the inspected t=0 chain.');
    assert(config.cycle_count==2 && config.duration_s==20 && ...
        strcmp(config.diagnostic_state_options.mode,'restore_preflight') && ...
        config.diagnostic_state_options.command_horizon_cycles==200 && ...
        ~isfield(config.diagnostic_state_options,'restore_source_root'), ...
        'This entry supports only a new cold qualification, not a state import.');
    [status,dirty]=system(sprintf('git -C "%s" status --porcelain',fileparts(repo)));
    assert(status==0 && isempty(strtrim(dirty)),'Use the clean execution checkout.');
    Test_HeatDriveECC_MechanismProvenance();
    config.output_root=output_root;
    config.pressure_command_domain_closure_enabled=true;
    config.pressure_command_domain_margin_MPa=static.pressure_domain.declared_margin_MPa;
    if strcmp(static.pressure_domain.schema,'heatdrive_ecc_pressure_command_domain_v2')
        assert(static.pressure_domain.named_reference_topology.pass && ...
            strcmp(static.reference_mode,'named_source_reference'));
        config.pressure_command_reference_mode=static.reference_mode;
        config.pressure_reference_head_budget_MPa=static.pressure_domain.reference_head_budget_MPa;
    end
    path=[output_root,'.state_preflight_config.json'];assert(~isfile(path));
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(config,'PrettyPrint',true));fclose(fid);
    record=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(path);
    assert(record.state_restore_preflight_pass && record.requested_arm_collection_pass && ...
        numel(record.bounded_cold_mechanism_cases)==1 && ...
        record.bounded_cold_mechanism_cases{1}.mechanism_pass, ...
        'Cold physics and same-model state interface must both pass.');
    fprintf('%s\n',jsonencode(struct('bounded_cold_mechanism_pass',true, ...
        'same_model_restore_pass',true,'local_inventory_post_audit_still_required',true, ...
        'rebuilt_full_cycle_restore_still_required',true,'production_recovery_allowed',false)));
end

function hash=file_hash(file)
    fid=fopen(file,'rb');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    digest=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
