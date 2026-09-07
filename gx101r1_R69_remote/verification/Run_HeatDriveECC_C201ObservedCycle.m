function audit = Run_HeatDriveECC_C201ObservedCycle(model, input, original_op, options, output_root)
% Full diagnostic cycle with bounded native logs and exact segment-state checks.
    assert(original_op.snapshotTime == 2000 && options.cycle_count == 201);
    assert(options.simulation.fixed_step_s == .001);
    assert(get_param(model, 'SimscapeLogDataHistory') == 5000);
    ends = [2004 2008 2010];
    current_op = original_op;
    previous = [];
    audit = struct('schema', 'heatdrive_ecc_c201_observed_cycle_v1', ...
        'computation_complete', false, 'production_recovery_allowed', false, ...
        'full_scientific_gates_pass', false, 'whole_model_first_law_verified', false, ...
        'segment_end_times_s', ends, 'segments', {{}});
    save(fullfile(output_root, 'diagnostic_options.mat'), 'options', '-v7.3');
    try
        for segment = 1:numel(ends)
            start = current_op.snapshotTime;
            run_input = input.setModelParameter('StopTime', num2str(ends(segment), '%.15g'));
            run_input = run_input.setInitialState(current_op);
            started = tic;
            output = sim(run_input);
            elapsed = toc(started);
            assert(isempty(output.ErrorMessage), 'HeatDriveECC:C201SimulationFailed', '%s', output.ErrorMessage);
            assert(output.xFinal.snapshotTime == ends(segment), 'Wrong segment endpoint.');
            signals = struct();
            names = output.who;
            for k = 1:numel(names)
                item = output.get(names{k});
                if isa(item, 'timeseries')
                    signals.(names{k}) = struct('time_s', item.Time, 'values', item.Data);
                elseif isstruct(item) && isscalar(item) && isfield(item, 'time') && ...
                        isfield(item, 'signals') && isscalar(item.signals) && isfield(item.signals, 'values')
                    signals.(names{k}) = struct('time_s', item.time, 'values', item.signals.values);
                end
            end
            native = Extract_HeatDriveECC_NativeStorageTraces(output.get('simlog'), model);
            observation = Extract_HeatDriveECC_ObservedStates(output.internal_state_log, 10, 1);
            save(fullfile(output_root, sprintf('segment_%02d.mat', segment)), ...
                'signals', 'native', 'observation', '-v7.3');
            fields = fieldnames(signals);
            assert(numel(fields) == 161 && numel(native) == 1240 && numel(observation.states) == 73, ...
                'Incomplete component observation coverage.');
            rows = cell(numel(fields) + numel(native) + numel(observation.states), 1);
            for k = 1:numel(fields)
                row = signals.(fields{k});
                row.identity = ['signal/' fields{k}];
                rows{k} = row;
            end
            offset = numel(fields);
            collections = {native, observation.states};
            prefixes = {'native/', 'state/'};
            for group = 1:numel(collections)
                for k = 1:numel(collections{group})
                    row = collections{group}{k};
                    row.identity = [prefixes{group} row.block_path '/' row.state_name];
                    rows{offset + k} = row;
                end
                offset = offset + numel(collections{group});
            end
            first = struct(); last = struct();
            first.identities = cellfun(@(r) r.identity, rows, 'UniformOutput', false);
            last.identities = first.identities;
            first.values = cell(size(rows)); last.values = cell(size(rows));
            expected_t = (start:.001:ends(segment)).';
            for k = 1:numel(rows)
                row = rows{k};
                t = row.time_s(:); y = row.values;
                assert(numel(t) == numel(expected_t) && max(abs(t-expected_t)) < 1e-9 && ...
                    size(y, 1) == numel(t) && all(isfinite(y), 'all'), ...
                    'Incomplete/nonfinite time coverage: %s', row.identity);
                first.values{k} = y(1, :); last.values{k} = y(end, :);
            end
            boundary = struct('checked', segment > 1, 'pass', true, 'compared_groups', 0, 'max_abs_difference', 0);
            if segment > 1
                assert(isequal(previous.identities, first.identities), 'State identities changed.');
                boundary.compared_groups = numel(rows);
                for k = 1:numel(rows)
                    a = previous.values{k}; b = first.values{k};
                    assert(isequal(size(a), size(b)), 'State dimensions changed.');
                    difference = abs(a-b);
                    boundary.max_abs_difference = max(boundary.max_abs_difference, max(difference));
                    assert(all(difference <= 1e-10 + 1e-11 * max(abs(a), abs(b))), ...
                        'HeatDriveECC:C201SegmentDiscontinuity', 'Segment boundary changed: %s', first.identities{k});
                end
            end
            audit.segments{segment} = struct('start_time_s', start, 'end_time_s', ends(segment), ...
                'sample_count', numel(expected_t), 'wall_time_s', elapsed, 'boundary', boundary);
            previous = last;
            current_op = output.xFinal;
            clear output signals native observation rows
        end
        audit.final_snapshot_time_s = current_op.snapshotTime;
        audit.computation_complete = true;
        diagnostic_op = current_op;
        production_recovery_allowed = false;
        save(fullfile(output_root, 'DO_NOT_RESUME_FOR_PRODUCTION.mat'), ...
            'diagnostic_op', 'production_recovery_allowed', '-v7.3');
    catch exception
        audit.error_identifier = exception.identifier;
        audit.error_message = exception.message;
        write_audit(output_root, audit);
        rethrow(exception);
    end
    write_audit(output_root, audit);
end

function write_audit(root, audit)
    fid = fopen(fullfile(root, 'cycle_observation_audit.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot write cycle evidence.');
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(audit, 'PrettyPrint', true));
end
