function options = Build_PerovskiteECC_Default_Options(overrides)
% Build default options for the paper-aligned axial ECC model.
%
% The geometry is represented only by length L and cross-sectional area S,
% matching the paper Eq. 6-21 abstraction. The default cross-section label is
% generic_area; no plate, rectangular strip, or wire diameter is implied.

    if nargin < 1
        overrides = struct();
    end

    root_dir = fileparts(mfilename('fullpath'));

    options = struct();
    options.schema_version = 'perovskite_psc_ecc_article_eq1_26_v1';
    options.model_family = 'perovskite_psc_ecc_article_reproduction';
    options.source_paper_section = 'Sections 2.1-2.3, Eq. 1-26';
    options.node_count = 51;
    options.cycle_count = 1;
    options.stage_steps = 40;
    options.cycle_frequency_Hz = 1.0;
    options.write_outputs = true;
    options.outputs_dir = fullfile(root_dir, 'outputs_perovskite_ecc');

    options.geometry = struct();
    options.geometry.cross_section_shape = 'generic_area';
    options.geometry.L_a_m = 1.0;
    options.geometry.L_r_m = 0.4;
    options.geometry.S_a_m2 = 1.0e-6;
    options.geometry.S_r_m2 = 0.2e-6;
    options.geometry.L_r_over_L_a = 0.4;
    options.geometry.S_r_over_S_a = 0.2;

    options.system = struct();
    options.system.T_c_K = 288.0;
    options.system.T0_K = 308.0;
    options.system.eta_hr = 0.7;
    options.system.G_W_per_m2 = 1000.0;
    options.system.A_PSC_m2 = 15.57 / (0.1731 * 1000.0);
    options.system.Qh_W = NaN;

    options.psc = struct();
    options.psc.T_PSC_K = 345.0;
    options.psc.Eg_eV = 1.55;
    options.psc.Rs_ohm_m2 = 9.0e-4;
    options.psc.Rsh_ohm_m2 = 1.2;
    options.psc.q_C = 1.6e-19;
    options.psc.h_eV_s = 4.14e-15;
    options.psc.c_m_per_s = 3.0e8;
    options.psc.kB_J_per_K = 1.38e-23;
    options.psc.ideality_factor = 1.0;
    options.psc.voltage_min_V = 0.0;
    options.psc.voltage_max_V = 1.25;
    options.psc.voltage_points = 501;
    options.psc.article_reference = struct( ...
        'Vm_V', 0.96, ...
        'P_PSC_max_W', 15.57, ...
        'eta_PSC_max', 0.1731);
    options.psc.calibration_mode = 'article_mpp_reverse_calibration';

    options.psc_ecc = struct();
    options.psc_ecc.K_L_W_per_m2K = NaN;
    options.psc_ecc.calibrate_K_L_to_article_PH = true;
    options.psc_ecc.article_reference = struct( ...
        'P_H_max_W', 19.19, ...
        'eta_H_max', 0.2132, ...
        'P_H_lift_fraction', 0.2325, ...
        'eta_H_lift_fraction', 0.2317);

    options.material = struct();
    options.material.SMA = build_material('actuator_sma', 323.0, 343.0, 293.0, 313.0);
    options.material.SE = build_material('refrigerant_se', 268.0, 288.0, 238.0, 258.0);
    options.material.SE.w_uld_J_per_kg = 4.1e3;
    options.material.SE.w_ld_J_per_kg = 5.6e3;

    options.d2_kernel = struct();
    options.d2_kernel.enabled = true;
    options.d2_kernel.entropy_change_J_per_kgK = -36.0;
    options.d2_kernel.H_forward_Pa = 0.5e6;
    options.d2_kernel.H_reverse_Pa = 0.5e6;
    options.d2_kernel.H_shape_Pa = 0.2e6;
    options.d2_kernel.X0_Pa = 1.0e6;
    options.d2_kernel.rate_exponent = 1.0;
    options.d2_kernel.rate_coefficient_1_per_s = 4.0;
    options.d2_kernel.rate_limit_1_per_s = 50.0;
    options.d2_kernel.transformation_threshold_Pa = 0.1e6;

    options.controls = struct();
    options.controls.pump_threshold_xM_sma = 0.5;
    options.controls.stage_valve_open_signal = 1.0;
    options.controls.stage_valve_closed_signal = 0.0;

    options.numerics = struct();
    options.numerics.coupling_tolerance = 1.0e-10;
    options.numerics.coupling_max_iterations = 80;
    options.numerics.coupling_grid_points = 2001;
    options.numerics.max_residual_ok = 1.0e-7;
    options.numerics.min_temperature_K = 1.0;

    options.validation = struct();
    options.validation.required_node_count = 51;
    options.validation.main_model_is_axial = true;
    options.validation.deprecated_first_round_route = ...
        'GlobalXi/round-plate/pressure/u-w/101-node surrogate route is not used by PerovskiteECC.';

    options = merge_structs(options, overrides);
    options = normalize_geometry(options);
end

function material = build_material(name, T_As_K, T_Af_K, T_Mf_K, T_Ms_K)
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

function options = normalize_geometry(options)
    g = options.geometry;
    if isfield(g, 'L_r_over_L_a') && isfinite(g.L_r_over_L_a)
        g.L_r_m = g.L_a_m * g.L_r_over_L_a;
    else
        g.L_r_over_L_a = g.L_r_m / g.L_a_m;
    end
    if isfield(g, 'S_r_over_S_a') && isfinite(g.S_r_over_S_a)
        g.S_r_m2 = g.S_a_m2 * g.S_r_over_S_a;
    else
        g.S_r_over_S_a = g.S_r_m2 / g.S_a_m2;
    end
    g.volume_a_m3 = g.L_a_m * g.S_a_m2;
    g.volume_r_m3 = g.L_r_m * g.S_r_m2;
    options.geometry = g;
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
