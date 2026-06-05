function summary = Validate_PerovskiteECC_Article_Reproduction(options)
% Validate article-level PSC/ECC/PSC-ECC reproduction against reported values.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if ~isfield(options, 'outputs_dir')
        options.outputs_dir = fullfile(fileparts(mfilename('fullpath')), ...
            'outputs_perovskite_article_validation');
    end
    options.write_outputs = true;
    options = Build_PerovskiteECC_Default_Options(options);

    sweep = Run_PerovskiteECC_Article_Sweep(options);
    summary = build_reproduction_summary(options, sweep);

    if ~summary.ok
        error('Validate_PerovskiteECC_Article_Reproduction:ValidationFailed', ...
            'Article reproduction validation failed.');
    end

    out_dir = options.outputs_dir;
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    write_json(fullfile(out_dir, 'article_reproduction_summary.json'), summary);
    save(fullfile(out_dir, 'article_reproduction_summary.mat'), 'summary', 'sweep', '-v7.3');

    if nargout == 0
        disp(summary);
    end
end

function summary = build_reproduction_summary(options, sweep)
    ref_psc = options.psc.article_reference;
    ref_h = options.psc_ecc.article_reference;
    program = struct();
    program.Vm_V = sweep.max_hybrid.V_m_V;
    program.P_PSC_max_W = sweep.max_psc.P_PSC_max_W;
    program.eta_PSC_max = sweep.max_psc.eta_PSC_max;
    program.P_H_max_W = sweep.max_hybrid.P_H_max_W;
    program.eta_H_max = sweep.max_hybrid.eta_H_max;
    program.P_H_lift_fraction = (program.P_H_max_W - program.P_PSC_max_W) / program.P_PSC_max_W;
    program.eta_H_lift_fraction = (program.eta_H_max - program.eta_PSC_max) / program.eta_PSC_max;
    program.MDTD_K = sweep.coupling.MDTD_K;

    reference = struct();
    reference.Vm_V = ref_psc.Vm_V;
    reference.P_PSC_max_W = ref_psc.P_PSC_max_W;
    reference.eta_PSC_max = ref_psc.eta_PSC_max;
    reference.P_H_max_W = ref_h.P_H_max_W;
    reference.eta_H_max = ref_h.eta_H_max;
    reference.P_H_lift_fraction = ref_h.P_H_lift_fraction;
    reference.eta_H_lift_fraction = ref_h.eta_H_lift_fraction;
    reference.MDTD_K = sweep.coupling.MDTD_K;

    table_rows = [
        row('Vm_V', reference.Vm_V, program.Vm_V, 'V')
        row('P_PSC_max_W', reference.P_PSC_max_W, program.P_PSC_max_W, 'W')
        row('eta_PSC_max', reference.eta_PSC_max, program.eta_PSC_max, 'fraction')
        row('P_H_max_W', reference.P_H_max_W, program.P_H_max_W, 'W')
        row('eta_H_max', reference.eta_H_max, program.eta_H_max, 'fraction')
        row('P_H_lift_fraction', reference.P_H_lift_fraction, program.P_H_lift_fraction, 'fraction')
        row('eta_H_lift_fraction', reference.eta_H_lift_fraction, program.eta_H_lift_fraction, 'fraction')
        row('MTDT_or_Th_minus_T0_K', reference.MDTD_K, program.MDTD_K, 'K')
    ];

    max_rel_error = max([table_rows.relative_error]);
    checks = struct();
    checks.article_errors_under_5_percent = max_rel_error <= 0.05;
    checks.psc_peak_at_096V = abs(program.Vm_V - ref_psc.Vm_V) <= 2.5e-3;
    checks.trends_ok = sweep.trends.P_PSC_has_interior_maximum && ...
        sweep.trends.eta_PSC_has_interior_maximum && ...
        sweep.trends.PECC_decreases_when_PPSC_increases && ...
        sweep.trends.PH_has_interior_maximum;
    checks.ecc_strict_residual_ok = sweep.coupling.max_scaled_residual <= ...
        options.numerics.max_residual_ok;
    checks.eq7_unload_in_strict_audit = isfield(sweep.coupling.residuals.strict_scaled, 'eq7_unload');
    checks.article_area_not_second_round_default = abs(options.system.A_PSC_m2 - 0.01) > 1.0e-6;

    summary = struct();
    summary.schema_version = 'perovskite_article_reproduction_validation_v1';
    summary.ok = all_struct_logical(checks);
    summary.checks = checks;
    summary.reference = reference;
    summary.program = program;
    summary.reproduction_error_table = table_rows;
    summary.max_relative_error = max_rel_error;
    summary.calibration = struct( ...
        'psc', sweep.psc.calibration, ...
        'K_L_W_per_m2K', sweep.K_L_W_per_m2K(1), ...
        'K_L_source', 'reverse_calibrated_to_article_PH_max');
    summary.coupling_residuals = sweep.coupling.residuals;
    summary.trends = sweep.trends;
end

function item = row(name, article_value, program_value, unit)
    item = struct();
    item.metric = name;
    item.unit = unit;
    item.article_value = article_value;
    item.program_value = program_value;
    item.relative_error = abs(program_value - article_value) / max(abs(article_value), eps);
end

function ok = all_struct_logical(s)
    names = fieldnames(s);
    ok = true;
    for idx = 1:numel(names)
        ok = ok && logical(s.(names{idx}));
    end
end

function write_json(path, data)
    try
        text = jsonencode(data, 'PrettyPrint', true);
    catch
        text = jsonencode(data);
    end
    fid = fopen(path, 'w');
    if fid < 0
        error('Validate_PerovskiteECC_Article_Reproduction:CannotWriteJson', ...
            'Cannot write JSON file: %s', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end

