function options = Build_HeatDriveECC_EighthRound_Defaults(overrides)
% Unified defaults for Qian 2019 21-node axial Simulink ECC validation.
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
    options.schema_version = ...
        'heatdrive_ecc_qian2019_table2_table4_simscape_defaults_v3';
    options.node_count = 21;
    options.cycle_count = 3;
    options.model_name = 'heatdrive_ecc_coupled_se21';
    options.model_path = fullfile(root_dir, [options.model_name '.slx']);
    options.outputs_dir = fullfile(root_dir, 'outputs', ...
        'heatdrive_ecc_qian2019_3cycle');
    options.report_path = fullfile(fileparts(root_dir), '项目文档', ...
        '审核分析', '当前主线物理验证报告.txt');

    options.system = article.system;
    options.system.Th_K = article.reference.T_gas_source_K;
    options.system.Tshex_K = article.reference.T_gas_source_K;
    options.system.Tshex_source_K = article.reference.T_gas_source_K;
    options.system.Thhex_K = article.reference.T_hot_K;
    options.system.Tchex_K = article.reference.T_hot_K;
    options.system.cp_fluid_J_per_kgK = ...
        article.reference.se_fluid.cp_J_per_kgK;
    options.system.thermal_mass_cp_ref_J_per_kgK = article.material.SE.cp_J_per_kgK;
    options.system.SE_heat_capacity_J_per_K = ...
        article.equilibrium.m_r_kg * article.material.SE.cp_J_per_kgK;
    options.system.cold_sink_C_J_per_K = ...
        article.reference.endpoint_reservoir_mass_kg * ...
        article.reference.se_fluid.cp_J_per_kgK;
    options.system.hot_sink_C_J_per_K = ...
        article.reference.endpoint_reservoir_mass_kg * ...
        article.reference.se_fluid.cp_J_per_kgK;
    options.system.cold_sink_capacity_multiplier_vs_SE = ...
        options.system.cold_sink_C_J_per_K / ...
        max(options.system.SE_heat_capacity_J_per_K, eps);
    options.system.hot_sink_capacity_multiplier_vs_SE = ...
        options.system.hot_sink_C_J_per_K / ...
        max(options.system.SE_heat_capacity_J_per_K, eps);
    options.system.cold_load_C_J_per_K = options.system.cold_sink_C_J_per_K;
    options.system.cold_load_heat_W = 0.0;
    options.system.cold_load_mode = 'no_load';
    options.system.cold_load_heat_reference_W = ...
        article.reference.maximum_zero_lift_specific_cooling_W_per_g * ...
        article.geometry.se_mass_kg * 1.0e3;
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
    options.system.shex_sink_C_J_per_K = ...
        article.reference.endpoint_reservoir_mass_kg * ...
        article.reference.water_cp_J_per_kgK;
    options.fluid = struct();
    options.fluid.SMA = struct( ...
        'name', 'liquid_water_IAPWS_0p5MPa', ...
        'rho_kg_per_m3', article.reference.water_rho_kg_per_m3, ...
        'cp_J_per_kgK', article.reference.water_cp_J_per_kgK, ...
        'k_W_per_mK', article.reference.water_k_W_per_mK, ...
        'mu_Pa_s', NaN, ...
        'source', 'Qian2019 Table2 water; IAPWS-IF97 0.5 MPa table');
    options.fluid.SE = article.reference.se_fluid;
    options.system.capacity_scale_source = [ ...
        'Qian2017 Table1 0.1 kg accessory reservoir closure; no invented ', ...
        '5x/10x SE capacity multipliers.'];
    options.system.fluid_domain_scope = [ ...
        'Qian uses water on the actuator side and glycol-water on the SE ', ...
        'side. The canonical SLX must retain two hydraulically disconnected ', ...
        'Thermal Liquid domains coupled only through exchanger thermal ports.'];

    options.geometry = article.geometry;
    options.material = article.material;
    options.equilibrium = article.equilibrium;
    options.schedule = article.schedule;
    options.route_matrix = article.route_matrix;

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
    options.simulation.persist_model_configuration = false;

    options.simscape = struct();
    options.simscape.local_solver_enabled = true;
    options.simscape.local_solver_choice = 'NE_BACKWARD_EULER_ADVANCER';
    options.simscape.local_solver_sample_time_s = 1.0e-3;

    options.branch = struct();
    options.branch.m_dot_kg_per_s = article.reference.se_m_dot_kg_per_s;
    options.branch.m_dot_sma_shex_kg_per_s = ...
        article.reference.sma_m_dot_kg_per_s;
    options.branch.m_dot_sma_the_kg_per_s = ...
        article.reference.sma_m_dot_kg_per_s;
    options.branch.m_dot_se_the_kg_per_s = ...
        article.reference.se_m_dot_kg_per_s;
    options.branch.m_dot_se_chex_kg_per_s = ...
        article.reference.se_m_dot_kg_per_s;
    options.branch.fluid_mass_total_kg = ...
        article.geometry.se_fluid_void_volume_m3 * ...
        article.reference.se_fluid.rho_kg_per_m3;
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
        article.geometry.driver_volume_m3 * ...
        article.reference.sma_porosity * 1.0e6;
    options.branch.sma_pipe_internal_volume_source = ...
        ['Qian Table4 driver wire-bundle void volume; the model uses ', ...
        'the equivalent 21-node axial branch.'];
    options.branch.sma_pipe_heat_transfer_multiplier = 1.0;
    options.branch.sma_pipe_heat_transfer_multiplier_source = ...
        ['unit axial pipe-to-solid discretization multiplier; the physical ', ...
        'UA is set by the new mass, heat duty and stage duration closure.'];
    % Stage-specific pump-pressure closures are calibrated only against the
    % physical Simscape mass-flow logs.  They are not thermal-state
    % assignments and remain separate because the valve topology changes.
    options.branch.sma_stage1_pressure_bias_MPa = -0.0480;
    options.branch.sma_stage3_pressure_bias_MPa = -0.0454;
    options.branch.sma_inactive_pressure_bias_MPa = 0.0;
    % The SE branch has different hydraulic losses in stages 2 and 4.
    % Keep the old scalar as a fallback, but expose the two active-stage
    % commands so flow calibration cannot silently couple the two routes.
    options.branch.se_pressure_bias_MPa = -0.0015;
    options.branch.se_stage2_pressure_bias_MPa = -0.002754;
    options.branch.se_stage4_pressure_bias_MPa = -0.001480;
    options.branch.se_inactive_pressure_bias_MPa = 0.0;
    % The old -0.02 MPa ceiling clipped the SMA calibration, but the
    % pressure source is referenced to the model's absolute TL pressure
    % network.  Keep the validated operating range below the first
    % pressure-invalid trial; the remaining flow gap must be solved by the
    % hydraulic geometry/reference, not by an illegal negative pressure.
    options.branch.pressure_pi_min_MPa = -0.05;
    options.branch.pressure_pi_max_MPa = 0.02;
    options.branch.sma_hydraulic_area_scale = 2.50;
    options.branch.sma_hydraulic_area_source = ...
        ['Qian Table4 SMA water flow target closure; SMA and SE ', ...
        'branches use independent axial hydraulic areas while the ', ...
        'Simulink topology and thermal state model remain unchanged.'];
    options.branch.valve_min_Cv = 0.005;
    options.branch.valve_min_Cv_source = ...
        'continuous Simscape liquid pressure-reference leakage closure';
    options.branch.sma_source_select_valve_min_Cv = 1.0e-4;
    options.branch.sma_source_select_valve_min_Cv_source = [ ...
        'separate V1/V2 closed-state leakage contract; accepted by the ', ...
        '2026-08-03 three-cycle physical buffer-isolation regression'];
    options.branch.se_pressure_pi_kp_MPa_per_kgps = -1.0;
    options.branch.se_pressure_pi_ki_MPa_per_kgps_s = -2.0;
    options.branch.stage_command_ramp_s = ...
        0.10 * min(article.schedule.stage_durations_s);
    options.branch.sma_pipe_thermal_gate_active_G_W_per_K = 1.0e6;
    options.branch.sma_pipe_thermal_gate_inactive_G_W_per_K = 1.0e-6;
    options.branch.se_pipe_thermal_gate_active_G_W_per_K = 1.0e6;
    options.branch.se_pipe_thermal_gate_inactive_G_W_per_K = 1.0e-6;
    options.branch.boundary_T_se_chex_K = options.system.Tc_K;
    options.branch.boundary_T_se_chex_source = ...
        'Qian2019 Table4 CHEX cooled-end reference temperature';
    options.branch.source = ...
        'Qian2019_Table4_flow_utilization_geometry_with_explicit_HX_closure';
    options.branch.calibration_bounds = struct( ...
        'm_dot_kg_per_s', [0.002, 0.06], ...
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
    rate99_stage1 = -log(0.01) / article.schedule.loading_transform_s;
    rate99_stage3 = -log(0.01) / article.schedule.unloading_transform_s;
    options.constitutive.rate_a_to_A_1_per_s = rate99_stage1;
    options.constitutive.rate_a_to_M_1_per_s = rate99_stage3;
    options.constitutive.rate_r_load_1_per_s = rate99_stage1;
    options.constitutive.rate_r_stage3_unload_1_per_s = rate99_stage3;
    options.constitutive.rate_r_stage4_unload_1_per_s = ...
        rate99_stage3;
    options.constitutive.max_rate_1_per_s = 5.0 * max([ ...
        options.constitutive.rate_a_to_A_1_per_s, ...
        options.constitutive.rate_a_to_M_1_per_s, ...
        options.constitutive.rate_r_stage4_unload_1_per_s]);
    options.constitutive.phase_front_smoothing_1_per_s = ...
        1.0 / min(article.schedule.stage_durations_s);
    options.constitutive.se_load_hardening_Pa = 0.0;
    options.constitutive.se_loading_assist_Pa = 0.0;
    options.constitutive.se_unload_assist_Pa = 0.0;
    options.constitutive.phase_surface_min_width_Pa = 1.0e6;
    options.constitutive.drive_width_a_Pa = ...
        options.constitutive.phase_surface_min_width_Pa;
    options.constitutive.drive_width_r_Pa = ...
        options.constitutive.phase_surface_min_width_Pa;
    options.constitutive.se_loading_work_J_per_kg = options.material.SE.w_ld_J_per_kg;
    options.constitutive.se_unloading_work_J_per_kg = options.material.SE.w_uld_J_per_kg;
    options.constitutive.source = [ ...
        'Qian2019 Eq3 reduced directional kinetics. Table2 As/Ms are ', ...
        'start-line gates, not fabricated Af/Mf finish temperatures. ', ...
        'Finite rates use the Fig3 0.9 s loading and 1.9 s unloading windows.'];
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
    options.validation.min_active_flow_fraction_of_target = 0.10;
    options.validation.max_active_flow_relative_error = 0.15;
    options.validation.max_inactive_core_flow_fraction_of_target = 0.01;
    options.validation.max_stage1_HHEX_SMA_buffer_rise_K = 5.0;
    options.validation.max_stage3_SHEX_buffer_above_source_K = 3.0;
    options.validation.max_periodic_endpoint_drift_K = 0.05;
    options.validation.max_periodic_same_phase_temperature_drift_K = 0.05;
    options.validation.max_periodic_phase_drift = 1.0e-4;
    options.validation.min_sma_phase_swing = 0.50;
    options.validation.nominal_sma_stress_Pa = ...
        options.material.SMA.nominal_stress_Pa;
    options.validation.reference_system_scope = ...
        'Qian2019_Table4_complete_heat_driven_SMA_plus_SE_system';
    options.validation.strict_table4_reproduction_applicable = true;
    options.validation.strict_table4_reproduction_evaluated = false;
    options.validation.strict_table4_reproduction_pass = false;
    options.validation.dual_fluid_domain_required = true;
    options.validation.dual_fluid_domain_implemented = false;
    options.validation.table4_max_no_load_lift_K = ...
        article.reference.maximum_no_load_lift_K;
    options.validation.table4_zero_lift_specific_cooling_W_per_g = ...
        article.reference.maximum_zero_lift_specific_cooling_W_per_g;

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
    % Qian reports bed geometry, fluids and flow rates but not every
    % accessory UA.  Solid-fluid UA follows the reported geometry and
    % Nu=3.66.  Endpoint contact uses the Qian-2017 mixed-tank 99% finite-NTU
    % closure already audited in the standalone SE workspace.
    eq = article.equilibrium;
    mat = article.material;
    ref = article.reference;
    g = article.geometry;
    stage_d = article.schedule.stage_durations_s(:);
    driver_void_area_m2 = ref.sma_porosity / (1.0 - ref.sma_porosity) * ...
        g.S_a_m2;
    driver_wetted_perimeter_m = ref.sma_wire_count * pi * ...
        ref.sma_wire_diameter_m;
    driver_hydraulic_diameter_m = 4.0 * driver_void_area_m2 / ...
        driver_wetted_perimeter_m;
    driver_wetted_area_m2 = driver_wetted_perimeter_m * g.L_a_m;
    driver_h_W_per_m2K = ref.driver_htc_calibration_factor * 3.66 * ...
        ref.water_k_W_per_mK / driver_hydraulic_diameter_m;
    driver_UA_W_per_K = driver_h_W_per_m2K * driver_wetted_area_m2;
    se_h_W_per_m2K = 3.66 * ref.se_fluid.k_W_per_mK / ...
        g.se_hydraulic_diameter_m;
    se_UA_W_per_K = se_h_W_per_m2K * g.se_wetted_area_m2;
    endpoint_capacity_rate_W_per_K = ref.se_m_dot_kg_per_s * ...
        ref.se_fluid.cp_J_per_kgK;
    endpoint_overall_UA_W_per_K = -log(0.01) * ...
        endpoint_capacity_rate_W_per_K;
    endpoint_contact_G_W_per_K = 10.0 * endpoint_overall_UA_W_per_K;

    stage1_Qh_W = eq.m_a_kg * eq.qa_J_per_kg / ...
        max(stage_d(1), eps);
    stage3_SMA_to_HHEX_W = stage1_Qh_W;
    se_hot_reject_J_per_kg = mat.SE.Delta_h_J_per_kg;
    stage2_SE_to_HHEX_W = eq.m_r_kg * se_hot_reject_J_per_kg / ...
        max(stage_d(2), eps);
    stage4_Qr_W = eq.m_r_kg * eq.qr_J_per_kg / max(stage_d(4), eps);

    hx = struct();
    hx.stage1_Qh_W = stage1_Qh_W;
    hx.stage2_SE_to_HHEX_W = stage2_SE_to_HHEX_W;
    hx.stage3_SMA_to_HHEX_W = stage3_SMA_to_HHEX_W;
    hx.stage4_Qr_W = stage4_Qr_W;
    hx.UA_sma_shex_W_per_K = driver_UA_W_per_K;
    hx.UA_sma_the_W_per_K = driver_UA_W_per_K;
    hx.UA_se_the_W_per_K = se_UA_W_per_K;
    hx.UA_se_chex_W_per_K = se_UA_W_per_K;
    hx.boundary_UA_shex_W_per_K = endpoint_overall_UA_W_per_K;
    hx.boundary_UA_the_W_per_K = endpoint_overall_UA_W_per_K;
    hx.boundary_UA_chex_W_per_K = endpoint_overall_UA_W_per_K;
    hx.shex_source_to_sink_UA_W_per_K = endpoint_contact_G_W_per_K;
    hx.hhex_to_ambient_UA_W_per_K = endpoint_contact_G_W_per_K;
    hx.chex_environment_leak_UA_W_per_K = 1.0e-12;
    hx.cold_load_to_chex_UA_W_per_K = endpoint_overall_UA_W_per_K;
    hx.driver_hydraulic_diameter_m = driver_hydraulic_diameter_m;
    hx.driver_wetted_area_m2 = driver_wetted_area_m2;
    hx.driver_h_W_per_m2K = driver_h_W_per_m2K;
    hx.se_h_W_per_m2K = se_h_W_per_m2K;
    hx.endpoint_overall_UA_W_per_K = endpoint_overall_UA_W_per_K;
    hx.endpoint_contact_G_W_per_K = endpoint_contact_G_W_per_K;
    hx.effective_UA_source = ...
        ['Qian Table4 geometry and flow with Nu=3.66; driver HTC factor 3.5 ', ...
        'and Qian2017 99 percent endpoint NTU are declared closures.'];
    hx.reference_note = ...
        ['SHEX gas source is 393.15 K; HHEX/CHEX reference is 303.15 K. ', ...
        'Table4 Qr remains an acceptance reference, not an imposed load.'];
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
