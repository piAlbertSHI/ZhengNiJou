function options = Build_HeatDriveECC_Article_Defaults(overrides)
% Build the coupled-cycle parameter contract.
%
% Both solid elements are one-dimensional axial NiTi representations.  The
% material temperatures, transformation strain, heat capacity, density and
% latent heat come from Qian et al. 2019 Table 2.  The SE bed, driver wire
% bundle, flow rates, utilization, exchange time and reservoir temperatures
% come from Qian et al. 2019 Table 4.  Quantities absent from those tables
% are retained as explicit Qian-2017 accessory closures or derived values.

    if nargin < 1
        overrides = struct();
    end

    root_dir = fileparts(mfilename('fullpath'));
    options = struct();
    options.schema_version = 'heatdrive_ecc_qian2019_table2_table4_defaults_v4';
    options.model_name = 'heatdrive_ecc_coupled_se21';
    options.model_path = fullfile(root_dir, [options.model_name, '.slx']);
    options.outputs_dir = fullfile(root_dir, 'outputs', ...
        'heatdrive_ecc_qian2019_3cycle');
    options.cycle_count = 3;
    options.node_count = 21;

    options.reference = build_reference_contract();
    options.material = struct();
    options.material.SMA = qian_table2_driver_material();
    options.material.SE = qian_table2_se_material();
    options.geometry = build_equivalent_geometry(options.material, options.reference);

    scale = options.geometry.volume_scale_vs_previous;
    options.system = struct();
    options.system.Tc_K = options.reference.T_hot_K;
    options.system.T0_K = options.reference.T_hot_K;
    options.system.eta_hr = 0.0;
    options.system.G_W_per_m2 = NaN;
    options.system.A_PSC_m2 = NaN;
    options.system.T_PSC_K = options.reference.T_gas_source_K;
    options.system.hot_side_approach_K = 0.0;
    options.system.P_PSC_W = NaN;
    options.system.Qh_reference_W = NaN;
    options.system.P_H_W = NaN;
    options.system.extensive_scale = scale;
    options.system.temperature_source = [ ...
        'Qian2019 Table4 gas source 393.15 K, hot/cold endpoint ', ...
        'reference 303.15 K; no solar collector boundary is used.'];
    options.system.extensive_scale_source = [ ...
        'Solid volumes and endpoint capacities are derived from Qian2019 ', ...
        'Table4 geometry and Qian2017 accessory reservoir closure.'];

    options = finalize_derived_options(options, struct());
    options = merge_structs(options, overrides);
    options = finalize_derived_options(options, overrides);
end

