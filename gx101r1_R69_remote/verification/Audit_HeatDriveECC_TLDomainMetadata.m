function audit = Audit_HeatDriveECC_TLDomainMetadata(output_root)
% Build/read the approved diagnostic source; no sim or OP save is performed.
    repo = fileparts(fileparts(mfilename('fullpath')));
    output_path = fullfile(output_root, 'tl_domain_metadata.json');
    assert(~isfile(output_path), 'Do not overwrite topology evidence.');
    authority = Resolve_HeatDriveECC_SourceHeatFlowRecovery(struct( ...
        'contract_path', fullfile(repo, 'verification', 'runtime_c180_recovery_contract.json'), ...
        'recovery_use', 'inventory_diagnostic', 'verify_large_result_hash', true));
    prior = load(authority.result_path, 'options');
    prior.options.cycle_count = authority.completed_cycles + 1;
    [model, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(prior.options);
    cleanup = onCleanup(@() close_system(model, 0));
    audit = Export_HeatDriveECC_TLConnectivity(model);
    audit.source_result_sha256 = authority.result_sha256;
    audit.source_checkpoint_sha256 = authority.checkpoint_sha256;
    audit.simulation_run = false;
    audit.checkpoint_saved = false;
    audit.settings_tables = {};
    for k = 1:numel(audit.blocks)
        block = audit.blocks{k};
        if ~strcmp(block.source_file, 'foundation.thermal_liquid.utilities.thermal_liquid_settings')
            continue;
        end
        path = block.block_path;
        names = {'table_dimensions', 'T_TLU', 'T_TLU_unit', ...
            'T_min_1D', 'T_max_1D', 'p_min_1D', 'p_max_1D', 'p_min_1D_unit', 'p_max_1D_unit', ...
            'rho_parameterization_1D', 'rho_TLU_4', 'rho_TLU_4_unit', ...
            'beta_const_4', 'beta_const_4_unit', 'p_ref_4', 'p_ref_4_unit'};
        parameters = struct();
        for j = 1:numel(names), parameters.(names{j}) = get_param(path, names{j}); end
        audit.settings_tables{end + 1} = struct('block_path', path, 'parameters', parameters);
    end
    audit.metadata_collection_pass = numel(audit.settings_tables) == 2;
    if ~isfolder(output_root), mkdir(output_root); end
    fid = fopen(output_path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot write topology metadata.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(audit, 'PrettyPrint', true));
    clear file_cleanup cleanup
    assert(audit.metadata_collection_pass, ...
        'Expected two TL property-setting domains; found %d. Partial metadata saved.', ...
        numel(audit.settings_tables));
    fprintf('TL_DOMAIN_METADATA_EXPORTED=1 BLOCKS=%d PORTS=%d\n', ...
        numel(audit.blocks), numel(audit.vertices));
end
