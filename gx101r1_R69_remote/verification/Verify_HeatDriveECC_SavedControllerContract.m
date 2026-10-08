function record = Verify_HeatDriveECC_SavedControllerContract(source_root, output_root)
% Rebuild without simulation; prove only the audit expression changed since producer.
    assert(~isfolder(output_root), 'Never overwrite controller contract evidence.');
    execution = jsondecode(fileread(fullfile(source_root, 'cold_chamber_execution.json')));
    producer = execution.execution_commit;
    assert(~isempty(regexp(producer, '^[0-9a-f]{40}$', 'once')), 'Require exact producer.');
    [status, historical] = system(sprintf('git show %s:gx101r1_R69_remote/Build_HeatDriveECC_EighthRound_Simulink_Model.m', producer));
    assert(status == 0, 'Missing historical model builder.');
    historical = strrep(historical, sprintf('\r\n'), newline);
    current = strrep(fileread(which('Build_HeatDriveECC_EighthRound_Simulink_Model')), sprintf('\r\n'), newline);
    added = sprintf(['    se_stage2_i_output_enable = ...\n' ...
        '        [model_name ''/SEStage2PressureIOutputEnableFromWorkspace''];\n' ...
        '    se_stage4_i_output_enable = ...\n' ...
        '        [model_name ''/SEStage4PressureIOutputEnableFromWorkspace''];\n']);
    current = strrep(current, added, '');
    for stage = [2 4]
        corrected = sprintf('blocks_directly_connected(se_stage%d_i_output_enable, ...\n                se_stage%d_i_output_gate)', stage, stage);
        legacy = sprintf('blocks_directly_connected(se_stage%d_i_enable, ...\n                se_stage%d_i_output_gate)', stage, stage);
        current = strrep(current, corrected, legacy);
    end
    assert(strcmp(strtrim(current), strtrim(historical)), ...
        'Changes beyond the two documented audit-source expressions are not qualified.');
    unchanged = {'Integrate_HeatDriveECC_Constitutive21_Interface.m', ...
        'Build_HeatDriveECC_EighthRound_Defaults.m', 'heatdrive_ecc_coupled_se21.slx', ...
        'verification/Configure_HeatDriveECC_DistributedPressureFeedforward.m'};
    for k = 1:numel(unchanged)
        [status, ~] = system(sprintf('git diff --quiet %s HEAD -- "gx101r1_R69_remote/%s"', producer, unchanged{k}));
        assert(status == 0, 'Physical model/control source changed since observed run.');
    end
    configured = load(fullfile(source_root, 'native', 'configuration.mat'), 'options');
    original = configured.options;
    assert(~original.simulation.persist_model_configuration && ...
        original.branch.se_distributed_pressure_feedforward_diagnostic, 'Invalid diagnostic scope.');
    old_path = path;
    cleanup_path = onCleanup(@() path(old_path));
    addpath(fullfile(source_root, 'component_build'), fullfile(source_root, 'buffer_component_build'));
    library = original.branch.independent_conservative_chamber_library;
    library_file = fullfile(source_root, 'component_build', [library '.slx']);
    assert(strcmp(file_hash(library_file), execution.chamber_library_sha256), ...
        'Diagnostic component library differs from the observed producer.');
    load_system(library_file);
    cleanup_library = onCleanup(@() close_system(library, 0));
    [model, refreshed] = Build_HeatDriveECC_EighthRound_Simulink_Model(original);
    cleanup_model = onCleanup(@() close_system(model, 0));
    before = Audit_HeatDriveECC_RouteMemoryContract(model);
    distributed = Configure_HeatDriveECC_DistributedPressureFeedforward(model, refreshed);
    after = Audit_HeatDriveECC_RouteMemoryContract(model);
    assert(before.pass && after.pass && isequaln(before, after), ...
        'Actual independent route update/output wiring was not verified.');
    old_audit = original.validation.article_component_pipe_UA_audit;
    new_audit = refreshed.validation.article_component_pipe_UA_audit;
    names = fieldnames(old_audit);
    for k = 1:numel(names)
        if ismember(names{k}, {'pressure','ok'}), continue; end
        assert(isequaln(old_audit.(names{k}), new_audit.(names{k})), ...
            'Non-controller component audit changed: %s', names{k});
    end
    old_pressure = old_audit.pressure; new_pressure = new_audit.pressure;
    names = fieldnames(old_pressure);
    for k = 1:numel(names)
        if ismember(names{k}, {'independent_controller_limits','ok'}), continue; end
        assert(isequaln(old_pressure.(names{k}), new_pressure.(names{k})), ...
            'Physical pressure audit changed: %s', names{k});
    end
    record = struct('schema', 'heatdrive_ecc_saved_controller_contract_verification_v1', ...
        'source_root', source_root, 'source_producer', producer, ...
        'audit_expression_only_change_verified', true, 'source_model_control_unchanged', true, ...
        'route_memory_before_distributed', before, 'route_memory_after_distributed', after, ...
        'physical_audit_sections_unchanged', true, ...
        'original_article_audit', old_audit, 'corrected_article_audit', new_audit, ...
        'distributed_formula', distributed.formula, 'simulation_executed', false, ...
        'operating_point_loaded', false, 'production_recovery_allowed', false);
    mkdir(output_root);
    fid = fopen(fullfile(output_root, 'controller_contract_verification.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot save verified controller audit.');
    cleanup_file = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('%s\n', jsonencode(struct('actual_route_memory_pass', after.pass, ...
        'corrected_article_audit_pass', new_audit.ok, 'simulation_executed', false)));
end

function result = file_hash(file)
    digest = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(file, 'rb'); assert(fid >= 0, 'Missing diagnostic component library.');
    cleanup = onCleanup(@() fclose(fid));
    while ~feof(fid), digest.update(fread(fid, 8*1024*1024, '*uint8')); end
    result = upper(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
end
