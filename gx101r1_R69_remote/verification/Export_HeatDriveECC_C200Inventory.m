function metadata = Export_HeatDriveECC_C200Inventory(repo, output_root)
% Build-only inventory of the exact archival model used by the C201 diagnosis.
    assert(~isfolder(output_root), 'Do not overwrite inventory evidence.');
    mkdir(output_root);
    original_folder = pwd; original_path = path;
    cleanup_path = onCleanup(@() restore_path(original_folder, original_path));
    old_generation = Simulink.fileGenControl('getConfig');
    cleanup_generation = onCleanup(@() Simulink.fileGenControl('setConfig', 'config', old_generation));
    Simulink.fileGenControl('set', 'CacheFolder', fullfile(output_root,'build_cache'), ...
        'CodeGenFolder', fullfile(output_root,'generated_code'), 'createDir', true);
    run_root = fullfile(repo, 'outputs_storage_audit', 'c201_bounded_20260907', 'nominal_s01');
    record = jsondecode(fileread(fullfile(run_root, 'cycle_observation_audit.json')));
    options_path = fullfile(run_root, 'diagnostic_options.mat');
    assert(strcmp(file_sha256(options_path), record.artifact_sha256.options), 'C201 options changed.');
    restored = jsondecode(fileread(fullfile(run_root, 'source_restore_audit.json')));
    assert(restored.strict_restore_pass && isempty(restored.error_message), 'C201 producer failed.');
    saved = load(options_path, 'options');
    source = fullfile(repo, 'outputs_storage_audit', 'c200_source_compatibility_20260907', 'source', 'gx101r1_R69_remote');
    addpath(repo, '-end'); addpath(source, '-begin'); cd(source);
    assert(strcmp(which('Build_HeatDriveECC_EighthRound_Simulink_Model'), ...
        fullfile(source,'Build_HeatDriveECC_EighthRound_Simulink_Model.m')), 'Wrong builder.');
    assert(strcmp(file_sha256(saved.options.model_path), restored.archived_model_sha256), 'Archived SLX changed.');
    [model, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(saved.options);
    cleanup_model = onCleanup(@() close_system(model,0));
    fields = {'geometry','material','system','branch','constitutive','fluid','schedule','simulation'};
    for k = 1:numel(fields)
        assert(isequaln(options.(fields{k}), saved.options.(fields{k})), 'Inventory options differ: %s', fields{k});
    end
    metadata = struct('schema','heatdrive_ecc_c200_inventory_metadata_v1', ...
        'simulation_run',false,'checkpoint_saved',false,'production_recovery_allowed',false, ...
        'source_code_commit',restored.source_commit,'source_result_sha256',restored.result_sha256, ...
        'source_checkpoint_sha256',restored.checkpoint_sha256,'options_sha256',record.artifact_sha256.options, ...
        'archived_model_sha256',restored.archived_model_sha256, 'matlab_release', version('-release'), ...
        'storage_blocks',{{}},'settings_tables',{{}});
    types = {'Pipe (TL)','Tank (TL)','Constant Volume Chamber (TL)','Thermal Mass'};
    mode_names = {'dynamic_compressibility','inertia','mass_type','p_nominal','p_nominal_unit', ...
        'T_nominal','T_nominal_unit','num_ports'};
    parameter_names = {'area','length','volume','mass','sp_heat'};
    for kind = 1:numel(types)
        blocks = find_system(model,'LookUnderMasks','all','FollowLinks','on', ...
            'Type','Block','MaskType',types{kind});
        for k = 1:numel(blocks)
            block_path = blocks{k}; dialog = get_param(block_path,'DialogParameters');
            row = struct('block_path',block_path,'mask_type',types{kind}, ...
                'reference_block',get_param(block_path,'ReferenceBlock'),'model_modes',struct(),'mask_parameters',struct());
            for j = 1:numel(mode_names)
                name = mode_names{j};
                if isfield(dialog,name), row.model_modes.(name)=get_param(block_path,name); end
            end
            for j = 1:numel(parameter_names)
                name = parameter_names{j};
                if isfield(dialog,name)
                    expression = get_param(block_path,name);
                    row.mask_parameters.(name) = struct('expression',expression, ...
                        'value',slResolve(expression,block_path),'unit',get_param(block_path,[name '_unit']));
                end
            end
            metadata.storage_blocks{end+1}=row;
        end
    end
    topology = Export_HeatDriveECC_TLConnectivity(model);
    names = {'table_dimensions','T_TLU','T_TLU_unit','T_min_1D','T_max_1D', ...
        'p_min_1D','p_max_1D','p_min_1D_unit','p_max_1D_unit', ...
        'rho_parameterization_1D','rho_TLU_4','rho_TLU_4_unit','beta_const_4','beta_const_4_unit', ...
        'p_ref_4','p_ref_4_unit','u_parameterization_1D','u_TLU_4','u_TLU_4_unit','cp_TLU_5','cp_TLU_5_unit'};
    for k = 1:numel(topology.blocks)
        block = topology.blocks{k};
        if strcmp(block.source_file,'foundation.thermal_liquid.utilities.thermal_liquid_settings')
            row = struct('block_path',block.block_path,'parameters',struct());
            for j = 1:numel(names), row.parameters.(names{j})=get_param(block.block_path,names{j}); end
            metadata.settings_tables{end+1}=row;
        end
    end
    assert(numel(metadata.storage_blocks)==119 && numel(metadata.settings_tables)==2, 'Incomplete inventory metadata.');
    metadata.collection_pass = true;
    write_json(fullfile(output_root,'inventory_metadata.json'),metadata);
    write_json(fullfile(output_root,'tl_connectivity.json'),topology);
    thermal = Export_HeatDriveECC_TLConnectivity(model,'foundation.thermal.thermal');
    write_json(fullfile(output_root,'thermal_connectivity.json'),thermal);
    clear cleanup_model cleanup_generation cleanup_path
    fprintf('C200_ARCHIVAL_INVENTORY_EXPORT_PASS=1 COMPONENTS=119\n');
end

function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8'); assert(fid>=0,'Cannot write metadata.');
    cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function value=file_sha256(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(path,'rb'); assert(fid>=0,'Cannot read source.');
    cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid), digest.update(fread(fid,8*1024*1024,'*uint8')); end
    value=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

function restore_path(folder,old_path)
    cd(folder); path(old_path);
end
