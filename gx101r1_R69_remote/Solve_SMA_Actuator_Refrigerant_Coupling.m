function coupling = Solve_SMA_Actuator_Refrigerant_Coupling( ...
        actuator_state, actuator_params, refrigerant_checkpoint, refrigerant_options, coupling_options, stage_mode)
% Solve the first-version actuator/refrigerant mechanical coupling.
%
% Positive actuator force maps to positive refrigerant pressure loading.

    if nargin < 1 || isempty(actuator_state)
        error('Solve_SMA_Actuator_Refrigerant_Coupling:MissingActuatorState', ...
            'actuator_state is required.');
    end
    if nargin < 2 || isempty(actuator_params)
        options = Build_CoupledSMA_Default_Options();
        actuator_params = options.actuator;
    end
    if nargin < 3
        refrigerant_checkpoint = [];
    end
    if nargin < 4 || isempty(refrigerant_options)
        options = Build_CoupledSMA_Default_Options();
        refrigerant_options = options.refrigerant;
    end
    if nargin < 5 || isempty(coupling_options)
        options = Build_CoupledSMA_Default_Options();
        coupling_options = options.coupling;
    end
    if nargin < 6 || isempty(stage_mode)
        stage_mode = 'heating_load';
    end
    stage_mode = lower(char(string(stage_mode)));

    actuator_state = merge_structs(actuator_state, ...
        SMA_Actuator_LumpedModel('constitutive', actuator_state, actuator_params));
    checkpoint_state = load_checkpoint_state(refrigerant_checkpoint);

    area_m2 = resolve_effective_area(coupling_options, refrigerant_options, checkpoint_state);
    pressure_min_MPa = get_field(coupling_options, 'pressure_min_MPa', 0.0);
    pressure_max_MPa = get_field(coupling_options, 'pressure_max_MPa', 0.90);

    force_actuator_free_N = max(get_field(actuator_state, 'force_N', 0.0), 0.0);
    free_displacement_m = max(get_field(actuator_state, 'displacement_m', ...
        get_field(actuator_state, 'free_strain', 0.0) * get_field(actuator_params, 'length_m', 1.0)), 0.0);
    actuator_stiffness_N_per_m = max(get_field(actuator_state, 'stiffness_N_per_m', ...
        SMA_Actuator_LumpedModel('stiffness', actuator_state, actuator_params)), 0.0);
    transmission_ratio = get_field(coupling_options, 'transmission_ratio', 1.0);
    compliance_m_per_Pa = get_field(coupling_options, 'compliance_m_per_Pa', NaN);
    if isfinite(compliance_m_per_Pa) && compliance_m_per_Pa > 0 && actuator_stiffness_N_per_m > 0
        pressure_raw_Pa = actuator_stiffness_N_per_m * free_displacement_m / ...
            max(area_m2 + actuator_stiffness_N_per_m * transmission_ratio * compliance_m_per_Pa, eps);
        pressure_raw_MPa = pressure_raw_Pa / 1.0e6;
    else
        pressure_raw_MPa = force_actuator_free_N / max(area_m2, eps) / 1.0e6;
    end
    pressure_MPa = min(max(pressure_raw_MPa, pressure_min_MPa), pressure_max_MPa);

    current_pressure_MPa = get_field(checkpoint_state, 'pressure_MPa', NaN);
    if is_unload_mode(stage_mode) && logical(get_field(coupling_options, 'monotonic_unload_pressure', true)) && ...
            isfinite(current_pressure_MPa)
        pressure_MPa = min(pressure_MPa, max(current_pressure_MPa, pressure_min_MPa));
    end
    pressure_Pa = pressure_MPa * 1.0e6;

    force_refrigerant_N = pressure_Pa * area_m2;
    displacement_refrigerant_proxy_m = compute_refrigerant_displacement_proxy( ...
        pressure_Pa, checkpoint_state, coupling_options);
    displacement_actuator_m = transmission_ratio * displacement_refrigerant_proxy_m;
    if actuator_stiffness_N_per_m > 0
        force_actuator_N = max(actuator_stiffness_N_per_m * ...
            (free_displacement_m - displacement_actuator_m), 0.0);
    else
        force_actuator_N = force_actuator_free_N;
    end

    residual_force_N = force_actuator_N - force_refrigerant_N;
    residual_displacement_m = displacement_actuator_m - transmission_ratio * displacement_refrigerant_proxy_m;
    force_ref = max([abs(force_actuator_N), abs(force_refrigerant_N), ...
        get_field(coupling_options, 'residual_reference_force_N', 100.0), eps]);
    displacement_ref = max([abs(displacement_actuator_m), ...
        abs(transmission_ratio * displacement_refrigerant_proxy_m), ...
        get_field(coupling_options, 'residual_reference_displacement_m', 1.0e-4), eps]);
    residual_force_norm = abs(residual_force_N) / force_ref;
    residual_displacement_norm = abs(residual_displacement_m) / displacement_ref;
    residual_norm = max(residual_force_norm, residual_displacement_norm);

    pressure_clamped = abs(pressure_raw_MPa - pressure_MPa) > max(1.0e-12, 1.0e-9 * max(abs(pressure_raw_MPa), 1.0));
    finite_values = [pressure_MPa, force_actuator_N, force_refrigerant_N, ...
        displacement_actuator_m, displacement_refrigerant_proxy_m, ...
        residual_force_N, residual_displacement_m, residual_norm];

    coupling = struct();
    coupling.stage_mode = stage_mode;
    coupling.pressure_MPa = pressure_MPa;
    coupling.pressure_Pa = pressure_Pa;
    coupling.pressure_raw_MPa = pressure_raw_MPa;
    coupling.pressure_min_MPa = pressure_min_MPa;
    coupling.pressure_max_MPa = pressure_max_MPa;
    coupling.current_pressure_MPa = current_pressure_MPa;
    coupling.force_actuator_N = force_actuator_N;
    coupling.force_actuator_free_N = force_actuator_free_N;
    coupling.force_refrigerant_N = force_refrigerant_N;
    coupling.displacement_actuator_m = displacement_actuator_m;
    coupling.displacement_actuator_free_m = free_displacement_m;
    coupling.displacement_refrigerant_proxy_m = displacement_refrigerant_proxy_m;
    coupling.actuator_stiffness_N_per_m = actuator_stiffness_N_per_m;
    coupling.transmission_ratio = transmission_ratio;
    coupling.effective_plate_area_m2 = area_m2;
    coupling.residual_force_N = residual_force_N;
    coupling.residual_displacement_m = residual_displacement_m;
    coupling.residual_force_norm = residual_force_norm;
    coupling.residual_displacement_norm = residual_displacement_norm;
    coupling.residual_norm = residual_norm;
    coupling.solver_status = struct( ...
        'ok', all(isfinite(finite_values)) && pressure_MPa >= pressure_min_MPa && pressure_MPa <= pressure_max_MPa, ...
        'method', 'force_to_pressure_with_compliance_displacement_proxy_v1', ...
        'pressure_clamped', pressure_clamped, ...
        'uses_checkpoint_center_w', isfinite(get_field(checkpoint_state, 'center_w_m', NaN)), ...
        'approximation', 'linear_compliance_proxy_no_globalxi_pressure_search');
    coupling.checkpoint_proxy = struct( ...
        'path', get_field(checkpoint_state, 'path', ''), ...
        'center_w_m', get_field(checkpoint_state, 'center_w_m', NaN), ...
        'pressure_MPa', current_pressure_MPa);
