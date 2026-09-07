function audit = Audit_HeatDriveECC_C200SourceRestore(source_root, authority_repo, output_root)
% Restore the unedited frozen C200 OP with the archived builder's own settings.
    assert(~isfolder(output_root), 'Do not overwrite restore evidence.');
    mkdir(output_root);
    old = pwd;
    old_path = path;
    cleanup_path = onCleanup(@() restore_environment(old, old_path));
    audit = struct('schema', 'heatdrive_ecc_c200_source_restore_v1', ...
        'source_root', source_root, 'source_commit', 'e3f1dcfa85c1cad7dd7a6d257b7eb9fb8820ef7d', ...
        'strict_restore_pass', false, 'production_recovery_allowed', false, ...
        'source_operating_point_edited', false, 'partial_restore_executed', false, ...
        'cold_start_executed', false, 'error_identifier', '', 'error_message', '');
    try
        contract_path = fullfile(authority_repo, 'verification', 'c200_mainline_freeze_contract.json');
        authority = jsondecode(fileread(contract_path));
        assert(strcmp(authority.source_code_commit, audit.source_commit), 'Unexpected C200 source.');
        result_path = fullfile(authority_repo, authority.result_relative_path);
        op_path = fullfile(authority_repo, authority.checkpoint_relative_path);
        audit.result_sha256 = file_sha256(result_path);
        audit.checkpoint_sha256 = file_sha256(op_path);
        assert(strcmp(audit.result_sha256, authority.result_sha256) && ...
            strcmp(audit.checkpoint_sha256, authority.checkpoint_sha256), 'Frozen inputs changed.');
        prior = load(result_path, 'options');
        saved = load(op_path, 'operating_point', 'checkpoint_meta');
        audit.checkpoint_meta = saved.checkpoint_meta;
        audit.snapshot_time_s = saved.operating_point.snapshotTime;
        assert(audit.snapshot_time_s == 2000 && saved.checkpoint_meta.time_s == 2000, 'Wrong C200 time.');
        audit.operating_point_properties = properties(saved.operating_point);
        audit.logged_state_class = class(saved.operating_point.loggedStates);
        addpath(source_root, '-begin');
        cd(source_root);
        builder = which('Build_HeatDriveECC_EighthRound_Simulink_Model');
        assert(strcmp(builder, fullfile(source_root, 'Build_HeatDriveECC_EighthRound_Simulink_Model.m')), ...
            'Archived builder is shadowed.');
        prior.options.model_path = fullfile(source_root, [prior.options.model_name '.slx']);
        prior.options.simulation.persist_model_configuration = false;
        audit.transport_overrides = {'model_path', 'simulation.persist_model_configuration=false'};
        audit.archived_model_sha256 = file_sha256(prior.options.model_path);
        assert(strcmpi(audit.archived_model_sha256, saved.checkpoint_meta.contract.model_file_sha256), ...
            'Archived SLX differs from the checkpoint contract.');
        audit.archived_defaults_sha256 = file_sha256(fullfile(source_root, 'Build_HeatDriveECC_EighthRound_Defaults.m'));
        audit.archived_defaults_patch = 'Only recurse into scalar structs; replace struct arrays as in the current builder.';
        [model, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(prior.options);
        cleanup_model = onCleanup(@() close_system(model, 0));
        physical_fields = {'geometry','material','branch','system','constitutive','schedule','fluid'};
        audit.physical_options_unchanged = struct();
        for k = 1:numel(physical_fields)
            field = physical_fields{k};
            equal = isequaln(options.(field), prior.options.(field));
            audit.physical_options_unchanged.(field) = equal;
            assert(equal, 'Physical options changed while reconstructing %s.', field);
        end
        audit.resolved_builder = builder;
        helpers = {'Build_HeatDriveECC_EighthRound_Defaults', 'Build_HeatDriveECC_Article_Defaults', ...
            'Integrate_HeatDriveECC_Constitutive21_Interface', 'Build_Simulink_Exchange_Params', ...
            'HeatDriveECC_ConstitutiveCompatibilityStep51', 'HeatDriveECC_EighthRound_SimulinkStep'};
        audit.resolved_helpers = struct();
        for k = 1:numel(helpers)
            resolved = which(helpers{k});
            assert(strcmp(fileparts(resolved), source_root), 'Archived helper is shadowed: %s', helpers{k});
            audit.resolved_helpers.(helpers{k}) = resolved;
        end
        keys = {'SimscapeLogType', 'SimscapeLogName', 'SimscapeLogLimitData', 'SimscapeLogDataHistory', ...
            'SaveState', 'SaveFormat', 'SaveTime', 'SaveOutput', 'SignalLogging', 'SaveFinalState', ...
            'SaveOperatingPoint', 'Solver', 'FixedStep'};
        audit.builder_settings = struct();
        for k = 1:numel(keys), audit.builder_settings.(keys{k}) = get_param(model, keys{k}); end
        assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
        input = Simulink.SimulationInput(model);
        input = input.setVariable('EIGHTH_ROUND_OPTIONS', options);
        input = input.setModelParameter('StartTime', '0', 'StopTime', '2000.001', ...
            'Solver', options.simulation.solver, 'FixedStep', num2str(options.simulation.fixed_step_s, '%.15g'), ...
            'SimulationMode', options.simulation.mode, 'ReturnWorkspaceOutputs', 'on', 'CaptureErrors', 'on', ...
            'SaveTime', 'off', 'SaveOutput', 'off', 'SignalLogging', 'off', ...
            'SaveFinalState', 'on', 'FinalStateName', 'xFinal', 'SaveOperatingPoint', 'on', ...
            'OperatingPointContentsChecksumMismatchMsg', 'error', 'OperatingPointInterfaceChecksumMismatchMsg', 'error');
        assert(options.simulation.fixed_step_s == .001, 'Unexpected frozen timestep.');
        audit.input_parameters = input.ModelParameters;
        input = input.setInitialState(saved.operating_point);
        started = tic;
        output = sim(input);
        audit.wall_time_s = toc(started);
        audit.error_message = output.ErrorMessage;
        audit.strict_restore_pass = isempty(output.ErrorMessage);
        if audit.strict_restore_pass
            audit.final_snapshot_time_s = output.xFinal.snapshotTime;
            assert(abs(audit.final_snapshot_time_s-2000.001) < 1e-10, 'Wrong restored endpoint.');
            signals = struct();
            names = output.who;
            for k = 1:numel(names)
                item = output.get(names{k});
                if isa(item, 'timeseries')
                    signals.(names{k}) = struct('time_s', item.Time, 'values', item.Data);
                end
            end
            audit.signal_count = numel(fieldnames(signals));
            save(fullfile(output_root, 'restored_step_signals.mat'), 'signals', '-v7.3');
            diagnostic_op = output.xFinal;
            production_recovery_allowed = false;
            save(fullfile(output_root, 'DO_NOT_RESUME_FOR_PRODUCTION.mat'), ...
                'diagnostic_op', 'production_recovery_allowed', '-v7.3');
        end
        clear cleanup_model
    catch exception
        audit.error_identifier = exception.identifier;
        audit.error_message = exception.message;
        audit.error_stack = exception.stack;
        audit.strict_restore_pass = false;
    end
    fid = fopen(fullfile(output_root, 'source_restore_audit.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot save restore evidence.');
    cleanup_file = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(audit, 'PrettyPrint', true));
    clear cleanup_file cleanup_path
    fprintf('C200_SOURCE_STRICT_RESTORE_PASS=%d\n', audit.strict_restore_pass);
    assert(audit.strict_restore_pass, 'HeatDriveECC:C200SourceRestoreFailed', '%s', audit.error_message);
end

function value = file_sha256(path)
    digest = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(path, 'rb');
    assert(fid >= 0, 'Cannot read protected artifact.');
    cleanup = onCleanup(@() fclose(fid));
    while ~feof(fid)
        bytes = fread(fid, 8*1024*1024, '*uint8');
        digest.update(bytes);
    end
    value = upper(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
end

function restore_environment(folder, old_path)
    cd(folder);
    path(old_path);
end
