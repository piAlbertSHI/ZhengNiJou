function study=Run_HeatDriveECC_BufferColdFactorialStudy(template_path,component_audit_path,repo,output_root)
% Four independent cold trajectories; no failed or previous endpoint is propagated.
    assert(~isfolder(output_root),'Never duplicate a factorial study.');
    workspace=fileparts(repo);
    [code,dirty]=system(sprintf('git -C "%s" status --porcelain',workspace));
    assert(code==0 && isempty(strtrim(dirty)),'Use a clean managed checkout.');
    tests=Test_HeatDriveECC_BufferColdFactorial(component_audit_path);
    base=jsondecode(fileread(template_path));
    assert(base.stage2_kp==-126 && base.stage4_kp==-225 && base.stage4_ki==-255 && ...
        strcmp(base.diagnostic_inventory_options.storage_closure,'pressure_only_density') && ...
        strcmp(base.diagnostic_se_reference_options.mode,'coherent_envelope'), ...
        'Wrong baseline physical/control recipe.');
    base.repo_root=repo;base.cycle_count=1;base.duration_s=10;base.diagnostic_arm='native';
    base.diagnostic_state_options=struct('mode','off','command_horizon_cycles',1);
    base.diagnostic_inventory_options=struct('storage_closure','pressure_only_density');
    base.diagnostic_se_reference_options=struct('mode','coherent_envelope');
    assert(~isfield(base,'diagnostic_buffer_factor_options'),'Template must not contain an old intervention.');
    mkdir(output_root);
    pointer=jsondecode(fileread(fullfile(repo,'verification','current_storage_warmup_contract.json')));
    op=fullfile(pointer.execution_repo,pointer.source_root_relative,pointer.operating_point_relative);
    history=fullfile(pointer.execution_repo,pointer.source_root_relative,pointer.history_relative);
    assert(strcmp(file_hash(op),pointer.operating_point_sha256) && strcmp(file_hash(history),pointer.history_sha256), ...
        'Current complete point changed before cold diagnostics.');
    study=struct('schema','heatdrive_ecc_cold_buffer_factorial_study_v1','tests',tests, ...
        'template_path',template_path,'template_sha256',file_hash(template_path), ...
        'component_audit_path',component_audit_path,'component_audit_sha256',file_hash(component_audit_path), ...
        'cold_initialization_source',base.initial_observation_root, ...
        'cold_initial_observation_sha256',file_hash(fullfile(base.initial_observation_root,'native','observations.mat')), ...
        'coupled_start_time_s',0,'coupled_stop_time_s',10,'command_horizon_cycles',1, ...
        'C200_state_loaded',false,'C62_state_loaded',false,'source_state_edited',false, ...
        'cases',{{}},'collection_pass',false,'production_recovery_allowed',false,'outer_solve_eligible',false);
    levels={'baseline_legacy','inherited','inherited';'baseline_tight','inherited','local_tight'; ...
        'sma_pipe_legacy','sma_pipe_matched','inherited';'sma_pipe_tight','sma_pipe_matched','local_tight'};
    try
        for k=1:4
            config=base;config.output_root=fullfile(output_root,levels{k,1});
            config.diagnostic_buffer_factor_options=struct('geometry',levels{k,2},'precision',levels{k,3}, ...
                'component_audit_path',component_audit_path);
            path=fullfile(output_root,[levels{k,1},'_config.json']);write_json(path,config);
            record=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(path);
            assert(record.requested_arm_collection_pass && isempty(record.error_message) && ...
                ~record.checkpoint_saved && ~record.c200_state_imported && ...
                record.start_time_s==0 && record.stop_time_s==10 && numel(record.bounded_cold_mechanism_cases)==1, ...
                'Incomplete cold point; diagnose before another execution.');
            study.cases{end+1}=struct('name',levels{k,1},'geometry',levels{k,2},'precision',levels{k,3}, ...
                'source_root',config.output_root,'config_path',path,'config_sha256',file_hash(path), ...
                'execution_sha256',file_hash(fullfile(config.output_root,'cold_chamber_execution.json')), ...
                'mechanism_pass',record.bounded_cold_mechanism_cases{1}.mechanism_pass, ...
                'failed_state_used',false,'production_recovery_allowed',false);
            write_json(fullfile(output_root,'factorial_progress.json'),study);
            for library={'ecc_inventory_pressure_only_lib','ecc_buffer_coupled_offset_lib'}
                if bdIsLoaded(library{1})
                    location=get_param(library{1},'FileName');
                    assert(startsWith(location,output_root),'Refuse to close a foreign component library.');
                    close_system(library{1},0);
                end
            end
        end
        study.collection_pass=numel(study.cases)==4;
        assert(strcmp(file_hash(op),pointer.operating_point_sha256) && strcmp(file_hash(history),pointer.history_sha256), ...
            'Cold experiments modified C62 state.');
        study.C62_state_hashes_unchanged=true;
    catch exception
        study.error_message=getReport(exception,'extended','hyperlinks','off');
        write_json(fullfile(output_root,'factorial_execution.json'),study);rethrow(exception);
    end
    write_json(fullfile(output_root,'factorial_execution.json'),study);
    fprintf('FINAL_JSON=%s\n',jsonencode(study));
end

function write_json(path,data)
    assert(~isfile(path) || endsWith(path,'factorial_progress.json'),'Never overwrite a scientific result.');
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(data,'PrettyPrint',true));
end
function result=file_hash(file)
    md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),md.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
