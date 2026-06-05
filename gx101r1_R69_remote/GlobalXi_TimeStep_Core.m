function varargout = GlobalXi_TimeStep_Core(action, varargin)
%GLOBALXI_TIMESTEP_CORE  Isolated scalar-xi 4N loading prototype.
%   This file intentionally does not call the v10 continuation solver. It is
%   a small-grid audit/prototype for Y=[u,w,T,xi]^T with real loading time.

    switch lower(char(string(action)))
        case 'jv_audit'
            varargout{1} = run_jv_audit(varargin{:});
        case 'loading'
            varargout{1} = run_loading(varargin{:});
        case 'reverse_jv_audit'
            varargout{1} = run_reverse_jv_audit(varargin{:});
        case 'unloading'
            varargout{1} = run_unloading(varargin{:});
        case 'exchange_restart_balance'
            varargout{1} = run_exchange_restart_balance(varargin{:});
        case 'assemble'
            [varargout{1:nargout}] = assemble_system(varargin{:});
        otherwise
            error('GlobalXi_TimeStep_Core:UnknownAction', 'Unknown action: %s', char(string(action)));
    end
end

function result = run_jv_audit(options)
    if nargin < 1 || ~isstruct(options)
        options = struct();
    end
    [params, grid] = setup_problem(options);
    if isfield(options, 'initial_checkpoint') && ~isempty(options.initial_checkpoint)
        [Y_old, state_old, params, grid, initial_checkpoint] = load_or_create_loading_checkpoint(options);
    else
        [Y_old, state_old] = initial_state(params, grid);
        initial_checkpoint = struct();
    end
    [Y, trial_report] = representative_trial_state(Y_old, params, grid);
    step_ctx = build_step_context(0.035, 0.038, params, Y, state_old, grid);

    [R, J, terms] = assemble_system(Y, Y_old, state_old, step_ctx, params, grid);
    audit = directional_jv_audit(Y, Y_old, state_old, step_ctx, params, grid, R, J);

    metrics = default_time_metrics(params, grid);
    metrics.global_xi_time_available = true;
    metrics.global_xi_time_mode = 'jv_audit';
    metrics.global_xi_time_Jv_Ru_err = audit.err_Ru;
    metrics.global_xi_time_Jv_Rw_err = audit.err_Rw;
    metrics.global_xi_time_Jv_RT_err = audit.err_RT;
    metrics.global_xi_time_Jv_Rxi_err = audit.err_Rxi;
    metrics.global_xi_time_active_node_count = nnz(step_ctx.active_mask);
    metrics.global_xi_time_failure_block = audit.failure_block;
    metrics.global_xi_time_failure_reason = audit.failure_reason;
    metrics.global_xi_time_route_decision = route_decision_from_audit(metrics, false);
    metrics.global_xi_time_residual_norm_Ru = norm(R(1:grid.N));
    metrics.global_xi_time_residual_norm_Rw = norm(R(grid.N + (1:grid.N)));
    metrics.global_xi_time_residual_norm_RT = norm(R(2 * grid.N + (1:grid.N)));
    metrics.global_xi_time_residual_norm_Rxi = norm(R(3 * grid.N + (1:grid.N)));
    metrics.global_xi_time_max_abs_delta_xi = max(abs(Y(3 * grid.N + (1:grid.N)) - Y_old(3 * grid.N + (1:grid.N))));
    metrics.global_xi_time_max_dxi_dt = metrics.global_xi_time_max_abs_delta_xi / step_ctx.dt;
    metrics.global_xi_time_xi_truncation_count = trial_report.xi_trial_clipped_count;
    metrics.global_xi_time_trial_max_xi_old = trial_report.max_xi_old;
    metrics.global_xi_time_trial_max_xi = trial_report.max_xi_trial;
    metrics.global_xi_time_trial_min_delta_xi = trial_report.min_delta_xi_trial;
    metrics.global_xi_time_trial_max_delta_xi = trial_report.max_delta_xi_trial;
    metrics.global_xi_time_trial_xi_regression_count = trial_report.xi_trial_regression_count;
    metrics.global_xi_time_cache_used = false;
    metrics.global_xi_time_reached_Pmax = false;

    result = base_result('round101_global_xi_time_jv_audit_v1');
    result.ok = isempty(audit.failure_block);
    result.failure_reason = audit.failure_reason;
    result.metrics = metrics;
    result.summary_metrics = metrics;
    result.diagnostics_handle.audit = audit;
    result.diagnostics_handle.terms = terms;
    result.diagnostics_handle.trial_report = trial_report;
    result.summary = sprintf(['global-xi Jv audit | N=%d | active=%d | ' ...
        'err(Ru/Rw/RT/Rxi)=%.3e/%.3e/%.3e/%.3e | decision=%s'], ...
        grid.N, nnz(step_ctx.active_mask), audit.err_Ru, audit.err_Rw, ...
        audit.err_RT, audit.err_Rxi, metrics.global_xi_time_route_decision);
end

function result = run_loading(options)
    if nargin < 1 || ~isstruct(options)
        options = struct();
    end
    [params, grid] = setup_problem(options);
    skip_loading_jv_audit = isfield(options, 'skip_loading_jv_audit') && ...
        (islogical(options.skip_loading_jv_audit) || isnumeric(options.skip_loading_jv_audit)) && ...
        logical(options.skip_loading_jv_audit);
    if skip_loading_jv_audit
        jv = base_result('round101_global_xi_time_jv_audit_skipped_v1');
        jv.ok = true;
        jv.metrics = default_time_metrics(params, grid);
        jv.metrics.global_xi_time_available = true;
        jv.metrics.global_xi_time_mode = 'jv_audit_skipped';
        jv.metrics.global_xi_time_failure_block = '';
        jv.metrics.global_xi_time_failure_reason = '';
        jv.summary_metrics = jv.metrics;
        jv.summary = 'global-xi loading Jv audit skipped by explicit option';
    else
        jv = run_jv_audit(options);
    end
    if ~(isfield(jv, 'ok') && jv.ok)
        result = base_result('round101_global_xi_time_loading_v1');
        result.ok = false;
        result.failure_reason = 'jv_audit_failed';
        result.metrics = default_time_metrics(params, grid);
        result.metrics.global_xi_time_available = true;
        result.metrics.global_xi_time_mode = 'time_loading';
        result.metrics.global_xi_time_failure_block = 'Jv';
        result.metrics.global_xi_time_failure_reason = result.failure_reason;
        result.metrics.global_xi_time_route_decision = 'fix_global_xi_assembly_before_loading';
        result.summary_metrics = result.metrics;
        result.summary = 'global-xi loading skipped | Jv audit failed';
        return;
    end

    if isfield(options, 'initial_checkpoint') && ~isempty(options.initial_checkpoint)
        [Y_old, state_old, params, grid, initial_checkpoint] = load_or_create_loading_checkpoint(options);
    else
        [Y_old, state_old] = initial_state(params, grid);
        initial_checkpoint = struct();
    end
    time_vec = linspace(0, params.T_load, params.Nt);
    Y_hist = zeros(4 * grid.N, numel(time_vec));
    Y_hist(:, 1) = Y_old;
    q_hist = zeros(1, numel(time_vec));
    ok = true;
    failure_block = '';
    failure_reason = '';
    active_update_count = 0;
    active_oscillation_count = 0;
    projection_count = 0;
    max_line_search = 0;
    max_newton = 0;
    max_abs_delta_xi = 0;
    max_dxi_dt = 0;
    last_terms = struct();
    Y_prevprev = Y_old;
    work_acc = init_work_accumulator(Y_old, loading_pressure(time_vec(1), params), ...
        grid, store_work_history_enabled(params));

    for step = 2:numel(time_vec)
        t_prev = time_vec(step - 1);
        t_curr = time_vec(step);
        q_prev = loading_pressure(t_prev, params);
        q_curr = loading_pressure(t_curr, params);
        q_hist(step) = q_curr;
        step_ctx = build_step_context(t_prev, t_curr, params, Y_old, state_old, grid);
        step_ctx.q_prev = q_prev;
        step_ctx.q_load = q_curr;
        if step > 2
            dt_prev = max(time_vec(step - 1) - time_vec(step - 2), 1.0e-12);
            dt_curr = max(t_curr - t_prev, 1.0e-12);
            step_ctx.initial_guess = project_state(Y_old + (dt_curr / dt_prev) * (Y_old - Y_prevprev), Y_old, grid);
        else
            step_ctx.initial_guess = Y_old;
        end

        [step_ok, Y_new, state_new, step_diag] = solve_one_step(Y_old, state_old, step_ctx, params, grid);
        active_update_count = active_update_count + step_diag.active_set_update_count;
        active_oscillation_count = active_oscillation_count + step_diag.active_set_oscillation_count;
        projection_count = projection_count + step_diag.projection_count;
        max_line_search = max(max_line_search, step_diag.max_line_search);
        max_newton = max(max_newton, step_diag.newton_iter_count);
        max_abs_delta_xi = max(max_abs_delta_xi, step_diag.max_abs_delta_xi);
        max_dxi_dt = max(max_dxi_dt, step_diag.max_dxi_dt);
        last_terms = step_diag.terms;

        if ~step_ok
            ok = false;
            failure_block = step_diag.failure_block;
            failure_reason = step_diag.failure_reason;
            Y_hist(:, step) = Y_new;
            break;
        end

        work_acc = update_work_accumulator(work_acc, q_prev, q_curr, Y_new, grid);
        Y_prevprev = Y_old;
        Y_old = Y_new;
        state_old = state_new;
        Y_hist(:, step) = Y_old;
    end

    last_idx = find(any(abs(Y_hist) > 0, 1) | (1:numel(time_vec)) == 1, 1, 'last');
    if isempty(last_idx)
        last_idx = 1;
    end
    Y_final = Y_hist(:, last_idx);
    metrics = default_time_metrics(params, grid);
    metrics.global_xi_time_available = true;
    metrics.global_xi_time_mode = 'time_loading';
    metrics.global_xi_time_Jv_Ru_err = jv.metrics.global_xi_time_Jv_Ru_err;
    metrics.global_xi_time_Jv_Rw_err = jv.metrics.global_xi_time_Jv_Rw_err;
    metrics.global_xi_time_Jv_RT_err = jv.metrics.global_xi_time_Jv_RT_err;
    metrics.global_xi_time_Jv_Rxi_err = jv.metrics.global_xi_time_Jv_Rxi_err;
    metrics.global_xi_time_trial_max_xi_old = jv.metrics.global_xi_time_trial_max_xi_old;
    metrics.global_xi_time_trial_max_xi = jv.metrics.global_xi_time_trial_max_xi;
    metrics.global_xi_time_trial_min_delta_xi = jv.metrics.global_xi_time_trial_min_delta_xi;
    metrics.global_xi_time_trial_max_delta_xi = jv.metrics.global_xi_time_trial_max_delta_xi;
    metrics.global_xi_time_trial_xi_regression_count = jv.metrics.global_xi_time_trial_xi_regression_count;
    metrics.global_xi_time_reached_Pmax = ok && abs(q_hist(last_idx) - params.Pmax) <= 1.0e-6 * params.Pmax;
    metrics.global_xi_time_final_pressure_MPa = q_hist(last_idx) / 1.0e6;
    metrics.global_xi_time_active_set_update_count = active_update_count;
    metrics.global_xi_time_active_set_oscillation_count = active_oscillation_count;
    metrics.global_xi_time_projection_count = projection_count;
    metrics.global_xi_time_xi_truncation_count = 0;
    metrics.global_xi_time_cache_used = false;
    metrics.global_xi_time_jv_audit_skipped = skip_loading_jv_audit;
    metrics.global_xi_time_max_line_search = max_line_search;
    metrics.global_xi_time_max_newton_iter = max_newton;
    metrics.global_xi_time_max_abs_delta_xi = max_abs_delta_xi;
    metrics.global_xi_time_max_dxi_dt = max_dxi_dt;
    metrics.global_xi_time_failure_block = failure_block;
    metrics.global_xi_time_failure_reason = failure_reason;
    metrics.global_xi_time_route_decision = route_decision_from_audit(metrics, ok);
    metrics = attach_final_metrics(metrics, Y_final, params, grid, last_terms);
    metrics = attach_work_metrics(metrics, work_acc, 'loading', ok);

    result = base_result('round101_global_xi_time_loading_v1');
    result.ok = ok;
    result.failure_reason = failure_reason;
    result.metrics = metrics;
    result.summary_metrics = metrics;
    result.final_state = struct('Y', Y_final, 'time_s', time_vec(last_idx), ...
        'pressure_MPa', metrics.global_xi_time_final_pressure_MPa);
    result.diagnostics_handle.last_terms = last_terms;
    result.diagnostics_handle.initial_checkpoint = initial_checkpoint;
    if ok && isfield(params, 'save_checkpoint_path') && ~isempty(params.save_checkpoint_path)
        checkpoint_path = save_loading_checkpoint(params.save_checkpoint_path, Y_final, state_old, grid, params, metrics);
        result.diagnostics_handle.checkpoint_path = checkpoint_path;
        result.metrics.global_xi_time_checkpoint_path = checkpoint_path;
        result.summary_metrics = result.metrics;
    end
    result.summary = sprintf(['global-xi loading | ok=%d | N=%d Nt=%d | p=%.6f MPa | ' ...
        'w=%.3f mm | avg_xi=%.3f max_xi=%.3f | fail=%s/%s'], ...
        ok, grid.N, params.Nt, metrics.global_xi_time_final_pressure_MPa, ...
        metrics.global_xi_time_max_w_mm, metrics.global_xi_time_avg_xi, ...
        metrics.global_xi_time_max_xi, metrics.global_xi_time_failure_block, ...
        metrics.global_xi_time_failure_reason);
end

