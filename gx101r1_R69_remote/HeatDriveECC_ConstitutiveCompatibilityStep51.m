function [state, audit] = HeatDriveECC_ConstitutiveCompatibilityStep51(state, options, dt_s, stage_id)
% Eighth-round 21-node constitutive compatibility step.
%
% Stress is solved from current 21-node phase state using paper Eq.6/Eq.7.
% Phase rates use current Ta_21/Tr_21, solved stress, and calibrated kinetics.

    if nargin < 4
        stage_id = state.stage_id;
    end
    N = options.node_count;
    state = normalize_state21(state, N);
    old = solve_compatibility(state, options);
    rates = phase_rates(state, old, options, stage_id);

    old_xA = state.xM_a_21(:);
    old_xR = state.xM_r_21(:);
    state.xM_a_21 = clamp01(old_xA + dt_s .* rates.r_xi_a_21);
    state.xM_r_21 = clamp01(old_xR + dt_s .* rates.r_xi_r_21);
    next = solve_compatibility(state, options);
    rates = phase_rates(state, next, options, stage_id);

    state.sigma_a_21 = next.sigma_a_Pa .* ones(N, 1);
    state.sigma_r_21 = next.sigma_r_Pa .* ones(N, 1);
    state.epsilon_a_21 = next.epsilon_a_21;
    state.epsilon_r_21 = next.epsilon_r_21;
    state.pai_a_21 = rates.pai_a_21;
    state.pai_r_21 = rates.pai_r_21;
    state.r_xi_a_21 = rates.r_xi_a_21;
    state.r_xi_r_21 = rates.r_xi_r_21;

    dxA = state.xM_a_21 - old_xA;
    dxR = state.xM_r_21 - old_xR;
    sma = options.material.SMA;
    se = options.material.SE;
    c = options.constitutive;
    g = options.geometry;
    massA_node = sma.rho_kg_per_m3 * g.S_a_m2 * (g.L_a_m / N);
    massR_node = se.rho_kg_per_m3 * g.S_r_m2 * (g.L_r_m / N);
    latentA_J_21 = -massA_node .* sma.Delta_h_J_per_kg .* dxA;
    latentR_J_21 = -massR_node .* se.Delta_h_J_per_kg .* dxR;
    d_eps_a = next.epsilon_a_21 - old.epsilon_a_21;
    d_eps_r = next.epsilon_r_21 - old.epsilon_r_21;
    mechA_J_21 = next.sigma_a_Pa .* d_eps_a .* g.S_a_m2 .* (g.L_a_m / N);
    stressWorkR_J_21 = next.sigma_r_Pa .* d_eps_r .* g.S_r_m2 .* (g.L_r_m / N);
    phaseWorkR_J_21 = zeros(N, 1);
    loadMask = dxR > 0.0;
    unloadMask = dxR < 0.0;
    phaseWorkR_J_21(loadMask) = ...
        -massR_node .* c.se_loading_work_J_per_kg .* dxR(loadMask);
    phaseWorkR_J_21(unloadMask) = ...
        -massR_node .* c.se_unloading_work_J_per_kg .* dxR(unloadMask);
    mechR_J_21 = stressWorkR_J_21 + phaseWorkR_J_21;

    audit = struct();
    audit.sigma_a_Pa = next.sigma_a_Pa;
    audit.sigma_r_Pa = next.sigma_r_Pa;
    audit.epsilon_a_mean = mean(next.epsilon_a_21);
    audit.epsilon_r_mean = mean(next.epsilon_r_21);
    audit.eq6_scaled = next.eq6_scaled;
    audit.eq7_scaled = next.eq7_scaled;
    audit.force_residual_N = next.force_residual_N;
    audit.disp_residual_m = next.disp_residual_m;
    audit.latentA_J_21 = latentA_J_21;
    audit.latentR_J_21 = latentR_J_21;
    audit.mechanicalA_J_21 = mechA_J_21;
    audit.mechanicalR_J_21 = mechR_J_21;
    audit.stressWorkR_J_21 = stressWorkR_J_21;
    audit.phaseWorkR_J_21 = phaseWorkR_J_21;
    audit.latentA_W_21 = latentA_J_21 ./ max(dt_s, eps);
    audit.latentR_W_21 = latentR_J_21 ./ max(dt_s, eps);
    audit.mechanicalA_W_21 = mechA_J_21 ./ max(dt_s, eps);
    audit.mechanicalR_W_21 = mechR_J_21 ./ max(dt_s, eps);
    audit.stressWorkR_W_21 = stressWorkR_J_21 ./ max(dt_s, eps);
    audit.phaseWorkR_W_21 = phaseWorkR_J_21 ./ max(dt_s, eps);
    audit.latentA_W = sum(audit.latentA_W_21);
    audit.latentR_W = sum(audit.latentR_W_21);
    audit.mechanicalA_W = sum(audit.mechanicalA_W_21);
    audit.mechanicalR_W = sum(audit.mechanicalR_W_21);
    audit.stressWorkR_W = sum(audit.stressWorkR_W_21);
    audit.phaseWorkR_W = sum(audit.phaseWorkR_W_21);
    audit.delta_xM_a_mean = mean(dxA);
    audit.delta_xM_r_mean = mean(dxR);
    audit = sync_legacy_audit51_aliases(audit);
    state = sync_legacy_state51_aliases(state);
