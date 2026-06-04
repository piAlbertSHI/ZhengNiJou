function varargout = SMA_Actuator_LumpedModel(action, varargin)
% Lumped thermal SMA actuator model for coupled single-stage runs.

    switch lower(char(string(action)))
        case 'constitutive'
            varargout{1} = constitutive_impl(varargin{:});
        case 'phase_target'
            varargout{1} = phase_target_impl(varargin{:});
        case 'thermal_step'
            [varargout{1}, varargout{2}] = thermal_step_impl(varargin{:});
        case 'force_at_displacement'
            varargout{1} = force_at_displacement_impl(varargin{:});
        case 'free_strain'
            varargout{1} = free_strain_impl(varargin{:});
        case 'stiffness'
            varargout{1} = stiffness_impl(varargin{:});
        otherwise
            error('SMA_Actuator_LumpedModel:UnknownAction', ...
                'Unknown actuator action: %s', char(string(action)));
    end
end

function out = constitutive_impl(state, params)
    T_K = get_field(state, 'T_K', get_field(params, 'T_initial_K', 293.0));
    xi = clamp(get_field(state, 'xi', get_field(params, 'xi_initial', 1.0)), 0.0, 1.0);
    epsilon = get_field(state, 'epsilon', get_field(params, 'epsilon_initial', get_field(params, 'eps_L', 0.06)));
    E = effective_E(xi, params);
    alpha = effective_alpha(xi, params);
    eps_tr = get_field(params, 'eps_L', 0.06) * xi;
    sigma_raw = E * (epsilon - eps_tr - alpha * (T_K - get_field(params, 'T_ref_K', 293.0)));
    sigma = clamp(sigma_raw, -get_field(params, 'max_abs_sigma_Pa', inf), ...
        get_field(params, 'max_abs_sigma_Pa', inf));
    area_m2 = get_field(params, 'area_m2', 1.0);
    force_raw = sigma * area_m2;
    force_N = clamp(force_raw, get_field(params, 'min_force_N', -inf), get_field(params, 'max_force_N', inf));
    length_m = get_field(params, 'length_m', 1.0);
    free_strain = free_strain_from_xi(xi, params);

    out = struct();
    out.T_K = T_K;
    out.xi = xi;
    out.epsilon = epsilon;
    out.E_Pa = E;
    out.alpha_1_per_K = alpha;
    out.eps_tr = eps_tr;
    out.sigma_Pa = sigma;
    out.force_N = force_N;
    out.free_strain = free_strain;
    out.displacement_m = length_m * free_strain;
    out.stiffness_N_per_m = stiffness_from_xi(xi, params);
end

function xi_target = phase_target_impl(T_K, params, mode)
    if nargin < 3 || isempty(mode)
        mode = 'auto';
    end
    mode = lower(char(string(mode)));
    switch mode
        case {'heating', 'heating_load', 'actuator_heat_load'}
            xi_target = heating_phase_target(T_K, params);
        case {'cooling', 'cooling_unload', 'actuator_cool_unload'}
            xi_target = cooling_phase_target(T_K, params);
        otherwise
            xi_heat = heating_phase_target(T_K, params);
            xi_cool = cooling_phase_target(T_K, params);
            xi_target = min(max(0.5 * (xi_heat + xi_cool), 0.0), 1.0);
    end
end

