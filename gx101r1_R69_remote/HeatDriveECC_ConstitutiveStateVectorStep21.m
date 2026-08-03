function y = HeatDriveECC_ConstitutiveStateVectorStep21(u)
% Simulink vector interface for the coupled 21-node SMA/SE constitutive law.
%
% Input vector:
%   [time_s; T_sma_21; T_se_21; previous_constitutive_state_210]
% Output vector:
%   [Q_sma_constitutive_21_W; Q_se_constitutive_21_W; next_state_210]

    options = get_options();
    N = options.node_count;
    if N ~= 21
        error('HeatDriveECC:ConstitutiveVectorNodeCount', ...
            'Expected 21 nodes, got %d.', N);
    end

    state_width = 10 * N;
    output_width = 2 * N + state_width;
    u = u(:);
    expected_width = 1 + 2 * N + state_width;
    if numel(u) ~= expected_width
        y = zeros(output_width, 1);
        return;
    end

    t_s = max(u(1), 0.0);
    Ta = sanitize_temperature(u(2:(1 + N)), options.system.T0_K, N);
    Tr = sanitize_temperature(u((2 + N):(1 + 2 * N)), options.system.T0_K, N);
    state_vec = u((2 + 2 * N):end);

    state = vector_to_state(state_vec, options, Ta, Tr);
    stage_id = stage_from_time(t_s, options);
    dt_s = constitutive_sample_time(options);
    if t_s <= 0.0
        dt_s = 0.0;
    end

    [state, audit] = HeatDriveECC_ConstitutiveCompatibilityStep51( ...
        state, options, dt_s, stage_id);

    % epsilon_a is the positive recovery-displacement magnitude, whereas
    % epsilon_r is the positive tensile strain.  Their physical stress-work
    % signs are therefore opposite and cancel under Eq. 7/Eq. 8 coupling.
    q_sma_W = -audit.latentA_W_21(:) - audit.mechanicalA_W_21(:);
    q_se_W = -audit.latentR_W_21(:) + audit.mechanicalR_W_21(:);
    next_state = state_to_vector(state);
    y = [q_sma_W; q_se_W; next_state];
end

function options = get_options()
    if evalin('base', 'exist(''EIGHTH_ROUND_OPTIONS'', ''var'')')
        options = evalin('base', 'EIGHTH_ROUND_OPTIONS');
    else
        options = Build_HeatDriveECC_EighthRound_Defaults();
    end
end

function T = sanitize_temperature(values, fallback_K, N)
    T = values(:);
    if numel(T) ~= N || any(~isfinite(T))
        T = fallback_K * ones(N, 1);
    end
end

function dt_s = constitutive_sample_time(options)
    if isfield(options.constitutive, 'simulink_sample_time_s')
        dt_s = options.constitutive.simulink_sample_time_s;
    else
        dt_s = options.simulation.fixed_step_s;
    end
    dt_s = max(dt_s, 0.0);
end

function stage_id = stage_from_time(t_s, options)
    tau = options.schedule.tau_cycle_s;
    if tau <= 0
        stage_id = 1;
        return;
    end
    local_t = mod(t_s, tau);
    ends = options.schedule.stage_end_s(:).';
    stage_id = find(local_t <= ends + 1.0e-12, 1, 'first');
    if isempty(stage_id)
        stage_id = 4;
    end
end

function state = vector_to_state(x, options, Ta, Tr)
    N = options.node_count;
    if numel(x) ~= 10 * N || any(~isfinite(x))
        x = Initialize_HeatDriveECC_ConstitutiveVector21(options);
    end
    state = Initialize_HeatDriveECC_EighthRound_State(options);
    state.Ta_21 = Ta(:);
    state.Tr_21 = Tr(:);
    offset = 0;
    fields = {'xM_a_21','xM_r_21','sigma_a_21','sigma_r_21', ...
        'epsilon_a_21','epsilon_r_21','pai_a_21','pai_r_21', ...
        'r_xi_a_21','r_xi_r_21'};
    for idx = 1:numel(fields)
        state.(fields{idx}) = x((offset + 1):(offset + N));
        offset = offset + N;
    end
    state = sync_legacy_state51_aliases(state);
end

function x = state_to_vector(state)
    fields = {'xM_a_21','xM_r_21','sigma_a_21','sigma_r_21', ...
        'epsilon_a_21','epsilon_r_21','pai_a_21','pai_r_21', ...
        'r_xi_a_21','r_xi_r_21'};
    parts = cell(numel(fields), 1);
    for idx = 1:numel(fields)
        parts{idx} = state.(fields{idx})(:);
    end
    x = vertcat(parts{:});
end

function state = sync_legacy_state51_aliases(state)
    bases = {'Ta','Tr','xM_a','xM_r','sigma_a','sigma_r', ...
        'epsilon_a','epsilon_r','pai_a','pai_r','r_xi_a','r_xi_r'};
    for idx = 1:numel(bases)
        primary = [bases{idx} '_21'];
        legacy = [bases{idx} '_51'];
        if isfield(state, primary)
            state.(legacy) = state.(primary);
        end
    end
end