function result = run_reverse_jv_audit(options)
    if nargin < 1 || ~isstruct(options)
        options = struct();
    end
    [Y_old, state_old, params, grid, checkpoint] = load_or_create_loading_checkpoint(options);
    Y = representative_reverse_trial_state(Y_old, params, grid);
    t_prev = 0.0;
    t_curr = params.T_unload / max(params.Nt_unload - 1, 1);
    step_ctx = build_unload_step_context(t_prev, t_curr, params, Y, state_old, grid);

    [R, J, terms] = assemble_system(Y, Y_old, state_old, step_ctx, params, grid);
    audit = directional_jv_audit(Y, Y_old, state_old, step_ctx, params, grid, R, J);

    metrics = default_time_metrics(params, grid);
    metrics.global_xi_time_available = true;
    metrics.global_xi_time_mode = 'reverse_jv_audit';
    metrics.global_xi_unload_available = true;
    metrics.reverse_Jv_Ru_err = audit.err_Ru;
    metrics.reverse_Jv_Rw_err = audit.err_Rw;
    metrics.reverse_Jv_RT_err = audit.err_RT;
    metrics.reverse_Jv_Rxi_err = audit.err_Rxi;
    metrics.reverse_failure_block = audit.failure_block;
    metrics.reverse_failure_reason = audit.failure_reason;
    metrics.reverse_checkpoint_path = checkpoint.path;
    metrics.reverse_active_node_count = nnz(step_ctx.active_mask);
    metrics.reverse_lower_bound_node_count = 0;
    metrics.reverse_inactive_node_count = grid.N - metrics.reverse_active_node_count;
    metrics.global_xi_time_residual_norm_Ru = norm(R(1:grid.N));
    metrics.global_xi_time_residual_norm_Rw = norm(R(grid.N + (1:grid.N)));
    metrics.global_xi_time_residual_norm_RT = norm(R(2 * grid.N + (1:grid.N)));
    metrics.global_xi_time_residual_norm_Rxi = norm(R(3 * grid.N + (1:grid.N)));

    result = base_result('round104_global_xi_reverse_jv_audit_v1');
    result.ok = isempty(audit.failure_block);
    result.failure_reason = audit.failure_reason;
    result.metrics = metrics;
    result.summary_metrics = metrics;
    result.diagnostics_handle.audit = audit;
    result.diagnostics_handle.terms = terms;
    result.diagnostics_handle.checkpoint = checkpoint;
    result.summary = sprintf(['global-xi reverse Jv audit | ok=%d | N=%d | active=%d | ' ...
        'err(Ru/Rw/RT/Rxi)=%.3e/%.3e/%.3e/%.3e | fail=%s/%s'], ...
        result.ok, grid.N, nnz(step_ctx.active_mask), audit.err_Ru, audit.err_Rw, ...
        audit.err_RT, audit.err_Rxi, metrics.reverse_failure_block, metrics.reverse_failure_reason);
end

function result = run_unloading(options)
    if nargin < 1 || ~isstruct(options)
        options = struct();
    end
    [Y_old, state_old, params, grid, checkpoint] = load_or_create_loading_checkpoint(options);
    time_vec = linspace(0, params.T_unload, params.Nt_unload);
    Y_hist = zeros(4 * grid.N, numel(time_vec));
    Y_hist(:, 1) = Y_old;
    q_hist = zeros(1, numel(time_vec));
    q_hist(1) = params.Pmax;
    ok = true;
    failure_block = '';
    failure_reason = '';
    active_update_count = 0;
    active_oscillation_count = 0;
    projection_count = 0;
    max_line_search = 0;
    max_newton = 0;
    max_abs_delta_xi = 0;
    max_dxi_dt = 0;
    reverse_active_count = 0;
    reverse_lower_count = 0;
    reverse_inactive_count = 0;
    latent_absorbed_total_J = 0.0;
    last_terms = struct();
    Y_prevprev = Y_old;
    work_acc = init_work_accumulator(Y_old, unloading_pressure(time_vec(1), params), ...
        grid, store_work_history_enabled(params));

    for step = 2:numel(time_vec)
        t_prev = time_vec(step - 1);
        t_curr = time_vec(step);
        q_prev = unloading_pressure(t_prev, params);
        q_curr = unloading_pressure(t_curr, params);
        q_hist(step) = q_curr;
        step_ctx = build_unload_step_context(t_prev, t_curr, params, Y_old, state_old, grid);
        if step > 2
            dt_prev = max(time_vec(step - 1) - time_vec(step - 2), 1.0e-12);
            dt_curr = max(t_curr - t_prev, 1.0e-12);
            step_ctx.initial_guess = project_state(Y_old + (dt_curr / dt_prev) * (Y_old - Y_prevprev), Y_old, grid, step_ctx);
        else
            step_ctx.initial_guess = Y_old;
        end

        [step_ok, Y_new, state_new, step_diag] = solve_one_step(Y_old, state_old, step_ctx, params, grid);
        active_update_count = active_update_count + step_diag.active_set_update_count;
        active_oscillation_count = active_oscillation_count + step_diag.active_set_oscillation_count;
        projection_count = projection_count + step_diag.projection_count;
        max_line_search = max(max_line_search, step_diag.max_line_search);
        max_newton = max(max_newton, step_diag.newton_iter_count);
        max_abs_delta_xi = max(max_abs_delta_xi, step_diag.max_abs_delta_xi);
        max_dxi_dt = max(max_dxi_dt, step_diag.max_dxi_dt);
        if isfield(step_diag, 'terms') && isstruct(step_diag.terms)
            last_terms = step_diag.terms;
            reverse_active_count = reverse_active_count + get_optional_struct_numeric(last_terms, 'reverse_active_node_count', 0);
            reverse_lower_count = reverse_lower_count + get_optional_struct_numeric(last_terms, 'reverse_lower_bound_node_count', 0);
            reverse_inactive_count = reverse_inactive_count + get_optional_struct_numeric(last_terms, 'reverse_inactive_node_count', 0);
            latent_absorbed_total_J = latent_absorbed_total_J + ...
                2.0 * pi * params.t_delta * radial_integral(last_terms.Q_lat * step_ctx.dt, grid);
        end

        if ~step_ok
            ok = false;
            failure_block = step_diag.failure_block;
            failure_reason = step_diag.failure_reason;
            Y_hist(:, step) = Y_new;
            break;
        end

        work_acc = update_work_accumulator(work_acc, q_prev, q_curr, Y_new, grid);
        Y_prevprev = Y_old;
        Y_old = Y_new;
        state_old = state_new;
        Y_hist(:, step) = Y_old;
    end

    last_idx = find(any(abs(Y_hist) > 0, 1) | (1:numel(time_vec)) == 1, 1, 'last');
    if isempty(last_idx)
        last_idx = 1;
    end
    Y_final = Y_hist(:, last_idx);
    metrics = default_time_metrics(params, grid);
    metrics.global_xi_time_available = true;
    metrics.global_xi_time_mode = 'time_unloading';
    metrics.global_xi_unload_available = true;
    metrics.reached_zero_pressure = ok && q_hist(last_idx) <= 1.0e-9 * params.Pmax;
    metrics.reverse_checkpoint_path = checkpoint.path;
    metrics.reverse_active_node_count = reverse_active_count;
    metrics.reverse_lower_bound_node_count = reverse_lower_count;
    metrics.reverse_inactive_node_count = reverse_inactive_count;
    metrics.reverse_failure_block = failure_block;
    metrics.reverse_failure_reason = failure_reason;
    metrics.global_xi_time_failure_block = failure_block;
    metrics.global_xi_time_failure_reason = failure_reason;
    metrics.global_xi_time_final_pressure_MPa = q_hist(last_idx) / 1.0e6;
    metrics.global_xi_time_active_set_update_count = active_update_count;
    metrics.global_xi_time_active_set_oscillation_count = active_oscillation_count;
    metrics.global_xi_time_projection_count = projection_count;
    metrics.global_xi_time_xi_truncation_count = 0;
    metrics.global_xi_time_cache_used = false;
    metrics.global_xi_time_max_line_search = max_line_search;
    metrics.global_xi_time_max_newton_iter = max_newton;
    metrics.global_xi_time_max_abs_delta_xi = max_abs_delta_xi;
    metrics.global_xi_time_max_dxi_dt = max_dxi_dt;
    metrics.latent_absorbed_total_J = latent_absorbed_total_J;
    metrics = attach_unload_metrics(metrics, Y_final, params, grid, last_terms);
    metrics = attach_work_metrics(metrics, work_acc, 'unloading', ok && metrics.reached_zero_pressure);

    result = base_result('round104_global_xi_time_unloading_v1');
    result.ok = ok && metrics.reached_zero_pressure;
    if ~result.ok && isempty(failure_reason)
        failure_reason = 'global_xi_unload_did_not_reach_zero_pressure';
    end
    result.failure_reason = failure_reason;
    result.metrics = metrics;
    result.summary_metrics = metrics;
    result.final_state = struct('Y', Y_final, 'time_s', time_vec(last_idx), ...
        'pressure_MPa', metrics.global_xi_time_final_pressure_MPa);
    result.diagnostics_handle.last_terms = last_terms;
    result.diagnostics_handle.checkpoint = checkpoint;
    if isfield(params, 'save_checkpoint_path') && ~isempty(params.save_checkpoint_path)
        checkpoint_path = save_loading_checkpoint(params.save_checkpoint_path, Y_final, state_old, grid, params, metrics);
        result.diagnostics_handle.checkpoint_path = checkpoint_path;
        result.metrics.global_xi_time_checkpoint_path = checkpoint_path;
        result.summary_metrics = result.metrics;
    end
    result.summary = sprintf(['global-xi unloading | ok=%d | N=%d Nt=%d | p=%.6f MPa | ' ...
        'w_end=%.3f mm | avg_xi_end=%.3e max_xi_end=%.3e | Qabs=%.3e J | fail=%s/%s'], ...
        result.ok, grid.N, params.Nt_unload, metrics.global_xi_time_final_pressure_MPa, ...
        metrics.w_max_unload_end_mm, metrics.avg_xi_unload_end, metrics.max_xi_unload_end, ...
        metrics.latent_absorbed_total_J, metrics.reverse_failure_block, metrics.reverse_failure_reason);
end

