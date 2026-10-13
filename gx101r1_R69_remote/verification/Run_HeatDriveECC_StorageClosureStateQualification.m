function study = Run_HeatDriveECC_StorageClosureStateQualification(storage_audit_path, reference_audit_path, output_root)
% One new 0-20 s chain, no imported OP and no rerun of completed controls.
    output_root=char(java.io.File(output_root).getCanonicalPath());
    assert(~isfolder(output_root),'Never overwrite a state-qualification experiment.');
    contract=Require_HeatDriveECC_StorageClosureColdSource(storage_audit_path);
    config=jsondecode(fileread(contract.candidate_config_path));
    assert(strcmp(config.output_root,contract.source_root) && ...
        strcmp(config.diagnostic_inventory_options.storage_closure,'pressure_only_density'));
    config.output_root=fullfile(output_root,'candidate');config.cycle_count=2;config.duration_s=20;
    config.diagnostic_state_options=struct('mode','restore_preflight','command_horizon_cycles',200);
    config.diagnostic_inventory_options.cold_followup_audit_path=storage_audit_path;
    config.diagnostic_se_reference_options.cold_followup_audit_path=reference_audit_path;
    mkdir(output_root);
    path=fullfile(output_root,'candidate_config.json');write_json(path,config);
    study=struct('schema','heatdrive_ecc_storage_closure_state_qualification_v1','status','running', ...
        'source_cold_contract',contract,'candidate_root',config.output_root, ...
        'candidate_config_sha256',file_hash(path),'existing_OP_imported',false, ...
        'real_fluid_EOS_claim',false,'production_recovery_allowed',false,'outer_solve_eligible',false);
    try
        result=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(path);
        assert(result.requested_arm_collection_pass && isempty(result.error_message) && ...
            result.checkpoint_saved && result.state_restore_preflight_pass, ...
            'C2 physics/state collection failed; preserve evidence and diagnose before any continuation.');
        study.status='collected_requires_inventory_and_complete_cycle_restore_audit';
        study.candidate_execution_sha256=file_hash(fullfile(config.output_root,'cold_chamber_execution.json'));
    catch exception
        study.status='failed_requires_diagnosis';study.error_message=getReport(exception,'extended','hyperlinks','off');
        write_json(fullfile(output_root,'storage_state_execution.json'),study);rethrow(exception);
    end
    write_json(fullfile(output_root,'storage_state_execution.json'),study);
    fprintf('%s\n',jsonencode(study));
end

function write_json(path,record)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