function reference = build_reference_contract()
    reference = struct();
    reference.previous_sma_volume_m3 = 1.0e-6;
    reference.T_gas_source_K = 393.15;
    reference.T_hot_K = 303.15;
    reference.T_initial_K = 303.15;
    reference.se_m_dot_kg_per_s = 3.2e-3;
    reference.sma_m_dot_kg_per_s = 50.8e-3;
    reference.se_exchange_time_s = 1.5;
    reference.cycle_frequency_Hz = 0.1;
    reference.sma_heating_time_s = 5.0;
    reference.sma_cooling_time_s = 5.0;
    reference.se_utilization = 1.7;
    reference.se_porosity = 0.42;
    reference.se_plate_count = 2;
    reference.se_plate_thickness_m = 0.50e-3;
    reference.se_plate_width_m = 17.0e-3;
    reference.se_channel_spacing_m = 0.50e-3;
    reference.sma_wire_count = 32;
    reference.sma_wire_diameter_m = 1.0e-3;
    reference.sma_porosity = 0.75;
    reference.driver_to_se_mass_ratio = 3.2;
    reference.maximum_no_load_lift_K = 26.2;
    reference.maximum_zero_lift_specific_cooling_W_per_g = 0.64;
    reference.endpoint_reservoir_mass_kg = 0.1;
    reference.water_cp_J_per_kgK = 4180.0;
    reference.water_rho_kg_per_m3 = 997.0;
    reference.water_k_W_per_mK = 0.60;
    reference.water_mu_Pa_s = 7.9722e-4;
    reference.fully_developed_laminar_Nu = 3.66;
    reference.se_natural_convection_h_W_per_m2K = 50.0;
    reference.se_natural_convection_source = ...
        'Qian2019 Table2 SE-bed natural convective HTC';
    reference.connecting_pipe_diameter_m = 3.2e-3;
    reference.connecting_pipe_length_m = 0.2;
    reference.connecting_pipe_wall_thickness_m = 0.5e-3;
    reference.connecting_pipe_source = 'Qian2019 Table2 connecting HTF pipes';
    reference.se_fluid = struct( ...
        'name', '40vol_percent_inhibited_propylene_glycol_water_closure', ...
        'volume_fraction_propylene_glycol', 0.40, ...
        'reference_temperature_K', 303.15, ...
        'rho_kg_per_m3', 1044.97333333333, ...
        'cp_J_per_kgK', 3638.0, ...
        'k_W_per_mK', 0.407866666666667, ...
        'mu_Pa_s', 0.00330735934424454, ...
        'freezing_point_K', 252.05, ...
        'minimum_operating_temperature_K', 255.05, ...
        'maximum_tabulated_temperature_K', 393.15, ...
        'source', [ ...
            'Qian2019 Table2 reports glycol-water without concentration. ', ...
            'The 40 vol% inhibited propylene-glycol closure is selected ', ...
            'because its Dow DOWFROST HD -21.1 degC freeze point preserves ', ...
            'the recommended 3 K margin below the SE TMs=-15 degC state. ', ...
            'Reference properties at 303.15 K interpolate the official ', ...
            '10/40 degC 40 vol% table; viscosity uses log interpolation.']);
    reference.source = [ ...
        'Qian2019 Table2/Table4 plus Qian2017 Table1 endpoint reservoir ', ...
        'closure; unreported fluid concentration remains explicit; ', ...
        'SMA forced convection uses Qian2017 Eq15 entrance correction ', ...
        'without an empirical multiplier'];
end

function material = qian_table2_driver_material()
    material = struct();
    material.name = 'Qian2019_Table2_Actuator_NiTi';
    material.parameter_source = [ ...
        'Qian et al. 2019 Table 2 actuator SMA: As=50 degC, ', ...
        'Ms=40 degC; shared NiTi CA/CM/E/epsilon_t/cp/rho/latent entries. ', ...
        'Fig.5 explicitly plots 100/50/0 percent martensite surfaces; ', ...
        'their outer intercepts are closed with the Table 2 TMs/TAs entries.'];
    material.E_A_Pa = 30.0e9;
    material.E_M_Pa = 30.0e9;
    material.E_m_Pa = material.E_M_Pa;
    material.nu_A = 0.33;
    material.nu_M = 0.33;
    material.alpha_A_1_per_K = 1.0e-5;
    material.alpha_M_1_per_K = 1.0e-5;
    material.C_A_Pa_per_K = 7.6e6;
    material.C_M_Pa_per_K = 7.3e6;
    material.T_Ms_K = 313.15;
    material.T_Mf_K = NaN;
    material.T_As_K = 323.15;
    material.T_Af_K = NaN;
    material.Hmax_initial = 0.03;
    material.Hmax_final = 0.03;
    material.Hmin = 0.0;
    material.k_t_1_per_MPa = NaN;
    material.k_t_1_per_Pa = NaN;
    material.tau_crit_Pa = NaN;
    material.n1 = NaN;
    material.n2 = NaN;
    material.n3 = NaN;
    material.n4 = NaN;
    material.sigma_b_Pa = NaN;
    material.lambda1 = NaN;
    material.Cp1 = NaN;
    material.Cp2 = NaN;
    material.nominal_stress_Pa = 200.0e6;
    material.thermal_cycle_min_K = 303.15;
    material.thermal_cycle_max_K = 393.15;
    material.rho_kg_per_m3 = 6500.0;
    material.cp_J_per_kgK = 500.0;
    material.k_W_per_mK = 18.0;
    material.epsilon_T = 0.03;
    material.Delta_h_J_per_kg = 10.0e3;
    material.Delta_s0_J_per_kgK = material.Delta_h_J_per_kg / ...
        mean([material.T_As_K, material.T_Ms_K]);
    material.transformation_reference_T_K = ...
        mean([material.T_As_K, material.T_Ms_K]);
    material.Hcur_nominal = material.epsilon_T;
    material.w_uld_J_per_kg = 0.0;
    material.w_ld_J_per_kg = 0.0;
    material.thermophysical_source = ...
        'Qian2019 Table 2 values with Fig.5 plotted phase-surface closure';
