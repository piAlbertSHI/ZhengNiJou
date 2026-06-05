function sweep = Run_PerovskiteECC_Article_Sweep(options, V_PSC)
% Sweep PSC voltage and compute PSC/ECC/hybrid Eq. 1-26 indicators.

    if nargin < 1 || isempty(options)
        options = Build_PerovskiteECC_Default_Options();
    else
        options = Build_PerovskiteECC_Default_Options(options);
    end
    if nargin < 2 || isempty(V_PSC)
        V_PSC = linspace(options.psc.voltage_min_V, options.psc.voltage_max_V, ...
            options.psc.voltage_points).';
    end

    psc = PerovskiteECC_PSCModel(options, V_PSC);
    coupling = PerovskiteECC_CouplingEquations(options);
    ecc_energy = PerovskiteECC_EnergyModel(options, coupling);

    n = numel(psc.V_PSC_V);
    QL = zeros(n, 1);
    Qh = zeros(n, 1);
    Qa = zeros(n, 1);
    Qr = zeros(n, 1);
    PECC = zeros(n, 1);
    etaECC = zeros(n, 1);
    nu = zeros(n, 1);
    PH = zeros(n, 1);
    etaH = zeros(n, 1);
    K_L = zeros(n, 1);

    for idx = 1:n
        point = struct( ...
            'V_PSC_V', psc.V_PSC_V(idx), ...
            'P_PSC_W', psc.P_PSC_W(idx), ...
            'eta_PSC', psc.eta_PSC(idx));
        coupled = PerovskiteECC_CoupledSystem(options, point, ecc_energy);
        QL(idx) = coupled.QL_W;
        Qh(idx) = coupled.Qh_W;
        Qa(idx) = coupled.Qa_W;
        Qr(idx) = coupled.Qr_W;
        PECC(idx) = coupled.PECC_W;
        etaECC(idx) = coupled.etaECC;
        nu(idx) = coupled.nu_Hz;
        PH(idx) = coupled.PH_W;
        etaH(idx) = coupled.etaH;
        K_L(idx) = coupled.K_L_W_per_m2K;
    end

    [PH_max, idx_h] = max(PH);
    [~, idx_p] = max(psc.P_PSC_W);

    sweep = struct();
    sweep.schema_version = 'perovskite_article_sweep_eq1_26_v1';
    sweep.options = options;
    sweep.psc = psc;
    sweep.coupling = coupling;
    sweep.ecc_energy = ecc_energy;
    sweep.V_PSC_V = psc.V_PSC_V;
    sweep.P_PSC_W = psc.P_PSC_W;
    sweep.eta_PSC = psc.eta_PSC;
    sweep.QL_W = QL;
    sweep.Qh_W = Qh;
    sweep.Qa_W = Qa;
    sweep.Qr_W = Qr;
    sweep.PECC_W = PECC;
    sweep.etaECC = etaECC;
    sweep.nu_Hz = nu;
    sweep.PH_W = PH;
    sweep.etaH = etaH;
    sweep.K_L_W_per_m2K = K_L;
    sweep.max_psc = struct( ...
        'index', idx_p, ...
        'V_m_V', psc.V_PSC_V(idx_p), ...
        'P_PSC_max_W', psc.P_PSC_W(idx_p), ...
        'eta_PSC_max', psc.eta_PSC(idx_p));
    sweep.max_hybrid = struct( ...
        'index', idx_h, ...
        'V_m_V', psc.V_PSC_V(idx_h), ...
        'P_H_max_W', PH_max, ...
        'eta_H_max', etaH(idx_h), ...
        'P_PSC_at_Vm_W', psc.P_PSC_W(idx_h), ...
        'eta_PSC_at_Vm', psc.eta_PSC(idx_h), ...
        'PECC_at_Vm_W', PECC(idx_h), ...
        'Qh_at_Vm_W', Qh(idx_h), ...
        'nu_at_Vm_Hz', nu(idx_h));
    sweep.trends = struct( ...
        'P_PSC_has_interior_maximum', idx_p > 1 && idx_p < n, ...
        'eta_PSC_has_interior_maximum', idx_p > 1 && idx_p < n, ...
        'PECC_decreases_when_PPSC_increases', corrcoef_fallback(psc.P_PSC_W, PECC) < 0.0, ...
        'PH_has_interior_maximum', idx_h > 1 && idx_h < n);

    if options.write_outputs
        out_dir = fullfile(options.outputs_dir, 'article_sweep');
        if ~exist(out_dir, 'dir')
            mkdir(out_dir);
        end
        save(fullfile(out_dir, 'perovskite_article_sweep.mat'), 'sweep', '-v7.3');
        write_json(fullfile(out_dir, 'perovskite_article_sweep_summary.json'), ...
            compact_sweep_summary(sweep));
    end
end

function r = corrcoef_fallback(x, y)
    x = x(:);
    y = y(:);
    x = x - mean(x);
    y = y - mean(y);
    r = sum(x .* y) / max(sqrt(sum(x .^ 2) * sum(y .^ 2)), eps);
end

function summary = compact_sweep_summary(sweep)
    summary = struct();
    summary.schema_version = 'perovskite_article_sweep_summary_v1';
    summary.max_psc = sweep.max_psc;
    summary.max_hybrid = sweep.max_hybrid;
    summary.trends = sweep.trends;
    summary.K_L_W_per_m2K = sweep.K_L_W_per_m2K(1);
    summary.MDTD_K = sweep.coupling.MDTD_K;
    summary.qa_J_per_kg = sweep.ecc_energy.qa_J_per_kg;
    summary.qr_J_per_kg = sweep.ecc_energy.qr_J_per_kg;
end

function write_json(path, data)
    try
        text = jsonencode(data, 'PrettyPrint', true);
    catch
        text = jsonencode(data);
    end
    fid = fopen(path, 'w');
    if fid < 0
        error('Run_PerovskiteECC_Article_Sweep:CannotWriteJson', ...
            'Cannot write JSON file: %s', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end

