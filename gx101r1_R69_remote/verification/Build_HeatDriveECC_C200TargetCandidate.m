function audit = Build_HeatDriveECC_C200TargetCandidate(mapping_path, output_root)
% Materialize a public target candidate; this is NOT a model operating point.
    assert(~isfolder(output_root), 'Do not overwrite target candidate evidence.');
    data = jsondecode(fileread(mapping_path));
    assert(strcmp(data.schema,'heatdrive_ecc_state_target_mapping_v1') && ...
        data.computation_complete && data.source_time_s==2000 && ...
        ~data.production_recovery_allowed && ~data.structural_migration_verified && ...
        ~data.opaque_solver_mapping_attempted, 'Unexpected target mapping contract.');
    rows = data.initialization_candidates;
    assert(numel(rows)==125 && numel(unique(string({rows.path})))==125, 'Incomplete target identities.');
    candidate = simscape.op.OperatingPoint;
    for k=1:numel(rows)
        row=rows(k);
        assert(isscalar(row.c200_value) && isfinite(row.c200_value) && ...
            row.sample_time_s==2000 && any(strcmp(row.priority,{'High','Low'})), 'Invalid target.');
        candidate=set(candidate,row.path,simscape.op.Target(row.c200_value,row.unit,row.priority));
    end
    assert(~hasPrivateData(candidate), 'Candidate must not copy cached default/private data.');
    mkdir(output_root);
    production_recovery_allowed=false;
    model_initialization_executed=false;
    save(fullfile(output_root,'DO_NOT_RESUME_TARGET_CANDIDATE.mat'), ...
        'candidate','production_recovery_allowed','model_initialization_executed','-v7.3');
    loaded=load(fullfile(output_root,'DO_NOT_RESUME_TARGET_CANDIDATE.mat'),'candidate');
    tab=simscape.op.targetTable(loaded.candidate);
    assert(height(tab)==125 && ~hasPrivateData(loaded.candidate), 'Target serialization changed coverage.');
    for k=1:numel(rows)
        row=rows(k); actual=get(loaded.candidate,row.path);
        assert(isequal(value(actual.Value,row.unit),row.c200_value) && ...
            strcmp(char(actual.Priority),row.priority), 'Target round trip changed: %s',row.path);
    end
    audit=struct('schema','heatdrive_ecc_c200_target_candidate_v1','serialization_pass',true, ...
        'target_count',125,'high_priority_count',sum(strcmp({rows.priority},'High')), ...
        'low_priority_count',sum(strcmp({rows.priority},'Low')), ...
        'contains_private_data',hasPrivateData(candidate),'model_initialized',false, ...
        'simulation_run',false,'state_preservation_verified',false, ...
        'production_recovery_allowed',false,'mapping_path',mapping_path, ...
        'mapping_sha256',file_sha256(mapping_path), ...
        'candidate_sha256',file_sha256(fullfile(output_root,'DO_NOT_RESUME_TARGET_CANDIDATE.mat')), ...
        'scope','Public target serialization only; not unchanged-model initialization or structural migration.');
    fid=fopen(fullfile(output_root,'target_candidate_audit.json'),'w','n','UTF-8');
    assert(fid>=0,'Cannot write audit.'); cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('C200_TARGET_SERIALIZATION_PASS=1\n%s\n',jsonencode(audit));
end

function result=file_sha256(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(path,'rb'); assert(fid>=0,'Cannot read source.');
    cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid), digest.update(fread(fid,8*1024*1024,'*uint8')); end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
