function audit = Audit_HeatDriveECC_StorageModelMetadata(output_root)
% Read actual mask modes and property tables without running or saving an OP.
    repo = fileparts(fileparts(mfilename('fullpath')));
    output_path = fullfile(output_root, 'storage_model_metadata.json');
    assert(~isfile(output_path), 'Do not overwrite storage metadata.');
    authority = Resolve_HeatDriveECC_SourceHeatFlowRecovery(struct( ...
        'contract_path', fullfile(repo, 'verification', 'runtime_c180_recovery_contract.json'), ...
        'recovery_use', 'inventory_diagnostic', 'verify_large_result_hash', true));
    prior = load(authority.result_path, 'options');
    prior.options.cycle_count = authority.completed_cycles + 1;
    [model, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(prior.options);
    cleanup = onCleanup(@() close_system(model, 0));
    audit = struct('schema', 'heatdrive_ecc_storage_model_metadata_v1', ...
        'source_result_sha256', authority.result_sha256, ...
        'source_checkpoint_sha256', authority.checkpoint_sha256, ...
        'simulation_run', false, 'checkpoint_saved', false, ...
        'component_modes', {{}}, 'thermal_liquid_settings', {{}});
    types = {'Pipe (TL)', 'Tank (TL)', 'Constant Volume Chamber (TL)', 'Thermal Mass'};
    names = {'dynamic_compressibility', 'inertia', 'mass_type', ...
        'p_nominal', 'p_nominal_unit', 'T_nominal', 'T_nominal_unit', 'num_ports'};
    for k = 1:numel(types)
        blocks = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
            'Type', 'Block', 'MaskType', types{k});
        for j = 1:numel(blocks)
            audit.component_modes{end + 1} = struct('block_path', blocks{j}, ...
                'mask_type', types{k}, 'parameters', read_parameters(blocks{j}, names));
        end
    end
    all_blocks = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Type', 'Block');
    for k = 1:numel(all_blocks)
        dialog = get_param(all_blocks{k}, 'DialogParameters');
        if isstruct(dialog) && all(isfield(dialog, {'rho_TLU_4', 'T_TLU', 'table_dimensions'}))
            fields = {'table_dimensions', 'T_TLU', 'T_TLU_unit', ...
                'rho_parameterization_1D', 'rho_TLU_4', 'rho_TLU_4_unit', ...
                'p_ref_4', 'p_ref_4_unit', 'beta_const_4', 'beta_const_4_unit'};
            audit.thermal_liquid_settings{end + 1} = struct( ...
                'block_path', all_blocks{k}, 'parameters', read_parameters(all_blocks{k}, fields));
        end
    end
    assert(numel(audit.component_modes) == 119 && numel(audit.thermal_liquid_settings) == 2, ...
        'Unexpected source model inventory or property-table count.');
    if ~isfolder(output_root), mkdir(output_root); end
    fid = fopen(output_path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot write storage model metadata.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(audit, 'PrettyPrint', true));
    clear file_cleanup cleanup
    fprintf('STORAGE_MODEL_METADATA_PASS=1 COMPONENTS=119 FLUID_DOMAINS=2\n');
end

function result = read_parameters(path, names)
    dialog = get_param(path, 'DialogParameters');
    result = struct();
    for k = 1:numel(names)
        if isfield(dialog, names{k})
            result.(names{k}) = get_param(path, names{k});
        end
    end
end
