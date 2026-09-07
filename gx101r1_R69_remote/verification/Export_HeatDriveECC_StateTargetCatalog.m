function audit = Export_HeatDriveECC_StateTargetCatalog(repo, output_root)
% Inspect public initialization targets without initializing physical states.
    assert(~isfolder(output_root), 'Do not overwrite target discovery evidence.');
    mkdir(output_root);
    old_folder = pwd; old_path = path;
    cleanup_path = onCleanup(@() restore_path(old_folder, old_path));
    generation = Simulink.fileGenControl('getConfig');
    cleanup_generation = onCleanup(@() Simulink.fileGenControl('setConfig', 'config', generation));
    Simulink.fileGenControl('set', 'CacheFolder', fullfile(output_root,'build_cache'), ...
        'CodeGenFolder', fullfile(output_root,'generated_code'), 'createDir', true);
    audit = struct('schema','heatdrive_ecc_state_target_catalog_v1', ...
        'collection_pass',false,'simulation_run',false,'model_initialization_requested',false, ...
        'production_checkpoint_loaded',false,'production_recovery_allowed',false, ...
        'state_migration_verified',false,'error_identifier','','error_message','');
    try
        run_root = fullfile(repo,'outputs_storage_audit','c201_bounded_20260907','nominal_s01');
        record = jsondecode(fileread(fullfile(run_root,'cycle_observation_audit.json')));
        restored = jsondecode(fileread(fullfile(run_root,'source_restore_audit.json')));
        options_path = fullfile(run_root,'diagnostic_options.mat');
        assert(strcmp(file_sha256(options_path),record.artifact_sha256.options), 'Options changed.');
        assert(restored.strict_restore_pass && isempty(restored.error_message), 'Unverified source.');
        saved = load(options_path,'options');
        source = fullfile(repo,'outputs_storage_audit','c200_source_compatibility_20260907','source','gx101r1_R69_remote');
        addpath(repo,'-end'); addpath(source,'-begin'); cd(source);
        assert(strcmp(which('Build_HeatDriveECC_EighthRound_Simulink_Model'), ...
            fullfile(source,'Build_HeatDriveECC_EighthRound_Simulink_Model.m')), 'Wrong builder.');
        assert(strcmp(file_sha256(saved.options.model_path),restored.archived_model_sha256), 'SLX changed.');
        [model, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(saved.options);
        cleanup_model = onCleanup(@() close_system(model,0));
        fields = {'geometry','material','system','branch','constitutive','fluid','schedule','simulation'};
        for k = 1:numel(fields)
            assert(isequaln(options.(fields{k}),saved.options.(fields{k})), 'Changed options: %s',fields{k});
        end
        % R2025b Prestart updates the model, but does not initialize or simulate it.
        targets = simscape.op.create(model,'Prestart');
        catalog = walk(targets,'');
        assert(~isempty(catalog), 'No public targets discovered.');
        target_table = simscape.op.targetTable(targets);
        save(fullfile(output_root,'public_targets.mat'),'targets','target_table','-v7.3');
        audit.matlab_release = version('-release');
        audit.extraction_phase = 'Prestart';
        audit.options_sha256 = record.artifact_sha256.options;
        audit.archived_model_sha256 = restored.archived_model_sha256;
        audit.source_checkpoint_sha256 = restored.checkpoint_sha256;
        audit.source_code_commit = restored.source_commit;
        audit.public_create_api_path = which('simscape.op.create');
        audit.public_create_api_sha256 = file_sha256(audit.public_create_api_path);
        audit.root_identifier = targets.Identifier;
        audit.has_private_data = hasPrivateData(targets);
        audit.table_variable_names = target_table.Properties.VariableNames;
        audit.target_count = numel(catalog);
        audit.targets = catalog;
        audit.public_targets_sha256 = file_sha256(fullfile(output_root,'public_targets.mat'));
        audit.scope = 'Model-declared targets only, not C200 values or hidden solver execution state.';
        audit.collection_pass = true;
        clear cleanup_model
    catch ME
        audit.error_identifier = ME.identifier;
        audit.error_message = ME.message;
        write_json(fullfile(output_root,'target_catalog.json'),audit);
        rethrow(ME);
    end
    write_json(fullfile(output_root,'target_catalog.json'),audit);
    clear cleanup_generation cleanup_path
    fprintf('STATE_TARGET_CATALOG_PASS=1 TARGETS=%d\n',audit.target_count);
end

function rows = walk(node, prefix)
    rows = {};
    for k = 1:numel(node.ChildIds)
        key = node.ChildIds{k}; child = node.Children{k};
        if isempty(prefix), location = key; else, location = [prefix '/' key]; end
        if isa(child,'simscape.op.Target')
            units = unit(child.Value);
            numeric = value(child.Value,units);
            assert(all(isfinite(numeric),'all'), 'Nonfinite declared target: %s',location);
            rows{end+1} = struct('path',location,'unit',char(units),'value',numeric, ...
                'priority',char(child.Priority),'description',char(child.Description)); %#ok<AGROW>
        elseif isa(child,'simscape.op.OperatingPoint')
            rows = [rows walk(child,location)]; %#ok<AGROW>
        else
            error('HeatDriveECC:UnknownTargetClass','Unsupported public child type: %s',class(child));
        end
    end
end

function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8'); assert(fid>=0,'Cannot write metadata.');
    cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function result=file_sha256(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(path,'rb'); assert(fid>=0,'Cannot read source.');
    cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid), digest.update(fread(fid,8*1024*1024,'*uint8')); end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

function restore_path(folder,old_path)
    cd(folder); path(old_path);
end
