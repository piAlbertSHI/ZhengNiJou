function [next_state, audit] = HeatDriveECC_ConstitutiveCompatibilityStep(state, options, dt_s, stage_id)
% Advance the seventh-round axial SMA/SE constitutive state by one step.
%
% Inputs are explicit 51-node state variables. Stress is solved from paper
% Eq.6 force balance and Eq.7 displacement compatibility; it is not supplied
% by a stage profile or a prescribed load trajectory.

    if nargin < 2 || isempty(options)
        options = Build_HeatDriveECC_SeventhRound_Defaults();
    end
    if nargin < 3 || isempty(dt_s)
        dt_s = 0.0;
    end
    if nargin < 4 || isempty(stage_id)
        stage_id = state.stage_id;
    end

    state = normalize_state(state, options);
    stage_id = round(stage_id);
    dt_s = max(dt_s, 0.0);

    old = solve_compatibility(state, options);
    rates = phase_rates(state, old, options, stage_id);

    next_state = state;
    next_state.xM_a_51 = clamp01(state.xM_a_51 + dt_s .* rates.r_xi_a_51);
    next_state.xM_r_51 = clamp01(state.xM_r_51 + dt_s .* rates.r_xi_r_51);

    if isfield(state, 'time_s')
        next_state.time_s = state.time_s + dt_s;
    else
        next_state.time_s = dt_s;
    end
    next_state.stage_id = stage_id;

    next = solve_compatibility(next_state, options);
    rates = phase_rates(next_state, next, options, stage_id);
    next_state.sigma_a_51 = next.sigma_a_Pa .* ones(options.node_count, 1);
    next_state.sigma_r_51 = next.sigma_r_Pa .* ones(options.node_count, 1);
    next_state.epsilon_a_51 = next.epsilon_a_51;
    next_state.epsilon_r_51 = next.epsilon_r_51;
    next_state.pai_a_51 = rates.pai_a_Pa_51;
    next_state.pai_r_51 = rates.pai_r_Pa_51;
    next_state.r_xi_a_51 = rates.r_xi_a_51;
    next_state.r_xi_r_51 = rates.r_xi_r_51;
    next_state.q_latent_a_W_per_m3_51 = rates.q_latent_a_W_per_m3_51;
    next_state.q_latent_r_W_per_m3_51 = rates.q_latent_r_W_per_m3_51;

    dxR_mean = mean(next_state.xM_r_51 - state.xM_r_51);
    dT_se = 0.0;
    adiabaticR_J = 0.0;
    if options.constitutive.adiabatic_se_temperature_enabled && dt_s > 0
        se = options.material.SE;
        work_J_per_kg = options.constitutive.se_loading_work_J_per_kg;
        if dxR_mean < 0
            work_J_per_kg = options.constitutive.se_unloading_work_J_per_kg;
        end
        dT_se = dxR_mean .* (se.Delta_h_J_per_kg + work_J_per_kg) ./ ...
            max(se.cp_J_per_kgK, eps);
        next_state.Tr_51 = max(next_state.Tr_51 + dT_se, ...
            options.system.Tc_K - 80.0);
        massR_kg = se.rho_kg_per_m3 .* options.geometry.L_r_m .* options.geometry.S_r_m2;
        adiabaticR_J = massR_kg .* se.cp_J_per_kgK .* dT_se;
    end

    audit = build_audit(state, next_state, old, next, rates, options, dt_s, stage_id);
    audit.se_adiabatic_dT_K = dT_se;
    audit.se_adiabatic_energy_J = adiabaticR_J;
end

function state = normalize_state(state, options)
    N = options.node_count;
    required = {'Ta_51','Tr_51','xM_a_51','xM_r_51'};
    for idx = 1:numel(required)
        key = required{idx};
        if ~isfield(state, key)
            error('HeatDriveECC_ConstitutiveCompatibilityStep:MissingField', ...
                'State is missing %s.', key);
        end
        value = state.(key)(:);
        if numel(value) ~= N
            error('HeatDriveECC_ConstitutiveCompatibilityStep:BadNodeCount', ...
                '%s must contain %d nodes.', key, N);
        end
        state.(key) = value;
    end
    state.xM_a_51 = clamp01(state.xM_a_51);
    state.xM_r_51 = clamp01(state.xM_r_51);
    if ~isfield(state, 'time_s')
        state.time_s = 0.0;
    end
    if ~isfield(state, 'stage_id')
        state.stage_id = 0;
    end
end

