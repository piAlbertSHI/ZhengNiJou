function coupled = PerovskiteECC_CoupledSystem(options, psc_point, ecc_energy)
% Coupled PSC-ECC Eq. 22-26 model.

    if nargin < 1 || isempty(options)
        options = Build_PerovskiteECC_Default_Options();
    end
    if nargin < 2 || isempty(psc_point)
        psc = PerovskiteECC_PSCModel(options, options.psc.article_reference.Vm_V);
        psc_point = scalar_psc_point(psc);
    end
    if nargin < 3 || isempty(ecc_energy)
        coupling = PerovskiteECC_CouplingEquations(options);
        ecc_energy = PerovskiteECC_EnergyModel(options, coupling);
    end

    sys = options.system;
    psc_ecc = options.psc_ecc;
    K_L = psc_ecc.K_L_W_per_m2K;
    K_L_source = 'options.psc_ecc.K_L_W_per_m2K';
    if ~isfinite(K_L) && logical(psc_ecc.calibrate_K_L_to_article_PH)
        [K_L, K_L_source] = calibrate_K_L(options, ecc_energy);
    end

    QL_W = K_L * sys.A_PSC_m2 * (options.psc.T_PSC_K - sys.T0_K);
    Qh_W = sys.G_W_per_m2 * sys.A_PSC_m2 - psc_point.P_PSC_W - QL_W;
    Qh_W = max(Qh_W, 0.0);
    nu_Hz = Qh_W / max(ecc_energy.m_a_kg * ecc_energy.qa_J_per_kg, eps);
    Qa_W = Qh_W;
    Qr_W = ecc_energy.m_r_kg * nu_Hz * ecc_energy.qr_J_per_kg;
    PECC_W = Qr_W;
    PH_W = psc_point.P_PSC_W + PECC_W;
    etaH = PH_W / max(sys.G_W_per_m2 * sys.A_PSC_m2, eps);
    etaECC = PECC_W / max(sys.G_W_per_m2 * sys.A_PSC_m2, eps);

    coupled = struct();
    coupled.schema_version = 'perovskite_psc_ecc_eq22_26_v1';
    coupled.V_PSC_V = psc_point.V_PSC_V;
    coupled.P_PSC_W = psc_point.P_PSC_W;
    coupled.eta_PSC = psc_point.eta_PSC;
    coupled.QL_W = QL_W;
    coupled.Qh_W = Qh_W;
    coupled.Qa_W = Qa_W;
    coupled.Qr_W = Qr_W;
    coupled.PECC_W = PECC_W;
    coupled.etaECC = etaECC;
    coupled.nu_Hz = nu_Hz;
    coupled.PH_W = PH_W;
    coupled.etaH = etaH;
    coupled.K_L_W_per_m2K = K_L;
    coupled.K_L_source = K_L_source;
    coupled.energy_ratio_mu_qr_over_qa = ecc_energy.mu_mass_ratio * ...
        ecc_energy.qr_J_per_kg / ecc_energy.qa_J_per_kg;
    coupled.eq_coverage = struct( ...
        'Eq22_heat_leakage', true, ...
        'Eq23_heat_to_ECC', true, ...
        'Eq24_cycle_frequency', true, ...
        'Eq25_hybrid_power', true, ...
        'Eq26_hybrid_efficiency', true);
end

function point = scalar_psc_point(psc)
    point = struct();
    point.V_PSC_V = psc.V_PSC_V(1);
    point.J_PSC_A_per_m2 = psc.J_PSC_A_per_m2(1);
    point.P_PSC_W = psc.P_PSC_W(1);
    point.eta_PSC = psc.eta_PSC(1);
end

function [K_L, source] = calibrate_K_L(options, ecc_energy)
    ref_psc = options.psc.article_reference;
    ref_hybrid = options.psc_ecc.article_reference;
    incident_W = options.system.G_W_per_m2 * options.system.A_PSC_m2;
    target_PECC_W = ref_hybrid.P_H_max_W - ref_psc.P_PSC_max_W;
    q_factor = ecc_energy.mu_mass_ratio * ecc_energy.qr_J_per_kg / ecc_energy.qa_J_per_kg;
    target_Qh_W = target_PECC_W / max(q_factor, eps);
    numerator = incident_W - ref_psc.P_PSC_max_W - target_Qh_W;
    denominator = options.system.A_PSC_m2 * (options.psc.T_PSC_K - options.system.T0_K);
    K_L = max(numerator / max(denominator, eps), 0.0);
    source = 'reverse_calibrated_to_article_PH_max';
end

