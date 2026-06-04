function [stage_result, actuator_state_out] = Run_CoupledSMA_LoadUnload_Stage( ...
        stage_mode, actuator_state_in, refrigerant_checkpoint, options, save_checkpoint_path)
% Run coupled actuator-driven loading or unloading for one mechanical stage.

    if nargin < 1 || isempty(stage_mode)
        stage_mode = 'heating_load';
    end
    stage_mode = lower(char(string(stage_mode)));
    if nargin < 4 || isempty(options)
        options = Build_CoupledSMA_Default_Options();
    end
    if nargin < 2 || isempty(actuator_state_in)
        actuator_state_in = Initialize_SMA_Actuator_State(options.actuator);
    end
    if nargin < 3
        refrigerant_checkpoint = [];
    end
    if nargin < 5
        save_checkpoint_path = '';
    end

    [duration_s, step_count, thermal_mode, solver_kind] = resolve_stage_mode(stage_mode, options);
    time_s = linspace(0.0, duration_s, step_count);
    actuator_trace = repmat(empty_actuator_trace_row(), 1, step_count);
    coupling_trace = repmat(empty_coupling_trace_row(), 1, step_count);
    pressure_MPa = zeros(1, step_count);

    actuator_state = actuator_state_in;
    for idx = 1:step_count
        if idx > 1
            dt_s = time_s(idx) - time_s(idx - 1);
            [actuator_state, step_report] = SMA_Actuator_LumpedModel( ...
                'thermal_step', actuator_state, options.actuator, ...
                struct('mode', thermal_mode, 'dt_s', dt_s));
        else
            step_report = empty_step_report(thermal_mode);
        end
        coupling = Solve_SMA_Actuator_Refrigerant_Coupling( ...
            actuator_state, options.actuator, refrigerant_checkpoint, ...
            options.refrigerant, options.coupling, thermal_mode);
        pressure_MPa(idx) = coupling.pressure_MPa;
        actuator_trace(idx) = make_actuator_trace_row(time_s(idx), actuator_state, step_report);
        coupling_trace(idx) = make_coupling_trace_row(time_s(idx), coupling);
    end

    pressure_MPa = sanitize_pressure_profile(pressure_MPa, solver_kind, options);
    pressure_Pa = 1.0e6 * pressure_MPa;

    solver_options = options.refrigerant.solver_options;
    solver_options.pressure_time_s = time_s;
    solver_options.pressure_MPa = pressure_MPa;
    solver_options.Pmax = max(max(pressure_Pa), eps);
    solver_options.store_work_history = true;
    if ~isempty(save_checkpoint_path)
        solver_options.save_checkpoint_path = save_checkpoint_path;
    end
    if strcmp(solver_kind, 'loading')
        solver_options.Nt = step_count;
        solver_options.T_load = duration_s;
        if ~isempty(refrigerant_checkpoint)
            solver_options.initial_checkpoint = refrigerant_checkpoint;
        end
        solver_result = Run_GlobalXi_Time_Loading_Prototype(solver_options);
    else
        if isempty(refrigerant_checkpoint)
            error('Run_CoupledSMA_LoadUnload_Stage:MissingUnloadCheckpoint', ...
                'cooling_unload requires a refrigerant checkpoint.');
        end
        solver_options.Nt_unload = step_count;
        solver_options.T_unload = duration_s;
        solver_options.initial_checkpoint = refrigerant_checkpoint;
        solver_result = Run_GlobalXi_Unloading_Prototype(solver_options);
    end

    actuator_state_out = actuator_state;
    stage_result = struct();
    stage_result.ok = isstruct(solver_result) && isfield(solver_result, 'ok') && solver_result.ok;
    stage_result.failure_reason = get_field(solver_result, 'failure_reason', '');
    stage_result.stage_mode = stage_mode;
    stage_result.thermal_mode = thermal_mode;
    stage_result.solver_kind = solver_kind;
    stage_result.time_s = time_s;
    stage_result.pressure_MPa = pressure_MPa;
    stage_result.pressure_trace = struct('time_s', time_s, 'pressure_MPa', pressure_MPa);
    stage_result.actuator_trace = actuator_trace;
    stage_result.coupling_trace = coupling_trace;
    stage_result.actuator_state_in = actuator_state_in;
    stage_result.actuator_state_out = actuator_state_out;
    stage_result.refrigerant_checkpoint_in = checkpoint_path_or_empty(refrigerant_checkpoint);
    stage_result.refrigerant_checkpoint_out = get_field(get_field(solver_result, 'diagnostics_handle', struct()), 'checkpoint_path', save_checkpoint_path);
    stage_result.solver_result = solver_result;
    stage_result.summary = build_stage_summary(stage_result);
