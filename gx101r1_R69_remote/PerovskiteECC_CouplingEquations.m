function result = PerovskiteECC_CouplingEquations(options, mode)
% Solve and audit paper Eq. 6-15 for a single axial ECC stage.

    if nargin < 1 || isempty(options)
        options = Build_PerovskiteECC_Default_Options();
    end
    if nargin < 2 || isempty(mode)
        mode = 'solve_cycle_point';
    end

    switch lower(strtrim(mode))
        case 'solve_cycle_point'
            result = solve_cycle_point(options);
        otherwise
            error('PerovskiteECC_CouplingEquations:InvalidMode', ...
                'Unknown mode: %s', mode);
    end
end

function result = solve_cycle_point(options)
    g = options.geometry;
    sma = options.material.SMA;
    se = options.material.SE;
    sys = options.system;

    [delta_xM_a, solve_diag] = solve_strict_bidirectional_delta(g, sma, se, sys);

    [eq11_residual, calc] = residual_for_delta_xM(delta_xM_a, g, sma, se, sys);
    result = calc;
    result.schema_version = 'perovskite_ecc_coupling_eq6_15_v1';
    result.mode = 'solve_cycle_point';
    result.delta_xM_a = delta_xM_a;
    result.delta_xM_r = 1.0;
    result.eq11_residual = eq11_residual;
    result.solve_diag = solve_diag;
    result.residuals = audit_residuals(result, g, sma, se, sys);
    result.max_scaled_residual = max(abs(struct_values(result.residuals.strict_scaled)));
    result.audit_max_scaled_residual = max(abs(struct_values(result.residuals.scaled)));
    result.ok = isfinite(result.max_scaled_residual) && ...
        result.max_scaled_residual <= max(options.numerics.max_residual_ok, 1.0e-12) && ...
        delta_xM_a >= -1.0e-12 && delta_xM_a <= 1.0 + 1.0e-12;
end

function [residual, calc] = residual_for_delta_xM(delta_xM_a, g, sma, se, sys)
    L_ratio = g.L_r_over_L_a;
    S_ratio = g.S_r_over_S_a;
    inv_S_ratio = 1.0 / S_ratio;
    T0 = sys.T0_K;

    sigma_r_common_Pa = inv_S_ratio * sma.C_A_Pa_per_K * ...
        (T0 - sma.T_Ms_K - delta_xM_a * (sma.T_Mf_K - sma.T_Ms_K));
    sigma_r_ld_Pa = sigma_r_common_Pa;
    sigma_r_uld_Pa = sigma_r_common_Pa;
    sigma_a_ld_Pa = S_ratio * sigma_r_ld_Pa;
    sigma_a_uld_Pa = S_ratio * sigma_r_uld_Pa;
    delta_sigma_r_Pa = sigma_r_ld_Pa - sigma_r_uld_Pa;
    T_h_K = sma.T_As_K + delta_xM_a * (sma.T_Af_K - sma.T_As_K) + ...
        sigma_a_ld_Pa / sma.C_M_Pa_per_K;

    eq11_delta_xM_a = L_ratio * se.epsilon_T / sma.epsilon_T + ...
        (L_ratio + S_ratio * (se.E_m_Pa / sma.E_m_Pa)) * ...
        sigma_r_ld_Pa / (se.E_m_Pa * sma.epsilon_T);
    residual = delta_xM_a - eq11_delta_xM_a;

    calc = struct();
    calc.T_h_K = T_h_K;
    calc.T0_K = T0;
    calc.T_c_K = sys.T_c_K;
    calc.MDTD_K = T_h_K - T0;
    calc.delta_sigma_r_Pa = delta_sigma_r_Pa;
    calc.delta_sigma_r_convention = 'sigma_r_ld_minus_sigma_r_uld_signed_common_stress_for_strict_eq7';
    calc.sigma_r_ld_Pa = sigma_r_ld_Pa;
    calc.sigma_r_uld_Pa = sigma_r_uld_Pa;
    calc.sigma_a_ld_Pa = sigma_a_ld_Pa;
    calc.sigma_a_uld_Pa = sigma_a_uld_Pa;
    calc.eq11_delta_xM_a = eq11_delta_xM_a;
end

function [root, diag] = solve_strict_bidirectional_delta(g, sma, se, sys)
    L_ratio = g.L_r_over_L_a;
    S_ratio = g.S_r_over_S_a;
    inv_S_ratio = 1.0 / S_ratio;
    k0 = L_ratio * se.epsilon_T / sma.epsilon_T;
    k1 = (L_ratio + S_ratio * (se.E_m_Pa / sma.E_m_Pa)) / ...
        (se.E_m_Pa * sma.epsilon_T);
    a0 = inv_S_ratio * sma.C_A_Pa_per_K * (sys.T0_K - sma.T_Ms_K);
    a1 = -inv_S_ratio * sma.C_A_Pa_per_K * (sma.T_Mf_K - sma.T_Ms_K);
    root = (k0 + k1 * a0) / max(1.0 - k1 * a1, eps);
    [residual, ~] = residual_for_delta_xM(root, g, sma, se, sys);
    diag = struct( ...
        'method', 'closed_form_common_stress_from_eq7_load_unload_eq11_eq14', ...
        'iterations', 1, ...
        'final_residual', residual);