function c = solve_compatibility(state, options)
    g = options.geometry;
    sma = options.material.SMA;
    se = options.material.SE;
    N = options.node_count;

    delta_a_51 = 1.0 - state.xM_a_51(:);
    delta_r_51 = state.xM_r_51(:);
    force_ratio = g.S_r_m2 / g.S_a_m2;
    numerator_m = g.L_a_m .* mean(sma.epsilon_T .* delta_a_51) - ...
        g.L_r_m .* mean(se.epsilon_T .* delta_r_51);
    denominator_m_per_Pa = g.L_a_m .* force_ratio ./ sma.E_m_Pa + ...
        g.L_r_m ./ se.E_m_Pa;
    sigma_r_Pa = numerator_m ./ max(denominator_m_per_Pa, eps);
    sigma_a_Pa = force_ratio .* sigma_r_Pa;

    epsilon_a_51 = sma.epsilon_T .* delta_a_51 - sigma_a_Pa ./ sma.E_m_Pa;
    epsilon_r_51 = se.epsilon_T .* delta_r_51 + sigma_r_Pa ./ se.E_m_Pa;

    force_residual_N = sigma_a_Pa .* g.S_a_m2 - sigma_r_Pa .* g.S_r_m2;
    disp_residual_m = g.L_a_m .* mean(epsilon_a_51) - ...
        g.L_r_m .* mean(epsilon_r_51);
    eq6_scaled = force_residual_N ./ max(abs(sigma_r_Pa .* g.S_r_m2), 1.0e-9);
    eq7_scaled = disp_residual_m ./ max(abs(g.L_r_m .* mean(epsilon_r_51)), 1.0e-9);

    c = struct();
    c.sigma_a_Pa = sigma_a_Pa;
    c.sigma_r_Pa = sigma_r_Pa;
    c.epsilon_a_51 = epsilon_a_51;
    c.epsilon_r_51 = epsilon_r_51;
    c.force_residual_N = force_residual_N;
    c.disp_residual_m = disp_residual_m;
    c.eq6_scaled = eq6_scaled;
    c.eq7_scaled = eq7_scaled;
    c.delta_a_mean = mean(delta_a_51);
    c.delta_r_mean = mean(delta_r_51);
    c.sigma_a_51 = sigma_a_Pa .* ones(N, 1);
    c.sigma_r_51 = sigma_r_Pa .* ones(N, 1);
end

function rates = phase_rates(state, compatible, options, stage_id)
    sma = options.material.SMA;
    se = options.material.SE;
    c = options.constitutive;

    delta_a = 1.0 - state.xM_a_51(:);
    xR = state.xM_r_51(:);
    Ta = state.Ta_51(:);
    Tr = state.Tr_51(:);
    sigma_a = compatible.sigma_a_Pa;
    sigma_r = compatible.sigma_r_Pa;

    pai_a = zeros(size(Ta));
    pai_r = zeros(size(Tr));
    rxi_a = zeros(size(Ta));
    rxi_r = zeros(size(Tr));

    switch stage_id
        case 1
            equilibrium_sigma_a = sma.C_M_Pa_per_K .* ...
                (Ta - sma.T_As_K - delta_a .* (sma.T_Af_K - sma.T_As_K));
            pai_a = equilibrium_sigma_a - sigma_a;
            drive_a = positive_drive(pai_a, c.drive_width_a_Pa);
            rxi_a = -c.rate_a_to_A_1_per_s .* drive_a .* state.xM_a_51(:);

            se_threshold = se.C_A_Pa_per_K .* max(Tr - se.T_Af_K, 0.0) + ...
                c.se_load_hardening_Pa .* xR;
            pai_r = sigma_r - se_threshold;
            drive_r = positive_drive(pai_r, c.drive_width_r_Pa);
            rxi_r = c.rate_r_load_1_per_s .* drive_r .* (1.0 - xR);
        case 3
            equilibrium_sigma_a = sma.C_A_Pa_per_K .* ...
                (Ta - sma.T_Ms_K - delta_a .* (sma.T_Mf_K - sma.T_Ms_K));
            pai_a = equilibrium_sigma_a - sigma_a;
            drive_a = positive_drive(-pai_a, c.drive_width_a_Pa);
            rxi_a = c.rate_a_to_M_1_per_s .* drive_a .* (1.0 - state.xM_a_51(:));

            se_unload_threshold = se.C_M_Pa_per_K .* max(Tr - se.T_As_K, 0.0) - ...
                c.se_unload_hysteresis_Pa .* (1.0 - xR);
            pai_r = se_unload_threshold - sigma_r;
            drive_r = positive_drive(pai_r, c.drive_width_r_Pa);
            rxi_r = -c.rate_r_unload_1_per_s .* drive_r .* xR;
        otherwise
            % Stage 2 and 4 exchange heat while the mechanical phase state is
            % held unless the coupled stress/temperature drive becomes active
            % in a later fully coupled simulation.
    end

    rxi_a = min(max(rxi_a, -c.max_rate_1_per_s), c.max_rate_1_per_s);
    rxi_r = min(max(rxi_r, -c.max_rate_1_per_s), c.max_rate_1_per_s);

    rates = struct();
    rates.pai_a_Pa_51 = pai_a;
    rates.pai_r_Pa_51 = pai_r;
    rates.r_xi_a_51 = rxi_a;
    rates.r_xi_r_51 = rxi_r;
    rates.q_latent_a_W_per_m3_51 = -state.Ta_51(:) .* ...
        sma.rho_kg_per_m3 .* sma.Delta_h_J_per_kg .* rxi_a;
    rates.q_latent_r_W_per_m3_51 = state.Tr_51(:) .* ...
        se.rho_kg_per_m3 .* se.Delta_h_J_per_kg .* rxi_r;
