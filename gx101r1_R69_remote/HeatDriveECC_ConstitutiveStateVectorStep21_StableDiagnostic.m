function y = HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic(u)
% Isolated diagnostic constitutive step using stable internal substeps.
% The outer Simulink clock and state vector contract remain unchanged.
    options = evalin('base', 'EIGHTH_ROUND_OPTIONS');
    N = options.node_count;
    state_width = 10 * N;
    output_width = 2 * N + state_width;
    u = u(:);
    if numel(u) ~= 1 + 2 * N + state_width
        y = zeros(output_width, 1);
        return;
    end
    t_s = max(u(1), 0.0);
    Ta = u(2:(1 + N));
    Tr = u((2 + N):(1 + 2 * N));
    state = Initialize_HeatDriveECC_EighthRound_State(options);
    state.Ta_21 = Ta(:);
    state.Tr_21 = Tr(:);
    fields = {'xM_a_21','xM_r_21','sigma_a_21','sigma_r_21', ...
        'epsilon_a_21','epsilon_r_21','pai_a_21','pai_r_21','r_xi_a_21','r_xi_r_21'};
    offset = 2 + 2 * N - 1;
    previous = u((offset + 1):(offset + state_width));
    for idx = 1:numel(fields)
        state.(fields{idx}) = previous((idx - 1) * N + (1:N));
    end
    state = sync_legacy_state51_aliases(state);
    stage_id = stage_from_time(t_s, options);
    dt_s = options.constitutive.simulink_sample_time_s;
    [state, audit] = Integrate_HeatDriveECC_StableConstitutiveSample( ...
        state, options, dt_s, stage_id);
    next_state = state_to_vector(state);
    q_sma_W = -audit.latentA_W_21(:) - audit.mechanicalA_W_21(:);
    q_se_W = -audit.latentR_W_21(:) + audit.mechanicalR_W_21(:);
    y = [q_sma_W; q_se_W; next_state];
end

function stage_id = stage_from_time(t_s, options)
    local_t = mod(t_s, options.schedule.tau_cycle_s);
    stage_id = find(local_t < options.schedule.stage_end_s(:).', 1, 'first');
    if isempty(stage_id), stage_id = 4; end
end

function x = state_to_vector(state)
    fields = {'xM_a_21','xM_r_21','sigma_a_21','sigma_r_21', ...
        'epsilon_a_21','epsilon_r_21','pai_a_21','pai_r_21','r_xi_a_21','r_xi_r_21'};
    parts = cellfun(@(name) state.(name)(:), fields, 'UniformOutput', false);
    x = vertcat(parts{:});
end

function state = sync_legacy_state51_aliases(state)
    bases = {'Ta','Tr','xM_a','xM_r','sigma_a','sigma_r', ...
        'epsilon_a','epsilon_r','pai_a','pai_r','r_xi_a','r_xi_r'};
    for idx = 1:numel(bases)
        primary = [bases{idx} '_21'];
        legacy = [bases{idx} '_51'];
        state.(legacy) = state.(primary);
    end
end