function result = run_exchange_restart_balance(options)
    if nargin < 1 || ~isstruct(options)
        options = struct();
    end

    balance_tic = tic;
    source_state = GlobalXi_Checkpoint_To_Simulink_State( ...
        get_struct_field(options, 'source_checkpoint_input', ''));
    exchange_state = GlobalXi_Checkpoint_To_Simulink_State( ...
        get_struct_field(options, 'exchange_checkpoint_input', ''));
    assert_balance_contract(source_state, exchange_state);

    params = merge_params_with_defaults(exchange_state.params);
    grid = ensure_grid_operators(exchange_state.grid, params);
    balance_options = get_struct_field(options, 'balance_options', struct());
    params = apply_restart_balance_numeric_options(params, balance_options);

    stage_name = char(string(get_struct_field(options, 'stage_name', '')));
    boundary_kind = char(string(get_struct_field(options, 'balance_boundary_kind', '')));
    if isempty(boundary_kind)
        boundary_kind = infer_balance_boundary_kind(stage_name);
    end

    N = grid.N;
    Y_exchange = exchange_state.Y(:);
    Y_source = source_state.Y(:);
    state_old = exchange_state.state;
    T_target = Y_exchange(2 * N + (1:N));
    pressure_before_MPa = exchange_state.pressure_MPa;
    if ~isfinite(pressure_before_MPa)
        pressure_before_MPa = source_state.pressure_MPa;
    end
    target_pressure_MPa = get_numeric_field(options, 'target_pressure_MPa', NaN);
    if ~isfinite(target_pressure_MPa)
        if strcmp(boundary_kind, 'cooldown_zero_pressure_free_recovery')
            target_pressure_MPa = 0.0;
        else
            target_pressure_MPa = pressure_before_MPa;
        end
    end

    target_volume = integrate_plate_deflection_volume(Y_source, grid);
    volume_before = integrate_plate_deflection_volume(Y_exchange, grid);
    center_w_before = Y_exchange(N + 1) * 1.0e3;
    max_abs_w_before = max(abs(Y_exchange(N + (1:N)))) * 1.0e3;
    avg_xi_before = area_average(Y_exchange(3 * N + (1:N)), grid);
    max_xi_before = max(Y_exchange(3 * N + (1:N)));

    switch boundary_kind
        case 'hold_closed_hydraulic_volume_simplified'
            [ok, Y_balanced, state_balanced, solve_diag, pressure_after_Pa, constraint_report] = ...
                solve_hold_exchange_balance(Y_exchange, state_old, T_target, ...
                target_volume, max(pressure_before_MPa, 0.0) * 1.0e6, params, grid, balance_options);
            pressure_locked = false;
            hydraulic_volume_locked = true;
        case 'cooldown_zero_pressure_free_recovery'
            pressure_after_Pa = 0.0;
            step_ctx = build_exchange_balance_step_context('unloading', T_target, ...
                pressure_after_Pa, params, grid, balance_options);
            step_ctx.initial_guess = Y_exchange;
            [ok, Y_balanced, state_balanced, solve_diag] = solve_one_step( ...
                Y_exchange, state_old, step_ctx, params, grid);
            constraint_report = struct( ...
                'constraint_kind', 'zero_pressure_free_recovery', ...
                'volume_constraint_rel_error', NaN, ...
                'volume_constraint_abs_error_m3', NaN, ...
                'hold_balance_volume_rel_strict_tol', NaN, ...
                'hold_balance_volume_rel_soft_tol', NaN, ...
                'hydraulic_volume_constraint_strict_ok', false, ...
                'hydraulic_volume_constraint_soft_ok', false, ...
                'hold_balance_acceptance_kind', '', ...
                'hold_balance_acceptance_warning', false, ...
                'pressure_trial_table', struct([]), ...
                'pressure_trial_csv_path', '', ...
                'pressure_search_attempt_count', 1, ...
                'pressure_search_bracketed', false);
            pressure_locked = true;
            hydraulic_volume_locked = false;
        otherwise
            error('GlobalXi_TimeStep_Core:UnknownBalanceBoundary', ...
                'Unsupported restart balance boundary kind: %s', boundary_kind);
    end

    if ~ok
        failure_reason = solve_diag.failure_reason;
        if isempty(failure_reason)
            failure_reason = 'restart_balance_solve_failed';
        end
    else
        failure_reason = '';
    end

    step_ctx_final = build_exchange_balance_step_context( ...
        phase_from_balance_boundary(boundary_kind), T_target, pressure_after_Pa, ...
        params, grid, balance_options);
    step_ctx_final = update_active_set(Y_balanced, state_old, step_ctx_final, params, grid);
    [R_final, ~, terms_final] = assemble_system(Y_balanced, Y_exchange, ...
        state_old, step_ctx_final, params, grid);
    [res_norm, block_norms] = scaled_residual_norm(R_final, params, grid, step_ctx_final.dt);

    T_after = Y_balanced(2 * N + (1:N));
    xi_after = Y_balanced(3 * N + (1:N));
    volume_after = integrate_plate_deflection_volume(Y_balanced, grid);
    dY_exchange_to_balanced = Y_balanced - Y_exchange;
    temperature_error = max(abs(T_after - T_target));

    metrics = default_time_metrics(params, grid);
    metrics.global_xi_time_available = true;
    metrics.global_xi_time_mode = 'exchange_restart_balance';
    metrics.global_xi_time_final_pressure_MPa = pressure_after_Pa / 1.0e6;
    metrics.global_xi_time_failure_block = solve_diag.failure_block;
    metrics.global_xi_time_failure_reason = failure_reason;
    metrics.global_xi_time_active_set_update_count = solve_diag.active_set_update_count;
    metrics.global_xi_time_active_set_oscillation_count = solve_diag.active_set_oscillation_count;
    metrics.global_xi_time_projection_count = solve_diag.projection_count;
    metrics.global_xi_time_max_line_search = solve_diag.max_line_search;
    metrics.global_xi_time_max_newton_iter = solve_diag.newton_iter_count;
    metrics.global_xi_time_max_abs_delta_xi = max(abs(xi_after - Y_exchange(3 * N + (1:N))));
    metrics.global_xi_time_max_dxi_dt = metrics.global_xi_time_max_abs_delta_xi / step_ctx_final.dt;
    metrics = attach_final_metrics(metrics, Y_balanced, params, grid, terms_final);
    metrics.work_signed_J = 0.0;
    metrics.work_complete = ok;
    metrics.work_accepted_step_count = 0;
    metrics.V_deflect_start_m3 = volume_before;
    metrics.V_deflect_end_m3 = volume_after;
    metrics.V_deflect_delta_m3 = volume_after - volume_before;
    metrics.W_load_signed_J = NaN;
    metrics.W_load_input_J = NaN;
    metrics.W_unload_signed_J = NaN;
    metrics.W_unload_recovered_J = NaN;

    checkpoint = exchange_state.checkpoint;
    checkpoint.Y = Y_balanced;
    checkpoint.state = state_balanced;
    checkpoint.params = params;
    checkpoint.grid = grid;
    checkpoint.pressure_MPa = pressure_after_Pa / 1.0e6;
    checkpoint.metrics = metrics;
    checkpoint.restart_balance_strategy = 'stage_boundary_equilibrium_v1';
    checkpoint.restart_balance_boundary_kind = boundary_kind;
    checkpoint.restart_balance_stage_name = stage_name;
    checkpoint.restart_balance_changed = max(abs(dY_exchange_to_balanced)) > 0;
    checkpoint.restart_balance_source_checkpoint = source_state.path;
    checkpoint.restart_balance_exchange_checkpoint = exchange_state.path;
    checkpoint.restart_balance_created_at = char(datetime('now', ...
        'TimeZone', 'local', 'Format', 'yyyy-MM-dd HH:mm:ssXXX'));

    Q_latent_balance_est_J = 2.0 * pi * params.t_delta * radial_integral( ...
        -params.rho * params.ds0 * T_after .* (xi_after - Y_exchange(3 * N + (1:N))), grid);
    report = struct( ...
        'restart_balance_ok', ok, ...
        'balance_ok', ok, ...
        'restart_balance_strategy', 'stage_boundary_equilibrium_v1', ...
        'balance_boundary_kind', boundary_kind, ...
        'pressure_locked', pressure_locked, ...
        'hydraulic_volume_locked', hydraulic_volume_locked, ...
        'target_hydraulic_volume_m3', target_volume, ...
        'hydraulic_volume_before_balance_m3', volume_before, ...
        'hydraulic_volume_after_balance_m3', volume_after, ...
        'hydraulic_volume_delta_m3', volume_after - volume_before, ...
        'hydraulic_volume_constraint_kind', get_struct_field(constraint_report, 'constraint_kind', ''), ...
        'hydraulic_volume_constraint_rel_error', get_numeric_field(constraint_report, 'volume_constraint_rel_error', NaN), ...
        'hydraulic_volume_constraint_abs_error_m3', get_numeric_field(constraint_report, 'volume_constraint_abs_error_m3', NaN), ...
        'hold_balance_volume_rel_strict_tol', get_numeric_field(constraint_report, 'hold_balance_volume_rel_strict_tol', NaN), ...
        'hold_balance_volume_rel_soft_tol', get_numeric_field(constraint_report, 'hold_balance_volume_rel_soft_tol', NaN), ...
        'hydraulic_volume_constraint_strict_ok', get_struct_field(constraint_report, 'hydraulic_volume_constraint_strict_ok', false), ...
        'hydraulic_volume_constraint_soft_ok', get_struct_field(constraint_report, 'hydraulic_volume_constraint_soft_ok', false), ...
        'hold_balance_acceptance_kind', get_struct_field(constraint_report, 'hold_balance_acceptance_kind', ''), ...
        'hold_balance_acceptance_warning', get_struct_field(constraint_report, 'hold_balance_acceptance_warning', false), ...
        'pressure_trial_table', get_struct_field(constraint_report, 'pressure_trial_table', struct([])), ...
        'pressure_trial_csv_path', get_struct_field(constraint_report, 'pressure_trial_csv_path', ''), ...
        'pressure_before_balance_MPa', pressure_before_MPa, ...
        'pressure_after_balance_MPa', pressure_after_Pa / 1.0e6, ...
        'target_pressure_MPa', target_pressure_MPa, ...
        'temperature_locked', true, ...
        'temperature_lock_max_abs_error_K', temperature_error, ...
        'source_to_exchange_max_abs_delta_T', max(abs(Y_exchange(2 * N + (1:N)) - Y_source(2 * N + (1:N)))), ...
        'exchange_to_balanced_max_abs_delta_u', max(abs(dY_exchange_to_balanced(1:N))), ...
        'exchange_to_balanced_max_abs_delta_w', max(abs(dY_exchange_to_balanced(N + (1:N)))), ...
        'exchange_to_balanced_max_abs_delta_T', max(abs(dY_exchange_to_balanced(2 * N + (1:N)))), ...
        'exchange_to_balanced_max_abs_delta_xi', max(abs(dY_exchange_to_balanced(3 * N + (1:N)))), ...
        'source_to_balanced_max_abs_delta_w', max(abs(Y_balanced(N + (1:N)) - Y_source(N + (1:N)))), ...
        'avg_xi_before_balance', avg_xi_before, ...
        'avg_xi_after_balance', area_average(xi_after, grid), ...
        'max_xi_before_balance', max_xi_before, ...
        'max_xi_after_balance', max(xi_after), ...
        'center_w_before_balance_mm', center_w_before, ...
        'center_w_after_balance_mm', Y_balanced(N + 1) * 1.0e3, ...
        'max_abs_w_before_balance_mm', max_abs_w_before, ...
        'max_abs_w_after_balance_mm', max(abs(Y_balanced(N + (1:N)))) * 1.0e3, ...
        'mechanical_residual_norm_after_balance', max(block_norms(1:2)), ...
        'thermal_residual_norm_after_balance', block_norms(3), ...
        'phase_residual_norm_after_balance', block_norms(4), ...
        'scaled_residual_norm_after_balance', res_norm, ...
        'balance_failure_reason', failure_reason, ...
        'balance_retry_used', get_struct_field(constraint_report, 'pressure_search_bracketed', false), ...
        'balance_iteration_count', solve_diag.newton_iter_count, ...
        'balance_active_set_update_count', solve_diag.active_set_update_count, ...
        'balance_projection_count', solve_diag.projection_count, ...
        'balance_walltime_s', toc(balance_tic), ...
        'pressure_search_attempt_count', get_numeric_field(constraint_report, 'pressure_search_attempt_count', NaN), ...
        'Q_latent_balance_est_J', Q_latent_balance_est_J);

    result = base_result('globalxi_exchange_restart_balance_v1');
    result.ok = ok && temperature_error <= get_numeric_field(balance_options, ...
        'temperature_lock_tolerance_K', 1.0e-8);
    if ~result.ok && isempty(failure_reason)
        failure_reason = 'restart_balance_acceptance_failed';
        report.balance_failure_reason = failure_reason;
    end
    report.restart_balance_ok = result.ok;
    report.balance_ok = result.ok;
    result.failure_reason = failure_reason;
    result.metrics = metrics;
    result.summary_metrics = metrics;
    result.final_state = struct('Y', Y_balanced, 'time_s', get_struct_field(exchange_state.checkpoint, 'time_s', NaN), ...
        'pressure_MPa', pressure_after_Pa / 1.0e6);
    result.balanced_checkpoint = checkpoint;
    result.balance_report = report;
    result.diagnostics_handle.terms = terms_final;
    result.diagnostics_handle.R_final = R_final;
    result.diagnostics_handle.block_norms = block_norms;
    result.summary = sprintf('exchange restart balance | ok=%d | %s | %s | p=%.6f MPa | dTlock=%.3e K | dw=%.3e m | dxi=%.3e', ...
        result.ok, boundary_kind, report.hold_balance_acceptance_kind, ...
        pressure_after_Pa / 1.0e6, temperature_error, ...
        report.exchange_to_balanced_max_abs_delta_w, report.exchange_to_balanced_max_abs_delta_xi);
end

function [step_ok, Y_curr, state_curr, diag] = solve_one_step(Y_old, state_old, step_ctx, params, grid)
    if isfield(step_ctx, 'initial_guess') && ~isempty(step_ctx.initial_guess)
        Y_curr = step_ctx.initial_guess;
    else
        Y_curr = Y_old;
    end
    state_curr = state_old;
    step_ok = false;
    diag = empty_step_diag(grid);
    active_mask_prev = false(grid.N, 1);

    for aset_iter = 1:params.active_set_max_iter
        step_ctx = update_active_set(Y_curr, state_old, step_ctx, params, grid);
        if aset_iter > 1 && ~isequal(step_ctx.active_mask, active_mask_prev)
            diag.active_set_update_count = diag.active_set_update_count + 1;
        end
        active_mask_prev = step_ctx.active_mask;

        [newton_ok, Y_candidate, state_candidate, newton_diag] = ...
            newton_solve_fixed_active(Y_curr, Y_old, state_old, step_ctx, params, grid);
        diag = merge_step_diag(diag, newton_diag);
        Y_curr = Y_candidate;
        state_curr = state_candidate;
        if ~newton_ok
            diag.failure_block = newton_diag.failure_block;
            diag.failure_reason = newton_diag.failure_reason;
            return;
        end

        step_ctx_check = update_active_set(Y_curr, state_old, step_ctx, params, grid);
        if isequal(step_ctx_check.active_mask, step_ctx.active_mask)
            step_ok = true;
            return;
        end
        Y_curr = project_state(Y_curr, Y_old, grid, step_ctx);
    end

    diag.active_set_oscillation_count = diag.active_set_oscillation_count + 1;
    diag.failure_block = 'R_xi';
    diag.failure_reason = 'global_xi_active_set_oscillation';
end

function [ok, Y_curr, state_curr, diag] = newton_solve_fixed_active(Y_init, Y_old, state_old, step_ctx, params, grid)
    Y_curr = project_state(Y_init, Y_old, grid, step_ctx);
    state_curr = state_old;
    diag = empty_step_diag(grid);
    ok = false;
    best_norm = inf;
    best_block = '';
    best_reason = '';

    for iter = 1:params.nr_max_iter
        [R, J, terms] = assemble_system(Y_curr, Y_old, state_old, step_ctx, params, grid);
        diag.newton_iter_count = diag.newton_iter_count + 1;
        diag.terms = terms;
        [res_norm, block_norms] = scaled_residual_norm(R, params, grid, step_ctx.dt);
        if res_norm < best_norm
            best_norm = res_norm;
            [~, idx] = max(block_norms);
            best_block = block_name(idx);
        end
        if res_norm <= params.nr_tol
            ok = true;
            state_curr = terms.state_new;
            return;
        end

        [dY, solve_ok] = solve_scaled_linear_system(J, R, params, grid);
        if ~solve_ok
            diag.failure_block = best_block;
            diag.failure_reason = 'global_xi_linear_solve_failed';
            return;
        end
        dY = limit_increment(dY, params, grid);

        accepted = false;
        omega = 1.0;
        for ls = 1:params.line_search_max
            Y_trial_raw = Y_curr + omega * dY;
            [Y_trial, projected] = project_state(Y_trial_raw, Y_old, grid, step_ctx);
            diag.projection_count = diag.projection_count + double(projected);
            [R_trial, ~, terms_trial] = assemble_system(Y_trial, Y_old, state_old, step_ctx, params, grid);
            [trial_norm, ~] = scaled_residual_norm(R_trial, params, grid, step_ctx.dt);
            if isfinite(trial_norm) && trial_norm < (1.0 - 1.0e-4 * omega) * res_norm
                Y_curr = Y_trial;
                state_curr = terms_trial.state_new;
                accepted = true;
                break;
            end
            omega = 0.5 * omega;
        end
        diag.max_line_search = max(diag.max_line_search, ls);
        if ~accepted
            diag.failure_block = best_block;
            diag.failure_reason = 'global_xi_line_search_failed';
            return;
        end
    end

    diag.failure_block = best_block;
    if isempty(diag.failure_block)
        diag.failure_block = 'unknown';
    end
    best_reason = sprintf('global_xi_newton_max_iter_residual_%.3e', best_norm);
    diag.failure_reason = best_reason;