end

function residuals = audit_residuals(calc, g, sma, se, sys)
    eps_a_ld = sma.epsilon_T * calc.delta_xM_a - calc.sigma_a_ld_Pa / sma.E_m_Pa;
    eps_r_ld = se.epsilon_T * calc.delta_xM_r + calc.sigma_r_ld_Pa / se.E_m_Pa;
    eps_a_uld = sma.epsilon_T * calc.delta_xM_a - calc.sigma_a_uld_Pa / sma.E_m_Pa;
    eps_r_uld = se.epsilon_T * calc.delta_xM_r + calc.sigma_r_uld_Pa / se.E_m_Pa;

    eq13_sigma_a = PerovskiteECC_ClausiusClapeyron(sma, 'loading', ...
        calc.T_h_K, calc.delta_xM_a);
    eq14_sigma_a = PerovskiteECC_ClausiusClapeyron(sma, 'unloading', ...
        sys.T0_K, calc.delta_xM_a);
    eq15_exact_rhs_K = g.S_r_over_S_a * calc.sigma_r_ld_Pa / sma.C_M_Pa_per_K - ...
        g.S_r_over_S_a * calc.sigma_r_uld_Pa / sma.C_A_Pa_per_K + ...
        sma.T_As_K - sma.T_Ms_K + calc.delta_xM_a * ...
        ((sma.T_Af_K - sma.T_As_K) + (sma.T_Ms_K - sma.T_Mf_K));
    eq15_paper_rhs_K = g.S_r_over_S_a * calc.delta_sigma_r_Pa / sma.C_A_Pa_per_K + ...
        sma.T_As_K - sma.T_Ms_K + calc.delta_xM_a * ...
        ((sma.T_Af_K - sma.T_As_K) + (sma.T_Ms_K - sma.T_Mf_K));

    raw = struct();
    raw.eq6_load_N = calc.sigma_a_ld_Pa * g.S_a_m2 - calc.sigma_r_ld_Pa * g.S_r_m2;
    raw.eq6_unload_N = calc.sigma_a_uld_Pa * g.S_a_m2 - calc.sigma_r_uld_Pa * g.S_r_m2;
    raw.eq7_load_m = eps_a_ld * g.L_a_m - eps_r_ld * g.L_r_m;
    raw.eq7_unload_m = eps_a_uld * g.L_a_m - eps_r_uld * g.L_r_m;
    raw.eq10_delta_xM_r = calc.delta_xM_r - 1.0;
    raw.eq11_delta_xM_a = calc.delta_xM_a - calc.eq11_delta_xM_a;
    raw.eq13_sigma_Pa = eq13_sigma_a.sigma_Pa - calc.sigma_a_ld_Pa;
    raw.eq14_sigma_Pa = eq14_sigma_a.sigma_Pa - calc.sigma_a_uld_Pa;
    raw.eq15_temperature_K = (calc.T_h_K - sys.T0_K) - eq15_exact_rhs_K;
    raw.eq15_paper_approx_temperature_K = (calc.T_h_K - sys.T0_K) - eq15_paper_rhs_K;

    scaled = struct();
    scaled.eq6_load = raw.eq6_load_N / max(abs(calc.sigma_r_ld_Pa * g.S_r_m2), 1.0);
    scaled.eq6_unload = raw.eq6_unload_N / max(abs(calc.sigma_r_uld_Pa * g.S_r_m2), 1.0);
    scaled.eq7_load = raw.eq7_load_m / max(abs(eps_r_ld * g.L_r_m), 1.0e-12);
    scaled.eq7_unload = raw.eq7_unload_m / max(abs(eps_r_uld * g.L_r_m), 1.0e-12);
    scaled.eq10_delta_xM_r = raw.eq10_delta_xM_r;
    scaled.eq11_delta_xM_a = raw.eq11_delta_xM_a;
    scaled.eq13_sigma = raw.eq13_sigma_Pa / max(abs(calc.sigma_a_ld_Pa), 1.0);
    scaled.eq14_sigma = raw.eq14_sigma_Pa / max(abs(calc.sigma_a_uld_Pa), 1.0);
    scaled.eq15_temperature = raw.eq15_temperature_K / max(abs(calc.T_h_K - sys.T0_K), 1.0);
    scaled.eq15_paper_approx_temperature = raw.eq15_paper_approx_temperature_K / ...
        max(abs(calc.T_h_K - sys.T0_K), 1.0);

    strict_scaled = rmfield(scaled, 'eq15_paper_approx_temperature');
    residuals = struct('raw', raw, 'scaled', scaled, 'strict_scaled', strict_scaled);
end

function values = struct_values(s)
    names = fieldnames(s);
    values = zeros(numel(names), 1);
    for idx = 1:numel(names)
        values(idx) = s.(names{idx});
    end
end