function [state_next, report] = thermal_step_impl(state, params, step_options)
    if nargin < 3 || isempty(step_options)
        step_options = struct();
    end

    dt_s = get_field(step_options, 'dt_s', get_field(step_options, 'dt', 0.0));
    if ~(isnumeric(dt_s) && isscalar(dt_s) && isfinite(dt_s) && dt_s >= 0)
        error('SMA_Actuator_LumpedModel:InvalidDt', 'dt_s must be a finite nonnegative scalar.');
    end

    mode = lower(char(string(get_field(step_options, 'mode', 'heating_load'))));
    state = merge_structs(state, constitutive_impl(state, params));
    T0 = state.T_K;
    xi0 = state.xi;
    displacement0 = state.displacement_m;
    force0 = state.force_N;

    [Q_hot_W, Q_cool_W, Q_loss_W] = boundary_heat_rates(T0, params, step_options, mode);
    Q_net_W = Q_hot_W + Q_cool_W - Q_loss_W;
    heat_capacity_J_per_K = max(get_field(params, 'mass_kg', 1.0) * get_field(params, 'cp_J_per_kgK', 500.0), eps);
    T_trial = T0 + dt_s * Q_net_W / heat_capacity_J_per_K;
    T_trial = max(get_field(params, 'T_min_K', 150.0), min(get_field(params, 'T_max_K', 450.0), T_trial));

    xi_target = phase_target_impl(T_trial, params, mode);
    tau_xi_s = get_field(params, 'tau_xi_s', 0.0);
    if tau_xi_s > 0 && dt_s > 0
        relax = 1.0 - exp(-dt_s / tau_xi_s);
    else
        relax = 1.0;
    end
    xi1 = clamp(xi0 + relax * (xi_target - xi0), 0.0, 1.0);
    latent_step_J = get_field(params, 'mass_kg', 1.0) * get_field(params, 'latent_J_per_kg', 0.0) * abs(xi1 - xi0);

    if logical(get_field(params, 'latent_heat_affects_temperature', false)) && latent_step_J > 0
        latent_sign = latent_temperature_sign(mode);
        T_trial = T_trial + latent_sign * latent_step_J / heat_capacity_J_per_K;
    end

    state_next = state;
    state_next.T_K = T_trial;
    state_next.xi = xi1;
    state_next.time_s = get_field(state, 'time_s', 0.0) + dt_s;
    state_next.mode = mode;
    state_next.heat_input_J = get_field(state, 'heat_input_J', 0.0) + max(Q_hot_W, 0.0) * dt_s;
    state_next.heat_rejected_J = get_field(state, 'heat_rejected_J', 0.0) + max(-Q_cool_W, 0.0) * dt_s + max(Q_loss_W, 0.0) * dt_s;
    state_next.latent_J = get_field(state, 'latent_J', 0.0) + latent_step_J;
    state_next = merge_structs(state_next, constitutive_impl(state_next, params));

    displacement1 = state_next.displacement_m;
    force1 = state_next.force_N;
    d_mech_J = 0.5 * (force0 + force1) * (displacement1 - displacement0);
    state_next.mechanical_work_J = get_field(state, 'mechanical_work_J', 0.0) + max(d_mech_J, 0.0);

    report = struct();
    report.mode = mode;
    report.dt_s = dt_s;
    report.T_start_K = T0;
    report.T_end_K = state_next.T_K;
    report.xi_start = xi0;
    report.xi_target = xi_target;
    report.xi_end = state_next.xi;
    report.Q_hot_W = Q_hot_W;
    report.Q_cool_W = Q_cool_W;
    report.Q_loss_W = Q_loss_W;
    report.Q_net_W = Q_net_W;
    report.heat_input_step_J = max(Q_hot_W, 0.0) * dt_s;
    report.heat_rejected_step_J = max(-Q_cool_W, 0.0) * dt_s + max(Q_loss_W, 0.0) * dt_s;
    report.latent_step_J = latent_step_J;
    report.mechanical_work_step_J = max(d_mech_J, 0.0);
    report.force_start_N = force0;
    report.force_end_N = force1;
    report.displacement_start_m = displacement0;
    report.displacement_end_m = displacement1;
    report.finite = all(isfinite([state_next.T_K, state_next.xi, state_next.sigma_Pa, ...
        state_next.force_N, state_next.displacement_m, state_next.mechanical_work_J]));
end

function out = force_at_displacement_impl(state, params, displacement_m)
    if nargin < 3 || isempty(displacement_m)
        displacement_m = get_field(state, 'displacement_m', 0.0);
    end
    state_eval = state;
    length_m = max(get_field(params, 'length_m', 1.0), eps);
    state_eval.epsilon = displacement_m / length_m;
    out = constitutive_impl(state_eval, params);
end

function value = free_strain_impl(state_or_xi, params)
    if isstruct(state_or_xi)
        xi = get_field(state_or_xi, 'xi', 1.0);
    else
        xi = state_or_xi;
    end
    value = free_strain_from_xi(xi, params);
end

function value = stiffness_impl(state_or_xi, params)
    if isstruct(state_or_xi)
        xi = get_field(state_or_xi, 'xi', 1.0);
    else
        xi = state_or_xi;
    end
    value = stiffness_from_xi(xi, params);
