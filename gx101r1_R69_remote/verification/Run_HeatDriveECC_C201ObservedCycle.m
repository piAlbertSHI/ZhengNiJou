function audit = Run_HeatDriveECC_C201ObservedCycle(model, input, original_op, options, output_root, request)
% Full diagnostic cycle with bounded native logs and exact segment-state checks.
    assert(original_op.snapshotTime == 2000 && options.cycle_count == 201);
    assert(options.simulation.fixed_step_s == .001);
    assert(get_param(model, 'SimscapeLogDataHistory') == 5000);
    ends = [2004 2008 2010];
    if nargin < 6, request = struct('index', 0, 'prior_root', ''); end
    observe_boundary = isfield(request,'boundary_observation') && request.boundary_observation;
    assert(islogical(observe_boundary) && isscalar(observe_boundary), 'Invalid boundary observation mode.');
    assert(isscalar(request.index) && any(request.index == 0:3), 'Invalid planned segment.');
    assert((request.index <= 1) == isempty(request.prior_root), 'Unexpected diagnostic predecessor.');
    requested = 1:3;
    if request.index > 0, requested = request.index; end
    current_op = original_op;
    previous = [];
    audit = struct('schema', 'heatdrive_ecc_c201_observed_cycle_v1', ...
        'computation_complete', false, 'production_recovery_allowed', false, ...
        'full_scientific_gates_pass', false, 'whole_model_first_law_verified', false, ...
        'segment_end_times_s', ends, 'segments', {{}});
    audit.request = request;
    audit.runner_sha256 = file_sha256([mfilename('fullpath') '.m']);
    if observe_boundary
        audit.boundary_observation_requested = true;
        audit.boundary_extractor_sha256 = file_sha256(which('Extract_HeatDriveECC_BoundaryTraces'));
    end
    save(fullfile(output_root, 'diagnostic_options.mat'), 'options', '-v7.3');
    try
        if request.index > 1
            previous_audit = jsondecode(fileread(fullfile(request.prior_root, 'cycle_observation_audit.json')));
            outer = jsondecode(fileread(fullfile(request.prior_root, 'source_restore_audit.json')));
            independent = jsondecode(fileread(fullfile(request.prior_root, 'independent_segment_audit.json')));
            assert(independent.data_audit_pass && independent.diagnostic_continuation_eligible && ...
                ~independent.production_recovery_allowed && ~independent.interrupted_without_final_record, ...
                'Independent predecessor observation audit is required.');
            assert(previous_audit.computation_complete && previous_audit.diagnostic_resume_allowed && ...
                ~previous_audit.production_recovery_allowed && outer.strict_restore_pass && ...
                outer.observation_complete && isempty(outer.error_message), 'Predecessor did not finish verification.');
            assert(previous_audit.request.index == request.index-1 && ...
                previous_audit.final_snapshot_time_s == ends(request.index-1), 'Wrong predecessor segment.');
            assert(strcmp(previous_audit.runner_sha256, audit.runner_sha256), 'Diagnostic runner changed.');
            previous_boundary = isfield(previous_audit,'boundary_observation_requested') && previous_audit.boundary_observation_requested;
            assert(previous_boundary==observe_boundary, 'Cannot change source observation within a diagnostic chain.');
            if observe_boundary
                assert(strcmp(previous_audit.boundary_extractor_sha256,audit.boundary_extractor_sha256), ...
                    'Boundary extraction code changed within the chain.');
            end
            fields = fieldnames(previous_audit.artifact_sha256);
            for k = 1:numel(fields)
                artifact = previous_audit.artifact_names.(fields{k});
                assert(strcmp(independent.input_sha256.(matlab.lang.makeValidName(artifact)), ...
                    previous_audit.artifact_sha256.(fields{k})), 'Independent artifact hash differs.');
                assert(strcmp(file_sha256(fullfile(request.prior_root, artifact)), ...
                    previous_audit.artifact_sha256.(fields{k})), 'Changed predecessor artifact: %s', artifact);
            end
            old_options = load(fullfile(request.prior_root, 'diagnostic_options.mat'), 'options');
            physical_fields = {'geometry','material','branch','system','constitutive','schedule','fluid','simulation'};
            for k = 1:numel(physical_fields)
                key = physical_fields{k};
                assert(isequaln(old_options.options.(key), options.(key)), 'Diagnostic contract changed: %s', key);
            end
            old_commands = load(fullfile(request.prior_root, 'command_profiles.mat'));
            new_commands = load(fullfile(output_root, 'command_profiles.mat'));
            assert(isequaln(old_commands, new_commands), 'Diagnostic command branch changed.');
            saved = load(fullfile(request.prior_root, 'DO_NOT_RESUME_FOR_PRODUCTION.mat'));
            assert(~saved.production_recovery_allowed, 'Unexpected checkpoint status.');
            current_op = saved.diagnostic_op;
            assert(current_op.snapshotTime == ends(request.index-1), 'Wrong saved snapshot time.');
            tail = load(fullfile(request.prior_root, 'final_observation_tail.mat'), 'last');
            previous = tail.last;
            audit.predecessor_audit_sha256 = file_sha256(fullfile(request.prior_root, 'cycle_observation_audit.json'));
        end
        for segment = requested
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
            source_traces = {};
            if observe_boundary
                [source_traces, boundary_metadata] = Extract_HeatDriveECC_BoundaryTraces(output.get('simlog'),model);
                assert(numel(source_traces)==162, 'Incomplete source observation.');
                save(fullfile(output_root,sprintf('segment_%02d.mat',segment)), ...
                    'signals','native','observation','source_traces','boundary_metadata','-v7.3');
            else
                save(fullfile(output_root, sprintf('segment_%02d.mat', segment)), ...
                    'signals', 'native', 'observation', '-v7.3');
            end
            fields = fieldnames(signals);
            assert(numel(fields) == 161 && numel(native) == 1240 && numel(observation.states) == 73, ...
                'Incomplete component observation coverage.');
            rows = cell(numel(fields) + numel(native) + numel(observation.states) + numel(source_traces), 1);
            for k = 1:numel(fields)
                row = signals.(fields{k});
                row.identity = ['signal/' fields{k}];
                rows{k} = row;
            end
            offset = numel(fields);
            collections = {native, observation.states, source_traces};
            prefixes = {'native/', 'state/', 'source/'};
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
            audit.segments{end+1} = struct('index', segment, 'start_time_s', start, 'end_time_s', ends(segment), ...
                'sample_count', numel(expected_t), 'wall_time_s', elapsed, 'boundary', boundary);
            previous = last;
            current_op = output.xFinal;
            clear output signals native observation source_traces boundary_metadata rows
        end
        audit.final_snapshot_time_s = current_op.snapshotTime;
        audit.computation_complete = true;
        diagnostic_op = current_op;
        production_recovery_allowed = false;
        save(fullfile(output_root, 'DO_NOT_RESUME_FOR_PRODUCTION.mat'), ...
            'diagnostic_op', 'production_recovery_allowed', '-v7.3');
        save(fullfile(output_root, 'final_observation_tail.mat'), 'last', '-v7.3');
        audit.artifact_names = struct('checkpoint', 'DO_NOT_RESUME_FOR_PRODUCTION.mat', ...
            'tail', 'final_observation_tail.mat', 'options', 'diagnostic_options.mat', ...
            'commands', 'command_profiles.mat');
        for segment = requested
            audit.artifact_names.(sprintf('segment_%02d',segment)) = sprintf('segment_%02d.mat',segment);
        end
        fields = fieldnames(audit.artifact_names);
        for k = 1:numel(fields)
            audit.artifact_sha256.(fields{k}) = file_sha256(fullfile(output_root, audit.artifact_names.(fields{k})));
        end
        audit.diagnostic_resume_allowed = true;
    catch exception
        audit.error_identifier = exception.identifier;
        audit.error_message = exception.message;
        write_audit(output_root, audit);
        rethrow(exception);
    end
    write_audit(output_root, audit);
end

function value = file_sha256(path)
    digest = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(path, 'rb');
    assert(fid >= 0, 'Cannot read diagnostic artifact.');
    cleanup = onCleanup(@() fclose(fid));
    while ~feof(fid), digest.update(fread(fid, 8*1024*1024, '*uint8')); end
    value = upper(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
end

function write_audit(root, audit)
    fid = fopen(fullfile(root, 'cycle_observation_audit.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot write cycle evidence.');
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(audit, 'PrettyPrint', true));
end
