function study = Run_HeatDriveECC_SEReferenceDiagnostic(baseline_config_path, output_root)
    baseline_config_path=char(java.io.File(baseline_config_path).getCanonicalPath());
    output_root=char(java.io.File(output_root).getCanonicalPath());
    assert(~isfolder(output_root),'Never overwrite reference-diagnostic evidence.');
    config=jsondecode(fileread(baseline_config_path));
    baseline_root=config.output_root;
    baseline=jsondecode(fileread(fullfile(baseline_root,'cold_chamber_execution.json')));
    assert(baseline.requested_arm_collection_pass && isempty(baseline.error_message) && ...
        baseline.start_time_s==0 && baseline.stop_time_s==10 && ~baseline.checkpoint_saved && ...
        ~baseline.production_recovery_allowed && ~baseline.c200_state_imported && ...
        strcmp(file_hash(fullfile(baseline_root,'native','observations.mat')),baseline.cases(1).observation_sha256) && ...
        strcmp(config.diagnostic_state_options.mode,'off') && config.cycle_count==1 && ...
        config.distributed_pressure_feedforward_diagnostic && config.diagnostic_inventory_options.volume_factor==1, ...
        'Only the completed unchanged-volume cold baseline can be reused.');
    mkdir(output_root);
    config.output_root=fullfile(output_root,'candidate');
    config.diagnostic_se_reference_options=struct('mode','coherent_envelope');
    path=fullfile(output_root,'candidate_config.json');
    write_json(path,config);
    study=struct('schema','heatdrive_ecc_se_reference_counterfactual_v1','status','running', ...
        'baseline_root',baseline_root,'baseline_execution_sha256',file_hash(fullfile(baseline_root,'cold_chamber_execution.json')), ...
        'baseline_configuration_sha256',file_hash(baseline_config_path),'baseline_reused',true, ...
        'candidate_root',config.output_root,'candidate_config_sha256',file_hash(path), ...
        'geometry_changed',false,'PI_gains_changed',false,'c200_state_imported',false, ...
        'source_state_loaded',false,'production_recovery_allowed',false,'outer_solve_eligible',false);
    try
        result=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(path);
        assert(result.requested_arm_collection_pass && isempty(result.error_message),'Candidate collection failed.');
        study.status='collected_requires_physical_comparison';
        study.candidate_execution_sha256=file_hash(fullfile(config.output_root,'cold_chamber_execution.json'));
    catch exception
        study.status='failed_requires_diagnosis';study.error_message=getReport(exception,'extended','hyperlinks','off');
        write_json(fullfile(output_root,'reference_execution.json'),study);rethrow(exception);
    end
    write_json(fullfile(output_root,'reference_execution.json'),study);
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
