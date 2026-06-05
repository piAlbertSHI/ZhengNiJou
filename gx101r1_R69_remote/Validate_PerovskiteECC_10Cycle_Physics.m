function summary = Validate_PerovskiteECC_10Cycle_Physics(options)
% Validate 10-cycle dynamic axial ECC physics and Eq. 1-26 closures.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if ~isfield(options, 'outputs_dir')
        options.outputs_dir = fullfile(fileparts(mfilename('fullpath')), ...
            'outputs_perovskite_article_10cycle_validation');
    end
    options.cycle_count = 10;
    options.write_outputs = true;
    result = Run_PerovskiteECC_Article_Cycles(options);
    summary = build_10cycle_summary(result);

    if ~summary.ok
        error('Validate_PerovskiteECC_10Cycle_Physics:ValidationFailed', ...
            '10-cycle PerovskiteECC physics validation failed.');
    end

    write_json(fullfile(result.options.outputs_dir, 'perovskite_10cycle_physics_summary.json'), summary);
    save(fullfile(result.options.outputs_dir, 'perovskite_10cycle_physics_summary.mat'), ...
        'summary', 'result', '-v7.3');

    if nargout == 0
        disp(summary);
    end
end

function summary = build_10cycle_summary(result)
    options = result.options;
    checks = struct();
    checks.cycle_count_is_10 = numel(result.cycle_results) == 10;
    checks.stage_count_is_40 = result.summary.stage_count == 40;
    checks.node_count_sma_51 = result.summary.node_count_sma == 51;
    checks.node_count_se_51 = result.summary.node_count_se == 51;
    checks.no_nan_inf = true;
    checks.xM_in_bounds = true;
    checks.required_stage_fields_present = true;
    checks.phase_sequence_ok = true;

    for cidx = 1:numel(result.cycle_results)
        cycle = result.cycle_results(cidx);
        checks.required_stage_fields_present = checks.required_stage_fields_present && ...
            numel(cycle.stages) == 4;
        for sidx = 1:numel(cycle.stages)
            st = cycle.stages(sidx);
            [finite_ok, bounds_ok, fields_ok] = validate_stage_nodes(st);
            checks.no_nan_inf = checks.no_nan_inf && finite_ok;
            checks.xM_in_bounds = checks.xM_in_bounds && bounds_ok;
            checks.required_stage_fields_present = checks.required_stage_fields_present && fields_ok;
        end
        checks.phase_sequence_ok = checks.phase_sequence_ok && ...
            cycle.stages(1).stage_report.xM_SMA_mean < 0.999 && ...
            abs(cycle.stages(1).stage_report.xM_SE_mean - 1.0) < 1.0e-10 && ...
            abs(cycle.stages(3).stage_report.xM_SMA_mean - 1.0) < 1.0e-10 && ...
            abs(cycle.stages(4).stage_report.xM_SE_mean) < 1.0e-10;
    end

    residuals = result.coupling.residuals.strict_scaled;
    checks.eq6_eq7_eq15_strict_residuals_ok = max_abs_struct(residuals) <= ...
        options.numerics.max_residual_ok;
    checks.eq7_unload_strict = isfield(residuals, 'eq7_unload') && ...
        abs(residuals.eq7_unload) <= options.numerics.max_residual_ok;
    checks.no_cycle_drift_last_two = ...
        result.summary.no_cycle_drift_last_two.SMA_xM_inf_norm <= 1.0e-12 && ...
        result.summary.no_cycle_drift_last_two.SE_xM_inf_norm <= 1.0e-12;
    checks.energy_positive = result.coupled.Qh_W > 0.0 && result.coupled.Qa_W > 0.0 && ...
        result.coupled.Qr_W > 0.0 && result.coupled.PECC_W > 0.0 && ...
        result.ecc_energy.qa_J_per_kg > 0.0 && result.ecc_energy.qr_J_per_kg > 0.0;
    checks.energy_closure = abs(result.coupled.Qh_W - result.coupled.Qa_W) <= 1.0e-9 && ...
        abs(result.coupled.PH_W - result.coupled.P_PSC_W - result.coupled.PECC_W) <= 1.0e-9 && ...
        abs(result.coupled.etaH - result.coupled.PH_W / ...
        (options.system.G_W_per_m2 * options.system.A_PSC_m2)) <= 1.0e-12;
    checks.dynamic_latent_nonzero = abs(result.cycle_results(1).stages(1).stage_report.q_latent_SMA_mean_W_per_m3) > 0.0 && ...
        abs(result.cycle_results(1).stages(1).stage_report.q_latent_SE_mean_W_per_m3) > 0.0 && ...
        abs(result.cycle_results(1).stages(4).stage_report.q_latent_SE_mean_W_per_m3) > 0.0;
    checks.deprecated_first_round_route_not_used = ~result.summary.deprecated_first_round_route_used;

    summary = result.summary;
    summary.schema_version = 'perovskite_10cycle_physics_validation_v1';
    summary.ok = all_struct_logical(checks);
    summary.checks = checks;
    summary.strict_residuals = residuals;
    summary.cycle_metric_table = build_cycle_metric_table(result.cycle_results);
end

function [finite_ok, bounds_ok, fields_ok] = validate_stage_nodes(stage)
    required = {'T_51', 'xM_51', 'sigma_51', 'epsilon_51', 'pai_51', 'r_xi_51', 'q_latent_51'};
    finite_ok = true;
    bounds_ok = true;
    fields_ok = true;
    names = {'SMA', 'SE'};
    for nidx = 1:numel(names)
        part = stage.(names{nidx});
        for ridx = 1:numel(required)
            fields_ok = fields_ok && isfield(part, required{ridx}) && numel(part.(required{ridx})) == 51;
            if isfield(part, required{ridx})
                finite_ok = finite_ok && all(isfinite(part.(required{ridx})(:)));
            end
        end
        bounds_ok = bounds_ok && all(part.xM_51(:) >= -1.0e-12) && ...
            all(part.xM_51(:) <= 1.0 + 1.0e-12);
    end
end

function table_rows = build_cycle_metric_table(cycle_results)
    table_rows = repmat(struct(), numel(cycle_results), 1);
    for idx = 1:numel(cycle_results)
        m = cycle_results(idx).metrics;
        table_rows(idx).cycle_index = idx;
        table_rows(idx).qa = m.qa;
        table_rows(idx).qr = m.qr;
        table_rows(idx).Qa = m.Qa;
        table_rows(idx).Qr = m.Qr;
        table_rows(idx).PECC = m.PECC;
        table_rows(idx).etaECC = m.etaECC;
        table_rows(idx).PPSC = m.PPSC;
        table_rows(idx).etaPSC = m.etaPSC;
        table_rows(idx).PH = m.PH;
        table_rows(idx).etaH = m.etaH;
        table_rows(idx).Qh = m.Qh;
        table_rows(idx).QL = m.QL;
        table_rows(idx).nu = m.nu;
    end
end

function value = max_abs_struct(s)
    names = fieldnames(s);
    value = 0.0;
    for idx = 1:numel(names)
        value = max(value, abs(s.(names{idx})));
    end
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
        error('Validate_PerovskiteECC_10Cycle_Physics:CannotWriteJson', ...
            'Cannot write JSON file: %s', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end