end

function c = solve_compatibility(state, options)
    g = options.geometry;
    sma = options.material.SMA;
    se = options.material.SE;
    delta_a_21 = 1.0 - state.xM_a_21(:);
    delta_r_21 = state.xM_r_21(:);
    force_ratio = g.S_r_m2 / g.S_a_m2;
    numerator_m = g.L_a_m .* mean(sma.epsilon_T .* delta_a_21) - ...
        g.L_r_m .* mean(se.epsilon_T .* delta_r_21);
    denominator_m_per_Pa = g.L_a_m .* force_ratio ./ sma.E_m_Pa + ...
        g.L_r_m ./ se.E_m_Pa;
    sigma_r = numerator_m ./ max(denominator_m_per_Pa, eps);
    sigma_a = force_ratio .* sigma_r;
    eps_a = sma.epsilon_T .* delta_a_21 - sigma_a ./ sma.E_m_Pa;
    eps_r = se.epsilon_T .* delta_r_21 + sigma_r ./ se.E_m_Pa;
    force_residual = sigma_a .* g.S_a_m2 - sigma_r .* g.S_r_m2;
    disp_residual = g.L_a_m .* mean(eps_a) - g.L_r_m .* mean(eps_r);
    c = struct();
    c.sigma_a_Pa = sigma_a;
    c.sigma_r_Pa = sigma_r;
    c.epsilon_a_21 = eps_a;
    c.epsilon_r_21 = eps_r;
    c.force_residual_N = force_residual;
    c.disp_residual_m = disp_residual;
    c.eq6_scaled = force_residual ./ max(abs(sigma_r .* g.S_r_m2), 1.0e-9);
    c.eq7_scaled = disp_residual ./ max(abs(g.L_r_m .* mean(eps_r)), 1.0e-9);
end

