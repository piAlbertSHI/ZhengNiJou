function options = Build_HeatDriveECC_Article_Defaults(overrides)
% Build the coupled-cycle parameter contract.
%
% SMA material and geometry are anchored to Xu et al., Table 5 and Fig. 7:
% Ni55Ti45 plate, 100 mm x 10 mm x 0.5 mm, with a 2 mm through-hole.
% The physical model remains one-dimensional, so the perforated plate is
% represented by a uniform axial strip with the same net volume.

    if nargin < 1
        overrides = struct();
    end

    root_dir = fileparts(mfilename('fullpath'));
    options = struct();
    options.schema_version = 'heatdrive_ecc_xu2019_table5_defaults_v2';
    options.model_name = 'heatdrive_ecc_1d21_fullcycle';
    options.model_path = fullfile(root_dir, [options.model_name, '.slx']);
    options.outputs_dir = fullfile(root_dir, 'outputs_heatdrive_ecc_2cycle');
    options.cycle_count = 3;
    options.node_count = 21;

    options.reference = build_reference_contract();
    options.material = struct();
    options.material.SMA = xu2019_table5_sma_material();
    options.material.SE = retained_se_material();
    options.geometry = build_equivalent_geometry(options.material, options.reference);

    scale = options.geometry.volume_scale_vs_previous;
    options.system = struct();
    options.system.Tc_K = 275.0;
    options.system.T0_K = 280.0;
    options.system.eta_hr = 0.7;
    options.system.G_W_per_m2 = 1000.0;
    options.system.A_PSC_m2 = options.reference.A_PSC_m2 * scale;
    options.system.T_PSC_K = 400.0;
    options.system.hot_side_approach_K = 5.0;
    options.system.P_PSC_W = options.reference.P_PSC_W * scale;
    options.system.Qh_reference_W = options.reference.Qh_W * scale;
    options.system.P_H_W = NaN;
    options.system.extensive_scale = scale;
    options.system.temperature_source = [ ...
        'Xu et al. plate-actuator thermal cycle 280-400 K; CHEX is 275 K, ', ...
        'above the model water-property lower limit of 273.16 K.'];
    options.system.extensive_scale_source = [ ...
        'All retained system extensive quantities scale by net SMA volume ', ...
        'relative to the previous 1.0e-6 m3 actuator.'];

    options = finalize_derived_options(options, struct());
    options = merge_structs(options, overrides);
    options = finalize_derived_options(options, overrides);
end

function reference = build_reference_contract()
    reference = struct();
    reference.previous_sma_volume_m3 = 1.0e-6;
    reference.P_PSC_W = 15.57;
    reference.Qh_W = 44.2322866573;
    reference.A_PSC_m2 = 15.57 / (0.1731 * 1000.0);
    reference.shex_sink_C_J_per_K = 500.0;
    reference.hot_sink_C_J_per_K = 2.6;
    reference.cold_sink_C_J_per_K = 1.3;
    reference.fluid_mass_total_kg = 0.018;
    reference.m_dot_kg_per_s = 0.022;
    reference.sma_pipe_internal_volume_target_ml = 1.2;
    reference.source = 'pre-Xu coupled-system extensive baseline';
end

