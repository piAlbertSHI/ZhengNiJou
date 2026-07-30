function options = Build_HeatDriveECC_EighthRound_Defaults(overrides)
% Unified defaults for eighth-round 21-node axial Simulink ECC validation.
%
% The model is a one-dimensional axial SMA/SE representation using the paper
% length and generic area abstraction. It intentionally does not use the
% legacy circular plate w/u/radius model.

    if nargin < 1
        overrides = struct();
    end

    root_dir = fileparts(mfilename('fullpath'));
    article = Build_HeatDriveECC_Article_Defaults();
    article_hx = compute_article_heat_exchanger_closure(article);

    options = struct();
    options.schema_version = 'heatdrive_ecc_xu2019_table5_simscape_defaults_v2';
    options.node_count = 21;
    options.cycle_count = 3;
    options.model_name = 'heatdrive_ecc_coupled_se21';
    options.model_path = fullfile(root_dir, [options.model_name '.slx']);
    options.outputs_dir = fullfile(root_dir, 'outputs', 'heatdrive_ecc_eighth_round');
    options.report_path = fullfile(fileparts(root_dir), '项目文档', ...
        '审核分析', '当前主线物理验证报告.txt');

    options.system = article.system;
    options.system.Th_K = article.equilibrium.T_h_K;
    options.system.Tshex_K = article.equilibrium.T_h_K;
    options.system.Tshex_source_K = article.system.T_PSC_K;
    options.system.Thhex_K = article.system.T0_K;
    options.system.Tchex_K = article.system.Tc_K;
    options.system.cp_fluid_J_per_kgK = 4180.0;
    options.system.thermal_mass_cp_ref_J_per_kgK = article.material.SE.cp_J_per_kgK;
    options.system.SE_heat_capacity_J_per_K = ...
        article.equilibrium.m_r_kg * article.material.SE.cp_J_per_kgK;
    system_scale = article.geometry.volume_scale_vs_previous;
    options.system.cold_sink_C_J_per_K = ...
        article.reference.cold_sink_C_J_per_K * system_scale;
    options.system.hot_sink_C_J_per_K = ...
        article.reference.hot_sink_C_J_per_K * system_scale;
    options.system.cold_sink_capacity_multiplier_vs_SE = ...
        options.system.cold_sink_C_J_per_K / ...
        max(options.system.SE_heat_capacity_J_per_K, eps);
    options.system.hot_sink_capacity_multiplier_vs_SE = ...
        options.system.hot_sink_C_J_per_K / ...
        max(options.system.SE_heat_capacity_J_per_K, eps);
    options.system.cold_load_C_J_per_K = options.system.cold_sink_C_J_per_K;
    options.system.shex_sink_C_J_per_K = ...
        article.reference.shex_sink_C_J_per_K * system_scale;
    options.system.cold_load_heat_W = 0.0;
    options.system.cold_load_mode = 'no_load';
    options.system.cold_load_heat_reference_W = article.equilibrium.Qr_W;
    options.system.article_Qh_W = article.equilibrium.Qh_W;
    options.system.article_Qr_W = article.equilibrium.Qr_W;
    options.system.article_Qh_cycle_J = article.equilibrium.Qh_W * ...
        article.equilibrium.tau_cycle_s;
    options.system.article_Qr_cycle_J = article.equilibrium.Qr_W * ...
        article.equilibrium.tau_cycle_s;
    options.system.article_Qr_over_Qh = article.equilibrium.Qr_W / ...
        article.equilibrium.Qh_W;
    options.system.article_PECC_W = article.equilibrium.PECC_W;
    options.system.article_etaECC = article.equilibrium.etaECC;
    options.system.article_tau_cycle_s = article.equilibrium.tau_cycle_s;
    options.system.article_stage1_Qh_W = article_hx.stage1_Qh_W;
    options.system.article_stage2_SE_to_HHEX_W = article_hx.stage2_SE_to_HHEX_W;
    options.system.article_stage3_SMA_to_HHEX_W = article_hx.stage3_SMA_to_HHEX_W;
    options.system.article_stage4_Qr_W = article_hx.stage4_Qr_W;
    options.system.heat_exchanger_reference_note = article_hx.reference_note;
    options.system.capacity_scale_source = ...
        article.system.extensive_scale_source;

    options.geometry = article.geometry;
    options.material = article.material;
    options.equilibrium = article.equilibrium;
    options.schedule = article.schedule;

    options.simulation = struct();
    options.simulation.fixed_step_s = min(article.schedule.stage_durations_s) / 120.0;
    options.simulation.samples_per_stage = 120;
    options.simulation.solver = 'ode23t';
    options.simulation.stop_time_s = options.cycle_count * ...
        article.equilibrium.tau_cycle_s;
    options.simulation.output_variable = 'eighth_round_yout';
    options.simulation.output_variable_role = ...
        'legacy_surrogate_diagnostic_not_validation_authority';
    options.simulation.authority = 'physical_simscape_to_workspace_logs';

    options.simscape = struct();
    options.simscape.local_solver_enabled = true;
    options.simscape.local_solver_choice = 'NE_BACKWARD_EULER_ADVANCER';
    options.simscape.local_solver_sample_time_s = 1.0e-3;

    options.branch = struct();
    options.branch.m_dot_kg_per_s = ...
        article.reference.m_dot_kg_per_s * system_scale;
    options.branch.m_dot_sma_shex_kg_per_s = options.branch.m_dot_kg_per_s;
    options.branch.m_dot_sma_the_kg_per_s = options.branch.m_dot_kg_per_s;
    options.branch.m_dot_se_the_kg_per_s = options.branch.m_dot_kg_per_s;
    options.branch.m_dot_se_chex_kg_per_s = options.branch.m_dot_kg_per_s;
    options.branch.fluid_mass_total_kg = ...
        article.reference.fluid_mass_total_kg * system_scale;
    options.branch.UA_sma_shex_W_per_K = article_hx.UA_sma_shex_W_per_K;
    options.branch.UA_sma_the_W_per_K = article_hx.UA_sma_the_W_per_K;
    options.branch.UA_se_the_W_per_K = article_hx.UA_se_the_W_per_K;
    options.branch.UA_se_chex_W_per_K = article_hx.UA_se_chex_W_per_K;
    options.branch.boundary_UA_shex_W_per_K = article_hx.boundary_UA_shex_W_per_K;
    options.branch.boundary_UA_the_W_per_K = article_hx.boundary_UA_the_W_per_K;
    options.branch.boundary_UA_chex_W_per_K = article_hx.boundary_UA_chex_W_per_K;
    options.branch.shex_source_to_sink_UA_W_per_K = article_hx.shex_source_to_sink_UA_W_per_K;
    options.branch.hhex_to_ambient_UA_W_per_K = article_hx.hhex_to_ambient_UA_W_per_K;
    options.branch.chex_environment_leak_UA_W_per_K = article_hx.chex_environment_leak_UA_W_per_K;
    options.branch.cold_load_to_chex_UA_W_per_K = article_hx.cold_load_to_chex_UA_W_per_K;
    options.branch.effective_HX_UA_source = article_hx.effective_UA_source;
    options.branch.sma_pipe_internal_volume_target_ml = ...
        article.reference.sma_pipe_internal_volume_target_ml * system_scale;
    options.branch.sma_pipe_internal_volume_source = ...
        ['effective HTF inventory scaled by the Xu Table 5 net SMA volume; ', ...
        'the model uses the equivalent 100 mm axial strip.'];
    options.branch.sma_pipe_heat_transfer_multiplier = 1.0;
    options.branch.sma_pipe_heat_transfer_multiplier_source = ...
        ['unit axial pipe-to-solid discretization multiplier; the physical ', ...
        'UA is set by the new mass, heat duty and stage duration closure.'];
    options.branch.sma_stage1_pressure_bias_MPa = -0.00145;
    options.branch.sma_stage3_pressure_bias_MPa = -0.0040;
    options.branch.sma_inactive_pressure_bias_MPa = 0.0;
    options.branch.se_pressure_bias_MPa = -0.0025;
    options.branch.se_pressure_pi_kp_MPa_per_kgps = 0.0;
    options.branch.se_pressure_pi_ki_MPa_per_kgps_s = 0.0;
    options.branch.stage_command_ramp_s = ...
        0.05 * min(article.schedule.stage_durations_s);
    options.branch.sma_pipe_thermal_gate_active_G_W_per_K = 1.0e6;
    options.branch.sma_pipe_thermal_gate_inactive_G_W_per_K = 1.0e-6;
    options.branch.se_pipe_thermal_gate_active_G_W_per_K = 1.0e6;
    options.branch.se_pipe_thermal_gate_inactive_G_W_per_K = 1.0e-6;
    options.branch.boundary_T_se_chex_K = options.system.Tc_K;
    options.branch.boundary_T_se_chex_source = ...
        'article RHE/CHEX cooled-space temperature Tc';
    options.branch.source = ...
        'Xu2019_Table5_volume_scaled_finite_volume_21node_with_effective_HX_closure';
    options.branch.calibration_bounds = struct( ...
        'm_dot_kg_per_s', [0.004, 0.06], ...
        'UA_sma_shex_W_per_K', scale_bounds(article_hx.UA_sma_shex_W_per_K), ...
        'UA_sma_the_W_per_K', scale_bounds(article_hx.UA_sma_the_W_per_K), ...
        'UA_se_chex_W_per_K', scale_bounds(article_hx.UA_se_chex_W_per_K), ...
        'boundary_UA_shex_W_per_K', scale_bounds(article_hx.boundary_UA_shex_W_per_K), ...
        'boundary_UA_chex_W_per_K', scale_bounds(article_hx.boundary_UA_chex_W_per_K));

    options.solid = struct();
    options.solid.k_sma_W_per_mK = options.material.SMA.k_W_per_mK;
    options.solid.k_se_W_per_mK = 18.0;
    options.solid.axial_conduction_enabled = true;
    options.solid.boundary_condition = 'adiabatic_ends';
    options.solid.heat_recovery_efficiency = options.system.eta_hr;

    options.constitutive = struct();
    rate99_stage1 = -log(0.01) / article.schedule.stage_durations_s(1);
    rate99_stage3 = -log(0.01) / article.schedule.stage_durations_s(3);
    options.constitutive.rate_a_to_A_1_per_s = rate99_stage1;
    options.constitutive.rate_a_to_M_1_per_s = rate99_stage3;
    options.constitutive.rate_r_load_1_per_s = rate99_stage1;
    options.constitutive.rate_r_stage3_unload_1_per_s = rate99_stage3;
    options.constitutive.rate_r_stage4_unload_1_per_s = ...
        -log(0.01) / article.schedule.stage_durations_s(4);
    options.constitutive.max_rate_1_per_s = 5.0 * max([ ...
        options.constitutive.rate_a_to_A_1_per_s, ...
        options.constitutive.rate_a_to_M_1_per_s, ...
        options.constitutive.rate_r_stage4_unload_1_per_s]);
    options.constitutive.phase_front_smoothing_1_per_s = ...
        1.0 / min(article.schedule.stage_durations_s);
    options.constitutive.se_load_hardening_Pa = 0.0;
    options.constitutive.se_loading_assist_Pa = 100.0e6;
    options.constitutive.se_unload_assist_Pa = 120.0e6;
    options.constitutive.drive_width_a_Pa = ...
        options.material.SMA.C_M_Pa_per_K * ...
        (options.material.SMA.T_Af_K - options.material.SMA.T_As_K);
    options.constitutive.drive_width_r_Pa = ...
        options.material.SE.C_A_Pa_per_K * ...
        (options.material.SE.T_Af_K - options.material.SE.T_As_K);
    options.constitutive.se_loading_work_J_per_kg = options.material.SE.w_ld_J_per_kg;
    options.constitutive.se_unloading_work_J_per_kg = options.material.SE.w_uld_J_per_kg;
    options.constitutive.source = [ ...
        'SMA uses Xu2019 Table5 nominal one-dimensional reduction; ', ...
        'kinetic time constants are derived from 99 percent completion ', ...
        'over each mechanical stage.'];
    options.constitutive.simulink_sample_time_s = options.simulation.fixed_step_s;
    options.constitutive.simulink_state_width = 10 * options.node_count;
    options.constitutive.simulink_output_width = 12 * options.node_count;
    options.constitutive.simulink_heat_source_sign = ...
        'Q_node_W = -(latent_W + mechanical_W), positive into Simscape node';

    options.validation = struct();
    options.validation.min_samples_per_stage = 50;
    options.validation.max_abs_output = 1.0e10;
    options.validation.max_eq6_scaled = 1.0e-6;
    options.validation.max_eq7_scaled = 1.0e-3;
    options.validation.min_node_spread_K = 0.05;
    options.validation.max_qh_rel_error = 0.30;
    options.validation.max_qr_rel_error = 0.30;
    options.validation.max_qr_qh_rel_error = 0.30;
    options.validation.max_delta_xM_a_rel_error = 0.30;
    options.validation.max_delta_xM_r_rel_error = 0.30;
    options.validation.min_delta_xM_r = 0.70;
    options.validation.max_sigma_r_rel_error = 0.30;
    options.validation.max_Th_abs_error_K = 3.0;
    options.validation.max_energy_residual_fraction = 0.05;
    options.validation.required_authority = ...
        'physical_simscape_to_workspace_logs';
    options.validation.max_temperature_K = 450.0;
    options.validation.min_temperature_K = 220.0;
    options.validation.max_abs_stress_Pa = 1.2e9;
    options.validation.max_abs_flow_over_target = 4.0;
    options.validation.min_sma_phase_swing = 0.50;
    options.validation.nominal_sma_stress_Pa = ...
        options.material.SMA.nominal_stress_Pa;

    options.output = build_output_map(options.node_count);
    options = merge_structs(options, overrides);
    options.schedule.total_time_s = options.cycle_count * options.schedule.tau_cycle_s;
    if ~(isfield(overrides, 'simulation') && isstruct(overrides.simulation) && ...
            isfield(overrides.simulation, 'stop_time_s'))
        options.simulation.stop_time_s = ...
            options.cycle_count * options.schedule.tau_cycle_s;
    end
    options.output = build_output_map(options.node_count);