end

function [duration_s, step_count, thermal_mode, solver_kind] = resolve_stage_mode(stage_mode, options)
    schedule = get_field(options, 'stage_schedule', struct());
    switch stage_mode
        case {'heating_load', 'actuator_heat_load', 'stage1'}
            duration_s = get_field(schedule, 'stage1_duration_s', 0.10);
            step_count = get_field(schedule, 'stage1_steps', 80);
            thermal_mode = 'heating_load';
            solver_kind = 'loading';
        case {'cooling_unload', 'actuator_cool_unload', 'stage3'}
            duration_s = get_field(schedule, 'stage3_duration_s', 0.45);
            step_count = get_field(schedule, 'stage3_steps', 180);
            thermal_mode = 'cooling_unload';
            solver_kind = 'unloading';
        otherwise
            error('Run_CoupledSMA_LoadUnload_Stage:UnsupportedStageMode', ...
                'Unsupported stage_mode: %s', stage_mode);
    end
    step_count = max(3, round(step_count));
end

function pressure_MPa = sanitize_pressure_profile(pressure_MPa, solver_kind, options)
    pressure_MPa = pressure_MPa(:).';
    pressure_MPa(~isfinite(pressure_MPa)) = 0.0;
    pressure_MPa = max(0.0, pressure_MPa);
    pmax = get_field(options.coupling, 'pressure_max_MPa', 0.90);
    pressure_MPa = min(pressure_MPa, pmax);
    if strcmp(solver_kind, 'loading')
        pressure_MPa(1) = 0.0;
        pressure_MPa = cummax(pressure_MPa);
    else
        pressure_MPa = min(pressure_MPa, pressure_MPa(1));
        for idx = 2:numel(pressure_MPa)
            pressure_MPa(idx) = min(pressure_MPa(idx), pressure_MPa(idx - 1));
        end
        pressure_MPa(end) = 0.0;
    end
end

function summary = build_stage_summary(stage_result)
    pressure = stage_result.pressure_MPa(:);
    actuator = stage_result.actuator_trace;
    coupling = stage_result.coupling_trace;
    summary = struct();
    summary.ok = stage_result.ok;
    summary.failure_reason = stage_result.failure_reason;
    summary.stage_mode = stage_result.stage_mode;
    summary.pressure_min_MPa = finite_min(pressure);
    summary.pressure_max_MPa = finite_max(pressure);
    summary.pressure_first_MPa = finite_first(pressure);
    summary.pressure_last_MPa = finite_last(pressure);
    summary.actuator_T_first_K = finite_first([actuator.T_K]);
    summary.actuator_T_last_K = finite_last([actuator.T_K]);
    summary.actuator_xi_first = finite_first([actuator.xi]);
    summary.actuator_xi_last = finite_last([actuator.xi]);
    summary.force_max_N = finite_max([actuator.force_N]);
    summary.coupling_residual_norm_median = finite_median([coupling.residual_norm]);
    summary.coupling_residual_norm_max = finite_max([coupling.residual_norm]);
    summary.all_finite = all(isfinite([pressure(:).', [actuator.T_K], [actuator.xi], ...
        [actuator.force_N], [coupling.residual_norm]]));