end

function [R, J, terms] = assemble_system(Y, Y_old, state_old, step_ctx, params, grid)
    N = grid.N;
    u = Y(1:N);
    w = Y(N + (1:N));
    T = Y(2 * N + (1:N));
    xi = Y(3 * N + (1:N));
    u_old = Y_old(1:N); %#ok<NASGU>
    w_old = Y_old(N + (1:N)); %#ok<NASGU>
    T_old = Y_old(2 * N + (1:N));
    xi_old = Y_old(3 * N + (1:N));

    [eps_r, eps_theta, w_r, Etheta_u, Epsr_u, Epsr_w] = strain_operators(u, w, grid);
    eps_tr_old = state_old.eps_tr;
    lambda_hat = step_ctx.lambda_hat;
    active_mask = logical(step_ctx.active_mask(:));
    Delta_S = step_ctx.Delta_S;

    sigma = zeros(3, N);
    eps_tr = zeros(N, 3);
    N_r = zeros(N, 1);
    N_theta = zeros(N, 1);
    D_eff = zeros(N, 1);
    dD_dxi = zeros(N, 1);
    C_eff = zeros(N, 1);
    dCeff_dxi = zeros(N, 1);
    k_eff = zeros(N, 1);
    dk_dxi = zeros(N, 1);
    Q_mech = zeros(N, 1);
    Q_lat = zeros(N, 1);
    dNr_deps_r = zeros(N, 1);
    dNr_deps_theta = zeros(N, 1);
    dNr_dT = zeros(N, 1);
    dNr_dxi = zeros(N, 1);
    dNth_deps_r = zeros(N, 1);
    dNth_deps_theta = zeros(N, 1);
    dNth_dT = zeros(N, 1);
    dNth_dxi = zeros(N, 1);
    dQm_deps_r = zeros(N, 1);
    dQm_deps_theta = zeros(N, 1);
    dQm_dT = zeros(N, 1);
    dQm_dxi = zeros(N, 1);
    dQl_dT = zeros(N, 1);
    dQl_dxi = zeros(N, 1);
    dPhi_deps_r = zeros(N, 1);
    dPhi_deps_theta = zeros(N, 1);
    dPhi_dT = zeros(N, 1);
    dPhi_dxi = zeros(N, 1);
    R_xi = zeros(N, 1);

    for i = 1:N
        eps_i = [eps_r(i); eps_theta(i); 0.0];
        xi_i = xi(i);
        xi_old_i = xi_old(i);
        lambda_i = lambda_hat(:, i);
        [local, deriv] = local_quantities(eps_i, T(i), xi_i, xi_old_i, ...
            eps_tr_old(i, :).', lambda_i, params, Delta_S, step_ctx.dt, step_ctx);
        sigma(:, i) = local.sigma;
        eps_tr(i, :) = local.eps_tr.';
        N_r(i) = params.t_delta * local.sigma(1);
        N_theta(i) = params.t_delta * local.sigma(2);
        D_eff(i) = local.props.D_eff;
        dD_dxi(i) = local.dD_dxi;
        C_eff(i) = local.props.rho * local.props.c_eff;
        dCeff_dxi(i) = local.props.rho * local.props.dc_eff_dxi;
        k_eff(i) = local.props.k_eff;
        dk_dxi(i) = local.props.dk_eff_dxi;
        Q_mech(i) = local.Q_mech;
        Q_lat(i) = local.Q_lat;

        dNr_deps_r(i) = params.t_delta * deriv.dsigma_deps_r(1);
        dNr_deps_theta(i) = params.t_delta * deriv.dsigma_deps_theta(1);
        dNr_dT(i) = params.t_delta * deriv.dsigma_dT(1);
        dNr_dxi(i) = params.t_delta * deriv.dsigma_dxi(1);
        dNth_deps_r(i) = params.t_delta * deriv.dsigma_deps_r(2);
        dNth_deps_theta(i) = params.t_delta * deriv.dsigma_deps_theta(2);
        dNth_dT(i) = params.t_delta * deriv.dsigma_dT(2);
        dNth_dxi(i) = params.t_delta * deriv.dsigma_dxi(2);

        dQm_deps_r(i) = deriv.dQ_mech(1);
        dQm_deps_theta(i) = deriv.dQ_mech(2);
        dQm_dT(i) = deriv.dQ_mech(3);
        dQm_dxi(i) = deriv.dQ_mech(4);
        dQl_dT(i) = deriv.dQ_lat(3);
        dQl_dxi(i) = deriv.dQ_lat(4);
        if ~params.include_mechanical_heat
            Q_mech(i) = 0.0;
            dQm_deps_r(i) = 0.0;
            dQm_deps_theta(i) = 0.0;
            dQm_dT(i) = 0.0;
            dQm_dxi(i) = 0.0;
        end
        dPhi_deps_r(i) = deriv.dPhi(1);
        dPhi_deps_theta(i) = deriv.dPhi(2);
        dPhi_dT(i) = deriv.dPhi(3);
        dPhi_dxi(i) = deriv.dPhi(4);

        if is_unloading_step(step_ctx)
            xi_tol = params.xi_bound_tol;
            if active_mask(i)
                if (xi_i >= xi_old_i - xi_tol) && (local.Phi <= 0.0)
                    R_xi(i) = params.Hrev * (xi_i - xi_old_i);
                    dPhi_deps_r(i) = 0.0;
                    dPhi_deps_theta(i) = 0.0;
                    dPhi_dT(i) = 0.0;
                    dPhi_dxi(i) = params.Hrev;
                elseif (xi_i <= xi_tol) && (local.Phi >= 0.0)
                    R_xi(i) = params.Hrev * xi_i;
                    dPhi_deps_r(i) = 0.0;
                    dPhi_deps_theta(i) = 0.0;
                    dPhi_dT(i) = 0.0;
                    dPhi_dxi(i) = params.Hrev;
                else
                    R_xi(i) = local.Phi;
                end
            else
                R_xi(i) = params.Hrev * (xi_i - xi_old_i);
                dPhi_deps_r(i) = 0.0;
                dPhi_deps_theta(i) = 0.0;
                dPhi_dT(i) = 0.0;
                dPhi_dxi(i) = params.Hrev;
            end
        elseif active_mask(i)
            xi_tol = params.xi_bound_tol;
            if (xi_i <= xi_old_i + xi_tol) && (local.Phi_f <= 0.0)
                R_xi(i) = params.Hfor * (xi_i - xi_old_i);
                dPhi_deps_r(i) = 0.0;
                dPhi_deps_theta(i) = 0.0;
                dPhi_dT(i) = 0.0;
                dPhi_dxi(i) = params.Hfor;
            elseif (xi_i >= 1.0 - xi_tol) && (local.Phi_f >= 0.0)
                R_xi(i) = params.Hfor * (xi_i - 1.0);
                dPhi_deps_r(i) = 0.0;
                dPhi_deps_theta(i) = 0.0;
                dPhi_dT(i) = 0.0;
                dPhi_dxi(i) = params.Hfor;
            else
                R_xi(i) = local.Phi_f;
            end
        else
            R_xi(i) = params.Hfor * (xi_i - xi_old_i);
            dPhi_deps_r(i) = 0.0;
            dPhi_deps_theta(i) = 0.0;
            dPhi_dT(i) = 0.0;
            dPhi_dxi(i) = params.Hfor;
        end
    end

    Diag = @(v) spdiags(v(:), 0, N, N);
    r_inv = grid.r_inv;
    L = grid.L;
    D1 = grid.D1;
    D1_wr = D1;
    D1_wr(1, :) = 0;

    lap_w = L * w;
    bending = L * (D_eff .* lap_w);
    flux_w = N_r .* w_r;
    coupling = (D1 + Diag(r_inv)) * flux_w;
    R_u = D1 * N_r + r_inv .* (N_r - N_theta);
    R_w = bending - coupling - step_ctx.q_load;
    diffusion = L * (k_eff .* T);
    R_T = C_eff .* (T - T_old) / step_ctx.dt - diffusion - Q_mech - Q_lat;

    R_u(1) = u(1);
    R_u(N) = u(N);
    R_w(N - 1) = D1(N, :) * w;
    R_w(N) = w(N);
    R_T(N) = (T(N) - T(N - 1)) / grid.dr;

    R = [R_u; R_w; R_T; R_xi];

    dNr_du = Diag(dNr_deps_r) * Epsr_u + Diag(dNr_deps_theta) * Etheta_u;
    dNr_dw = Diag(dNr_deps_r) * Epsr_w;
    dNth_du = Diag(dNth_deps_r) * Epsr_u + Diag(dNth_deps_theta) * Etheta_u;
    dNth_dw = Diag(dNth_deps_r) * Epsr_w;
    J_uu = D1 * dNr_du + Diag(r_inv) * (dNr_du - dNth_du);
    J_uw = D1 * dNr_dw + Diag(r_inv) * (dNr_dw - dNth_dw);
    J_uT = D1 * Diag(dNr_dT) + Diag(r_inv) * (Diag(dNr_dT) - Diag(dNth_dT));
    J_uxi = D1 * Diag(dNr_dxi) + Diag(r_inv) * (Diag(dNr_dxi) - Diag(dNth_dxi));

    div_flux = D1 + Diag(r_inv);
    dFlux_du = Diag(w_r) * dNr_du;
    dFlux_dw = Diag(w_r) * dNr_dw + Diag(N_r) * D1_wr;
    dFlux_dT = Diag(w_r) * Diag(dNr_dT);
    dFlux_dxi = Diag(w_r) * Diag(dNr_dxi);
    J_wu = -div_flux * dFlux_du;
    J_ww = L * Diag(D_eff) * L - div_flux * dFlux_dw;
    J_wT = -div_flux * dFlux_dT;
    J_wxi = L * Diag(dD_dxi .* lap_w) - div_flux * dFlux_dxi;

    J_Tu = -Diag(dQm_deps_r) * Epsr_u - Diag(dQm_deps_theta) * Etheta_u;
    J_Tw = -Diag(dQm_deps_r) * Epsr_w;
    J_TT = Diag(C_eff / step_ctx.dt) - L * Diag(k_eff) - Diag(dQm_dT + dQl_dT);
    J_Txi = Diag(dCeff_dxi .* (T - T_old) / step_ctx.dt) - ...
            L * Diag(dk_dxi .* T) - Diag(dQm_dxi + dQl_dxi);

    J_xiu = Diag(dPhi_deps_r) * Epsr_u + Diag(dPhi_deps_theta) * Etheta_u;
    J_xiw = Diag(dPhi_deps_r) * Epsr_w;
    J_xiT = Diag(dPhi_dT);
    J_xixi = Diag(dPhi_dxi);

    J_uu(1, :) = 0; J_uu(1, 1) = 1;
    J_uu(N, :) = 0; J_uu(N, N) = 1;
    J_uw([1, N], :) = 0;
    J_uT([1, N], :) = 0;
    J_uxi([1, N], :) = 0;

    J_wu(N - 1, :) = 0;
    J_wu(N, :) = 0;
    J_ww(N - 1, :) = D1(N, :);
    J_ww(N, :) = 0; J_ww(N, N) = 1;
    J_wT([N - 1, N], :) = 0;
    J_wxi([N - 1, N], :) = 0;

    J_Tu(N, :) = 0;
    J_Tw(N, :) = 0;
    J_Txi(N, :) = 0;
    J_TT(N, :) = 0;
    J_TT(N, N - 1) = -1 / grid.dr;
    J_TT(N, N) = 1 / grid.dr;

    if isfield(step_ctx, 'temperature_locked') && logical(step_ctx.temperature_locked)
        T_locked = step_ctx.T_locked(:);
        if numel(T_locked) ~= N
            error('GlobalXi_TimeStep_Core:InvalidLockedTemperature', ...
                'Locked temperature vector length must be N=%d.', N);
        end
        R(2 * N + (1:N)) = T - T_locked;
        J_Tu = sparse(N, N);
        J_Tw = sparse(N, N);
        J_TT = speye(N);
        J_Txi = sparse(N, N);
    end

    J = [J_uu, J_uw, J_uT, J_uxi; ...
         J_wu, J_ww, J_wT, J_wxi; ...
         J_Tu, J_Tw, J_TT, J_Txi; ...
         J_xiu, J_xiw, J_xiT, J_xixi];

    terms = struct();
    terms.sigma = sigma;
    terms.eps_tr = eps_tr;
    terms.N_r = N_r;
    terms.N_theta = N_theta;
    terms.Q_mech = Q_mech;
    terms.Q_lat = Q_lat;
    terms.active_mask = active_mask;
    if is_unloading_step(step_ctx)
        terms.reverse_active_node_count = nnz(active_mask);
        terms.reverse_lower_bound_node_count = nnz(xi <= params.xi_bound_tol);
        terms.reverse_inactive_node_count = N - terms.reverse_active_node_count;
    end
    terms.state_new = struct('eps_tr', eps_tr, 'xi', xi, 'lambda_hat', lambda_hat);
end

function [local, deriv] = local_quantities(eps_i, T, xi, xi_old, eps_tr_old, lambda, params, Delta_S, dt, step_ctx)
    if nargin < 10
        step_ctx = struct();
    end
    props = SMA_LocalKinetics('update_properties', xi, params);
    C = props.C_mat;
    nu = params.nu;
    C_shape = [1, nu, 0; nu, 1, 0; 0, 0, (1 - nu) / 2] / (1 - nu ^ 2);
    dE_dxi = props.xi_eff_slope * (params.E_M - params.E_A);
    dC_dxi = dE_dxi * C_shape;
    dalpha_vec = props.dalpha_dxi * [1; 1; 0];
    eps_tr = eps_tr_old + (xi - xi_old) * lambda;
    eps_e = eps_i - eps_tr - props.alpha_vec * (T - params.Tr);
    sigma = C * eps_e;
    dxi_dt = (xi - xi_old) / dt;
    eps_tr_dt = dxi_dt * lambda;
    Q_mech = sigma.' * eps_tr_dt;
    Q_lat = -props.rho * params.ds0 * T * dxi_dt;
    if is_unloading_step(step_ctx)
        drive_r = sigma.' * lambda + 0.5 * sigma.' * Delta_S * sigma + ...
            params.rho * params.ds0 * (T - params.A_s);
        Phi = -drive_r - params.Hrev * (1.0 - xi);
    else
        Phi = SMA_LocalKinetics('forward_transformation_residual_trial', ...
            sigma, T, xi, lambda, Delta_S, params);
    end

    dsigma_deps_r = C(:, 1);
    dsigma_deps_theta = C(:, 2);
    dsigma_dT = -C * props.alpha_vec;
    deps_e_dxi = -lambda - dalpha_vec * (T - params.Tr);
    dsigma_dxi = dC_dxi * eps_e + C * deps_e_dxi;
    if is_unloading_step(step_ctx)
        phi_sigma_grad = -(lambda + Delta_S * sigma);
    else
        phi_sigma_grad = lambda + Delta_S * sigma;
    end

    local = struct();
    local.props = props;
    local.sigma = sigma;
    local.eps_tr = eps_tr;
    local.Q_mech = Q_mech;
    local.Q_lat = Q_lat;
    local.Phi = Phi;
    if is_unloading_step(step_ctx)
        local.Phi_f = NaN;
        local.Phi_r = Phi;
    else
        local.Phi_f = Phi;
        local.Phi_r = NaN;
    end
    local.dD_dxi = dE_dxi * params.t_delta ^ 3 / (12 * (1 - params.nu ^ 2));

    deriv = struct();
    deriv.dsigma_deps_r = dsigma_deps_r;
    deriv.dsigma_deps_theta = dsigma_deps_theta;
    deriv.dsigma_dT = dsigma_dT;
    deriv.dsigma_dxi = dsigma_dxi;
    deriv.dQ_mech = [ ...
        dsigma_deps_r.' * eps_tr_dt, ...
        dsigma_deps_theta.' * eps_tr_dt, ...
        dsigma_dT.' * eps_tr_dt, ...
        dsigma_dxi.' * eps_tr_dt + sigma.' * (lambda / dt)];
    deriv.dQ_lat = [0.0, 0.0, -props.rho * params.ds0 * dxi_dt, -props.rho * params.ds0 * T / dt];
    if is_unloading_step(step_ctx)
        deriv.dPhi = [ ...
            phi_sigma_grad.' * dsigma_deps_r, ...
            phi_sigma_grad.' * dsigma_deps_theta, ...
            phi_sigma_grad.' * dsigma_dT - props.rho * params.ds0, ...
            phi_sigma_grad.' * dsigma_dxi + params.Hrev];
    else
        deriv.dPhi = [ ...
            phi_sigma_grad.' * dsigma_deps_r, ...
            phi_sigma_grad.' * dsigma_deps_theta, ...
            phi_sigma_grad.' * dsigma_dT + props.rho * params.ds0, ...
            phi_sigma_grad.' * dsigma_dxi - params.Hfor];
    end
end

function [params, grid] = setup_problem(options)
    params = default_params();
    fields = fieldnames(options);
    for k = 1:numel(fields)
        params.(fields{k}) = options.(fields{k});
    end
    params.Y_star = (params.M_s + params.M_f - params.A_s - params.A_f) * params.rho * params.ds0 / 4;
    params.Hrev = -params.rho * params.ds0 * (params.A_f - params.A_s);
    grid = make_grid(params.N, params.R);
end

function params = default_params()
    params = struct();
    params.R = 40.0e-3;
    params.t_delta = 0.2e-3;
    params.N = 51;
    params.Nt = 960;
    params.E_A = 35e9;
    params.E_M = 25e9;
    params.nu = 0.30;
    params.H_max = 0.06;
    params.rho = 6500;
    params.c_A = 450;
    params.c_M = 450;
    params.k_A = 18;
    params.k_M = 18;
    params.alpha_A = 1.0e-5;
    params.alpha_M = 1.0e-5;
    params.ds0 = -35;
    params.hc = 0;
    params.Tr = 293;
    params.M_s = 260;
    params.M_f = 250;
    params.A_s = 275;
    params.A_f = 285;
    params.Hfor = 1.1e6;
    params.Pmax = 0.59e6;
    params.T_load = 0.1;
    params.T_unload = 0.1;
    params.Nt_unload = params.Nt;
    params.load_power = 5.0;
    params.unload_power = 5.0;
    params.initial_checkpoint = '';
    params.save_checkpoint_path = '';
    params.xi_floor = 1.0e-6;
    params.xi_bound_tol = 1.0e-9;
    params.nr_tol = 1.0e-6;
    params.nr_max_iter = 30;
    params.line_search_max = 10;
    params.active_set_max_iter = 3;
    params.max_du_step = 2.5e-4;
    params.max_dw_step = 5.0e-4;
    params.max_dT_step = 5.0;
    params.max_dxi_step = 0.04;
    params.store_work_history = false;
    params.include_mechanical_heat = false;
end

function grid = make_grid(N, R)
    r = linspace(0, R, N).';
    dr = r(2) - r(1);
    D1 = sparse(N, N);
    D1(1, 1:3) = [-3, 4, -1] / (2 * dr);
    for i = 2:N-1
        D1(i, i - 1) = -1 / (2 * dr);
        D1(i, i + 1) = 1 / (2 * dr);
    end
    D1(N, N-2:N) = [1, -4, 3] / (2 * dr);

    L = sparse(N, N);
    L(1, 1) = -4 / dr ^ 2;
    L(1, 2) = 4 / dr ^ 2;
    for i = 2:N-1
        ri = r(i);
        L(i, i - 1) = 1 / dr ^ 2 - 1 / (2 * dr * ri);
        L(i, i) = -2 / dr ^ 2;
        L(i, i + 1) = 1 / dr ^ 2 + 1 / (2 * dr * ri);
    end
    L(N, N - 1) = 2 / dr ^ 2;
    L(N, N) = -2 / dr ^ 2;

    grid = struct('N', N, 'R', R, 'r', r, 'dr', dr, 'D1', D1, 'L', L);
    grid.r_inv = zeros(N, 1);
    grid.r_inv(2:N) = 1 ./ r(2:N);
end

function [Y, state] = initial_state(params, grid)
    N = grid.N;
    u = zeros(N, 1);
    w = zeros(N, 1);
    T = params.Tr * ones(N, 1);
    xi = zeros(N, 1);
    Y = [u; w; T; xi];
    state = struct('xi', xi, 'eps_tr', zeros(N, 3), 'lambda_hat', zeros(3, N));
end

function [Y, report] = representative_trial_state(Y_old, params, grid)
    N = grid.N;
    s = grid.r / params.R;
    shape = max(0.0, 1 - s .^ 2);
    u_old = Y_old(1:N);
    w_old = Y_old(N + (1:N));
    T_old = Y_old(2 * N + (1:N));
    xi_old = Y_old(3 * N + (1:N));

    u = u_old + 1.0e-4 * s .* (1 - s);
    w = w_old + 5.0e-3 * shape .^ 2;
    w(N) = 0.0;
    T = T_old + 8.0 * shape;

    dxi_probe = 0.02 * max(0.05, shape);
    xi_unclipped = xi_old + dxi_probe;
    xi = min(xi_unclipped, 1.0);
    xi = max(xi, min(xi_old, 1.0));

    Y = [u; w; T; xi];
    delta_xi = xi - xi_old;
    report = struct( ...
        'trial_state_kind', 'restart_anchored_monotone_loading_probe_v1', ...
        'max_xi_old', max(xi_old), ...
        'max_xi_trial', max(xi), ...
        'min_delta_xi_trial', min(delta_xi), ...
        'max_delta_xi_trial', max(delta_xi), ...
        'xi_trial_clipped_count', nnz(xi_unclipped > 1.0), ...
        'xi_trial_regression_count', nnz(delta_xi < -1.0e-12), ...
        'u_anchored_to_Y_old', true, ...
        'w_anchored_to_Y_old', true, ...
        'T_anchored_to_Y_old', true, ...
        'xi_anchored_to_Y_old', true);
end

function Y = representative_reverse_trial_state(Y_old, params, grid)
    N = grid.N;
    s = grid.r / params.R;
    u_old = Y_old(1:N);
    w_old = Y_old(N + (1:N));
    T_old = Y_old(2 * N + (1:N));
    xi_old = Y_old(3 * N + (1:N));
    shape = max(0, 1 - s .^ 2);
    u = 0.95 * u_old;
    w = 0.95 * w_old;
    T = T_old - 1.5 * shape;
    xi = max(0.0, xi_old - 0.02 * max(0.2, shape));
    Y = [u; w; T; xi];
end

function step_ctx = build_step_context(t_prev, t_curr, params, Y_seed, state_old, grid)
    step_ctx = struct();
    step_ctx.phase = 'loading';
    step_ctx.t_prev = t_prev;
    step_ctx.t_curr = t_curr;
    step_ctx.dt = max(t_curr - t_prev, 1.0e-9);
    step_ctx.q_prev = loading_pressure(t_prev, params);
    step_ctx.q_load = loading_pressure(t_curr, params);
    step_ctx.Delta_S = SMA_LocalKinetics('compliance_matrix', 1.0, params) - ...
                       SMA_LocalKinetics('compliance_matrix', 0.0, params);
    step_ctx.active_mask = false(grid.N, 1);
    step_ctx.lambda_hat = zeros(3, grid.N);
    step_ctx = update_active_set(Y_seed, state_old, step_ctx, params, grid);
end

function step_ctx = build_unload_step_context(t_prev, t_curr, params, Y_seed, state_old, grid)
    step_ctx = struct();
    step_ctx.phase = 'unloading';
    step_ctx.t_prev = t_prev;
    step_ctx.t_curr = t_curr;
    step_ctx.dt = max(t_curr - t_prev, 1.0e-9);
    step_ctx.q_prev = unloading_pressure(t_prev, params);
    step_ctx.q_load = unloading_pressure(t_curr, params);
    step_ctx.Delta_S = SMA_LocalKinetics('compliance_matrix', 1.0, params) - ...
                       SMA_LocalKinetics('compliance_matrix', 0.0, params);
    step_ctx.active_mask = false(grid.N, 1);
    step_ctx.lambda_hat = zeros(3, grid.N);
    step_ctx = update_active_set(Y_seed, state_old, step_ctx, params, grid);
end

function step_ctx = build_exchange_balance_step_context(phase, T_target, q_load, params, grid, balance_options)
    if nargin < 6 || ~isstruct(balance_options)
        balance_options = struct();
    end
    step_ctx = struct();
    step_ctx.phase = char(string(phase));
    step_ctx.t_prev = 0.0;
    step_ctx.t_curr = get_numeric_field(balance_options, 'balance_pseudotime_step_s', ...
        params.T_load / max(params.Nt - 1, 1));
    step_ctx.dt = max(step_ctx.t_curr - step_ctx.t_prev, 1.0e-9);
    step_ctx.q_prev = q_load;
    step_ctx.q_load = q_load;
    step_ctx.Delta_S = SMA_LocalKinetics('compliance_matrix', 1.0, params) - ...
                       SMA_LocalKinetics('compliance_matrix', 0.0, params);
    step_ctx.active_mask = false(grid.N, 1);
    step_ctx.lambda_hat = zeros(3, grid.N);
    step_ctx.temperature_locked = true;
    step_ctx.T_locked = T_target(:);
end

function [ok, Y_best, state_best, diag_best, pressure_best_Pa, report] = solve_hold_exchange_balance( ...
        Y_old, state_old, T_target, target_volume_m3, pressure_ref_Pa, params, grid, balance_options)

    pressure_ref_Pa = max(double(pressure_ref_Pa), 0.0);
    if ~isfinite(pressure_ref_Pa) || pressure_ref_Pa <= 0
        pressure_ref_Pa = params.Pmax;
    end
    pressure_limit_Pa = get_numeric_field(balance_options, 'hold_balance_pressure_upper_factor', 2.5) * params.Pmax;
    pressure_limit_Pa = max(pressure_limit_Pa, pressure_ref_Pa);
    strict_tol = get_numeric_field(balance_options, 'hold_balance_volume_rel_strict_tol', ...
        get_numeric_field(balance_options, 'hold_balance_volume_rel_tol', 5.0e-3));
    soft_tol = get_numeric_field(balance_options, 'hold_balance_volume_rel_soft_tol', 2.0e-2);
    if soft_tol < strict_tol
        error('GlobalXi_TimeStep_Core:InvalidHoldBalanceTolerance', ...
            'hold_balance_volume_rel_soft_tol must be >= strict tolerance.');
    end
    abs_tol = get_numeric_field(balance_options, 'hold_balance_volume_abs_tol_m3', 1.0e-12);
    max_bisect = max(0, round(get_numeric_field(balance_options, 'hold_balance_pressure_bisect_iter', 8)));
    coarse_points = max(3, round(get_numeric_field(balance_options, 'hold_balance_pressure_coarse_points', 9)));
    refine_points = max(0, round(get_numeric_field(balance_options, 'hold_balance_pressure_refine_points', 7)));
    refine_span_factor = get_numeric_field(balance_options, 'hold_balance_pressure_refine_span_factor', 0.15);

    coarse_upper_Pa = min(pressure_limit_Pa, max(1.5 * params.Pmax, pressure_ref_Pa));
    candidate_pressures = unique(max(0.0, min(pressure_limit_Pa, ...
        [linspace(0.0, coarse_upper_Pa, coarse_points), pressure_ref_Pa, ...
         0.75 * pressure_ref_Pa, 1.25 * pressure_ref_Pa, ...
         0.5 * params.Pmax, params.Pmax, 1.5 * params.Pmax, pressure_limit_Pa])));
    trials = repmat(empty_hold_trial(), 1, 0);
    Y_guess = Y_old;
    for idx = 1:numel(candidate_pressures)
        trial = solve_balance_at_pressure(Y_old, state_old, Y_guess, T_target, ...
            candidate_pressures(idx), params, grid, balance_options, target_volume_m3);
        trials(end + 1) = trial; %#ok<AGROW>
        if trial.ok
            Y_guess = trial.Y;
        end
    end

    successful = find([trials.ok]);
    bracketed = false;
    if numel(successful) >= 2
        [~, order] = sort([trials(successful).pressure_Pa]);
        successful = successful(order);
        for idx = 1:(numel(successful) - 1)
            a = trials(successful(idx));
            b = trials(successful(idx + 1));
            if sign(a.volume_error_m3) == 0 || sign(a.volume_error_m3) ~= sign(b.volume_error_m3)
                bracketed = true;
                low = a;
                high = b;
                for iter = 1:max_bisect
                    p_mid = 0.5 * (low.pressure_Pa + high.pressure_Pa);
                    trial = solve_balance_at_pressure(Y_old, state_old, low.Y, ...
                        T_target, p_mid, params, grid, balance_options, target_volume_m3);
                    trials(end + 1) = trial; %#ok<AGROW>
                    if ~trial.ok
                        continue;
                    end
                    if abs(trial.volume_error_m3) <= max(abs_tol, strict_tol * max(abs(target_volume_m3), eps))
                        break;
                    end
                    if sign(trial.volume_error_m3) == sign(low.volume_error_m3)
                        low = trial;
                    else
                        high = trial;
                    end
                end
                break;
            end
        end
    end

    trials = refine_hold_pressure_trials(trials, Y_old, state_old, T_target, ...
        target_volume_m3, pressure_limit_Pa, params, grid, balance_options, ...
        refine_points, refine_span_factor);

    if isempty(successful) && ~any([trials.ok])
        ok = false;
        Y_best = Y_old;
        state_best = state_old;
        diag_best = empty_step_diag(grid);
        diag_best.failure_block = 'restart_balance';
        diag_best.failure_reason = 'hold_balance_all_pressure_trials_failed';
        pressure_best_Pa = pressure_ref_Pa;
        volume_error = NaN;
        strict_ok = false;
        soft_ok = false;
        acceptance_kind = 'no_converged_pressure_trial';
    else
        ok_trials = find([trials.ok]);
        [~, best_local_idx] = min(abs([trials(ok_trials).volume_error_m3]));
        best = trials(ok_trials(best_local_idx));
        Y_best = best.Y;
        state_best = best.state;
        diag_best = best.diag;
        pressure_best_Pa = best.pressure_Pa;
        volume_error = best.volume_error_m3;
        strict_ok = abs(volume_error) <= max(abs_tol, strict_tol * max(abs(target_volume_m3), eps));
        soft_ok = abs(volume_error) <= max(abs_tol, soft_tol * max(abs(target_volume_m3), eps));
        ok = strict_ok || soft_ok;
        if strict_ok
            acceptance_kind = 'strict_volume_proxy_satisfied';
        elseif soft_ok
            acceptance_kind = 'compliant_volume_proxy_accepted';
        else
            acceptance_kind = 'volume_proxy_not_satisfied';
        end
        if ~ok && isempty(diag_best.failure_reason)
            diag_best.failure_block = 'restart_balance';
            diag_best.failure_reason = 'hold_balance_volume_constraint_not_satisfied';
        end
    end

    trial_table = summarize_hold_pressure_trials(trials, target_volume_m3);
    report = struct( ...
        'constraint_kind', 'V_deflect_proxy_closed_hydraulic_volume', ...
        'volume_constraint_abs_error_m3', volume_error, ...
        'volume_constraint_rel_error', abs(volume_error) / max(abs(target_volume_m3), eps), ...
        'hold_balance_volume_rel_strict_tol', strict_tol, ...
        'hold_balance_volume_rel_soft_tol', soft_tol, ...
        'hydraulic_volume_constraint_strict_ok', strict_ok, ...
        'hydraulic_volume_constraint_soft_ok', soft_ok, ...
        'hold_balance_acceptance_kind', acceptance_kind, ...
        'hold_balance_acceptance_warning', soft_ok && ~strict_ok, ...
        'pressure_trial_table', trial_table, ...
        'pressure_trial_csv_path', '', ...
        'pressure_search_attempt_count', numel(trials), ...
        'pressure_search_bracketed', bracketed);
end

function trials = refine_hold_pressure_trials(trials, Y_old, state_old, T_target, target_volume_m3, ...
        pressure_limit_Pa, params, grid, balance_options, refine_points, refine_span_factor)
    ok_trials = find([trials.ok]);
    if isempty(ok_trials) || refine_points <= 0
        return;
    end
    [~, best_local_idx] = min(abs([trials(ok_trials).volume_error_m3]));
    best = trials(ok_trials(best_local_idx));
    existing_pressures = [trials.pressure_Pa];
    if numel(existing_pressures) > 1
        sorted_pressures = unique(existing_pressures(isfinite(existing_pressures)));
        local_spacing = min(abs(sorted_pressures - best.pressure_Pa));
        local_spacing = local_spacing(local_spacing > 0);
        if isempty(local_spacing)
            span = refine_span_factor * params.Pmax;
        else
            span = max(min(local_spacing), refine_span_factor * params.Pmax);
        end
    else
        span = refine_span_factor * params.Pmax;
    end
    refine_pressures = linspace(max(0.0, best.pressure_Pa - span), ...
        min(pressure_limit_Pa, best.pressure_Pa + span), refine_points);
    for idx = 1:numel(refine_pressures)
        if any(abs(existing_pressures - refine_pressures(idx)) <= max(1.0, 1.0e-9 * max(abs(refine_pressures(idx)), 1.0)))
            continue;
        end
        trial = solve_balance_at_pressure(Y_old, state_old, best.Y, T_target, ...
            refine_pressures(idx), params, grid, balance_options, target_volume_m3);
        trials(end + 1) = trial; %#ok<AGROW>
        existing_pressures(end + 1) = refine_pressures(idx); %#ok<AGROW>
        if trial.ok && abs(trial.volume_error_m3) < abs(best.volume_error_m3)
            best = trial;
        end
    end
end

function trial = solve_balance_at_pressure(Y_old, state_old, Y_guess, T_target, pressure_Pa, params, grid, balance_options, target_volume_m3)
    step_ctx = build_exchange_balance_step_context('loading', T_target, pressure_Pa, params, grid, balance_options);
    step_ctx.initial_guess = Y_guess;
    [ok, Y_new, state_new, diag] = solve_one_step(Y_old, state_old, step_ctx, params, grid);
    volume_new = integrate_plate_deflection_volume(Y_new, grid);
    [R_trial, ~, ~] = assemble_system(Y_new, Y_old, state_old, step_ctx, params, grid);
    [res_norm, block_norms] = scaled_residual_norm(R_trial, params, grid, step_ctx.dt);
    xi_new = Y_new(3 * grid.N + (1:grid.N));
    w_new = Y_new(grid.N + (1:grid.N));
    trial = struct( ...
        'ok', ok, ...
        'pressure_Pa', pressure_Pa, ...
        'volume_m3', volume_new, ...
        'volume_error_m3', volume_new - target_volume_m3, ...
        'volume_rel_error', abs(volume_new - target_volume_m3) / max(abs(target_volume_m3), eps), ...
        'center_w_mm', 1.0e3 * w_new(1), ...
        'avg_xi', area_average(xi_new, grid), ...
        'max_xi', max(xi_new), ...
        'mechanical_residual', max(block_norms(1:2)), ...
        'thermal_residual', block_norms(3), ...
        'phase_residual', block_norms(4), ...
        'scaled_residual', res_norm, ...
        'failure_reason', diag.failure_reason, ...
        'Y', Y_new, ...
        'state', state_new, ...
        'diag', diag);
end

function trial = empty_hold_trial()
    trial = struct( ...
        'ok', false, ...
        'pressure_Pa', NaN, ...
        'volume_m3', NaN, ...
        'volume_error_m3', NaN, ...
        'volume_rel_error', NaN, ...
        'center_w_mm', NaN, ...
        'avg_xi', NaN, ...
        'max_xi', NaN, ...
        'mechanical_residual', NaN, ...
        'thermal_residual', NaN, ...
        'phase_residual', NaN, ...
        'scaled_residual', NaN, ...
        'failure_reason', '', ...
        'Y', [], ...
        'state', struct(), ...
        'diag', struct());
end

function trial_table = summarize_hold_pressure_trials(trials, target_volume_m3)
    trial_table = repmat(struct( ...
        'trial_index', NaN, ...
        'trial_pressure_MPa', NaN, ...
        'trial_ok', false, ...
        'trial_volume_m3', NaN, ...
        'trial_volume_error_m3', NaN, ...
        'trial_volume_rel_error', NaN, ...
        'trial_center_w_mm', NaN, ...
        'trial_avg_xi', NaN, ...
        'trial_max_xi', NaN, ...
        'trial_mechanical_residual', NaN, ...
        'trial_phase_residual', NaN, ...
        'trial_scaled_residual', NaN, ...
        'trial_failure_reason', ''), 1, numel(trials));
    for idx = 1:numel(trials)
        rel_error = get_numeric_field(trials(idx), 'volume_rel_error', NaN);
        if ~isfinite(rel_error)
            rel_error = abs(get_numeric_field(trials(idx), 'volume_error_m3', NaN)) / ...
                max(abs(target_volume_m3), eps);
        end
        trial_table(idx).trial_index = idx;
        trial_table(idx).trial_pressure_MPa = trials(idx).pressure_Pa / 1.0e6;
        trial_table(idx).trial_ok = logical(trials(idx).ok);
        trial_table(idx).trial_volume_m3 = trials(idx).volume_m3;
        trial_table(idx).trial_volume_error_m3 = trials(idx).volume_error_m3;
        trial_table(idx).trial_volume_rel_error = rel_error;
        trial_table(idx).trial_center_w_mm = trials(idx).center_w_mm;
        trial_table(idx).trial_avg_xi = trials(idx).avg_xi;
        trial_table(idx).trial_max_xi = trials(idx).max_xi;
        trial_table(idx).trial_mechanical_residual = trials(idx).mechanical_residual;
        trial_table(idx).trial_phase_residual = trials(idx).phase_residual;
        trial_table(idx).trial_scaled_residual = trials(idx).scaled_residual;
        trial_table(idx).trial_failure_reason = trials(idx).failure_reason;
    end
end

function assert_balance_contract(source_state, exchange_state)
    if source_state.N ~= exchange_state.N || numel(source_state.Y) ~= numel(exchange_state.Y)
        error('GlobalXi_TimeStep_Core:BalanceContractMismatch', ...
            'Source/exchange checkpoints do not share the same GlobalXi contract.');
    end
    if any(~isfinite(exchange_state.Y(:)))
        error('GlobalXi_TimeStep_Core:InvalidExchangeCheckpoint', ...
            'Exchange checkpoint contains non-finite Y values.');
    end
end

function boundary_kind = infer_balance_boundary_kind(stage_name)
    switch char(string(stage_name))
        case 'hold_exchange'
            boundary_kind = 'hold_closed_hydraulic_volume_simplified';
        case 'cooldown_exchange'
            boundary_kind = 'cooldown_zero_pressure_free_recovery';
        otherwise
            error('GlobalXi_TimeStep_Core:UnknownBalanceStage', ...
                'Cannot infer restart balance boundary for stage "%s".', char(string(stage_name)));
    end
end

function phase = phase_from_balance_boundary(boundary_kind)
    switch char(string(boundary_kind))
        case 'cooldown_zero_pressure_free_recovery'
            phase = 'unloading';
        otherwise
            phase = 'loading';
    end
end

function params = apply_restart_balance_numeric_options(params, balance_options)
    if ~isstruct(balance_options)
        return;
    end
    option_names = {'nr_tol', 'nr_max_iter', 'line_search_max', ...
        'active_set_max_iter', 'max_du_step', 'max_dw_step', 'max_dxi_step'};
    for idx = 1:numel(option_names)
        name = option_names{idx};
        if isfield(balance_options, name) && ~isempty(balance_options.(name)) && isnumeric(balance_options.(name))
            params.(name) = balance_options.(name);
        end
    end
end

function params = merge_params_with_defaults(params_in)
    params = default_params();
    if ~isstruct(params_in)
        return;
    end
    names = fieldnames(params_in);
    for idx = 1:numel(names)
        params.(names{idx}) = params_in.(names{idx});
    end
    params.Y_star = (params.M_s + params.M_f - params.A_s - params.A_f) * params.rho * params.ds0 / 4;
    params.Hrev = -params.rho * params.ds0 * (params.A_f - params.A_s);
end

function grid = ensure_grid_operators(grid_in, params)
    grid = grid_in;
    if ~isstruct(grid) || ~isfield(grid, 'D1') || ~isfield(grid, 'L') || ~isfield(grid, 'r_inv')
        N = get_numeric_field(grid_in, 'N', params.N);
        R = get_numeric_field(grid_in, 'R', params.R);
        grid = make_grid(N, R);
    end
end

function step_ctx = update_active_set(Y, state_old, step_ctx, params, grid)
    N = grid.N;
    [eps_r, eps_theta] = membrane_strains(Y, grid);
    T = Y(2 * N + (1:N));
    xi_old = state_old.xi(:);
    active = false(N, 1);
    lambda_hat = zeros(3, N);
    for i = 1:N
        eps_i = [eps_r(i); eps_theta(i); 0.0];
        eps_tr_old = state_old.eps_tr(i, :).';
        state_trial = SMA_LocalKinetics('explicit_state_from_xi', ...
            eps_i, T(i), xi_old(i), xi_old(i), eps_tr_old, zeros(3, 1), params);
        if is_unloading_step(step_ctx)
            if xi_old(i) > params.xi_floor && norm(eps_tr_old) > 1.0e-14
                lambda_i = eps_tr_old / max(xi_old(i), params.xi_floor);
            else
                lambda_i = zeros(3, 1);
            end
            drive_r = state_trial.sigma.' * lambda_i + ...
                0.5 * state_trial.sigma.' * step_ctx.Delta_S * state_trial.sigma + ...
                params.rho * params.ds0 * (T(i) - params.A_s);
            phi = -drive_r - params.Hrev * (1.0 - xi_old(i));
            if xi_old(i) > params.xi_floor && phi > 0.0
                active(i) = true;
                lambda_hat(:, i) = lambda_i;
            end
            continue;
        end

        if xi_old(i) > params.xi_floor && norm(eps_tr_old) > 1.0e-14
            lambda_i = eps_tr_old / max(xi_old(i), params.xi_floor);
        else
            lambda_i = SMA_LocalKinetics('transformation_direction', state_trial.sigma, params.H_max);
        end
        phi = SMA_LocalKinetics('forward_transformation_residual_trial', ...
            state_trial.sigma, T(i), xi_old(i), lambda_i, step_ctx.Delta_S, params);
        if phi > 0 || xi_old(i) > params.xi_floor
            active(i) = true;
            lambda_hat(:, i) = lambda_i;
        end
    end
    step_ctx.active_mask = active;
    step_ctx.lambda_hat = lambda_hat;
end

function [eps_r, eps_theta, w_r, Etheta_u, Epsr_u, Epsr_w] = strain_operators(u, w, grid)
    N = grid.N;
    D1 = grid.D1;
    w_r = D1 * w;
    w_r(1) = 0.0;
    eps_r = D1 * u + 0.5 * w_r .^ 2;
    Etheta_u = sparse(N, N);
    Etheta_u(1, :) = D1(1, :);
    for i = 2:N
        Etheta_u(i, i) = 1 / grid.r(i);
    end
    eps_theta = Etheta_u * u;
    eps_theta(1) = eps_r(1);
    Epsr_u = D1;
    Epsr_w = spdiags(w_r, 0, N, N) * D1;
end

function [eps_r, eps_theta] = membrane_strains(Y, grid)
    N = grid.N;
    u = Y(1:N);
    w = Y(N + (1:N));
    [eps_r, eps_theta] = strain_operators(u, w, grid);
end

function [Y, projected] = project_state(Y_in, Y_old, grid, step_ctx)
    if nargin < 4
        step_ctx = struct();
    end
    N = grid.N;
    Y = Y_in;
    projected = false;
    T_idx = 2 * N + (1:N);
    xi_idx = 3 * N + (1:N);
    T = Y(T_idx);
    if isfield(step_ctx, 'temperature_locked') && logical(step_ctx.temperature_locked)
        T_new = step_ctx.T_locked(:);
        if numel(T_new) ~= N
            error('GlobalXi_TimeStep_Core:InvalidLockedTemperature', ...
                'Locked temperature vector length must be N=%d.', N);
        end
    else
        T_new = max(T, 150.0);
    end
    if any(T_new ~= T)
        projected = true;
    end
    xi_old = Y_old(xi_idx);
    xi = Y(xi_idx);
    if is_unloading_step(step_ctx)
        xi_new = min(max(xi, 0.0), xi_old);
    else
        xi_new = min(max(xi, xi_old), 1.0);
    end
    if any(abs(xi_new - xi) > 0)
        projected = true;
    end
    Y(T_idx) = T_new;
    Y(xi_idx) = xi_new;
end

function q = loading_pressure(t, params)
    tau = min(max(t / params.T_load, 0.0), 1.0);
    q = params.Pmax * tau ^ params.load_power;
end

function q = unloading_pressure(t, params)
    tau = min(max(t / params.T_unload, 0.0), 1.0);
    q = params.Pmax * (1.0 - tau) ^ params.unload_power;
end

function audit = directional_jv_audit(Y, Y_old, state_old, step_ctx, params, grid, R, J)
    N = grid.N;
    stream = RandStream('mt19937ar', 'Seed', 10101 + N);
    v = randn(stream, numel(Y), 1);
    v = v / max(norm(v), eps);
    h = 1.0e-7 * max(1.0, norm(Y, inf));
    [Yp, ~] = project_state(Y + h * v, Y_old, grid, step_ctx);
    [Ym, ~] = project_state(Y - h * v, Y_old, grid, step_ctx);
    [Rp, ~] = assemble_system(Yp, Y_old, state_old, step_ctx, params, grid);
    [Rm, ~] = assemble_system(Ym, Y_old, state_old, step_ctx, params, grid);
    fd = (Rp - Rm) / (2 * h);
    Jv = J * v;
    err = Jv - fd;
    audit = struct();
    audit.err_Ru = rel_block(err(1:N), Jv(1:N), fd(1:N));
    audit.err_Rw = rel_block(err(N + (1:N)), Jv(N + (1:N)), fd(N + (1:N)));
    audit.err_RT = rel_block(err(2 * N + (1:N)), Jv(2 * N + (1:N)), fd(2 * N + (1:N)));
    audit.err_Rxi = rel_block(err(3 * N + (1:N)), Jv(3 * N + (1:N)), fd(3 * N + (1:N)));
    audit.failure_block = '';
    audit.failure_reason = '';
    tol_Rw = 5.0e-5;
    tol_Rxi = 5.0e-5;
    tol_RT = 1.0e-5;
    if audit.err_Rw > tol_Rw || audit.err_RT > tol_RT || audit.err_Rxi > tol_Rxi || ...
            any(~isfinite([audit.err_Ru, audit.err_Rw, audit.err_RT, audit.err_Rxi]))
        [~, idx] = max([audit.err_Ru, audit.err_Rw, audit.err_RT, audit.err_Rxi]);
        audit.failure_block = block_name(idx);
        audit.failure_reason = 'global_xi_jv_audit_failed';
    end
    audit.residual_norm = norm(R);
    audit.direction_step_h = h;
end

function value = rel_block(err, Jv, fd)
    value = norm(err) / max([norm(Jv), norm(fd), eps]);
end

function [norm_value, block_norms] = scaled_residual_norm(R, params, grid, dt)
    N = grid.N;
    scale_u = max(params.E_A * params.t_delta / params.R, 1.0);
    scale_w = max(params.Pmax, 1.0);
    scale_T = max(params.rho * params.c_A * 5.0 / max(dt, 1.0e-9), 1.0);
    scale_xi = max(params.Hfor, 1.0);
    block_norms = [ ...
        norm(R(1:N) / scale_u) / sqrt(N), ...
        norm(R(N + (1:N)) / scale_w) / sqrt(N), ...
        norm(R(2 * N + (1:N)) / scale_T) / sqrt(N), ...
        norm(R(3 * N + (1:N)) / scale_xi) / sqrt(N)];
    norm_value = max(block_norms);
end

function [dY, ok] = solve_scaled_linear_system(J, R, params, grid)
    N = grid.N;
    row_scale = [ ...
        (1 / max(params.E_A * params.t_delta / params.R, 1.0)) * ones(N, 1); ...
        (1 / max(params.Pmax, 1.0)) * ones(N, 1); ...
        (1 / max(params.rho * params.c_A * 5.0 / (params.T_load / max(params.Nt - 1, 1)), 1.0)) * ones(N, 1); ...
        (1 / max(params.Hfor, 1.0)) * ones(N, 1)];
    col_scale = [ ...
        params.max_du_step * ones(N, 1); ...
        params.max_dw_step * ones(N, 1); ...
        params.max_dT_step * ones(N, 1); ...
        params.max_dxi_step * ones(N, 1)];
    A = spdiags(row_scale, 0, 4 * N, 4 * N) * J * spdiags(col_scale, 0, 4 * N, 4 * N);
    b = -(row_scale .* R);
    ok = true;
    try
        dz = (A + 1.0e-10 * speye(4 * N)) \ b;
        dY = col_scale .* dz;
    catch
        ok = false;
        dY = zeros(4 * N, 1);
    end
    if any(~isfinite(dY))
        ok = false;
    end
end

function dY = limit_increment(dY, params, grid)
    N = grid.N;
    limits = [ ...
        params.max_du_step * ones(N, 1); ...
        params.max_dw_step * ones(N, 1); ...
        params.max_dT_step * ones(N, 1); ...
        params.max_dxi_step * ones(N, 1)];
    factor = max(1.0, max(abs(dY) ./ limits));
    dY = dY / factor;
end

function metrics = attach_final_metrics(metrics, Y, params, grid, terms)
    if nargin < 5
        terms = struct();
    end
    N = grid.N;
    w = Y(N + (1:N));
    T = Y(2 * N + (1:N));
    xi = Y(3 * N + (1:N));
    metrics.global_xi_time_max_w_mm = max(abs(w)) * 1.0e3;
    metrics.global_xi_time_avg_xi = area_average(xi, grid);
    metrics.global_xi_time_max_xi = max(xi);
    metrics.global_xi_time_T_center_K = T(1);
    metrics.global_xi_time_T_edge_K = T(end);
    metrics.global_xi_time_T_avg_K = mean(T);
    metrics.global_xi_time_Tr = params.Tr;
    metrics.global_xi_time_Hfor = params.Hfor;
    metrics.global_xi_time_forward_Y_star_used = false;
    metrics.global_xi_time_forward_Y_star_value = params.Y_star;
    metrics.global_xi_time_latent_area_avg_J_m3 = area_average(abs(params.rho * params.ds0) * T .* xi, grid);
    metrics.global_xi_time_latent_total_J = 2.0 * pi * params.t_delta * radial_integral(abs(params.rho * params.ds0) * T .* xi, grid);
    if isfield(terms, 'sigma') && ~isempty(terms.sigma)
        sigma = terms.sigma;
        sigma_eq = sqrt(max(sigma(1, :).^2 - sigma(1, :) .* sigma(2, :) + ...
            sigma(2, :).^2 + 3.0 * sigma(3, :).^2, 0.0));
        metrics.global_xi_time_sigma_eq_max_MPa = max(sigma_eq) / 1.0e6;
    end
end

function avg = area_average(values, grid)
    r = grid.r;
    weights = r;
    weights(1) = grid.dr / 4;
    if sum(weights) <= 0
        avg = mean(values);
    else
        avg = sum(values(:) .* weights(:)) / sum(weights);
    end
end

function integral_value = radial_integral(values, grid)
    r = grid.r(:);
    values = values(:);
    if numel(r) < 2
        integral_value = 0.0;
        return;
    end
    integral_value = trapz(r, values .* r);
end

function metrics = attach_unload_metrics(metrics, Y, params, grid, terms)
    if nargin < 5
        terms = struct();
    end
    N = grid.N;
    w = Y(N + (1:N));
    T = Y(2 * N + (1:N));
    xi = Y(3 * N + (1:N));
    metrics.avg_xi_unload_end = area_average(xi, grid);
    metrics.max_xi_unload_end = max(xi);
    metrics.min_xi_unload_end = min(xi);
    metrics.w_max_unload_end_mm = max(abs(w)) * 1.0e3;
    metrics.T_center_unload_end_K = T(1);
    metrics.T_edge_unload_end_K = T(end);
    metrics.T_avg_unload_end_K = mean(T);
    metrics.global_xi_time_avg_xi = metrics.avg_xi_unload_end;
    metrics.global_xi_time_max_xi = metrics.max_xi_unload_end;
    metrics.global_xi_time_max_w_mm = metrics.w_max_unload_end_mm;
    metrics.global_xi_time_T_center_K = T(1);
    metrics.global_xi_time_T_edge_K = T(end);
    metrics.global_xi_time_T_avg_K = mean(T);
    metrics.global_xi_time_latent_area_avg_J_m3 = area_average(abs(params.rho * params.ds0) * T .* xi, grid);
    metrics.global_xi_time_latent_total_J = 2.0 * pi * params.t_delta * radial_integral(abs(params.rho * params.ds0) * T .* xi, grid);
    if isfield(terms, 'sigma') && ~isempty(terms.sigma)
        sigma = terms.sigma;
        sigma_eq = sqrt(max(sigma(1, :).^2 - sigma(1, :) .* sigma(2, :) + ...
            sigma(2, :).^2 + 3.0 * sigma(3, :).^2, 0.0));
        metrics.global_xi_time_sigma_eq_max_MPa = max(sigma_eq) / 1.0e6;
    end
end

function checkpoint_path = save_loading_checkpoint(path_value, Y, state, grid, params, metrics)
    checkpoint_path = char(string(path_value));
    checkpoint_dir = fileparts(checkpoint_path);
    if ~isempty(checkpoint_dir) && ~exist(checkpoint_dir, 'dir')
        mkdir(checkpoint_dir);
    end
    checkpoint = struct();
    checkpoint.Y = Y;
    checkpoint.state = state;
    checkpoint.grid = grid;
    checkpoint.params = params;
    checkpoint.Hfor = params.Hfor;
    checkpoint.forward_Y_star_used = false;
    checkpoint.latent_area_avg_J_m3 = metrics.global_xi_time_latent_area_avg_J_m3;
    checkpoint.pressure_MPa = metrics.global_xi_time_final_pressure_MPa;
    checkpoint.metrics = metrics;
    checkpoint.work_signed_J = metrics.work_signed_J;
    checkpoint.work_complete = metrics.work_complete;
    checkpoint.V_deflect_start_m3 = metrics.V_deflect_start_m3;
    checkpoint.V_deflect_end_m3 = metrics.V_deflect_end_m3;
    checkpoint.W_load_signed_J = metrics.W_load_signed_J;
    checkpoint.W_load_input_J = metrics.W_load_input_J;
    checkpoint.W_unload_signed_J = metrics.W_unload_signed_J;
    checkpoint.W_unload_recovered_J = metrics.W_unload_recovered_J;
    checkpoint.path = checkpoint_path;
    checkpoint.created_at = char(datetime('now', 'TimeZone', 'local', 'Format', 'yyyy-MM-dd HH:mm:ssXXX'));
    save(checkpoint_path, 'checkpoint');
end

function tf = store_work_history_enabled(params)
    tf = isstruct(params) && isfield(params, 'store_work_history') && ...
        ~isempty(params.store_work_history) && logical(params.store_work_history);
end

function work_acc = init_work_accumulator(Y0, P0_Pa, grid, store_history)
    V0 = integrate_plate_deflection_volume(Y0, grid);
    work_acc = struct( ...
        'work_signed_J', 0.0, ...
        'V_deflect_start_m3', V0, ...
        'V_deflect_end_m3', V0, ...
        'accepted_step_count', 0, ...
        'store_history', logical(store_history), ...
        'P_history_Pa', P0_Pa, ...
        'V_history_m3', V0);
    if ~work_acc.store_history
        work_acc.P_history_Pa = [];
        work_acc.V_history_m3 = [];
    end
end

function work_acc = update_work_accumulator(work_acc, P_prev_Pa, P_curr_Pa, Y_curr, grid)
    V_prev = work_acc.V_deflect_end_m3;
    V_curr = integrate_plate_deflection_volume(Y_curr, grid);
    dW = 0.5 * (P_prev_Pa + P_curr_Pa) * (V_curr - V_prev);
    work_acc.work_signed_J = work_acc.work_signed_J + dW;
    work_acc.V_deflect_end_m3 = V_curr;
    work_acc.accepted_step_count = work_acc.accepted_step_count + 1;
    if work_acc.store_history
        work_acc.P_history_Pa(end + 1) = P_curr_Pa;
        work_acc.V_history_m3(end + 1) = V_curr;
    end
end

function metrics = attach_work_metrics(metrics, work_acc, stage_kind, work_complete)
    signed_work = work_acc.work_signed_J;
    metrics.work_signed_J = signed_work;
    metrics.work_complete = logical(work_complete);
    metrics.work_accepted_step_count = work_acc.accepted_step_count;
    metrics.V_deflect_start_m3 = work_acc.V_deflect_start_m3;
    metrics.V_deflect_end_m3 = work_acc.V_deflect_end_m3;
    metrics.V_deflect_delta_m3 = work_acc.V_deflect_end_m3 - work_acc.V_deflect_start_m3;
    metrics.work_sign_convention = 'signed integral of pressure_Pa times dV_deflect_m3';
    metrics.work_cop_convention = ['Use W_total = W_load_input_J + Wpump_J. ' ...
        'Signed unloading work is released hydraulic energy, not additional external input.'];
    metrics.work_history_available = work_acc.store_history;
    metrics.work_history_point_count = 0;
    metrics.work_history_trapz_J = NaN;
    metrics.work_history_online_diff_J = NaN;
    metrics.work_history = struct();
    if work_acc.store_history
        metrics.work_history = struct( ...
            'pressure_Pa', work_acc.P_history_Pa, ...
            'V_deflect_m3', work_acc.V_history_m3);
        metrics.work_history_point_count = numel(work_acc.P_history_Pa);
        if numel(work_acc.P_history_Pa) >= 2
            metrics.work_history_trapz_J = trapz(work_acc.V_history_m3, work_acc.P_history_Pa);
            metrics.work_history_online_diff_J = signed_work - metrics.work_history_trapz_J;
        end
    end

    metrics.W_load_signed_J = NaN;
    metrics.W_load_input_J = NaN;
    metrics.W_unload_signed_J = NaN;
    metrics.W_unload_recovered_J = NaN;
    if strcmp(stage_kind, 'loading')
        metrics.W_load_signed_J = signed_work;
        metrics.W_load_input_J = max(signed_work, 0.0);
    elseif strcmp(stage_kind, 'unloading')
        metrics.W_unload_signed_J = signed_work;
        metrics.W_unload_recovered_J = max(-signed_work, 0.0);
    end
end

function V_deflect_m3 = integrate_plate_deflection_volume(Y, grid)
    N = grid.N;
    w = Y(N + (1:N));
    r = grid.r(:);
    V_deflect_m3 = 2.0 * pi * trapz(r, w(:) .* r);
end

function [Y, state, params, grid, checkpoint] = load_or_create_loading_checkpoint(options)
    if ~isfield(options, 'initial_checkpoint') || isempty(options.initial_checkpoint)
        error('GlobalXi_TimeStep_Core:MissingCheckpoint', 'Unloading requires options.initial_checkpoint.');
    end
    checkpoint_path = char(string(options.initial_checkpoint));
    if ~exist(checkpoint_path, 'file')
        build_options = options;
        build_options.save_checkpoint_path = checkpoint_path;
        if isfield(build_options, 'initial_checkpoint')
            build_options = rmfield(build_options, 'initial_checkpoint');
        end
        loading_result = run_loading(build_options);
        if ~(isfield(loading_result, 'ok') && loading_result.ok)
            error('GlobalXi_TimeStep_Core:CheckpointBuildFailed', ...
                'Could not build loading checkpoint: %s', loading_result.failure_reason);
        end
    end
    data = load(checkpoint_path, 'checkpoint');
    checkpoint = data.checkpoint;
    Y = checkpoint.Y;
    state = checkpoint.state;
    params = checkpoint.params;
    grid = checkpoint.grid;
    fields = fieldnames(options);
    for k = 1:numel(fields)
        name = fields{k};
        if strcmp(name, 'initial_checkpoint')
            continue;
        end
        params.(name) = options.(name);
    end
    if ~isfield(params, 'Nt_unload') || isempty(params.Nt_unload)
        params.Nt_unload = params.Nt;
    end
    params.Y_star = (params.M_s + params.M_f - params.A_s - params.A_f) * params.rho * params.ds0 / 4;
    params.Hrev = -params.rho * params.ds0 * (params.A_f - params.A_s);
    checkpoint.path = checkpoint_path;
end

function value = get_optional_struct_numeric(s, name, default_value)
    if isstruct(s) && isfield(s, name) && isnumeric(s.(name)) && isscalar(s.(name))
        value = double(s.(name));
    else
        value = default_value;
    end
end

function value = get_struct_field(s, name, default_value)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = default_value;
    end
end

function value = get_numeric_field(s, name, default_value)
    if isstruct(s) && isfield(s, name) && isnumeric(s.(name)) && isscalar(s.(name)) && isfinite(s.(name))
        value = double(s.(name));
    else
        value = default_value;
    end
end

function diag = empty_step_diag(grid)
    diag = struct();
    diag.active_set_update_count = 0;
    diag.active_set_oscillation_count = 0;
    diag.projection_count = 0;
    diag.max_line_search = 0;
    diag.newton_iter_count = 0;
    diag.max_abs_delta_xi = 0;
    diag.max_dxi_dt = 0;
    diag.failure_block = '';
    diag.failure_reason = '';
    diag.terms = struct();
    diag.active_node_count = 0 * grid.N;
end

function out = merge_step_diag(out, in)
    out.projection_count = out.projection_count + in.projection_count;
    out.max_line_search = max(out.max_line_search, in.max_line_search);
    out.newton_iter_count = out.newton_iter_count + in.newton_iter_count;
    out.max_abs_delta_xi = max(out.max_abs_delta_xi, in.max_abs_delta_xi);
    out.max_dxi_dt = max(out.max_dxi_dt, in.max_dxi_dt);
    if isfield(in, 'terms')
        out.terms = in.terms;
    end
end

function metrics = default_time_metrics(params, grid)
    metrics = struct();
    metrics.global_xi_time_available = false;
    metrics.global_xi_time_mode = '';
    metrics.global_xi_time_N = grid.N;
    metrics.global_xi_time_Nt = params.Nt;
    metrics.global_xi_time_Nt_unload = params.Nt_unload;
    metrics.global_xi_time_Tr = params.Tr;
    metrics.global_xi_time_Hfor = params.Hfor;
    metrics.global_xi_time_reached_Pmax = false;
    metrics.global_xi_time_final_pressure_MPa = NaN;
    metrics.global_xi_time_max_w_mm = NaN;
    metrics.global_xi_time_avg_xi = NaN;
    metrics.global_xi_time_max_xi = NaN;
    metrics.global_xi_time_T_center_K = NaN;
    metrics.global_xi_time_T_edge_K = NaN;
    metrics.global_xi_time_T_avg_K = NaN;
    metrics.global_xi_time_sigma_eq_max_MPa = NaN;
    metrics.global_xi_time_latent_area_avg_J_m3 = NaN;
    metrics.global_xi_time_latent_total_J = NaN;
    metrics.global_xi_time_forward_Y_star_used = false;
    metrics.global_xi_time_forward_Y_star_value = params.Y_star;
    metrics.global_xi_time_Jv_Ru_err = NaN;
    metrics.global_xi_time_Jv_Rw_err = NaN;
    metrics.global_xi_time_Jv_RT_err = NaN;
    metrics.global_xi_time_Jv_Rxi_err = NaN;
    metrics.global_xi_time_active_set_update_count = NaN;
    metrics.global_xi_time_active_set_oscillation_count = NaN;
    metrics.global_xi_time_projection_count = NaN;
    metrics.global_xi_time_xi_truncation_count = 0;
    metrics.global_xi_time_trial_max_xi_old = NaN;
    metrics.global_xi_time_trial_max_xi = NaN;
    metrics.global_xi_time_trial_min_delta_xi = NaN;
    metrics.global_xi_time_trial_max_delta_xi = NaN;
    metrics.global_xi_time_trial_xi_regression_count = NaN;
    metrics.global_xi_time_cache_used = false;
    metrics.global_xi_time_failure_block = '';
    metrics.global_xi_time_failure_reason = '';
    metrics.global_xi_time_route_decision = '';
    metrics.global_xi_time_active_node_count = NaN;
    metrics.global_xi_time_max_line_search = NaN;
    metrics.global_xi_time_max_newton_iter = NaN;
    metrics.global_xi_time_max_abs_delta_xi = NaN;
    metrics.global_xi_time_max_dxi_dt = NaN;
    metrics.global_xi_time_checkpoint_path = '';
    metrics.work_signed_J = NaN;
    metrics.W_load_signed_J = NaN;
    metrics.W_load_input_J = NaN;
    metrics.W_unload_signed_J = NaN;
    metrics.W_unload_recovered_J = NaN;
    metrics.V_deflect_start_m3 = NaN;
    metrics.V_deflect_end_m3 = NaN;
    metrics.V_deflect_delta_m3 = NaN;
    metrics.work_complete = false;
    metrics.work_accepted_step_count = 0;
    metrics.work_history_available = false;
    metrics.work_history_point_count = 0;
    metrics.work_history_trapz_J = NaN;
    metrics.work_history_online_diff_J = NaN;
    metrics.work_sign_convention = '';
    metrics.work_cop_convention = '';
    metrics.work_history = struct();
    metrics.global_xi_unload_available = false;
    metrics.reached_zero_pressure = false;
    metrics.avg_xi_unload_end = NaN;
    metrics.max_xi_unload_end = NaN;
    metrics.min_xi_unload_end = NaN;
    metrics.w_max_unload_end_mm = NaN;
    metrics.latent_absorbed_total_J = NaN;
    metrics.reverse_active_node_count = NaN;
    metrics.reverse_lower_bound_node_count = NaN;
    metrics.reverse_inactive_node_count = NaN;
    metrics.T_center_unload_end_K = NaN;
    metrics.T_edge_unload_end_K = NaN;
    metrics.T_avg_unload_end_K = NaN;
    metrics.reverse_Jv_Ru_err = NaN;
    metrics.reverse_Jv_Rw_err = NaN;
    metrics.reverse_Jv_RT_err = NaN;
    metrics.reverse_Jv_Rxi_err = NaN;
    metrics.reverse_failure_block = '';
    metrics.reverse_failure_reason = '';
    metrics.reverse_checkpoint_path = '';
end

function result = base_result(contract_version)
    result = struct();
    result.contract_version = contract_version;
    result.ok = false;
    result.failure_reason = '';
    result.summary = '';
    result.metrics = struct();
    result.summary_metrics = struct();
    result.diagnostics_handle = struct();
end

function name = block_name(idx)
    names = {'R_u', 'R_w', 'R_T', 'R_xi'};
    idx = max(1, min(numel(names), idx));
    name = names{idx};
end

function tf = is_unloading_step(step_ctx)
    tf = isstruct(step_ctx) && isfield(step_ctx, 'phase') && strcmp(char(string(step_ctx.phase)), 'unloading');
end

function decision = route_decision_from_audit(metrics, loading_ok)
    if metrics.global_xi_time_Jv_RT_err > 1.0e-3 || metrics.global_xi_time_Jv_Rxi_err > 1.0e-3
        decision = 'fix_global_xi_assembly_before_loading';
    elseif loading_ok && metrics.global_xi_time_reached_Pmax
        decision = 'continue_global_xi_to_difficult_small_grid';
    elseif strcmp(metrics.global_xi_time_failure_block, 'R_xi')
        decision = 'refine_active_set_outer_loop';
    elseif strcmp(metrics.global_xi_time_failure_block, 'R_T')
        decision = 'inspect_global_xi_thermal_residual';
    elseif strcmp(metrics.global_xi_time_failure_block, 'R_u') || strcmp(metrics.global_xi_time_failure_block, 'R_w')
        decision = 'inspect_global_xi_mechanical_block';
    else
        decision = 'global_xi_prototype_ready_for_loading';
    end
end
