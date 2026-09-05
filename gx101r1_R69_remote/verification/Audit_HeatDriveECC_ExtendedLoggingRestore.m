function audit = Audit_HeatDriveECC_ExtendedLoggingRestore(contract_path, output_root, mode)
% Test observation-only settings against the frozen OP with strict checksums.
% The one-step probe state is discarded regardless of the result.
    contract = jsondecode(fileread(contract_path));
    authority = Resolve_HeatDriveECC_SourceHeatFlowRecovery(struct( ...
        'contract_path', contract_path, 'verify_large_result_hash', true));
    if nargin < 3, mode = 'combined_dataset'; end
    assert(any(strcmp(mode, {'combined_dataset','combined_preserve', ...
        'inventory_only','state_only'})), 'Unsupported logging probe mode.');
    log_states = ~strcmp(mode, 'inventory_only');
    history_cycles = 11;
    if strcmp(mode, 'state_only'), history_cycles = 1; end
    if ~isfolder(output_root), mkdir(output_root); end
    prior = load(authority.result_path, 'options');
    checkpoint = load(authority.checkpoint_path, ...
        'operating_point', 'checkpoint_meta');
    audit = struct('schema', 'heatdrive_ecc_extended_logging_restore_v1', ...
        'source_result_sha256', contract.result_sha256, ...
        'source_checkpoint_sha256', contract.checkpoint_sha256, ...
        'start_time_s', checkpoint.checkpoint_meta.time_s, ...
        'strict_restore_pass', false, 'probe_mode', mode, ...
        'state_logging_enabled', log_states, ...
        'simscape_history_cycles', history_cycles, 'logged_state_count', 0, ...
        'logged_state_paths', {{}}, 'error_identifier', '', ...
        'error_message', '', 'probe_state_may_resume', false);
    try
        [model, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(prior.options);
        cleanup = onCleanup(@() close_system(model, 0));
        audit.base_save_format = get_param(model, 'SaveFormat');
        audit.base_save_state = get_param(model, 'SaveState');
        assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
        stop = checkpoint.checkpoint_meta.time_s + options.simulation.fixed_step_s;
        input = Simulink.SimulationInput(model);
        input = input.setModelParameter('StartTime', '0', ...
            'StopTime', num2str(stop, '%.15g'), ...
            'Solver', options.simulation.solver, ...
            'FixedStep', num2str(options.simulation.fixed_step_s, '%.15g'), ...
            'SimulationMode', options.simulation.mode, ...
            'CaptureErrors', 'on', 'ReturnWorkspaceOutputs', 'on', ...
            'SaveTime', 'off', 'SaveOutput', 'off', 'SignalLogging', 'off', ...
            'SimscapeLogLimitData', 'on', ...
            'SimscapeLogDataHistory', ceil(history_cycles * options.schedule.tau_cycle_s / ...
                options.simulation.fixed_step_s) + 2, ...
            'SaveFinalState', 'on', 'FinalStateName', 'xFinal', ...
            'SaveOperatingPoint', 'on', ...
            'OperatingPointContentsChecksumMismatchMsg', 'error', ...
            'OperatingPointInterfaceChecksumMismatchMsg', 'error');
        if log_states
            input = input.setModelParameter('SaveState', 'on', ...
                'StateSaveName', 'internal_state_log');
        end
        if strcmp(mode, 'combined_dataset')
            input = input.setModelParameter('SaveFormat', 'Dataset');
        end
        input = input.setVariable('EIGHTH_ROUND_OPTIONS', options);
        input = input.setInitialState(checkpoint.operating_point);
        output = sim(input);
        audit.error_message = char(string(output.ErrorMessage));
        audit.strict_restore_pass = isempty(audit.error_message);
        if audit.strict_restore_pass && log_states
            states = output.internal_state_log;
            audit.state_log_class = class(states);
            audit.state_log_size = size(states);
            if isa(states, 'Simulink.SimulationData.Dataset')
                audit.logged_state_count = states.numElements;
                for k = 1:states.numElements
                    state = states.getElement(k);
                    audit.logged_state_paths{k} = char(state.BlockPath.getBlock(1));
                end
            end
            audit.final_logged_state_class = class(output.xFinal.loggedStates);
            observation = Extract_HeatDriveECC_ObservedStates(states, ...
                options.schedule.tau_cycle_s, 11);
            save(fullfile(output_root, 'probe_observed_states.mat'), 'observation', '-v7.3');
            audit.observed_numeric_bytes = observation.numeric_bytes;
            audit.state_channel_counts = cellfun(@(s) s.channel_count, observation.states);
            if strcmp(mode, 'state_only')
                next_input = input.setInitialState(output.xFinal);
                next_input = next_input.setModelParameter('StopTime', ...
                    num2str(stop + options.simulation.fixed_step_s, '%.15g'));
                next_output = sim(next_input);
                audit.observed_checkpoint_round_trip_pass = ...
                    isempty(next_output.ErrorMessage);
                assert(audit.observed_checkpoint_round_trip_pass, ...
                    'HeatDriveECC:ObservedCheckpointRoundTripFailed', ...
                    '%s', next_output.ErrorMessage);
            end
        end
        clear cleanup
    catch e
        audit.strict_restore_pass = false;
        audit.error_identifier = e.identifier;
        audit.error_message = e.message;
    end
    path = fullfile(output_root, 'extended_logging_restore_audit.json');
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot write logging audit.');
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, jsonencode(audit, 'PrettyPrint', true), 'char');
    fprintf(fid, '\n');
    clear cleaner
    fprintf('EXTENDED_LOGGING_STRICT_RESTORE_PASS=%d STATES=%d\n', ...
        audit.strict_restore_pass, audit.logged_state_count);
end