function material = xu2019_table5_sma_material()
    material = struct();
    material.name = 'Ni55Ti45_SMA_Xu2019_Table5';
    material.composition_at_percent = 'Ni55Ti45';
    material.parameter_source = [ ...
        'Xu et al., finite-strain SMA model, Table 5 and Fig. 7; ', ...
        'nominal cyclic actuation stress 136 MPa, 280-400 K.'];
    material.E_A_Pa = 70.0e9;
    material.E_M_Pa = 70.0e9;
    material.E_m_Pa = material.E_M_Pa;
    material.nu_A = 0.33;
    material.nu_M = 0.33;
    material.alpha_A_1_per_K = 1.0e-5;
    material.alpha_M_1_per_K = 1.0e-5;
    material.C_A_Pa_per_K = 22.0e6;
    material.C_M_Pa_per_K = 22.0e6;
    material.T_Ms_K = 318.0;
    material.T_Mf_K = 298.0;
    material.T_As_K = 332.0;
    material.T_Af_K = 352.0;
    material.Hmax_initial = 0.015;
    material.Hmax_final = 0.015;
    material.Hmin = 0.0;
    material.k_t_1_per_MPa = 0.01;
    material.k_t_1_per_Pa = material.k_t_1_per_MPa / 1.0e6;
    material.tau_crit_Pa = 0.0;
    material.n1 = 0.5;
    material.n2 = 0.5;
    material.n3 = 0.5;
    material.n4 = 0.5;
    material.sigma_b_Pa = 0.0;
    material.lambda1 = NaN;
    material.Cp1 = 5.73e-3;
    material.Cp2 = 1.972;
    material.nominal_stress_Pa = 136.0e6;
    material.thermal_cycle_min_K = 280.0;
    material.thermal_cycle_max_K = 400.0;

    % Density, heat capacity and conductivity are not reported in Table 5.
    % Retain the established NiTi thermophysical values used by this model.
    material.rho_kg_per_m3 = 6500.0;
    material.cp_J_per_kgK = 500.0;
    material.k_W_per_mK = 18.0;
    material.thermophysical_source = [ ...
        'not reported by Xu Table 5; retained NiTi model values'];

    sigma_MPa = material.nominal_stress_Pa / 1.0e6;
    exponential = exp(-material.k_t_1_per_MPa * ...
        (sigma_MPa - material.tau_crit_Pa / 1.0e6));
    material.Hcur_nominal = material.Hmin + ...
        (material.Hmax_initial - material.Hmin) * (1.0 - exponential);
    material.dHcur_dsigma_1_per_Pa = ...
        (material.Hmax_initial - material.Hmin) * ...
        material.k_t_1_per_Pa * exponential;
    material.epsilon_T = material.Hcur_nominal;

    entropy_term = material.Hcur_nominal + ...
        material.nominal_stress_Pa * material.dHcur_dsigma_1_per_Pa;
    material.rho_Delta_s0_J_per_m3K = ...
        -2.0 * material.C_M_Pa_per_K * material.C_A_Pa_per_K * ...
        entropy_term / (material.C_M_Pa_per_K + material.C_A_Pa_per_K);
    material.Delta_s0_J_per_kgK = ...
        material.rho_Delta_s0_J_per_m3K / material.rho_kg_per_m3;
    material.latent_reference_T_K = 0.5 * ...
        (material.T_Ms_K + material.T_Af_K);
    material.Delta_h_J_per_kg = abs(material.latent_reference_T_K * ...
        material.Delta_s0_J_per_kgK);
    material.latent_heat_source = [ ...
        'derived from Xu Appendix B Eq. B.5 at 136 MPa; ', ...
        'Delta_h = abs(0.5*(Ms+Af)*Delta_s0)'];
    material.w_uld_J_per_kg = 0.0;
    material.w_ld_J_per_kg = 0.0;
end

function material = retained_se_material()
    material = struct();
    material.name = 'NiTi_SE_retained_coupled_baseline';
    material.C_M_Pa_per_K = 7.3e6;
    material.C_A_Pa_per_K = 7.6e6;
    material.cp_J_per_kgK = 500.0;
    material.Delta_h_J_per_kg = 1.0e4;
    material.epsilon_T = 0.03;
    material.T_As_K = 268.0;
    material.T_Af_K = 288.0;
    material.T_Mf_K = 238.0;
    material.T_Ms_K = 258.0;
    material.E_m_Pa = 30.0e9;
    material.rho_kg_per_m3 = 6500.0;
    material.w_uld_J_per_kg = 4.1e3;
    material.w_ld_J_per_kg = 5.6e3;
    material.parameter_source = [ ...
        'retained SE parameter set; this request changes the SMA anchor only'];
end

