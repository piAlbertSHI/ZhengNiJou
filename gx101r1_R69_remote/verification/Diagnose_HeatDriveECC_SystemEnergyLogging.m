function diagnostic = Diagnose_HeatDriveECC_SystemEnergyLogging( ...
        checkpoint_path, result_path, duration_s, output_json)
% Inventory native Simscape energy variables over a short OP continuation.

    arguments
        checkpoint_path (1, :) char
        result_path (1, :) char
        duration_s (1, 1) double {mustBePositive} = 0.02
        output_json (1, :) char = ''
    end
    assert(isfile(checkpoint_path) && isfile(result_path), ...
        'HeatDriveECC:MissingSystemEnergyDiagnosticInput', ...
        'Checkpoint and result are both required.');

    checkpoint = load(checkpoint_path, 'operating_point', 'checkpoint_meta');
    prior = load(result_path, 'options');
    assert(isfield(checkpoint, 'operating_point') && ...
        isfield(checkpoint, 'checkpoint_meta') && isfield(prior, 'options'), ...
        'HeatDriveECC:InvalidSystemEnergyDiagnosticInput', ...
        'Checkpoint or result is missing its required contract.');

    snapshot_s = double(checkpoint.checkpoint_meta.time_s);
    options_override = prior.options;
    options_override.cycle_count = ceil((snapshot_s + duration_s) / ...
        options_override.schedule.tau_cycle_s);
    options_override.output.generate_figures = false;
    options_override.simulation.stop_time_s = snapshot_s + duration_s;
    options_override.simulation.save_final_operating_point = false;
    options_override.simulation.resume_checkpoint_path = '';
    options_override.simulation.prior_result_path = '';

    [model_name, options] = ...
        Build_HeatDriveECC_EighthRound_Simulink_Model(options_override);
    cleanup = onCleanup(@() close_runtime_model(model_name));
    assignin('base', 'EIGHTH_ROUND_OPTIONS', options);

    sim_in = Simulink.SimulationInput(model_name);
    sim_in = sim_in.setModelParameter( ...
        'StartTime', '0', ...
        'StopTime', num2str(snapshot_s + duration_s, '%.15g'), ...
        'Solver', options.simulation.solver, ...
        'SimulationMode', 'normal', ...
        'ReturnWorkspaceOutputs', 'on', ...
        'CaptureErrors', 'on', ...
        'OperatingPointContentsChecksumMismatchMsg', 'warning', ...
        'SimscapeLogLimitData', 'on', ...
        'SimscapeLogDataHistory', required_simscape_history_steps(options), ...
        'SaveFinalState', 'off', ...
        'SaveOperatingPoint', 'off', ...
        'FixedStep', num2str(options.simulation.fixed_step_s, '%.15g'));
    sim_in = sim_in.setVariable('EIGHTH_ROUND_OPTIONS', options);
    sim_in = sim_in.setInitialState(checkpoint.operating_point);
    sim_out = sim(sim_in);
    if isprop(sim_out, 'ErrorMessage') && ~isempty(sim_out.ErrorMessage)
        error('HeatDriveECC:SystemEnergyDiagnosticSimulationFailed', ...
            '%s', sim_out.ErrorMessage);
    end

    simlog = sim_out.get('simlog');
    assert(isa(simlog, 'simscape.logging.Node'), ...
        'HeatDriveECC:MissingSystemEnergyDiagnosticSimlog', ...
        'Simscape logging root was not returned.');

    diagnostic = struct();
    diagnostic.schema = ...
        'heatdrive_ecc_system_energy_native_logging_diagnostic_v1';
    diagnostic.generated_at = char(datetime('now', 'TimeZone', 'local'));
    diagnostic.checkpoint_path = checkpoint_path;
    diagnostic.result_path = result_path;
    diagnostic.snapshot_time_s = snapshot_s;
    diagnostic.stop_time_s = snapshot_s + duration_s;
    diagnostic.requested_duration_s = duration_s;
    diagnostic.required_history_steps = required_simscape_history_steps(options);
    diagnostic.blocks = inventory_energy_blocks(model_name, simlog);
    diagnostic.block_count = numel(diagnostic.blocks);
    diagnostic.logged_block_count = nnz([diagnostic.blocks.logged]);
    diagnostic.energy_variable_count = sum( ...
        arrayfun(@(item) numel(item.variables), diagnostic.blocks));

    if ~isempty(output_json)
        parent = fileparts(output_json);
        if ~isempty(parent) && ~isfolder(parent)
            mkdir(parent);
        end
        fid = fopen(output_json, 'w', 'n', 'UTF-8');
        assert(fid >= 0, 'HeatDriveECC:SystemEnergyDiagnosticWriteFailed', ...
            'Cannot create diagnostic JSON: %s.', output_json);
        file_cleanup = onCleanup(@() fclose(fid));
        fprintf(fid, '%s\n', jsonencode(diagnostic, PrettyPrint = true));
        clear file_cleanup
    end

    fprintf(['SYSTEM_ENERGY_NATIVE_DIAGNOSTIC blocks=%d logged=%d ', ...
        'energy_variables=%d duration_s=%.12g\n'], ...
        diagnostic.block_count, diagnostic.logged_block_count, ...
        diagnostic.energy_variable_count, duration_s);
    clear cleanup