end

function area_m2 = resolve_effective_area(coupling_options, refrigerant_options, checkpoint_state)
    area_m2 = get_field(coupling_options, 'effective_plate_area_m2', NaN);
    if isfinite(area_m2) && area_m2 > 0
        return;
    end
    radius_m = get_field(coupling_options, 'plate_radius_m', NaN);
    if ~(isfinite(radius_m) && radius_m > 0)
        solver_options = get_field(refrigerant_options, 'solver_options', struct());
        radius_m = get_field(solver_options, 'R', NaN);
    end
    if ~(isfinite(radius_m) && radius_m > 0)
        params = get_field(checkpoint_state, 'params', struct());
        radius_m = get_field(params, 'R', 40.0e-3);
    end
    area_m2 = pi * radius_m ^ 2;
end

function displacement_m = compute_refrigerant_displacement_proxy(pressure_Pa, checkpoint_state, coupling_options)
    proxy_kind = lower(char(string(get_field(coupling_options, 'displacement_proxy', 'center_w'))));
    switch proxy_kind
        case 'center_w'
            compliance = get_field(coupling_options, 'compliance_m_per_Pa', NaN);
            if isfinite(compliance) && compliance > 0
                displacement_m = compliance * pressure_Pa;
            else
                displacement_m = max(get_field(checkpoint_state, 'center_w_m', 0.0), 0.0);
            end
        case 'checkpoint_center_w'
            displacement_m = max(get_field(checkpoint_state, 'center_w_m', 0.0), 0.0);
        case 'linear_compliance'
            displacement_m = get_field(coupling_options, 'compliance_m_per_Pa', 1.0e-8) * pressure_Pa;
        otherwise
            error('Solve_SMA_Actuator_Refrigerant_Coupling:UnsupportedProxy', ...
                'Unsupported displacement_proxy: %s', proxy_kind);
    end
end

function state = load_checkpoint_state(checkpoint_input)
    state = struct('pressure_MPa', NaN, 'center_w_m', NaN, 'path', '', 'params', struct());
    if nargin < 1 || isempty(checkpoint_input)
        return;
    end
    try
        state_std = GlobalXi_Checkpoint_To_Simulink_State(checkpoint_input);
    catch ME
        if isstruct(checkpoint_input)
            state_std = checkpoint_input;
        else
            rethrow(ME);
        end
    end
    state.pressure_MPa = get_field(state_std, 'pressure_MPa', NaN);
    state.path = get_field(state_std, 'path', '');
    state.params = get_field(state_std, 'params', struct());
    if isstruct(state_std) && isfield(state_std, 'w') && ~isempty(state_std.w)
        w = state_std.w(:);
        state.center_w_m = w(1);
    elseif isstruct(state_std) && isfield(state_std, 'Y') && isfield(state_std, 'N')
        N = state_std.N;
        Y = state_std.Y(:);
        if numel(Y) >= 2 * N
            state.center_w_m = Y(N + 1);
        end
    end
end

function tf = is_unload_mode(stage_mode)
    tf = contains(stage_mode, 'cool') || contains(stage_mode, 'unload');
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
