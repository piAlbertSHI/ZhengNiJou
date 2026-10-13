function study = Run_HeatDriveECC_SEReferenceStateQualification(baseline_config_path, audit_path, output_root)
% Both new cold chains capture complete points under an unchanged 200-cycle horizon.
    baseline_config_path=char(java.io.File(baseline_config_path).getCanonicalPath());
    audit_path=char(java.io.File(audit_path).getCanonicalPath());
    output_root=char(java.io.File(output_root).getCanonicalPath());
    assert(~isfolder(output_root),'Never overwrite state-qualification evidence.');
    audit=jsondecode(fileread(audit_path));
    assert(audit.two_cycle_cold_followup_allowed && ~audit.production_recovery_allowed, ...
        'Require passed single-cycle physical/reference comparison.');
    config=jsondecode(fileread(baseline_config_path));
    assert(config.diagnostic_inventory_options.volume_factor==1,'Restore nominal geometry.');
    config=rmfield(config,'diagnostic_inventory_options');
    config.cycle_count=2;config.duration_s=20;
    config.diagnostic_state_options=struct('mode','restore_preflight','command_horizon_cycles',200);
    names={'baseline','coherent'};
    study=struct('schema','heatdrive_ecc_se_reference_state_qualification_v1','status','running', ...
        'source_cold_audit_sha256',file_hash(audit_path),'case_roots',{{}},'cases',{{}}, ...
        'existing_OP_imported',false,'production_recovery_allowed',false,'outer_solve_eligible',false);
    mkdir(output_root);
    try
        for k=1:2
            current=config;current.output_root=fullfile(output_root,names{k});
            if k==2
                current.diagnostic_se_reference_options=struct('mode','coherent_envelope', ...
                    'cold_followup_audit_path',audit_path);
            end
            path=fullfile(output_root,[names{k},'_config.json']);write_json(path,current);
            result=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(path);
            assert(result.requested_arm_collection_pass && isempty(result.error_message) && ...
                result.checkpoint_saved && result.state_restore_preflight_pass, ...
                'Two-cycle collection or complete state roundtrip failed; diagnose before continuation.');
            study.case_roots{end+1}=current.output_root;
            study.cases{end+1}=struct('name',names{k},'checkpoint_saved',result.checkpoint_saved, ...
                'state_roundtrip_pass',result.state_restore_preflight_pass, ...
                'execution_sha256',file_hash(fullfile(current.output_root,'cold_chamber_execution.json')));
            write_json(fullfile(output_root,'state_qualification_execution.json'),study);
        end
        study.status='collected_requires_physical_and_complete_cycle_restore_audit';
    catch exception
        study.status='failed_requires_diagnosis';study.error_message=getReport(exception,'extended','hyperlinks','off');
        write_json(fullfile(output_root,'state_qualification_execution.json'),study);rethrow(exception);
    end
    write_json(fullfile(output_root,'state_qualification_execution.json'),study);
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
