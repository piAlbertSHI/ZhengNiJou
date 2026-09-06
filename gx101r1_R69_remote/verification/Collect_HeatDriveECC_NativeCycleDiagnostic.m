function record = Collect_HeatDriveECC_NativeCycleDiagnostic(output_root, cycle_count)
% Restricted continuous-state experiment; its OP files never authorize production.
    if nargin < 2, cycle_count = 1; end
    validateattributes(cycle_count, {'numeric'}, {'scalar','integer','>=',1,'<=',10});
    repo = fileparts(fileparts(mfilename('fullpath')));
    if isfolder(output_root)
        files = dir(output_root);
        files = files(~ismember({files.name}, {'.', '..', 'matlab_stdout.log'}));
        assert(isempty(files), 'HeatDriveECC:ExistingNativeCycleExperiment', 'Use a new output root.');
    else
        mkdir(output_root);
    end
    record = struct('schema', 'heatdrive_ecc_native_cycle_collection_v1', ...
        'requested_cycles', cycle_count, 'collected_cycles', 0, 'cycles', {{}}, ...
        'collection_pass', false, 'mechanism_all_collected_cycles_pass', false, ...
        'production_recovery_allowed', false, 'full_internal_periodicity_verified', false, ...
        'equation_matched_cycle_closure_verified', false, 'error_identifier', '', 'error_message', '');
    try
        [code, commit] = system('git rev-parse HEAD');
        assert(code == 0, 'Cannot record execution commit.');
        record.execution_commit = strtrim(commit);
        [code, dirty] = system('git status --porcelain');
        assert(code == 0 && isempty(strtrim(dirty)), 'Freeze reviewed source before the real experiment.');
        authority = Resolve_HeatDriveECC_SourceHeatFlowRecovery(struct( ...
            'contract_path', fullfile(repo, 'verification', 'runtime_c180_recovery_contract.json'), ...
            'recovery_use', 'inventory_diagnostic', 'verify_large_result_hash', true));
        checkpoint = load(authority.checkpoint_path, 'operating_point', 'checkpoint_meta');
        prior = load(authority.result_path, 'options', 'provenance');
        record.source_result_sha256 = authority.result_sha256;
        record.source_checkpoint_sha256 = authority.checkpoint_sha256;
        start = checkpoint.checkpoint_meta.time_s;
        overrides = prior.options;
        overrides.cycle_count = authority.completed_cycles + max(2, cycle_count);
        [model, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(overrides);
        cleanup = onCleanup(@() close_system(model, 0));
        assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
        tau = options.schedule.tau_cycle_s; dt = options.simulation.fixed_step_s;
        record.source_time_s = start;
        record.command_horizon_s = options.simulation.stop_time_s;
        record.simscape_history_points = ceil(tau / dt) + 2;
        input = Simulink.SimulationInput(model);
        input = input.setModelParameter('StartTime', '0', 'Solver', options.simulation.solver, ...
            'FixedStep', num2str(dt, '%.15g'), 'SimulationMode', options.simulation.mode, ...
            'ReturnWorkspaceOutputs', 'on', 'CaptureErrors', 'on', ...
            'SaveTime', 'off', 'SaveOutput', 'off', 'SignalLogging', 'off', ...
            'SimscapeLogLimitData', 'on', 'SimscapeLogDataHistory', record.simscape_history_points, ...
            'SaveState', 'on', 'StateSaveName', 'internal_state_log', ...
            'SaveFinalState', 'on', 'FinalStateName', 'xFinal', 'SaveOperatingPoint', 'on', ...
            'OperatingPointContentsChecksumMismatchMsg', 'error', ...
            'OperatingPointInterfaceChecksumMismatchMsg', 'error');
        input = input.setVariable('EIGHTH_ROUND_OPTIONS', options);
        source = checkpoint.operating_point;
        previous_physical = struct(); previous_cycle = struct(); previous_packet = '';
        for index = 1:cycle_count
            record.current_target_global_cycle = authority.completed_cycles + index;
            directory = fullfile(output_root, sprintf('cycle_%03d', record.current_target_global_cycle));
            mkdir(directory);
            stop = start + tau;
            segment = input.setInitialState(source);
            segment = segment.setModelParameter('StopTime', num2str(stop, '%.15g'));
            wall = tic;
            output = sim(segment);
            elapsed = toc(wall);
            assert(isempty(output.ErrorMessage), 'HeatDriveECC:NativeCycleStrictSimulation', '%s', output.ErrorMessage);
            native = Extract_HeatDriveECC_NativeStorageTraces(output.get('simlog'), model);
            observation = Extract_HeatDriveECC_ObservedStates(output.internal_state_log, tau, 1);
            settings = struct('source_result_sha256', authority.result_sha256, ...
                'source_checkpoint_sha256', authority.checkpoint_sha256, ...
                'start_s', start, 'stop_s', stop, 'fixed_step_s', dt, 'cycle_period_s', tau);
            packet = fullfile(directory, 'native_window.mat');
            Write_HeatDriveECC_NativeWindow(packet, native, observation.states, settings);
            clear native observation
            physical = Extract_HeatDriveECC_PhysicalLogs(output, options, model, false);
            physical.walltime_s = elapsed; physical.segment_walltime_s = elapsed;
            physical.authority = 'physical_simscape_to_workspace_logs';
            physical.sim_call_count = prior.provenance.sim_call_count + index;
            physical.legacy_surrogate_used_for_results = false;
            provenance = struct('sim_call_count', physical.sim_call_count, 'checkpoint_chain_verified', true, ...
                'checkpoint_restart_used', true, 'solver', options.simulation.solver, ...
                'fixed_step_s', dt, 'simulation_mode', options.simulation.mode, ...
                'execution_commit', record.execution_commit, 'production_recovery_allowed', false);
            save(fullfile(directory, 'segment_physical.mat'), 'physical', 'options', 'provenance', '-v7.3');
            view = Make_HeatDriveECC_MechanismWindow(physical, options, provenance, directory);
            validation = Validate_HeatDriveECC_EighthRound_Physics(view);
            item = struct('global_cycle', record.current_target_global_cycle, 'start_s', start, 'stop_s', stop, ...
                'strict_restore_pass', true, 'mechanism_pass', validation.passed, ...
                'checks', validation.checks, 'diagnostics', validation.diagnostics, ...
                'analysis_window', view.analysis_window, 'cycle_summary', validation.result.summary.cycle, ...
                'same_process_disk_roundtrip', index > 1, 'ledger_computation_pass', false, ...
                'boundary_audit_applicable', index > 1, 'boundary_pass', false, ...
                'production_recovery_allowed', false, 'equation_matched_cycle_closure_verified', false);
            if index > 1
                item.boundary = boundary_check(previous_packet, packet, previous_physical, physical, ...
                    previous_cycle, item.cycle_summary, options);
                item.boundary_pass = item.boundary.pass;
            end
            write_json(fullfile(directory, 'cycle_audit.json'), item);
            assert(item.mechanism_pass && (~item.boundary_audit_applicable || item.boundary_pass), ...
                'HeatDriveECC:NativeCycleMechanismFailed', 'Failed cycle cannot propagate. See %s.', directory);
            command = sprintf(['python "%s" --packet "%s" --topology "%s" ', ...
                '--probe "%s" --metadata "%s" --output "%s"'], ...
                fullfile(repo, 'verification', 'Audit_HeatDriveECC_NativeCyclePacket.py'), packet, ...
                fullfile(repo, 'outputs_storage_audit', 'tl_domain_energy_tables_20260906', 'tl_domain_metadata.json'), ...
                fullfile(repo, 'outputs_storage_audit', 'native_inventory_port_comparison_20260906', 'native_inventory_probe.json'), ...
                fullfile(repo, 'outputs_storage_audit', 'native_inventory_model_metadata_20260906', 'storage_model_metadata.json'), ...
                fullfile(directory, 'native_ledger.json'));
            [code, text] = system(command);
            fid = fopen(fullfile(directory, 'native_ledger_stdout.log'), 'w', 'n', 'UTF-8');
            assert(fid >= 0, 'Cannot retain native ledger output.');
            fprintf(fid, '%s', text); fclose(fid);
            assert(code == 0, 'HeatDriveECC:NativeLedgerComputationFailed', '%s', text);
            ledger = jsondecode(fileread(fullfile(directory, 'native_ledger.json')));
            assert(ledger.ledger_computation_pass && ledger.one_cycle_native_coverage_verified && ...
                ~ledger.production_recovery_allowed && ~ledger.equation_matched_cycle_closure_verified, ...
                'HeatDriveECC:InvalidNativeLedgerScope', 'Ledger scope or computation failed.');
            item.ledger_computation_pass = true;
            write_json(fullfile(directory, 'cycle_audit.json'), item);
            diagnostic_op = output.xFinal;
            production_recovery_allowed = false;
            use_within_this_experiment_only = true;
            op_path = fullfile(directory, 'DO_NOT_RESUME_FOR_PRODUCTION.mat');
            save(op_path, 'diagnostic_op', 'production_recovery_allowed', 'use_within_this_experiment_only', '-v7.3');
            clear output diagnostic_op view validation ledger
            restored = load(op_path, 'diagnostic_op', 'production_recovery_allowed', 'use_within_this_experiment_only');
            assert(~restored.production_recovery_allowed && restored.use_within_this_experiment_only);
            source = restored.diagnostic_op;
            previous_physical = physical; previous_cycle = item.cycle_summary; previous_packet = packet;
            record.cycles{end + 1} = item;
            record.collected_cycles = index;
            start = stop;
            write_json(fullfile(output_root, 'native_cycle_progress.json'), record);
        end
        record.collection_pass = record.collected_cycles == cycle_count;
        record.mechanism_all_collected_cycles_pass = all(cellfun(@(r) r.mechanism_pass, record.cycles));
        clear cleanup
    catch e
        record.error_identifier = e.identifier;
        record.error_message = e.message;
    end
    write_json(fullfile(output_root, 'native_cycle_result.json'), record);
    fprintf('NATIVE_CYCLE_COLLECTION_PASS=%d COLLECTED=%d REQUESTED=%d\n', ...
        record.collection_pass, record.collected_cycles, cycle_count);
    assert(record.collection_pass, 'HeatDriveECC:NativeCycleCollectionFailed', '%s', record.error_message);
end

function record = boundary_check(previous_path, current_path, before, after, previous_cycle, current_cycle, options)
    previous = load(previous_path, 'time_s', 'native_values', 'observed_values');
    current = load(current_path, 'time_s', 'native_values', 'observed_values');
    record = struct('shared_boundary_time', previous.time_s(end) == current.time_s(1), ...
        'native_bits_identical', same_bits(previous.native_values(end, :), current.native_values(1, :)), ...
        'observed_bits_identical', same_bits(previous.observed_values(end, :), current.observed_values(1, :)), ...
        'SMA_temperature_jump_K', max(abs(after.SMA_T_21_K(1, :) - before.SMA_T_21_K(end - 1, :))), ...
        'SE_temperature_jump_K', max(abs(after.SE_T_21_K(1, :) - before.SE_T_21_K(end - 1, :))), ...
        'SMA_phase_jump', max(abs(after.xM_SMA_21(1, :) - before.xM_SMA_21(end - 1, :))), ...
        'SE_phase_jump', max(abs(after.xM_SE_21(1, :) - before.xM_SE_21(end - 1, :))));
    limit = options.validation.max_cold_start_phase_swing_regression;
    record.phase_swing_progression = current_cycle.xM_SMA_swing - previous_cycle.xM_SMA_swing >= -limit && ...
        current_cycle.xM_SE_swing - previous_cycle.xM_SE_swing >= -limit;
    record.pass = record.shared_boundary_time && record.native_bits_identical && record.observed_bits_identical && ...
        record.SMA_temperature_jump_K <= 2 && record.SE_temperature_jump_K <= 2 && ...
        record.SMA_phase_jump <= .05 && record.SE_phase_jump <= .05 && record.phase_swing_progression;
end

function equal = same_bits(a, b)
    equal = isequal(typecast(a(:), 'uint64'), typecast(b(:), 'uint64'));
end

function write_json(path, value)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot write diagnostic evidence: %s', path);
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(value, 'PrettyPrint', true));
end