end

function hx = compute_article_heat_exchanger_closure(article)
    % The PSC waste-heat paper gives reservoir temperatures and heat rates,
    % not standalone heat-exchanger geometry, UA, mass, or heat capacity.
    % These effective conductances are finite-volume closure values derived
    % from the paper heat rates, stage durations, and temperature levels.
    sys = article.system;
    eq = article.equilibrium;
    mat = article.material;
    stage_d = article.schedule.stage_durations_s(:);
    dT_hot_K = max(eq.T_h_K - sys.T0_K, eps);
    dT_cold_lift_K = max(sys.T0_K - sys.Tc_K, eps);
    dT_psc_to_shex_K = max(sys.T_PSC_K - eq.T_h_K, eps);

    stage1_Qh_W = eq.m_a_kg * eq.qa_J_per_kg / max(stage_d(1), eps);
    stage3_SMA_to_HHEX_W = stage1_Qh_W;
    se_hot_reject_J_per_kg = mat.SE.Delta_h_J_per_kg + ...
        mat.SE.w_ld_J_per_kg + mat.SE.cp_J_per_kgK * ...
        dT_cold_lift_K * (1.0 - sys.eta_hr);
    stage2_SE_to_HHEX_W = eq.m_r_kg * se_hot_reject_J_per_kg / ...
        max(stage_d(2), eps);
    stage4_Qr_W = eq.m_r_kg * eq.qr_J_per_kg / max(stage_d(4), eps);

    hx = struct();
    hx.stage1_Qh_W = stage1_Qh_W;
    hx.stage2_SE_to_HHEX_W = stage2_SE_to_HHEX_W;
    hx.stage3_SMA_to_HHEX_W = stage3_SMA_to_HHEX_W;
    hx.stage4_Qr_W = stage4_Qr_W;
    hx.UA_sma_shex_W_per_K = stage1_Qh_W / dT_hot_K;
    hx.UA_sma_the_W_per_K = stage3_SMA_to_HHEX_W / dT_hot_K;
    hx.UA_se_the_W_per_K = stage2_SE_to_HHEX_W / dT_cold_lift_K;
    hx.UA_se_chex_W_per_K = stage4_Qr_W / dT_cold_lift_K;
    hx.boundary_UA_shex_W_per_K = hx.UA_sma_shex_W_per_K;
    hx.boundary_UA_the_W_per_K = max(hx.UA_sma_the_W_per_K, hx.UA_se_the_W_per_K);
    hx.boundary_UA_chex_W_per_K = hx.UA_se_chex_W_per_K;
    hx.shex_source_to_sink_UA_W_per_K = eq.Qh_W / dT_psc_to_shex_K;
    hx.hhex_to_ambient_UA_W_per_K = eq.Qh_W / dT_hot_K;
    hx.chex_environment_leak_UA_W_per_K = 1.0e-12;
    hx.cold_load_to_chex_UA_W_per_K = hx.UA_se_chex_W_per_K;
    hx.effective_UA_source = ...
        ['article-derived equivalent closure from Qh/Qr, stage durations, ', ...
        'Th/T0/Tc/TPSC; the paper does not report physical HX UA/C/mass.'];
    hx.reference_note = ...
        ['SHE source is PSC at TPSC, SMA hot HTF is Th, THE/HHEX is T0, ', ...
        'RHE/CHEX cooled space is Tc, and cold load heat is article Qr.'];
