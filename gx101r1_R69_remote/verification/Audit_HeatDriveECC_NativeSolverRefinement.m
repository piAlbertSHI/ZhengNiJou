function record = Audit_HeatDriveECC_NativeSolverRefinement(output_root)
% Same frozen C180 state in each case; only the continuous solver step changes.
    repo = fileparts(fileparts(mfilename('fullpath')));
    if isfolder(output_root)
        files = dir(output_root);
        assert(all(ismember({files.name}, {'.','..','matlab_stdout.log'})), 'Use a new experiment directory.');
    else
        mkdir(output_root);
    end
    record = struct('schema', 'heatdrive_ecc_native_solver_refinement_v1', ...
        'solver_steps_s', [.001 .0005 .00025], 'window_duration_s', .3, 'cases', {{}}, ...
        'collection_pass', false, 'production_recovery_allowed', false, ...
        'temporal_convergence_verified', false, 'full_internal_periodicity_verified', false, ...
        'equation_matched_cycle_closure_verified', false, 'error_identifier', '', 'error_message', '');
    try
        [code, commit] = system('git rev-parse HEAD');
        assert(code == 0, 'Cannot record execution commit.');
        record.execution_commit = strtrim(commit);
        [code, dirty] = system('git status --porcelain');
        assert(code == 0 && isempty(strtrim(dirty)), 'Commit reviewed source before the experiment.');
        authority = Resolve_HeatDriveECC_SourceHeatFlowRecovery(struct( ...
            'contract_path', fullfile(repo, 'verification', 'runtime_c180_recovery_contract.json'), ...
            'recovery_use', 'inventory_diagnostic', 'verify_large_result_hash', true));
        checkpoint = load(authority.checkpoint_path, 'operating_point', 'checkpoint_meta');
        prior = load(authority.result_path, 'options');
        assert(~prior.options.simscape.local_solver_enabled, ...
            'HeatDriveECC:GlobalRefinementNotPhysicalRefinement', ...
            ['The archived global-step experiment is invalid for local-solver refinement. ', ...
             'Its 0.5 ms strict OP restore failed. Preserve that evidence; ', ...
             'do not rerun or relax checks. Design a local-solver-compatible study first.']);
        prior.options.cycle_count = authority.completed_cycles + 2;
        [model, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(prior.options);
        cleanup = onCleanup(@() close_system(model, 0));
        assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
        start = checkpoint.checkpoint_meta.time_s;
        stop = start + record.window_duration_s;
        sample_time = evalin('base', 'constitutive_sample_time_s');
        assert(start == 1800 && options.simulation.fixed_step_s == .001 && sample_time == .001, ...
            'HeatDriveECC:RefinementProtocolMismatch', 'Unexpected frozen sampling contract.');
        record.command_coverage = Audit_HeatDriveECC_CommandCoverage(model, options, stop);
        record.configured_constitutive_sample_time_s = sample_time;
        record.source_result_sha256 = authority.result_sha256;
        record.source_checkpoint_sha256 = authority.checkpoint_sha256;
        record.simscape_history_points = 10002;
        input = Simulink.SimulationInput(model);
        input = input.setModelParameter('StartTime', '0', 'StopTime', num2str(stop, '%.15g'), ...
            'Solver', options.simulation.solver, 'SimulationMode', options.simulation.mode, ...
            'ReturnWorkspaceOutputs', 'on', 'CaptureErrors', 'on', ...
            'SaveTime', 'off', 'SaveOutput', 'off', 'SignalLogging', 'off', ...
            'SimscapeLogLimitData', 'on', 'SimscapeLogDataHistory', record.simscape_history_points, ...
            'SaveState', 'on', 'StateSaveName', 'internal_state_log', ...
            'SaveFinalState', 'on', 'FinalStateName', 'xFinal', 'SaveOperatingPoint', 'on', ...
            'OperatingPointContentsChecksumMismatchMsg', 'error', ...
            'OperatingPointInterfaceChecksumMismatchMsg', 'error');
        input = input.setVariable('EIGHTH_ROUND_OPTIONS', options);
        for k = 1:numel(record.solver_steps_s)
            dt = record.solver_steps_s(k);
            current = input.setInitialState(checkpoint.operating_point);
            current = current.setModelParameter('FixedStep', num2str(dt, '%.15g'));
            wall = tic;
            output = sim(current);
            elapsed = toc(wall);
            assert(isempty(output.ErrorMessage), 'HeatDriveECC:RefinementStrictRestoreFailed', '%s', output.ErrorMessage);
            native = Extract_HeatDriveECC_NativeStorageTraces(output.get('simlog'), model);
            observed = Extract_HeatDriveECC_ObservedStates(output.internal_state_log, options.schedule.tau_cycle_s, 1);
            traces = struct('native', {native}, 'observed', {observed.states});
            item = struct('schema', 'heatdrive_ecc_native_refinement_case_v1', ...
                'case_index', k, 'solver_step_s', dt, 'start_s', start, 'stop_s', stop, ...
                'configured_constitutive_sample_time_s', sample_time, 'walltime_s', elapsed, ...
                'strict_restore_pass', true, 'independent_case_audit_pass', false, ...
                'source_result_sha256', authority.result_sha256, ...
                'source_checkpoint_sha256', authority.checkpoint_sha256, ...
                'same_frozen_initial_state_for_each_case', true, 'state_resets_applied', false, ...
                'production_recovery_allowed', false, 'output_operating_point_saved', false);
            record_json = jsonencode(item);
            case_path = fullfile(output_root, sprintf('case_%d_traces.mat', k));
            save(case_path, 'traces', 'record_json', 'options', '-v7.3');
            clear output native observed traces
            command = sprintf('python "%s" --case-file "%s" --repo "%s" --output "%s"', ...
                fullfile(repo, 'verification', 'Audit_HeatDriveECC_NativeRefinementCase.py'), ...
                case_path, repo, fullfile(output_root, sprintf('case_%d_audit.json', k)));
            [code, text] = system(command);
            fid = fopen(fullfile(output_root, sprintf('case_%d_audit_stdout.log', k)), 'w', 'n', 'UTF-8');
            assert(fid >= 0, 'Cannot retain independent audit output.');
            fprintf(fid, '%s', text); fclose(fid);
            assert(code == 0, 'HeatDriveECC:RefinementCaseAuditFailed', '%s', text);
            item.independent_case_audit_pass = true;
            record.cases{end + 1} = item;
            write_json(fullfile(output_root, 'native_refinement_progress.json'), record);
        end
        record.collection_pass = numel(record.cases) == numel(record.solver_steps_s);
        clear cleanup
    catch e
        record.error_identifier = e.identifier;
        record.error_message = e.message;
    end
    write_json(fullfile(output_root, 'native_refinement_result.json'), record);
    fprintf('NATIVE_SOLVER_REFINEMENT_COLLECTION_PASS=%d CASES=%d\n', record.collection_pass, numel(record.cases));
    assert(record.collection_pass, 'HeatDriveECC:NativeRefinementFailed', '%s', record.error_message);
end

function write_json(path, value)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot write experiment evidence.');
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(value, 'PrettyPrint', true));
end