function geometry = build_equivalent_geometry(material, reference)
    sma = material.SMA;
    se = material.SE;
    length_m = 100.0e-3;
    width_m = 10.0e-3;
    thickness_m = 0.5e-3;
    hole_diameter_m = 2.0e-3;
    gross_volume_m3 = length_m * width_m * thickness_m;
    hole_volume_m3 = pi * (0.5 * hole_diameter_m)^2 * thickness_m;
    net_volume_m3 = gross_volume_m3 - hole_volume_m3;

    % Force compatibility sets the area ratio. Displacement compatibility
    % at the fully transformed nominal state sets the SE/SMA length ratio.
    sigma_sma_Pa = sma.nominal_stress_Pa;
    sigma_se_Pa = 690.0e6;
    area_ratio = sigma_sma_Pa / sigma_se_Pa;
    available_sma_strain = sma.Hcur_nominal - sigma_sma_Pa / sma.E_A_Pa;
    required_se_strain = se.epsilon_T + sigma_se_Pa / se.E_m_Pa;
    length_ratio = available_sma_strain / required_se_strain;
    if ~(area_ratio > 0.0 && length_ratio > 0.0)
        error('HeatDriveECC:InvalidCompatibilityGeometry', ...
            'Derived SMA/SE compatibility ratios must be positive.');
    end

    geometry = struct();
    geometry.shape = 'equivalent_1d_strip_from_Xu2019_perforated_plate';
    geometry.L_a_m = length_m;
    geometry.width_a_m = width_m;
    geometry.nominal_thickness_a_m = thickness_m;
    geometry.hole_diameter_m = hole_diameter_m;
    geometry.gross_sma_volume_m3 = gross_volume_m3;
    geometry.hole_volume_m3 = hole_volume_m3;
    geometry.net_sma_volume_m3 = net_volume_m3;
    geometry.S_a_m2 = net_volume_m3 / length_m;
    geometry.thickness_a_m = geometry.S_a_m2 / width_m;
    geometry.volume_scale_vs_previous = ...
        net_volume_m3 / reference.previous_sma_volume_m3;
    geometry.sigma_sma_design_Pa = sigma_sma_Pa;
    geometry.sigma_se_design_Pa = sigma_se_Pa;
    geometry.S_r_over_S_a = area_ratio;
    geometry.L_r_over_L_a = length_ratio;
    geometry.L_r_m = length_m * length_ratio;
    geometry.S_r_m2 = geometry.S_a_m2 * area_ratio;
    geometry.width_r_m = 1.0e-3;
    geometry.thickness_r_m = geometry.S_r_m2 / geometry.width_r_m;
    geometry.compatibility_source = [ ...
        'Sa*sigma_a=Sr*sigma_r and La*(Hcur-sigma_a/EA)=', ...
        'Lr*(epsilon_SE+sigma_r/ER), using 136 MPa SMA and 690 MPa SE'];
end

function options = finalize_derived_options(options, overrides)
    options.geometry.L_r_m = options.geometry.L_a_m * ...
        options.geometry.L_r_over_L_a;
    options.geometry.S_r_m2 = options.geometry.S_a_m2 * ...
        options.geometry.S_r_over_S_a;
    options.geometry.thickness_a_m = options.geometry.S_a_m2 / ...
        options.geometry.width_a_m;
    options.geometry.thickness_r_m = options.geometry.S_r_m2 / ...
        options.geometry.width_r_m;

    options.equilibrium = compute_coupled_design_point(options);
    options.system.P_H_W = options.equilibrium.P_H_W;
    options.schedule = Build_HeatDriveECC_StageSchedule(options);
    options.route_matrix = Build_HeatDriveECC_RouteMatrix(options.schedule);
    options.output_map = build_output_map(options.node_count);

    if ~isfield(options, 'simulation') || ~isstruct(options.simulation)
        options.simulation = struct();
    end
    if ~has_nested_override(overrides, {'simulation', 'stop_time_s'})
        options.simulation.stop_time_s = options.schedule.total_time_s;
    end
    if ~has_nested_override(overrides, {'simulation', 'fixed_step_s'})
        options.simulation.fixed_step_s = ...
            min(options.schedule.stage_durations_s) / 80.0;
    end
    if ~isfield(options.simulation, 'solver') || isempty(options.simulation.solver)
        options.simulation.solver = 'FixedStepDiscrete';
    end
    if ~isfield(options.simulation, 'stage_probe_samples') || ...
            isempty(options.simulation.stage_probe_samples)
        options.simulation.stage_probe_samples = 50;
    end

    if ~isfield(options, 'validation') || ~isstruct(options.validation)
        options.validation = struct();
    end
    options.validation = set_default_field(options.validation, ...
        'max_finite_abs', 1.0e12);
    options.validation = set_default_field(options.validation, ...
        'max_mechanical_active_eq7_endpoint_scaled', 0.25);
    options.validation = set_default_field(options.validation, ...
        'max_mechanical_active_eq7_transient_scaled', 5.0);
    options.validation = set_default_field(options.validation, ...
        'min_probe_samples_per_stage', 50);
end

