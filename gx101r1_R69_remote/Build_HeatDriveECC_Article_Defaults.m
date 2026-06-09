function options = Build_HeatDriveECC_Article_Defaults(overrides)
% Build defaults for the Simulink full-cycle heat-driven ECC model.

    if nargin < 1
        overrides = struct();
    end

    root_dir = fileparts(mfilename('fullpath'));
    options = struct();
    options.schema_version = 'heatdrive_ecc_article_simulink_defaults_v1';
    options.model_name = 'heatdrive_ecc_1d51_fullcycle';
    options.model_path = fullfile(root_dir, [options.model_name, '.slx']);
    options.outputs_dir = fullfile(root_dir, 'outputs_heatdrive_ecc_3cycle');
    options.cycle_count = 3;
    options.node_count = 51;

    options.system = struct();
    options.system.Tc_K = 288.0;
    options.system.T0_K = 308.0;
    options.system.eta_hr = 0.7;
    options.system.G_W_per_m2 = 1000.0;
    options.system.A_PSC_m2 = 15.57 / (0.1731 * 1000.0);
    options.system.T_PSC_K = 345.0;
    options.system.P_PSC_W = 15.57;
    options.system.P_H_W = 19.19;

    options.geometry = struct();
    options.geometry.shape = 'generic_rectangular_1d_bar';
    options.geometry.L_a_m = 1.0;
    options.geometry.S_a_m2 = 1.0e-6;
    options.geometry.L_r_over_L_a = 0.4;
    options.geometry.S_r_over_S_a = 0.2;
    options.geometry.L_r_m = options.geometry.L_a_m * options.geometry.L_r_over_L_a;
    options.geometry.S_r_m2 = options.geometry.S_a_m2 * options.geometry.S_r_over_S_a;
    options.geometry.width_a_m = 2.0e-3;
    options.geometry.thickness_a_m = options.geometry.S_a_m2 / options.geometry.width_a_m;
    options.geometry.width_r_m = 1.0e-3;
    options.geometry.thickness_r_m = options.geometry.S_r_m2 / options.geometry.width_r_m;

    options.material = struct();
    options.material.SMA = article_material('SMA', 323.0, 343.0, 293.0, 313.0);
    options.material.SE = article_material('SE', 268.0, 288.0, 238.0, 258.0);
    options.material.SE.w_uld_J_per_kg = 4.1e3;
    options.material.SE.w_ld_J_per_kg = 5.6e3;

    options.equilibrium = compute_article_equilibrium(options);
    options.schedule = Build_HeatDriveECC_StageSchedule(options);
    options.route_matrix = Build_HeatDriveECC_RouteMatrix(options.schedule);
    options.output_map = build_output_map(options.node_count);

    options.simulation = struct();
    options.simulation.stop_time_s = options.schedule.total_time_s;
    options.simulation.fixed_step_s = min(options.schedule.stage_durations_s) / 80.0;
    options.simulation.solver = 'FixedStepDiscrete';
    options.simulation.stage_probe_samples = 50;

    options.validation = struct();
    options.validation.max_finite_abs = 1.0e12;
    options.validation.max_mechanical_active_eq7_endpoint_scaled = 0.25;
    options.validation.max_mechanical_active_eq7_transient_scaled = 5.0;
    options.validation.min_probe_samples_per_stage = 50;

    options = merge_structs(options, overrides);
end

function material = article_material(name, T_As_K, T_Af_K, T_Mf_K, T_Ms_K)
    material = struct();
    material.name = name;
    material.C_M_Pa_per_K = 7.3e6;
    material.C_A_Pa_per_K = 7.6e6;
    material.cp_J_per_kgK = 500.0;
    material.Delta_h_J_per_kg = 1.0e4;
    material.epsilon_T = 0.03;
    material.T_As_K = T_As_K;
    material.T_Af_K = T_Af_K;
    material.T_Mf_K = T_Mf_K;
    material.T_Ms_K = T_Ms_K;
    material.E_m_Pa = 30.0e9;
    material.rho_kg_per_m3 = 6500.0;
    material.w_uld_J_per_kg = 0.0;
    material.w_ld_J_per_kg = 0.0;
end

