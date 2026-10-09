function record = Run_HeatDriveECC_StableConstitutiveDiagnosticSegment(source_root, verified_root, output_root, substeps)
% Continue one intact endpoint in an isolated numerical-constitutive branch.
    assert(~isfolder(output_root) && ~isfile([output_root,'.stable_config.json']), ...
        'Never overwrite a stable constitutive diagnostic.');
    if nargin < 4, substeps = 32; end
    source_root = char(java.io.File(source_root).getCanonicalPath());
    verified_root = char(java.io.File(verified_root).getCanonicalPath());
    output_root = char(java.io.File(output_root).getCanonicalPath());
    options = struct('mode','diagnostic_resume','command_horizon_cycles',200, ...
        'restore_source_root',source_root,'restore_verification_root',verified_root);
    [op,contract] = Load_HeatDriveECC_DiagnosticResumeSource(options); %#ok<ASGLU>
    source_execution=jsondecode(fileread(fullfile(source_root,'cold_chamber_execution.json')));
    base=jsondecode(fileread([source_root,'.resumed_config.json']));
    assert(source_execution.requested_arm_collection_pass && isempty(source_execution.error_message) && ...
        source_execution.cycle_count == source_execution.stop_time_s/10 && ...
        source_execution.diagnostic_state_options.command_horizon_cycles == 200 && ...
        ~source_execution.production_recovery_allowed && ~source_execution.c200_state_imported, ...
        'Require the intact latest endpoint, never production recovery.');
    assert(substeps == round(substeps) && ismember(substeps,[32 64]), ...
        'Only stability-qualified power-of-two diagnostic substeps are permitted.');
    base.output_root=output_root;
    base.duration_s=200;
    base.cycle_count=20;
    base.diagnostic_arm='native';
    base.diagnostic_constitutive_step_function='HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic';
    base.diagnostic_constitutive_substeps=substeps;
    base.diagnostic_state_options=options;
    base.stable_constitutive_parent=struct('source_root',source_root, ...
        'source_qualification_sha256',file_hash(fullfile(verified_root,'diagnostic_resume_qualification.json')), ...
        'source_snapshot_time_s',source_execution.stop_time_s,'source_op_sha256',contract.operating_point_sha256, ...
        'source_history_sha256',contract.history_sha256,'source_state_edited',false, ...
        'operating_point_loaded_for_simulation',true,'production_recovery_allowed',false);
    path=[output_root,'.stable_config.json'];
    mkdir(fileparts(path));
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(base,'PrettyPrint',true));fclose(fid);clear cleanup
    record=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(path);
    assert(record.requested_arm_collection_pass && ~record.collection_pass && ...
        record.start_time_s==source_execution.stop_time_s && record.stop_time_s==source_execution.stop_time_s+200 && ...
        record.cycle_count==source_execution.cycle_count+20 && record.checkpoint_saved && ...
        ~record.production_recovery_allowed,'Stable diagnostic segment did not complete as scoped.');
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
