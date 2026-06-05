function summary = Validate_PerovskiteECC_Paper_Smoke(options)
% Smoke validation for the second-round paper Eq. 6-21 axial ECC model.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if ~isfield(options, 'outputs_dir')
        options.outputs_dir = fullfile(fileparts(mfilename('fullpath')), ...
            'outputs_perovskite_ecc_smoke');
    end
    options.cycle_count = 1;
    options.write_outputs = true;
    options = Build_PerovskiteECC_Default_Options(options);

    result = Run_PerovskiteECC_SingleStage_Cycles(options);
    summary = build_validation_summary(result);

    if ~summary.ok
        error('Validate_PerovskiteECC_Paper_Smoke:ValidationFailed', ...
            'PerovskiteECC paper smoke validation failed.');
    end

    if options.write_outputs
        smoke_path = fullfile(options.outputs_dir, 'perovskite_ecc_smoke_summary.json');
        write_json(smoke_path, summary);
        summary.output_paths = result.output_paths;
        summary.output_paths.smoke_summary_json = smoke_path;
    end

    if nargout == 0
        disp(summary);
    end
end

function summary = build_validation_summary(result)
    final_state = result.final_state;
    stage_reports = result.stage_reports;
    energy = result.energy;
    coupling = result.coupling;

    checks = struct();
    checks.stage_count_is_4 = numel(stage_reports) == 4;
    checks.node_count_sma_51 = numel(final_state.SMA.T_51) == 51;
    checks.node_count_se_51 = numel(final_state.SE.T_51) == 51;
    checks.final_sma_arrays_finite = partition_is_finite(final_state.SMA);
    checks.final_se_arrays_finite = partition_is_finite(final_state.SE);
    checks.coupling_ok = logical(coupling.ok);
    checks.coupling_residual_finite = isfinite(coupling.max_scaled_residual);
    checks.coupling_residual_small = coupling.max_scaled_residual <= ...
        result.options.numerics.max_residual_ok;
    checks.energy_finite = all(isfinite([energy.qa_J_per_kg, energy.qr_J_per_kg, ...
        energy.Qa_W, energy.Qr_W, energy.PECC_W, energy.etaECC]));
    checks.energy_positive = all([energy.qa_J_per_kg, energy.qr_J_per_kg, ...
        energy.Qa_W, energy.Qr_W, energy.PECC_W, energy.etaECC] > 0.0);
    checks.deprecated_route_not_used = ~logical(result.summary.deprecated_first_round_route_used);

    checks.stage1_sma_transforms = stage_reports(1).xM_SMA_mean < 1.0 && ...
        stage_reports(1).xM_SMA_mean >= 0.0;
    checks.stage1_se_transforms = abs(stage_reports(1).xM_SE_mean - 1.0) <= 1.0e-12;
    checks.stage3_sma_returns_martensite = abs(stage_reports(3).xM_SMA_mean - 1.0) <= 1.0e-12;
    checks.stage4_se_returns_austenite = abs(stage_reports(4).xM_SE_mean) <= 1.0e-12;

    summary = result.summary;
    summary.schema_version = 'perovskite_ecc_paper_smoke_summary_v1';
    summary.ok = all_struct_logical(checks);
    summary.checks = checks;
    summary.required_outputs_present = struct( ...
        'node_T_stress_strain_xM_51', true, ...
        'coupling_residual', isfield(summary, 'coupling_residual'), ...
        'qa_qr_Qa_Qr_PECC_etaECC', true);
    summary.node_outputs = vectorize_node_outputs(result.node_outputs);
    summary.stage_node_outputs = vectorize_stage_node_outputs(result.state_history);
    summary.stage_reports_compact = compact_stage_reports(stage_reports);
end

function ok = partition_is_finite(part)
    ok = all(isfinite(part.T_51)) && all(isfinite(part.sigma_Pa_51)) && ...
        all(isfinite(part.epsilon_51)) && all(isfinite(part.xM_51)) && ...
        all(isfinite(part.pai_Pa_51)) && all(isfinite(part.r_xi_1_per_s_51)) && ...
        all(isfinite(part.q_latent_W_per_m3_51));
end

function ok = all_struct_logical(s)
    names = fieldnames(s);
    ok = true;
    for idx = 1:numel(names)
        ok = ok && logical(s.(names{idx}));
    end
end

function out = vectorize_node_outputs(node_outputs)
    out = struct();
    names = fieldnames(node_outputs);
    for idx = 1:numel(names)
        out.(names{idx}) = node_outputs.(names{idx})(:).';
    end
end

function out = vectorize_stage_node_outputs(state_history)
    out = repmat(struct(), numel(state_history), 1);
    for idx = 1:numel(state_history)
        snapshot = state_history{idx};
        out(idx).stage_name = snapshot.stage_name;
        out(idx).cycle_index = snapshot.cycle_index;
        out(idx).SMA_T_51_K = snapshot.SMA.T_51(:).';
        out(idx).SMA_sigma_51_Pa = snapshot.SMA.sigma_Pa_51(:).';
        out(idx).SMA_epsilon_51 = snapshot.SMA.epsilon_51(:).';
        out(idx).SMA_xM_51 = snapshot.SMA.xM_51(:).';
        out(idx).SE_T_51_K = snapshot.SE.T_51(:).';
        out(idx).SE_sigma_51_Pa = snapshot.SE.sigma_Pa_51(:).';
        out(idx).SE_epsilon_51 = snapshot.SE.epsilon_51(:).';
        out(idx).SE_xM_51 = snapshot.SE.xM_51(:).';
    end
end

function compact = compact_stage_reports(stage_reports)
    compact = repmat(struct(), numel(stage_reports), 1);
    for idx = 1:numel(stage_reports)
        report = stage_reports(idx);
        compact(idx).stage_index = report.stage_index;
        compact(idx).stage_name = report.stage_name;
        compact(idx).T_SMA_mean_K = report.T_SMA_mean_K;
        compact(idx).T_SE_mean_K = report.T_SE_mean_K;
        compact(idx).sigma_SMA_mean_Pa = report.sigma_SMA_mean_Pa;
        compact(idx).sigma_SE_mean_Pa = report.sigma_SE_mean_Pa;
        compact(idx).epsilon_SMA_mean = report.epsilon_SMA_mean;
        compact(idx).epsilon_SE_mean = report.epsilon_SE_mean;
        compact(idx).xM_SMA_mean = report.xM_SMA_mean;
        compact(idx).xM_SE_mean = report.xM_SE_mean;
        compact(idx).coupling_residual = report.coupling_residual;
        compact(idx).qa_J_per_kg = report.qa_J_per_kg;
        compact(idx).qr_J_per_kg = report.qr_J_per_kg;
        compact(idx).Qa_W = report.Qa_W;
        compact(idx).Qr_W = report.Qr_W;
        compact(idx).PECC_W = report.PECC_W;
        compact(idx).etaECC = report.etaECC;
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
        error('Validate_PerovskiteECC_Paper_Smoke:CannotWriteJson', ...
            'Cannot write JSON file: %s', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end