end

function material = qian_table2_se_material()
    material = struct();
    material.name = 'Qian2019_Table2_SE_NiTi';
    material.parameter_source = [ ...
        'Qian et al. 2019 Table 2 refrigerant SE. Fig.5 explicitly ', ...
        'plots 100/50/0 percent martensite surfaces; their outer ', ...
        'intercepts are closed with the Table 2 TMs/TAs entries.'];
    material.C_M_Pa_per_K = 7.3e6;
    material.C_A_Pa_per_K = 7.6e6;
    material.E_A_Pa = 30.0e9;
    material.E_M_Pa = 30.0e9;
    material.E_Pa = 30.0e9;
    material.E_m_Pa = 30.0e9;
    material.nu_A = 0.33;
    material.nu_M = 0.33;
    material.alpha_A_1_per_K = 1.0e-5;
    material.alpha_M_1_per_K = 1.0e-5;
    material.T_As_K = 268.15;
    material.T_Af_K = NaN;
    material.T_Ms_K = 258.15;
    material.T_Mf_K = NaN;
    material.Hmax_initial = 0.03;
    material.Hmax_final = 0.03;
    material.Hmin = 0.0;
    material.epsilon_T = 0.03;
    material.thermal_cycle_min_K = 276.95;
    material.thermal_cycle_max_K = 303.15;
    material.cp_J_per_kgK = 500.0;
    material.Delta_h_J_per_kg = 1.0e4;
    material.rho_kg_per_m3 = 6500.0;
    material.k_W_per_mK = 18.0;
    material.transformation_reference_T_K = ...
        mean([material.T_As_K, material.T_Ms_K]);
    material.Delta_s0_J_per_kgK = material.Delta_h_J_per_kg / ...
        material.transformation_reference_T_K;
    material.w_uld_J_per_kg = 0.0;
    material.w_ld_J_per_kg = 0.0;
    material.thermophysical_source = ...
        'Qian2019 Table 2 values with Fig.5 plotted phase-surface closure';
end