end

function row = make_actuator_trace_row(time_s, state, report)
    row = empty_actuator_trace_row();
    row.time_s = time_s;
    row.T_K = get_field(state, 'T_K', NaN);
    row.xi = get_field(state, 'xi', NaN);
    row.epsilon = get_field(state, 'epsilon', NaN);
    row.sigma_Pa = get_field(state, 'sigma_Pa', NaN);
    row.force_N = get_field(state, 'force_N', NaN);
    row.displacement_m = get_field(state, 'displacement_m', NaN);
    row.heat_input_J = get_field(state, 'heat_input_J', NaN);
    row.heat_rejected_J = get_field(state, 'heat_rejected_J', NaN);
    row.latent_J = get_field(state, 'latent_J', NaN);
    row.mechanical_work_J = get_field(state, 'mechanical_work_J', NaN);
    row.Q_net_W = get_field(report, 'Q_net_W', NaN);
end

function row = make_coupling_trace_row(time_s, coupling)
    row = empty_coupling_trace_row();
    row.time_s = time_s;
    row.pressure_MPa = get_field(coupling, 'pressure_MPa', NaN);
    row.force_actuator_N = get_field(coupling, 'force_actuator_N', NaN);
    row.force_refrigerant_N = get_field(coupling, 'force_refrigerant_N', NaN);
    row.displacement_actuator_m = get_field(coupling, 'displacement_actuator_m', NaN);
    row.displacement_refrigerant_proxy_m = get_field(coupling, 'displacement_refrigerant_proxy_m', NaN);
    row.residual_force_N = get_field(coupling, 'residual_force_N', NaN);
    row.residual_displacement_m = get_field(coupling, 'residual_displacement_m', NaN);
    row.residual_norm = get_field(coupling, 'residual_norm', NaN);
    status = get_field(coupling, 'solver_status', struct());
    row.solver_ok = logical(get_field(status, 'ok', false));
    row.pressure_clamped = logical(get_field(status, 'pressure_clamped', false));
end

function row = empty_actuator_trace_row()
    row = struct( ...
        'time_s', NaN, ...
        'T_K', NaN, ...
        'xi', NaN, ...
        'epsilon', NaN, ...
        'sigma_Pa', NaN, ...
        'force_N', NaN, ...
        'displacement_m', NaN, ...
        'heat_input_J', NaN, ...
        'heat_rejected_J', NaN, ...
        'latent_J', NaN, ...
        'mechanical_work_J', NaN, ...
        'Q_net_W', NaN);
end

function row = empty_coupling_trace_row()
    row = struct( ...
        'time_s', NaN, ...
        'pressure_MPa', NaN, ...
        'force_actuator_N', NaN, ...
        'force_refrigerant_N', NaN, ...
        'displacement_actuator_m', NaN, ...
        'displacement_refrigerant_proxy_m', NaN, ...
        'residual_force_N', NaN, ...
        'residual_displacement_m', NaN, ...
        'residual_norm', NaN, ...
        'solver_ok', false, ...
        'pressure_clamped', false);
end

function report = empty_step_report(mode)
    report = struct('mode', mode, 'Q_net_W', NaN);
end

function path_value = checkpoint_path_or_empty(checkpoint_input)
    path_value = '';
    if ischar(checkpoint_input) || isstring(checkpoint_input)
        path_value = char(string(checkpoint_input));
    elseif isstruct(checkpoint_input)
        path_value = get_field(checkpoint_input, 'path', '');
    end
end

function value = get_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end

function value = finite_min(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = min(values);
    end
end

function value = finite_max(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = max(values);
    end
end

function value = finite_first(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = values(1);
    end
end

function value = finite_last(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = values(end);
    end
end

function value = finite_median(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = median(values);
    end
end