end

function [Q_hot_W, Q_cool_W, Q_loss_W] = boundary_heat_rates(T_K, params, step_options, mode)
    heat_input_W = get_field(step_options, 'heat_input_W', get_field(params, 'heat_input_W', 0.0));
    hot_G = get_field(step_options, 'hot_side_G_W_per_K', get_field(params, 'hot_side_G_W_per_K', 0.0));
    cool_G = get_field(step_options, 'cool_side_G_W_per_K', get_field(params, 'cool_side_G_W_per_K', 0.0));
    loss_G = get_field(step_options, 'loss_G_W_per_K', get_field(params, 'loss_G_W_per_K', 0.0));
    T_hot = get_field(step_options, 'T_hot_K', get_field(params, 'T_hot_K', T_K));
    T_cold = get_field(step_options, 'T_cold_K', get_field(params, 'T_cold_K', T_K));
    T_amb = get_field(step_options, 'ambient_T_K', get_field(params, 'ambient_T_K', T_cold));

    switch mode
        case {'heating', 'heating_load', 'actuator_heat_load'}
            Q_hot_W = max(heat_input_W, 0.0) + hot_G * max(T_hot - T_K, 0.0);
            Q_cool_W = 0.0;
        case {'cooling', 'cooling_unload', 'actuator_cool_unload'}
            Q_hot_W = 0.0;
            Q_cool_W = cool_G * (T_cold - T_K);
        otherwise
            Q_hot_W = max(heat_input_W, 0.0);
            Q_cool_W = cool_G * (T_cold - T_K);
    end
    Q_loss_W = loss_G * max(T_K - T_amb, 0.0);
end

function xi_target = heating_phase_target(T_K, params)
    A_s = get_field(params, 'A_s_K', 315.0);
    A_f = get_field(params, 'A_f_K', 340.0);
    if T_K <= A_s
        xi_target = 1.0;
    elseif T_K >= A_f
        xi_target = 0.0;
    else
        xi_target = 1.0 - (T_K - A_s) / max(A_f - A_s, eps);
    end
    xi_target = clamp(xi_target, 0.0, 1.0);
end

function xi_target = cooling_phase_target(T_K, params)
    M_s = get_field(params, 'M_s_K', 315.0);
    M_f = get_field(params, 'M_f_K', 290.0);
    if T_K >= M_s
        xi_target = 0.0;
    elseif T_K <= M_f
        xi_target = 1.0;
    else
        xi_target = (M_s - T_K) / max(M_s - M_f, eps);
    end
    xi_target = clamp(xi_target, 0.0, 1.0);
end

function sign_value = latent_temperature_sign(mode)
    switch mode
        case {'heating', 'heating_load', 'actuator_heat_load'}
            sign_value = -1.0;
        case {'cooling', 'cooling_unload', 'actuator_cool_unload'}
            sign_value = 1.0;
        otherwise
            sign_value = 0.0;
    end
end

function E = effective_E(xi, params)
    E = get_field(params, 'E_A_Pa', 35.0e9) + clamp(xi, 0.0, 1.0) * ...
        (get_field(params, 'E_M_Pa', 25.0e9) - get_field(params, 'E_A_Pa', 35.0e9));
end

function alpha = effective_alpha(xi, params)
    alpha = get_field(params, 'alpha_A_1_per_K', 1.0e-5) + clamp(xi, 0.0, 1.0) * ...
        (get_field(params, 'alpha_M_1_per_K', 1.0e-5) - get_field(params, 'alpha_A_1_per_K', 1.0e-5));
end

function value = free_strain_from_xi(xi, params)
    value = get_field(params, 'eps_L', 0.06) * (1.0 - clamp(xi, 0.0, 1.0));
end

function value = stiffness_from_xi(xi, params)
    value = effective_E(xi, params) * get_field(params, 'area_m2', 1.0) / ...
        max(get_field(params, 'length_m', 1.0), eps);
end

function out = merge_structs(out, in)
    names = fieldnames(in);
    for idx = 1:numel(names)
        out.(names{idx}) = in.(names{idx});
    end
end

function value = get_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end

function value = clamp(value, lo, hi)
    value = min(max(value, lo), hi);
end
