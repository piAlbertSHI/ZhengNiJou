function result = PerovskiteECC_PSCModel(options, V_PSC)
% Perovskite solar cell Eq. 1-5 model with explicit article calibration.

    if nargin < 1 || isempty(options)
        options = Build_PerovskiteECC_Default_Options();
    end
    if nargin < 2 || isempty(V_PSC)
        V_PSC = linspace(options.psc.voltage_min_V, options.psc.voltage_max_V, ...
            options.psc.voltage_points).';
    end
    V_PSC = V_PSC(:);

    psc = options.psc;
    sys = options.system;
    calibration = calibrate_article_mpp(psc, sys);

    J = zeros(size(V_PSC));
    for idx = 1:numel(V_PSC)
        J(idx) = solve_current_density(V_PSC(idx), calibration.Jph_A_per_m2, ...
            calibration.Jr_A_per_m2, psc);
    end

    P = V_PSC .* J .* sys.A_PSC_m2;
    eta = P ./ max(sys.G_W_per_m2 * sys.A_PSC_m2, eps);
    [P_max, idx_max] = max(P);

    result = struct();
    result.schema_version = 'perovskite_psc_eq1_5_v1';
    result.V_PSC_V = V_PSC;
    result.J_PSC_A_per_m2 = J;
    result.P_PSC_W = P;
    result.eta_PSC = eta;
    result.max = struct( ...
        'V_m_V', V_PSC(idx_max), ...
        'J_m_A_per_m2', J(idx_max), ...
        'P_PSC_max_W', P_max, ...
        'eta_PSC_max', eta(idx_max));
    result.calibration = calibration;
    result.eq_coverage = struct( ...
        'Eq1_single_diode_current_density', true, ...
        'Eq2_Jph_article_reverse_calibrated', true, ...
        'Eq3_Jr_planck_shape_article_scaled', true, ...
        'Eq4_power', true, ...
        'Eq5_efficiency', true);
end

function calibration = calibrate_article_mpp(psc, sys)
    ref = psc.article_reference;
    area_m2 = sys.A_PSC_m2;
    incident_W = sys.G_W_per_m2 * area_m2;
    Jm = ref.P_PSC_max_W / (ref.Vm_V * area_m2);
    a = psc.q_C / (psc.ideality_factor * psc.kB_J_per_K * psc.T_PSC_K);
    U = ref.Vm_V + Jm * psc.Rs_ohm_m2;
    expU = exp(min(a * U, 700.0));
    Y = (Jm / ref.Vm_V) / max(1.0 - psc.Rs_ohm_m2 * Jm / ref.Vm_V, eps);
    Jr = max((Y - 1.0 / psc.Rsh_ohm_m2) / max(a * expU, realmin), realmin);
    Jph = Jm + Jr * (expU - 1.0) + U / psc.Rsh_ohm_m2;
    Jr_planck_raw = planck_reverse_saturation_raw(psc);

    calibration = struct();
    calibration.mode = psc.calibration_mode;
    calibration.reason = ['Article does not provide AM1.5G spectral S(lambda), ', ...
        'IPCE(lambda), or enough PSC optical-layer data; Jph and Jr are ', ...
        'reverse-calibrated to the reported maximum power point.'];
    calibration.Vm_target_V = ref.Vm_V;
    calibration.P_PSC_max_target_W = ref.P_PSC_max_W;
    calibration.eta_PSC_max_target = ref.eta_PSC_max;
    calibration.incident_power_W = incident_W;
    calibration.A_PSC_from_article_m2 = area_m2;
    calibration.Jm_target_A_per_m2 = Jm;
    calibration.Jph_A_per_m2 = Jph;
    calibration.Jr_A_per_m2 = Jr;
    calibration.Jr_planck_raw_A_per_m2 = Jr_planck_raw;
    calibration.Jr_planck_scale = Jr / max(Jr_planck_raw, realmin);
end

function J = solve_current_density(V, Jph, Jr, psc)
    J = max(Jph - V / psc.Rsh_ohm_m2, 0.0);
    a = psc.q_C / (psc.ideality_factor * psc.kB_J_per_K * psc.T_PSC_K);
    for iter = 1:80
        U = V + J * psc.Rs_ohm_m2;
        expU = exp(min(a * U, 700.0));
        F = J - Jph + Jr * (expU - 1.0) + U / psc.Rsh_ohm_m2;
        dF = 1.0 + Jr * expU * a * psc.Rs_ohm_m2 + psc.Rs_ohm_m2 / psc.Rsh_ohm_m2;
        step = F / max(dF, realmin);
        J = J - step;
        if abs(step) <= 1.0e-10 * max(abs(J), 1.0)
            break;
        end
    end
    J = max(J, 0.0);
end

function Jr_raw = planck_reverse_saturation_raw(psc)
    E_eV = linspace(psc.Eg_eV, 5.0, 5000).';
    kB_eV_per_K = psc.kB_J_per_K / psc.q_C;
    denom = exp(min(E_eV ./ (kB_eV_per_K * psc.T_PSC_K), 700.0)) - 1.0;
    integrand = E_eV .^ 2 ./ max(denom, realmin);
    integral_eV3 = trapz(E_eV, integrand);
    Jr_raw = 2.0 * pi * psc.q_C / (psc.h_eV_s ^ 3 * psc.c_m_per_s ^ 2) * integral_eV3;
end