function eq = compute_coupled_design_point(options)
    g = options.geometry;
    sys = options.system;
    sma = options.material.SMA;
    se = options.material.SE;

    delta_xM_a = 1.0;
    sigma_a_Pa = sma.nominal_stress_Pa;
    sigma_r_Pa = g.sigma_se_design_Pa;
    T_transform_complete_K = ...
        sma.T_Af_K + sigma_a_Pa / sma.C_A_Pa_per_K;
    T_h_K = sys.T_PSC_K - sys.hot_side_approach_K;
    if T_h_K <= T_transform_complete_K
        error('HeatDriveECC:InsufficientHotSideTemperature', ...
            'Hot-side fluid must exceed the stress-shifted Af temperature.');
    end
    mu = g.L_r_over_L_a * g.S_r_over_S_a * ...
        (se.rho_kg_per_m3 / sma.rho_kg_per_m3);
    qa = sma.cp_J_per_kgK * (T_h_K - sys.T0_K) * ...
        (1.0 - sys.eta_hr) + sma.Delta_h_J_per_kg * delta_xM_a + ...
        se.w_ld_J_per_kg * mu;
    qr = se.Delta_h_J_per_kg + se.w_uld_J_per_kg - ...
        se.cp_J_per_kgK * (sys.T0_K - sys.Tc_K) * ...
        (1.0 - sys.eta_hr);
    m_a = sma.rho_kg_per_m3 * g.L_a_m * g.S_a_m2;
    m_r = se.rho_kg_per_m3 * g.L_r_m * g.S_r_m2;
    Qh = sys.Qh_reference_W;
    Qr = Qh * mu * qr / max(qa, eps);
    incident = sys.G_W_per_m2 * sys.A_PSC_m2;
    P_H = sys.P_PSC_W + Qr;
    K_L = (incident - sys.P_PSC_W - Qh) / ...
        (sys.A_PSC_m2 * (sys.T_PSC_K - sys.T0_K));
    nu = Qh / (m_a * qa);

    eq = struct();
    eq.delta_xM_a = delta_xM_a;
    eq.delta_xM_r = 1.0;
    eq.sigma_r_Pa = sigma_r_Pa;
    eq.sigma_a_Pa = sigma_a_Pa;
    eq.T_h_K = T_h_K;
    eq.T_transform_complete_K = T_transform_complete_K;
    eq.MDTD_K = T_h_K - sys.T0_K;
    eq.mu = mu;
    eq.qa_J_per_kg = qa;
    eq.qr_J_per_kg = qr;
    eq.m_a_kg = m_a;
    eq.m_r_kg = m_r;
    eq.Qh_W = Qh;
    eq.Qa_W = Qh;
    eq.Qr_W = Qr;
    eq.PECC_W = Qr;
    eq.P_H_W = P_H;
    eq.etaECC = Qr / max(incident, eps);
    eq.nu_Hz = nu;
    eq.tau_cycle_s = 1.0 / nu;
    eq.K_L_W_per_m2K = K_L;
    eq.source = [ ...
        'Xu Table 5 full-transformation point plus coupled force/displacement ', ...
        'compatibility; extensive Qh scaled by net SMA volume.'];
end

function map = build_output_map(N)
    map = struct();
    names = {'time_s','cycle_index','stage_id','route_id','stage_elapsed_s', ...
        'valve1_position','valve2_position','pump_sma','pump_se', ...
        'SHEX_to_SMA','THE_to_SMA','SE_to_THE','CHEX_to_SE', ...
        'check_valve_1','check_valve_2','check_valve_3','check_valve_4', ...
        'sigma_a_Pa','sigma_r_Pa','epsilon_a_mean','epsilon_r_mean', ...
        'force_residual_N','disp_residual_m','eq6_scaled','eq7_scaled', ...
        'Q_shex_W','Q_the_sma_W','Q_the_se_W','Q_chex_W', ...
        'Qh_W','Qa_W','Qr_W','PECC_W','etaECC','nu_Hz', ...
        'Th_K','T0_K','Tc_K','xM_a_mean','xM_r_mean','T_a_mean_K','T_r_mean_K', ...
        'T_a_min_K','T_a_max_K','T_r_min_K','T_r_max_K', ...
        'mechanical_active','SMA_HTF_in_K','SMA_HTF_out_K','SMA_boundary_K', ...
        'SE_HTF_in_K','SE_HTF_out_K','SE_boundary_K', ...
        'SHEX_in_K','SHEX_out_K','THE_SMA_K','THE_SE_K','CHEX_in_K','CHEX_out_K', ...
        'SHEX_internal_hot_K','SHEX_internal_fluid_K','SHEX_boundary_K', ...
        'HHEX_internal_K','HHEX_in_K','HHEX_out_K', ...
        'HHEX_SMA_internal_K','HHEX_SMA_in_K','HHEX_SMA_out_K', ...
        'HHEX_SE_internal_K','HHEX_SE_in_K','HHEX_SE_out_K', ...
        'CHEX_internal_K','CHEX_in_K','CHEX_out_K'};
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

function value = set_default_field(value, key, default_value)
    if ~isfield(value, key) || isempty(value.(key))
        value.(key) = default_value;
    end
end

function tf = has_nested_override(s, keys)
    tf = false;
    if ~isstruct(s)
        return;
    end
    current = s;
    for idx = 1:numel(keys)
        key = keys{idx};
        if ~isstruct(current) || ~isfield(current, key)
            return;
        end
        current = current.(key);
    end
    tf = true;
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