end

function x = positive_drive(pai_Pa, width_Pa)
    x = max(pai_Pa ./ max(width_Pa, 1.0), 0.0);
end

function audit = build_audit(old_state, next_state, old, next, rates, options, dt_s, stage_id)
    g = options.geometry;
    sma = options.material.SMA;
    se = options.material.SE;

    d_eps_a = mean(next.epsilon_a_51 - old.epsilon_a_51);
    d_eps_r = mean(next.epsilon_r_51 - old.epsilon_r_51);
    volume_a_m3 = g.L_a_m .* g.S_a_m2;
    volume_r_m3 = g.L_r_m .* g.S_r_m2;
    mechA_J = next.sigma_a_Pa .* d_eps_a .* volume_a_m3;
    mechR_J = next.sigma_r_Pa .* d_eps_r .* volume_r_m3;

    dxA = mean(next_state.xM_a_51 - old_state.xM_a_51);
    dxR = mean(next_state.xM_r_51 - old_state.xM_r_51);
    massA_kg = sma.rho_kg_per_m3 .* volume_a_m3;
    massR_kg = se.rho_kg_per_m3 .* volume_r_m3;
    latentA_J = -massA_kg .* sma.Delta_h_J_per_kg .* dxA;
    latentR_J = massR_kg .* se.Delta_h_J_per_kg .* dxR;

    audit = struct();
    audit.schema_version = 'heatdrive_ecc_constitutive_compatibility_step_v1';
    audit.time_s = next_state.time_s;
    audit.dt_s = dt_s;
    audit.stage_id = stage_id;
    audit.Ta_mean_K = mean(next_state.Ta_51);
    audit.Tr_mean_K = mean(next_state.Tr_51);
    audit.xM_a_mean = mean(next_state.xM_a_51);
    audit.xM_r_mean = mean(next_state.xM_r_51);
    audit.dxM_a_mean = dxA;
    audit.dxM_r_mean = dxR;
    audit.sigma_a_Pa = next.sigma_a_Pa;
    audit.sigma_r_Pa = next.sigma_r_Pa;
    audit.epsilon_a_mean = mean(next.epsilon_a_51);
    audit.epsilon_r_mean = mean(next.epsilon_r_51);
    audit.force_residual_N = next.force_residual_N;
    audit.disp_residual_m = next.disp_residual_m;
    audit.eq6_scaled = next.eq6_scaled;
    audit.eq7_scaled = next.eq7_scaled;
    audit.pai_a_mean_Pa = mean(rates.pai_a_Pa_51);
    audit.pai_r_mean_Pa = mean(rates.pai_r_Pa_51);
    audit.r_xi_a_mean_1_per_s = mean(rates.r_xi_a_51);
    audit.r_xi_r_mean_1_per_s = mean(rates.r_xi_r_51);
    audit.latentA_J = latentA_J;
    audit.latentR_J = latentR_J;
    audit.mechanicalA_J = mechA_J;
    audit.mechanicalR_J = mechR_J;
    audit.latentA_W = latentA_J ./ max(dt_s, eps);
    audit.latentR_W = latentR_J ./ max(dt_s, eps);
    audit.mechanicalA_W = mechA_J ./ max(dt_s, eps);
    audit.mechanicalR_W = mechR_J ./ max(dt_s, eps);
end

function y = clamp01(x)
    y = min(max(x, 0.0), 1.0);
end