function geometry = build_equivalent_geometry(material, reference)
    sma = material.SMA;
    se = material.SE;
    se_cross_section_m2 = reference.se_plate_count * ...
        reference.se_plate_thickness_m * reference.se_plate_width_m;
    % Qian2019 Section 3.1 explicitly redefines the reported bed porosity as
    % epsilon = V_HTF / V_solid.  For a uniform axial bed this gives
    % A_void/A_solid=epsilon; the conventional Qian2017 Eq.4 definition must
    % not be substituted into the 2019 Table 4 prototype geometry.
    se_void_area_m2 = reference.se_porosity * se_cross_section_m2;
    % Qian2017 Eq. (18) defines utilization as the fluid volume displaced
    % during one blow divided by the bed void volume. Fluid cp appears in
    % both numerator and denominator and cancels; this is not a fluid/solid
    % heat-capacity ratio.
    se_length_m = reference.se_m_dot_kg_per_s * ...
        reference.se_exchange_time_s / ...
        (reference.se_fluid.rho_kg_per_m3 * ...
        reference.se_utilization * se_void_area_m2);
    se_volume_m3 = se_cross_section_m2 * se_length_m;
    se_mass_kg = se.rho_kg_per_m3 * se_volume_m3;
    driver_cross_section_m2 = reference.sma_wire_count * pi * ...
        reference.sma_wire_diameter_m ^ 2 / 4.0;
    driver_mass_kg = reference.driver_to_se_mass_ratio * se_mass_kg;
    driver_volume_m3 = driver_mass_kg / sma.rho_kg_per_m3;
    driver_length_m = driver_volume_m3 / driver_cross_section_m2;
    driver_void_area_m2 = reference.sma_porosity * driver_cross_section_m2;
    sigma_sma_Pa = sma.nominal_stress_Pa;
    sigma_se_Pa = sigma_sma_Pa * driver_cross_section_m2 / ...
        se_cross_section_m2;

    geometry = struct();
    geometry.shape = 'qian2019_table4_axial_wire_bundle_plus_two_plate_se';
    geometry.L_a_m = driver_length_m;
    geometry.width_a_m = reference.sma_wire_count * ...
        reference.sma_wire_diameter_m;
    geometry.S_a_m2 = driver_cross_section_m2;
    geometry.thickness_a_m = geometry.S_a_m2 / ...
        max(geometry.width_a_m, eps);
    geometry.net_sma_volume_m3 = driver_volume_m3;
    geometry.gross_sma_volume_m3 = driver_volume_m3;
    geometry.hole_volume_m3 = 0.0;
    geometry.volume_scale_vs_previous = ...
        driver_volume_m3 / reference.previous_sma_volume_m3;
    geometry.se_cross_section_m2 = se_cross_section_m2;
    geometry.se_volume_m3 = se_volume_m3;
    geometry.se_mass_kg = se_mass_kg;
    geometry.se_porosity = reference.se_porosity;
    geometry.se_utilization = reference.se_utilization;
    geometry.se_utilization_definition = ...
        'displaced_fluid_volume_per_blow_over_bed_void_volume_Qian2017_Eq18';
    geometry.porosity_definition = 'V_HTF_over_V_solid_Qian2019_Section3p1';
    geometry.se_plate_count = reference.se_plate_count;
    geometry.se_plate_thickness_m = reference.se_plate_thickness_m;
    geometry.se_plate_width_m = reference.se_plate_width_m;
    geometry.se_channel_spacing_m = reference.se_channel_spacing_m;
    geometry.se_fluid_void_area_m2 = se_void_area_m2;
    geometry.se_fluid_void_volume_m3 = se_void_area_m2 * se_length_m;
    geometry.se_porosity_calculated = se_void_area_m2 / se_cross_section_m2;
    geometry.se_utilization_calculated = reference.se_m_dot_kg_per_s * ...
        reference.se_exchange_time_s / ...
        (reference.se_fluid.rho_kg_per_m3 * ...
        geometry.se_fluid_void_volume_m3);
    geometry.se_wetted_perimeter_m = reference.se_plate_count * ...
        2.0 * reference.se_plate_width_m;
    geometry.se_wetted_area_m2 = geometry.se_wetted_perimeter_m * se_length_m;
    geometry.se_hydraulic_diameter_m = 4.0 * se_void_area_m2 / ...
        geometry.se_wetted_perimeter_m;
    geometry.plate_length_m = se_length_m;
    geometry.plate_count = reference.se_plate_count;
    geometry.plate_thickness_m = reference.se_plate_thickness_m;
    geometry.plate_width_m = reference.se_plate_width_m;
    geometry.channel_spacing_m = reference.se_channel_spacing_m;
    geometry.porosity = reference.se_porosity;
    geometry.solid_cross_section_m2 = se_cross_section_m2;
    geometry.fluid_void_area_m2 = se_void_area_m2;
    geometry.fluid_void_volume_m3 = geometry.se_fluid_void_volume_m3;
    geometry.wetted_area_m2 = geometry.se_wetted_area_m2;
    geometry.natural_convection_area_m2 = geometry.wetted_area_m2;
    geometry.node_dx_m = se_length_m / 21.0;
    geometry.driver_cross_section_m2 = driver_cross_section_m2;
    geometry.driver_wire_count = reference.sma_wire_count;
    geometry.driver_wire_diameter_m = reference.sma_wire_diameter_m;
    geometry.driver_porosity = reference.sma_porosity;
    geometry.driver_fluid_void_area_m2 = driver_void_area_m2;
    geometry.driver_fluid_void_volume_m3 = ...
        driver_void_area_m2 * driver_length_m;
    geometry.driver_porosity_calculated = ...
        driver_void_area_m2 / driver_cross_section_m2;
    geometry.driver_volume_m3 = driver_volume_m3;
    geometry.driver_mass_kg = driver_mass_kg;
    geometry.driver_length_m = driver_length_m;
    geometry.sigma_sma_design_Pa = sigma_sma_Pa;
    geometry.sigma_se_design_Pa = sigma_se_Pa;
    geometry.S_r_over_S_a = se_cross_section_m2 / driver_cross_section_m2;
    geometry.L_r_over_L_a = se_length_m / driver_length_m;
    geometry.L_r_m = se_length_m;
    geometry.S_r_m2 = se_cross_section_m2;
    geometry.width_r_m = reference.se_plate_width_m;
    geometry.thickness_r_m = se_cross_section_m2 / ...
        max(geometry.width_r_m, eps);
    geometry.compatibility_source = [ ...
        'Qian2019 Table4 plate/wire geometry and Section3.1 ', ...
        'V_HTF/V_solid porosity; ', ...
        'force ratio uses sigma_a*Sa=sigma_r*Sr and lengths use ', ...
        'Qian2017 Eq18 displaced-volume utilization.'];
    geometry.geometry_source = ...
        'Qian2019 Table 4 plus Qian2017 Eq18 derived axial lengths';
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
    T_h_K = sys.T_PSC_K;
    T_transform_start_K = ...
        sma.T_As_K + sigma_a_Pa / sma.C_A_Pa_per_K;
    mu = g.L_r_over_L_a * g.S_r_over_S_a * ...
        (se.rho_kg_per_m3 / sma.rho_kg_per_m3);
    qa = sma.cp_J_per_kgK * (T_h_K - sys.T0_K) * ...
        (1.0 - sys.eta_hr) + sma.Delta_h_J_per_kg * delta_xM_a + ...
        se.w_ld_J_per_kg * mu;
    qr = se.Delta_h_J_per_kg + se.w_uld_J_per_kg;
    m_a = sma.rho_kg_per_m3 * g.L_a_m * g.S_a_m2;
    m_r = se.rho_kg_per_m3 * g.L_r_m * g.S_r_m2;
    Qh = m_a * qa * reference_frequency(options);
    Qr = reference_zero_lift_cooling(options, m_r);
    P_H = Qr;
    K_L = NaN;
    nu = options.reference.cycle_frequency_Hz;

    eq = struct();
    eq.delta_xM_a = delta_xM_a;
    eq.delta_xM_r = 1.0;
    eq.sigma_r_Pa = sigma_r_Pa;
    eq.sigma_a_Pa = sigma_a_Pa;
    eq.T_h_K = T_h_K;
    eq.T_transform_start_K = T_transform_start_K;
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
    eq.etaECC = Qr / max(Qh, eps);
    eq.nu_Hz = nu;
    eq.tau_cycle_s = 1.0 / nu;
    eq.K_L_W_per_m2K = K_L;
    eq.source = [ ...
        'Qian2019 Table2/Table4 design point; Qh is derived from ', ...
        'SMA sensible plus latent heat per 0.1 Hz cycle, Qr is a ', ...
        'Table4 zero-lift reference only and is never injected as a state.'];
end

function frequency_Hz = reference_frequency(options)
    frequency_Hz = options.reference.cycle_frequency_Hz;
end

function Qr_W = reference_zero_lift_cooling(options, se_mass_kg)
    Qr_W = options.reference.maximum_zero_lift_specific_cooling_W_per_g * ...
        se_mass_kg * 1.0e3;
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
