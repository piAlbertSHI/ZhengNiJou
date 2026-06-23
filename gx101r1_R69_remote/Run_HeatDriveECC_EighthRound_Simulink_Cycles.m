function result = Run_HeatDriveECC_EighthRound_Simulink_Cycles(overrides)
% Run eighth-round ECC cycles through Simulink time advancement.

    if nargin < 1
        overrides = struct();
    end
    [model_name, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(overrides);
    if ~exist(options.outputs_dir, 'dir')
        mkdir(options.outputs_dir);
    end

    clear HeatDriveECC_EighthRound_SimulinkStep
    assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
    sim_in = Simulink.SimulationInput(model_name);
    sim_in = sim_in.setModelParameter( ...
        'StopTime', num2str(options.simulation.stop_time_s, '%.15g'), ...
        'Solver', options.simulation.solver, ...
        'ReturnWorkspaceOutputs', 'on', ...
        'CaptureErrors', 'on');
    if strcmpi(options.simulation.solver, 'FixedStepDiscrete')
        sim_in = sim_in.setModelParameter( ...
            'FixedStep', num2str(options.simulation.fixed_step_s, '%.15g'));
    else
        sim_in = sim_in.setModelParameter( ...
            'MaxStep', num2str(options.simulation.fixed_step_s, '%.15g'), ...
            'RelTol', '1e-2', ...
            'AbsTol', '1e-3');
    end
    sim_in = sim_in.setVariable('EIGHTH_ROUND_OPTIONS', options);
    sim_out = sim(sim_in);
    if isprop(sim_out, 'ErrorMessage') && ~isempty(sim_out.ErrorMessage)
        error('Run:EighthRound:SimulinkFailed', '%s', sim_out.ErrorMessage);
    end
    if ~any(strcmp(sim_out.who, options.simulation.output_variable))
        error('Run:EighthRound:MissingOutputVariable', ...
            'Expected Simulink output variable "%s". Available variables: %s', ...
            options.simulation.output_variable, strjoin(sim_out.who, ', '));
    end

    raw = sim_out.get(options.simulation.output_variable);
    Y = normalize_yout(raw, options);
    summary = Summarize_HeatDriveECC_EighthRound_Output(Y, options);
    time_s = Y(:, options.output.time_s);

    stamp = datestr(now, 'yyyymmdd_HHMMSS');
    output_mat = fullfile(options.outputs_dir, ...
        sprintf('eighth_round_simulink_%dcycle_%s.mat', options.cycle_count, stamp));
    save(output_mat, 'Y', 'summary', 'options');

    result = struct();
    result.model_name = model_name;
    result.model_path = options.model_path;
    result.options = options;
    result.time_s = time_s;
    result.Y = Y;
    result.summary = summary;
    result.sim_out = sim_out;
    result.output_mat = output_mat;
    result.used_simulink_sim = true;
    result.figures = Plot_HeatDriveECC_EighthRound_Result(result, ...
        sprintf('%dcycle', options.cycle_count));
end

function Y = normalize_yout(raw, options)
    if isa(raw, 'timeseries')
        Y = raw.Data;
    elseif isstruct(raw) && isfield(raw, 'signals')
        Y = raw.signals.values;
    else
        Y = raw;
    end
    Y = squeeze(Y);
    if size(Y, 2) ~= options.output.output_width && ...
            size(Y, 1) == options.output.output_width
        Y = Y.';
    end
    if size(Y, 2) ~= options.output.output_width
        error('Run:EighthRound:BadOutputWidth', ...
            'Expected Simulink output width %d, got [%d %d].', ...
            options.output.output_width, size(Y, 1), size(Y, 2));
    end
end