end

function blocks = inventory_energy_blocks(model_name, simlog)
    all_blocks = find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'Type', 'Block');
    blocks = repmat(empty_block(), 0, 1);
    for idx = 1:numel(all_blocks)
        path = all_blocks{idx};
        mask_type = get_mask_type(path);
        if ~is_energy_block(path, mask_type)
            continue;
        end

        item = empty_block();
        item.path = path;
        item.relative_path = erase(path, [model_name '/']);
        item.mask_type = mask_type;
        block_node = simscape.logging.findNode(simlog, path);
        item.logged = ~isempty(block_node);
        if item.logged
            item.variables = inventory_node_variables(block_node);
        end
        blocks(end + 1, 1) = item; %#ok<AGROW>
    end
end

function variables = inventory_node_variables(block_node)
    ids = cellstr(string(block_node.childIds));
    variables = repmat(empty_variable(), 0, 1);
    for idx = 1:numel(ids)
        id = ids{idx};
        child = block_node.child(id);
        if child.numChildren ~= 0
            continue;
        end
        try
            series = child.series;
            t = double(time(series));
            value = squeeze(double(values(series)));
        catch
            continue;
        end
        if isempty(t) || isempty(value) || size(value, 1) ~= numel(t)
            continue;
        end

        item = empty_variable();
        item.name = id;
        item.unit = char(string(series.unit));
        item.dimension = char(string(series.dimension));
        item.sample_count = numel(t);
        item.time_start_s = t(1);
        item.time_end_s = t(end);
        item.finite = all(isfinite(t), 'all') && all(isfinite(value), 'all');
        if item.finite && isvector(value)
            value = value(:);
            [unique_t, unique_idx] = unique(t(:), 'last');
            value = value(unique_idx);
            item.minimum = min(value);
            item.maximum = max(value);
            item.sample_mean = mean(value);
            if numel(unique_t) >= 2 && unique_t(end) > unique_t(1)
                item.time_integral = trapz(unique_t, value);
                item.time_weighted_mean = item.time_integral / ...
                    (unique_t(end) - unique_t(1));
            end
        end
        variables(end + 1, 1) = item; %#ok<AGROW>
    end
end

function yes = is_energy_block(path, mask_type)
    normalized_path = lower(strrep(path, '\', '/'));
    normalized_mask = lower(strrep(mask_type, newline, ' '));
    relevant_path = contains(normalized_path, '/shex/') || ...
        contains(normalized_path, 'chex') || ...
        contains(normalized_path, 'hotsink') || ...
        contains(normalized_path, 'coldsink') || ...
        contains(normalized_path, 'buffer') || ...
        contains(normalized_path, 'connectingpipe') || ...
        contains(normalized_path, '/sma/') || ...
        contains(normalized_path, '/se/');
    relevant_mask = contains(normalized_mask, 'heat flow') || ...
        contains(normalized_mask, 'conductive heat transfer') || ...
        contains(normalized_mask, 'thermal mass') || ...
        contains(normalized_mask, 'temperature source') || ...
        contains(normalized_mask, 'pipe (tl)') || ...
        contains(normalized_mask, 'tank (tl)') || ...
        contains(normalized_mask, 'constant volume chamber (tl)') || ...
        contains(normalized_mask, 'pressure source (tl)');
    yes = (relevant_path && relevant_mask) || ...
        contains(normalized_mask, 'pressure source (tl)');
end

function value = get_mask_type(path)
    try
        value = get_param(path, 'MaskType');
    catch
        value = '';
    end
end

function item = empty_block()
    item = struct('path', '', 'relative_path', '', 'mask_type', '', ...
        'logged', false, 'variables', repmat(empty_variable(), 0, 1));
end

function item = empty_variable()
    item = struct('name', '', 'unit', '', 'dimension', '', ...
        'sample_count', 0, 'time_start_s', NaN, 'time_end_s', NaN, ...
        'finite', false, 'minimum', NaN, 'maximum', NaN, ...
        'sample_mean', NaN, 'time_integral', NaN, ...
        'time_weighted_mean', NaN);
end

function steps = required_simscape_history_steps(options)
    cycle_steps = ceil(options.schedule.tau_cycle_s / ...
        options.simulation.fixed_step_s);
    steps = max(2, cycle_steps + 2);
end

function close_runtime_model(model_name)
    if bdIsLoaded(model_name)
        set_param(model_name, 'Dirty', 'off');
        close_system(model_name, 0);
    end
end
