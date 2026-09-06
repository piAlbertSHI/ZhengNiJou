function audit = Audit_HeatDriveECC_SegmentedInventoryRestore(output_root)
% Compare within-cycle and cycle-boundary strict disk OP continuation.
% All generated OPs are restricted to this experiment, never production sources.
    repo = fileparts(fileparts(mfilename('fullpath')));
    json_path = fullfile(output_root, 'segmented_inventory_restore.json');
    assert(~isfile(json_path) && ~isfile(fullfile(output_root, 'case_1_traces.mat')), ...
        'Do not overwrite diagnostic evidence.');
    if ~isfolder(output_root), mkdir(output_root); end
    audit = struct('schema', 'heatdrive_ecc_segmented_inventory_restore_v1', ...
        'absolute_tolerance', 1e-12, 'relative_tolerance', 1e-11, ...
        'cases', {{}}, 'collection_pass', false, 'segmentation_equivalence_pass', false, ...
        'production_recovery_allowed', false, 'full_internal_periodicity_verified', false, ...
        'equation_matched_cycle_closure_verified', false, 'error_identifier', '', 'error_message', '');
    try
        authority = Resolve_HeatDriveECC_SourceHeatFlowRecovery(struct( ...
            'contract_path', fullfile(repo, 'verification', 'runtime_c180_recovery_contract.json'), ...
            'recovery_use', 'inventory_diagnostic', 'verify_large_result_hash', true));
        audit.source_result_sha256 = authority.result_sha256;
        audit.source_checkpoint_sha256 = authority.checkpoint_sha256;
        checkpoint = load(authority.checkpoint_path, 'operating_point', 'checkpoint_meta');
        prior = load(authority.result_path, 'options');
        prior.options.cycle_count = authority.completed_cycles + 2;
        [model, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(prior.options);
        cleanup = onCleanup(@() close_system(model, 0));
        assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
        dt = options.simulation.fixed_step_s;
        tau = options.schedule.tau_cycle_s;
        t0 = checkpoint.checkpoint_meta.time_s;
        audit.source_time_s = t0;
        audit.fixed_step_s = dt;
        audit.cycle_period_s = tau;
        input = Simulink.SimulationInput(model);
        input = input.setModelParameter('StartTime', '0', ...
            'Solver', options.simulation.solver, 'FixedStep', num2str(dt, '%.15g'), ...
            'SimulationMode', options.simulation.mode, 'ReturnWorkspaceOutputs', 'on', ...
            'CaptureErrors', 'on', 'SaveTime', 'off', 'SaveOutput', 'off', 'SignalLogging', 'off', ...
            'SimscapeLogLimitData', 'on', 'SimscapeLogDataHistory', ceil(tau / dt) + 2, ...
            'SaveState', 'on', 'StateSaveName', 'internal_state_log', ...
            'SaveFinalState', 'on', 'FinalStateName', 'xFinal', 'SaveOperatingPoint', 'on', ...
            'OperatingPointContentsChecksumMismatchMsg', 'error', ...
            'OperatingPointInterfaceChecksumMismatchMsg', 'error');
        input = input.setVariable('EIGHTH_ROUND_OPTIONS', options);
        audit.simscape_history_points = ceil(tau / dt) + 2;
        source = checkpoint.operating_point;
        for case_index = 1:2
            start = t0;
            kind = 'within_cycle';
            if case_index == 2
                start = t0 + tau - 3 * dt;
                seed = run_strict(input, source, start);
                seed_native = Extract_HeatDriveECC_NativeStorageTraces(seed.get('simlog'), model, true);
                seed_observed = Extract_HeatDriveECC_ObservedStates(seed.internal_state_log, tau, 1);
                audit.boundary_seed_native_trace_count = numel(seed_native);
                audit.boundary_seed_numeric_state_groups = seed_observed.logged_state_group_count;
                audit.boundary_seed_generated_without_state_edits = true;
                source = seed.xFinal;
                clear seed seed_native seed_observed
                kind = 'cycle_boundary';
            end
            middle = start + 3 * dt;
            finish = start + 6 * dt;
            record = struct('kind', kind, 'start_s', start, 'split_s', middle, 'end_s', finish, ...
                'strict_reference_pass', false, 'strict_prefix_pass', false, 'strict_suffix_pass', false, ...
                'prefix_match_pass', false, 'suffix_match_pass', false, 'pass', false, ...
                'diagnostic_op_production_recovery_allowed', false, 'error_message', '');
            reference = struct(); prefix = struct(); suffix = struct();
            try
                output = run_strict(input, source, finish);
                reference = extract(output, model, tau, start, finish, dt);
                record.strict_reference_pass = true;
                clear output
                output = run_strict(input, source, middle);
                prefix = extract(output, model, tau, start, middle, dt);
                record.strict_prefix_pass = true;
                record.prefix_observed = Compare_HeatDriveECC_DiagnosticTraces(reference.observed, prefix.observed);
                record.prefix_native = Compare_HeatDriveECC_DiagnosticTraces(reference.native, prefix.native);
                record.prefix_match_pass = record.prefix_observed.pass && record.prefix_native.pass;
                assert(record.prefix_match_pass, 'HeatDriveECC:PrefixMismatch', ...
                    'Split prefix differs from uninterrupted reference; do not propagate it.');
                diagnostic_op = output.xFinal;
                production_recovery_allowed = false;
                op_path = fullfile(output_root, sprintf('case_%d_DO_NOT_RESUME_FOR_PRODUCTION.mat', case_index));
                assert(~isfile(op_path), 'Do not overwrite a diagnostic OP.');
                save(op_path, 'diagnostic_op', 'production_recovery_allowed', '-v7.3');
                clear output diagnostic_op
                restored = load(op_path, 'diagnostic_op', 'production_recovery_allowed');
                assert(~restored.production_recovery_allowed, 'Diagnostic OP scope changed.');
                output = run_strict(input, restored.diagnostic_op, finish);
                suffix = extract(output, model, tau, middle, finish, dt);
                record.strict_suffix_pass = true;
                record.suffix_observed = Compare_HeatDriveECC_DiagnosticTraces(reference.observed, suffix.observed);
                record.suffix_native = Compare_HeatDriveECC_DiagnosticTraces(reference.native, suffix.native);
                record.suffix_match_pass = record.suffix_observed.pass && record.suffix_native.pass;
                record.pass = record.prefix_match_pass && record.suffix_match_pass;
                clear output restored
            catch e
                record.error_message = e.message;
            end
            save(fullfile(output_root, sprintf('case_%d_traces.mat', case_index)), ...
                'reference', 'prefix', 'suffix', 'record', '-v7.3');
            audit.cases{end + 1} = record;
            assert(record.pass, 'HeatDriveECC:SegmentationMismatch', ...
                'Case %s failed: %s', kind, record.error_message);
        end
        audit.collection_pass = true;
        audit.segmentation_equivalence_pass = all(cellfun(@(r) r.pass, audit.cases));
        clear cleanup
    catch e
        audit.error_identifier = e.identifier;
        audit.error_message = e.message;
    end
    fid = fopen(json_path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot write segmentation audit.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(audit, 'PrettyPrint', true));
    clear file_cleanup
    fprintf('SEGMENTED_INVENTORY_EQUIVALENCE_PASS=%d CASES=%d\n', ...
        audit.segmentation_equivalence_pass, numel(audit.cases));
    assert(audit.segmentation_equivalence_pass, 'HeatDriveECC:SegmentedInventoryAuditFailed', ...
        '%s', audit.error_message);
end

function output = run_strict(input, op, finish)
    input = input.setInitialState(op);
    input = input.setModelParameter('StopTime', num2str(finish, '%.15g'));
    output = sim(input);
    assert(isempty(output.ErrorMessage), 'HeatDriveECC:SegmentStrictRestoreFailed', '%s', output.ErrorMessage);
end

function traces = extract(output, model, tau, start, finish, dt)
    observation = Extract_HeatDriveECC_ObservedStates(output.internal_state_log, tau, 1);
    traces = struct('observed', {observation.states}, ...
        'native', {Extract_HeatDriveECC_NativeStorageTraces(output.get('simlog'), model)});
    rows = [traces.observed(:); traces.native(:)];
    count = round((finish - start) / dt) + 1;
    tolerance = 16 * eps(finish);
    for k = 1:numel(rows)
        t = rows{k}.time_s(:);
        assert(numel(t) == count && abs(t(1) - start) <= tolerance && ...
            abs(t(end) - finish) <= tolerance && all(abs(diff(t) - dt) <= tolerance), ...
            'HeatDriveECC:UnexpectedDiagnosticWindow', 'Wrong start/stop/grid for %s', rows{k}.block_path);
    end
end