function eq = compute_article_equilibrium(options)
    g = options.geometry;
    sys = options.system;
    sma = options.material.SMA;
    se = options.material.SE;
    S_ratio = g.S_r_over_S_a;
    L_ratio = g.L_r_over_L_a;
    inv_S_ratio = 1.0 / S_ratio;
    k0 = L_ratio * se.epsilon_T / sma.epsilon_T;
    k1 = (L_ratio + S_ratio * (se.E_m_Pa / sma.E_m_Pa)) / ...
        (se.E_m_Pa * sma.epsilon_T);
    a0 = inv_S_ratio * sma.C_A_Pa_per_K * (sys.T0_K - sma.T_Ms_K);
    a1 = -inv_S_ratio * sma.C_A_Pa_per_K * (sma.T_Mf_K - sma.T_Ms_K);
    delta_xM_a = (k0 + k1 * a0) / (1.0 - k1 * a1);
    sigma_r_Pa = inv_S_ratio * sma.C_A_Pa_per_K * ...
        (sys.T0_K - sma.T_Ms_K - delta_xM_a * (sma.T_Mf_K - sma.T_Ms_K));
    sigma_a_Pa = S_ratio * sigma_r_Pa;
    T_h_K = sma.T_As_K + delta_xM_a * (sma.T_Af_K - sma.T_As_K) + ...
        sigma_a_Pa / sma.C_M_Pa_per_K;
    mu = L_ratio * S_ratio * (se.rho_kg_per_m3 / sma.rho_kg_per_m3);
    qa = sma.cp_J_per_kgK * (T_h_K - sys.T0_K) * (1.0 - sys.eta_hr) + ...
        sma.Delta_h_J_per_kg * delta_xM_a + se.w_ld_J_per_kg * mu;
    qr = se.Delta_h_J_per_kg + se.w_uld_J_per_kg - ...
        se.cp_J_per_kgK * (sys.T0_K - sys.Tc_K) * (1.0 - sys.eta_hr);
    m_a = sma.rho_kg_per_m3 * g.L_a_m * g.S_a_m2;
    m_r = se.rho_kg_per_m3 * g.L_r_m * g.S_r_m2;
    target_PECC = sys.P_H_W - sys.P_PSC_W;
    Qh = target_PECC / max(mu * qr / qa, eps);
    incident = sys.G_W_per_m2 * sys.A_PSC_m2;
    K_L = (incident - sys.P_PSC_W - Qh) / ...
        (sys.A_PSC_m2 * (sys.T_PSC_K - sys.T0_K));
    nu = Qh / (m_a * qa);

    eq = struct();
    eq.delta_xM_a = delta_xM_a;
    eq.delta_xM_r = 1.0;
    eq.sigma_r_Pa = sigma_r_Pa;
    eq.sigma_a_Pa = sigma_a_Pa;
    eq.T_h_K = T_h_K;
    eq.MDTD_K = T_h_K - sys.T0_K;
    eq.mu = mu;
    eq.qa_J_per_kg = qa;
    eq.qr_J_per_kg = qr;
    eq.m_a_kg = m_a;
    eq.m_r_kg = m_r;
    eq.Qh_W = Qh;
    eq.Qa_W = Qh;
    eq.Qr_W = target_PECC;
    eq.PECC_W = target_PECC;
    eq.etaECC = target_PECC / incident;
    eq.nu_Hz = nu;
    eq.tau_cycle_s = 1.0 / nu;
    eq.K_L_W_per_m2K = K_L;
end

function map = build_output_map(N)
    map = struct();
    names = {'time_s','cycle_index','stage_id','route_id','stage_elapsed_s', ...
        'valve1_position','valve2_position','pump_sma','pump_se', ...
        'SHEX_to_SMA','THE_to_SMA','SE_to_THE','RHE_to_SE', ...
        'check_valve_1','check_valve_2','check_valve_3','check_valve_4', ...
        'sigma_a_Pa','sigma_r_Pa','epsilon_a_mean','epsilon_r_mean', ...
        'force_residual_N','disp_residual_m','eq6_scaled','eq7_scaled', ...
        'Q_shex_W','Q_the_sma_W','Q_the_se_W','Q_rhe_W', ...
        'Qh_W','Qa_W','Qr_W','PECC_W','etaECC','nu_Hz', ...
        'Th_K','T0_K','Tc_K','xM_a_mean','xM_r_mean','T_a_mean_K','T_r_mean_K', ...
        'T_a_min_K','T_a_max_K','T_r_min_K','T_r_max_K', ...
        'mechanical_active','SMA_HTF_in_K','SMA_HTF_out_K','SMA_boundary_K', ...
        'SE_HTF_in_K','SE_HTF_out_K','SE_boundary_K', ...
        'SHEX_in_K','SHEX_out_K','THE_SMA_K','THE_SE_K','RHE_in_K','RHE_out_K'};
    for idx = 1:numel(names)
        map.(names{idx}) = idx;
    end
    start_idx = numel(names) + 1;
    map.T_a_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.xM_a_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.sigma_a_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.epsilon_a_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.pai_a_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.r_xi_a_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.q_latent_a_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.T_r_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.xM_r_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.sigma_r_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.epsilon_r_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.pai_r_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.r_xi_r_51 = start_idx:(start_idx + N - 1);
    start_idx = start_idx + N;
    map.q_latent_r_51 = start_idx:(start_idx + N - 1);
    map.output_width = start_idx + N - 1;
end

function out = merge_structs(out, overrides)
    if ~isstruct(overrides) || isempty(fieldnames(overrides))
        return;
    end
    names = fieldnames(overrides);
    for idx = 1:numel(names)
        key = names{idx};
        if isfield(out, key) && isstruct(out.(key)) && isstruct(overrides.(key))
            out.(key) = merge_structs(out.(key), overrides.(key));
        else
            out.(key) = overrides.(key);
        end
    end
end