end

function bounds = scale_bounds(value)
    value = max(abs(value), eps);
    bounds = [0.5 * value, 2.0 * value];
end

function map = build_output_map(N)
    scalar_names = {'time_s','cycle_index','stage_id','stage_elapsed_s', ...
        'Ta_mean_K','Ta_min_K','Ta_max_K','Tr_mean_K','Tr_min_K','Tr_max_K', ...
        'xM_a_mean','xM_r_mean','sigma_a_Pa','sigma_r_Pa', ...
        'epsilon_a_mean','epsilon_r_mean','eq6_scaled','eq7_scaled', ...
        'Q_sma_shex_W','Q_sma_the_W','Q_se_the_W','Q_se_chex_W', ...
        'Q_shex_boundary_W','Q_the_sma_boundary_W', ...
        'Q_the_se_boundary_W','Q_chex_boundary_W', ...
        'latentA_W','latentR_W','mechanicalA_W','mechanicalR_W', ...
        'SMA_SHEX_mdot','SMA_THE_mdot','SE_THE_mdot','SE_CHEX_mdot', ...
        'SMA_SHEX_Tin_K','SMA_SHEX_Tout_K','SMA_THE_Tin_K','SMA_THE_Tout_K', ...
        'SE_THE_Tin_K','SE_THE_Tout_K','SE_CHEX_Tin_K','SE_CHEX_Tout_K', ...
        'SHEX_boundary_T_K','HHEX_boundary_T_K','CHEX_boundary_T_K', ...
        'Q_psc_to_shex_W','Q_ambient_to_hhex_W', ...
        'Q_environment_to_chex_W','Q_cold_load_to_chex_W', ...
        'SMA_sensible_W','SE_sensible_W','branch_storage_W','energy_residual_W'};
    map = struct();
    for idx = 1:numel(scalar_names)
        map.(scalar_names{idx}) = idx;
    end
    start = numel(scalar_names) + 1;
    array_names = {'Ta_21','Tr_21','xM_a_21','xM_r_21', ...
        'sigma_a_21','sigma_r_21','epsilon_a_21','epsilon_r_21', ...
        'pai_a_21','pai_r_21','r_xi_a_21','r_xi_r_21', ...
        'SMA_SHEX_Tin_21','SMA_SHEX_Tout_21','SMA_SHEX_Tfluid_21','SMA_SHEX_Q_21', ...
        'SMA_THE_Tin_21','SMA_THE_Tout_21','SMA_THE_Tfluid_21','SMA_THE_Q_21', ...
        'SE_THE_Tin_21','SE_THE_Tout_21','SE_THE_Tfluid_21','SE_THE_Q_21', ...
        'SE_CHEX_Tin_21','SE_CHEX_Tout_21','SE_CHEX_Tfluid_21','SE_CHEX_Q_21'};
    for idx = 1:numel(array_names)
        map.(array_names{idx}) = start:(start + N - 1);
        start = start + N;
    end
    legacy_array_names = strrep(array_names, '_21', '_51');
    for idx = 1:numel(array_names)
        map.(legacy_array_names{idx}) = map.(array_names{idx});
    end
    map.scalar_names = scalar_names;
    map.array_names = array_names;
    map.legacy_array_names = legacy_array_names;
    map.output_width = start - 1;
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
