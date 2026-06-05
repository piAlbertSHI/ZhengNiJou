function energy = PerovskiteECC_EnergyModel(options, coupling)
% Compute paper Eq. 16-21 heat, cooling power, and ECC efficiency.

    if nargin < 1 || isempty(options)
        options = Build_PerovskiteECC_Default_Options();
    end
    if nargin < 2 || isempty(coupling)
        coupling = PerovskiteECC_CouplingEquations(options);
    end

    g = options.geometry;
    sys = options.system;
    sma = options.material.SMA;
    se = options.material.SE;

    m_a_kg = sma.rho_kg_per_m3 * g.volume_a_m3;
    m_r_kg = se.rho_kg_per_m3 * g.volume_r_m3;
    mu = (g.L_r_over_L_a) * (g.S_r_over_S_a) * ...
        (se.rho_kg_per_m3 / sma.rho_kg_per_m3);

    qa_J_per_kg = sma.cp_J_per_kgK * (coupling.T_h_K - sys.T0_K) * ...
        (1.0 - sys.eta_hr) + sma.Delta_h_J_per_kg * coupling.delta_xM_a + ...
        se.w_ld_J_per_kg * mu;
    qr_J_per_kg = se.Delta_h_J_per_kg + se.w_uld_J_per_kg - ...
        se.cp_J_per_kgK * (sys.T0_K - sys.T_c_K) * (1.0 - sys.eta_hr);

    nu_Hz = options.cycle_frequency_Hz;
    frequency_source = 'options.cycle_frequency_Hz';
    if isfield(sys, 'Qh_W') && isfinite(sys.Qh_W) && sys.Qh_W > 0.0
        nu_Hz = sys.Qh_W / max(m_a_kg * qa_J_per_kg, eps);
        frequency_source = 'system.Qh_W/(m_a*qa)';
    end

    Qa_W = m_a_kg * nu_Hz * qa_J_per_kg;
    Qr_W = m_r_kg * nu_Hz * qr_J_per_kg;
    PECC_W = Qr_W;
    etaECC = PECC_W / max(sys.G_W_per_m2 * sys.A_PSC_m2, eps);

    energy = struct();
    energy.schema_version = 'perovskite_ecc_energy_eq16_21_v1';
    energy.qa_J_per_kg = qa_J_per_kg;
    energy.qr_J_per_kg = qr_J_per_kg;
    energy.Qa_W = Qa_W;
    energy.Qr_W = Qr_W;
    energy.PECC_W = PECC_W;
    energy.etaECC = etaECC;
    energy.mu_mass_ratio = mu;
    energy.m_a_kg = m_a_kg;
    energy.m_r_kg = m_r_kg;
    energy.nu_Hz = nu_Hz;
    energy.frequency_source = frequency_source;
    energy.G_W_per_m2 = sys.G_W_per_m2;
    energy.A_PSC_m2 = sys.A_PSC_m2;
end