function rates = phase_rates(state, compatible, options, stage_id)
    sma = options.material.SMA;
    se = options.material.SE;
    c = options.constitutive;
    Ta = state.Ta_21(:);
    Tr = state.Tr_21(:);
    xA = state.xM_a_21(:);
    xR = state.xM_r_21(:);
    sigma_a = compatible.sigma_a_Pa;
    sigma_r = compatible.sigma_r_Pa;
    pai_a = zeros(size(xA));
    pai_r = zeros(size(xR));
    rA = zeros(size(xA));
    rR = zeros(size(xR));

    switch round(stage_id)
        case 1
            % Stage 1: SMA M->A on its reverse start line, while the
            % coupled SE A->M starts on its forward start line.
            pai_a = sma.C_A_Pa_per_K .* (Ta - sma.T_As_K) - sigma_a;
            pai_r = sigma_r - se.C_M_Pa_per_K .* (Tr - se.T_Ms_K);
            reverse_gate_a = smooth_gate(pai_a, c.drive_width_a_Pa);
            forward_gate_r = smooth_gate(pai_r, c.drive_width_r_Pa);
            rA = -c.rate_a_to_A_1_per_s .* reverse_gate_a .* xA;
            rR = c.rate_r_load_1_per_s .* forward_gate_r .* (1.0 - xR);
        case 3
            % Stage 3: SMA A->M on its forward start line, while the
            % coupled SE M->A is released on its reverse start line.
            pai_a = sigma_a - sma.C_M_Pa_per_K .* (Ta - sma.T_Ms_K);
            pai_r = se.C_A_Pa_per_K .* (Tr - se.T_As_K) - sigma_r;
            forward_gate_a = smooth_gate(pai_a, c.drive_width_a_Pa);
            reverse_gate_r = smooth_gate(pai_r, c.drive_width_r_Pa);
            rA = c.rate_a_to_M_1_per_s .* forward_gate_a .* (1.0 - xA);
            rR = -c.rate_r_stage3_unload_1_per_s .* reverse_gate_r .* xR;
        case 4
            % Stage 4 is an exchange stage.  It may remove only residual
            % SE martensite when the instantaneous reverse start line is met.
            pai_r = se.C_A_Pa_per_K .* (Tr - se.T_As_K) - sigma_r;
            reverse_gate_r = smooth_gate(pai_r, c.drive_width_r_Pa);
            rR = -c.rate_r_stage4_unload_1_per_s .* reverse_gate_r .* xR;
    end

    smoothing_rate = get_constitutive_scalar(c, ...
        'phase_front_smoothing_1_per_s', 0.0);
    if smoothing_rate > 0.0
        if any(round(stage_id) == [1, 3])
            rA = rA + smoothing_rate .* phase_laplacian_neumann(xA);
        end
        if any(round(stage_id) == [1, 3, 4])
            rR = rR + smoothing_rate .* phase_laplacian_neumann(xR);
        end
    end

    rA = min(max(rA, -c.max_rate_1_per_s), c.max_rate_1_per_s);
    rR = min(max(rR, -c.max_rate_1_per_s), c.max_rate_1_per_s);
    rates = struct('pai_a_21', pai_a, 'pai_r_21', pai_r, ...
        'r_xi_a_21', rA, 'r_xi_r_21', rR);
end

function gate = smooth_gate(driving_force_Pa, width_Pa)
    gate = 0.5 .* (1.0 + tanh(driving_force_Pa ./ ...
        max(width_Pa, 1.0)));
end

function lap = phase_laplacian_neumann(x)
    x = x(:);
    lap = zeros(size(x));
    if numel(x) < 2
        return;
    end
    lap(1) = x(2) - x(1);
    lap(end) = x(end - 1) - x(end);
    if numel(x) > 2
        lap(2:end - 1) = x(1:end - 2) - 2.0 .* x(2:end - 1) + x(3:end);
    end
end

function value = get_constitutive_scalar(options, field_name, default_value)
    if isstruct(options) && isfield(options, field_name) && ...
            isnumeric(options.(field_name)) && isscalar(options.(field_name)) && ...
            isfinite(options.(field_name))
        value = double(options.(field_name));
    else
        value = default_value;
    end
end

function y = clamp01(x)
    y = min(max(x, 0.0), 1.0);
end

function state = normalize_state21(state, N)
    bases = {'Ta','Tr','xM_a','xM_r','sigma_a','sigma_r', ...
        'epsilon_a','epsilon_r','pai_a','pai_r','r_xi_a','r_xi_r'};
    for idx = 1:numel(bases)
        primary = [bases{idx} '_21'];
        legacy = [bases{idx} '_51'];
        if ~isfield(state, primary) && isfield(state, legacy)
            legacy_values = state.(legacy);
            state.(primary) = legacy_values(:);
        end
        if isfield(state, primary)
            primary_values = state.(primary);
            state.(primary) = primary_values(:);
            if numel(state.(primary)) ~= N
                error('HeatDriveECC:NodeCountMismatch', ...
                    '%s has %d nodes, expected %d.', ...
                    primary, numel(state.(primary)), N);
            end
        end
    end
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

function audit = sync_legacy_audit51_aliases(audit)
    bases = {'latentA_J','latentR_J','mechanicalA_J','mechanicalR_J', ...
        'stressWorkR_J','phaseWorkR_J','latentA_W','latentR_W', ...
        'mechanicalA_W','mechanicalR_W','stressWorkR_W','phaseWorkR_W'};
    for idx = 1:numel(bases)
        primary = [bases{idx} '_21'];
        legacy = [bases{idx} '_51'];
        if isfield(audit, primary)
            audit.(legacy) = audit.(primary);
        end
    end
end
