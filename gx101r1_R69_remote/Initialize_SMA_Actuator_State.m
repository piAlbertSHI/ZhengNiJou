function state = Initialize_SMA_Actuator_State(actuator_options)
% Initialize the lumped thermal SMA actuator state.

    if nargin < 1 || isempty(actuator_options)
        options = Build_CoupledSMA_Default_Options();
        actuator_options = options.actuator;
    end

    state = struct();
    state.T_K = get_field(actuator_options, 'T_initial_K', 293.0);
    state.xi = clamp(get_field(actuator_options, 'xi_initial', 1.0), 0.0, 1.0);
    state.epsilon = get_field(actuator_options, 'epsilon_initial', ...
        get_field(actuator_options, 'eps_L', 0.06));
    state.sigma_Pa = NaN;
    state.force_N = NaN;
    state.displacement_m = NaN;
    state.free_strain = NaN;
    state.stiffness_N_per_m = NaN;
    state.heat_input_J = 0.0;
    state.heat_rejected_J = 0.0;
    state.latent_J = 0.0;
    state.mechanical_work_J = 0.0;
    state.time_s = 0.0;
    state.mode = 'initial';

    constitutive = SMA_Actuator_LumpedModel('constitutive', state, actuator_options);
    state = merge_structs(state, constitutive);
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
