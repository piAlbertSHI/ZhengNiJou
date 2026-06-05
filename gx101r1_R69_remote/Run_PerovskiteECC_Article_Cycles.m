function result = Run_PerovskiteECC_Article_Cycles(options)
% Product-grade article reproduction runner with 10 ECC cycles by default.

    if nargin < 1 || isempty(options)
        options = struct();
    end
    if ~isfield(options, 'cycle_count')
        options.cycle_count = 10;
    end
    if ~isfield(options, 'outputs_dir')
        options.outputs_dir = fullfile(fileparts(mfilename('fullpath')), ...
            'outputs_perovskite_article_10cycle');
    end
    options.write_outputs = get_field(options, 'write_outputs', true);
    options = Build_PerovskiteECC_Default_Options(options);

    sweep = Run_PerovskiteECC_Article_Sweep(set_field(options, 'write_outputs', false));
    coupling = sweep.coupling;
    constitutive = PerovskiteECC_Constitutive(options, coupling);
    ecc_energy = sweep.ecc_energy;
    psc_point = psc_point_from_sweep(sweep, sweep.max_hybrid.index);
    coupled = PerovskiteECC_CoupledSystem(options, psc_point, ecc_energy);
    state = Initialize_PerovskiteECC_State(options);
    initial_state = state;

    stage_names = {'sma_heat_load', 'se_reject_heat', 'sma_cool_unload', 'se_absorb_heat'};
    cycle_results = [];

    for cycle_idx = 1:options.cycle_count
        stage_results = [];
        for stage_idx = 1:numel(stage_names)
            state.cycle_index = cycle_idx;
            [state, stage_report] = PerovskiteECC_ThermalStep51( ...
                state, options, stage_names{stage_idx}, coupling, constitutive, ecc_energy);
            stage_report.cycle_index = cycle_idx;
            stage_report.psc_ecc = coupled;
            next_stage = struct( ...
                'stage_report', stage_report, ...
                'SMA', article_partition_snapshot(state.SMA), ...
                'SE', article_partition_snapshot(state.SE), ...
                'constraint_residuals', coupling.residuals);
            if isempty(stage_results)
                stage_results = next_stage;
            else
                stage_results(stage_idx) = next_stage; %#ok<AGROW>
            end
        end
        next_cycle = struct();
        next_cycle.cycle_index = cycle_idx;
        next_cycle.stages = stage_results;
        next_cycle.metrics = cycle_metrics(coupled, ecc_energy, coupling);
        next_cycle.final_state = struct( ...
            'SMA', article_partition_snapshot(state.SMA), ...
            'SE', article_partition_snapshot(state.SE));
        if isempty(cycle_results)
            cycle_results = next_cycle;
        else
            cycle_results(cycle_idx) = next_cycle; %#ok<AGROW>
        end
    end

    summary = build_article_cycle_summary(options, sweep, coupled, coupling, ...
        ecc_energy, initial_state, state, cycle_results);

    result = struct();
    result.schema_version = 'perovskite_article_10cycle_result_v1';
    result.options = options;
    result.sweep = sweep;
    result.psc_point = psc_point;
    result.coupled = coupled;
    result.coupling = coupling;
    result.ecc_energy = ecc_energy;
    result.initial_state = initial_state;
    result.final_state = state;
    result.cycle_results = cycle_results;
    result.summary = summary;

    if options.write_outputs
        result = write_outputs(result, options);
    end
end

function point = psc_point_from_sweep(sweep, idx)
    point = struct();
    point.V_PSC_V = sweep.V_PSC_V(idx);
    point.J_PSC_A_per_m2 = sweep.psc.J_PSC_A_per_m2(idx);
    point.P_PSC_W = sweep.P_PSC_W(idx);
    point.eta_PSC = sweep.eta_PSC(idx);
end

function part = article_partition_snapshot(src)
    part = struct();
    part.T_51 = src.T_51;
    part.xM_51 = src.xM_51;
    part.sigma_51 = src.sigma_Pa_51;
    part.sigma_Pa_51 = src.sigma_Pa_51;
    part.epsilon_51 = src.epsilon_51;
    part.pai_51 = src.pai_Pa_51;
    part.pai_Pa_51 = src.pai_Pa_51;
    part.r_xi_51 = src.r_xi_1_per_s_51;
    part.r_xi_1_per_s_51 = src.r_xi_1_per_s_51;
    part.q_latent_51 = src.q_latent_W_per_m3_51;
    part.q_latent_W_per_m3_51 = src.q_latent_W_per_m3_51;
end

function metrics = cycle_metrics(coupled, ecc_energy, coupling)
    metrics = struct();
    metrics.qa = ecc_energy.qa_J_per_kg;
    metrics.qr = ecc_energy.qr_J_per_kg;
    metrics.Qa = coupled.Qa_W;
    metrics.Qr = coupled.Qr_W;
    metrics.PECC = coupled.PECC_W;
    metrics.etaECC = coupled.etaECC;
    metrics.PPSC = coupled.P_PSC_W;
    metrics.etaPSC = coupled.eta_PSC;
    metrics.PH = coupled.PH_W;
    metrics.etaH = coupled.etaH;
    metrics.Qh = coupled.Qh_W;
    metrics.QL = coupled.QL_W;
    metrics.nu = coupled.nu_Hz;
    metrics.MDTD = coupling.MDTD_K;
    metrics.Th = coupling.T_h_K;
    metrics.coupling_residual = coupling.max_scaled_residual;
end

function summary = build_article_cycle_summary(options, sweep, coupled, coupling, ...
        ecc_energy, initial_state, final_state, cycle_results)
    ref_psc = options.psc.article_reference;
    ref_hybrid = options.psc_ecc.article_reference;
    psc_lift = (sweep.max_hybrid.P_H_max_W - ref_psc.P_PSC_max_W) / ref_psc.P_PSC_max_W;
    eta_lift = (sweep.max_hybrid.eta_H_max - ref_psc.eta_PSC_max) / ref_psc.eta_PSC_max;
    final_vs_prev = state_delta(cycle_results(max(numel(cycle_results) - 1, 1)).final_state, ...
        cycle_results(end).final_state);

    summary = struct();
    summary.schema_version = 'perovskite_article_10cycle_summary_v1';
    summary.ok = true;
    summary.cycle_count = options.cycle_count;
    summary.stage_count = options.cycle_count * 4;
    summary.node_count_sma = numel(final_state.SMA.T_51);
    summary.node_count_se = numel(final_state.SE.T_51);
    summary.model_route = 'article_eq1_26_axial_dynamic_51_51';
    summary.deprecated_first_round_route_used = false;
    summary.Vm_V = sweep.max_hybrid.V_m_V;
    summary.P_PSC_max_W = sweep.max_psc.P_PSC_max_W;
    summary.eta_PSC_max = sweep.max_psc.eta_PSC_max;
    summary.P_H_max_W = sweep.max_hybrid.P_H_max_W;
    summary.eta_H_max = sweep.max_hybrid.eta_H_max;
    summary.P_H_lift_fraction = psc_lift;
    summary.eta_H_lift_fraction = eta_lift;
    summary.reference = struct( ...
        'Vm_V', ref_psc.Vm_V, ...
        'P_PSC_max_W', ref_psc.P_PSC_max_W, ...
        'eta_PSC_max', ref_psc.eta_PSC_max, ...
        'P_H_max_W', ref_hybrid.P_H_max_W, ...
        'eta_H_max', ref_hybrid.eta_H_max, ...
        'P_H_lift_fraction', ref_hybrid.P_H_lift_fraction, ...
        'eta_H_lift_fraction', ref_hybrid.eta_H_lift_fraction);
    summary.ecc = struct( ...
        'T_h_K', coupling.T_h_K, ...
        'MDTD_K', coupling.MDTD_K, ...
        'delta_xM_a', coupling.delta_xM_a, ...
        'delta_xM_r', coupling.delta_xM_r, ...
        'qa_J_per_kg', ecc_energy.qa_J_per_kg, ...
        'qr_J_per_kg', ecc_energy.qr_J_per_kg, ...
        'coupling_residual', coupling.max_scaled_residual, ...
        'coupling_audit_residual', coupling.audit_max_scaled_residual);
    summary.psc_ecc = coupled;
    summary.trends = sweep.trends;
    summary.final_state = struct( ...
        'SMA_xM_min', min(final_state.SMA.xM_51), ...
        'SMA_xM_max', max(final_state.SMA.xM_51), ...
        'SE_xM_min', min(final_state.SE.xM_51), ...
        'SE_xM_max', max(final_state.SE.xM_51), ...
        'all_finite', all(isfinite([final_state.SMA.T_51; final_state.SMA.xM_51; ...
            final_state.SMA.sigma_Pa_51; final_state.SMA.epsilon_51; ...
            final_state.SE.T_51; final_state.SE.xM_51; final_state.SE.sigma_Pa_51; ...
            final_state.SE.epsilon_51])));
    summary.no_cycle_drift_last_two = final_vs_prev;
    summary.initial_to_final_xM = struct( ...
        'SMA_mean_delta', mean(final_state.SMA.xM_51) - mean(initial_state.SMA.xM_51), ...
        'SE_mean_delta', mean(final_state.SE.xM_51) - mean(initial_state.SE.xM_51));
end

function delta = state_delta(a, b)
    delta = struct();
    delta.SMA_xM_inf_norm = max(abs(a.SMA.xM_51 - b.SMA.xM_51));
    delta.SE_xM_inf_norm = max(abs(a.SE.xM_51 - b.SE.xM_51));
    delta.SMA_T_inf_norm_K = max(abs(a.SMA.T_51 - b.SMA.T_51));
    delta.SE_T_inf_norm_K = max(abs(a.SE.T_51 - b.SE.T_51));
end

function result = write_outputs(result, options)
    if ~exist(options.outputs_dir, 'dir')
        mkdir(options.outputs_dir);
    end
    result_path = fullfile(options.outputs_dir, 'perovskite_article_10cycle_result.mat');
    summary_path = fullfile(options.outputs_dir, 'perovskite_article_10cycle_summary.json');
    save(result_path, 'result', '-v7.3');
    write_json(summary_path, result.summary);
    result.output_paths = struct('result_mat', result_path, 'summary_json', summary_path);
end

function write_json(path, data)
    try
        text = jsonencode(data, 'PrettyPrint', true);
    catch
        text = jsonencode(data);
    end
    fid = fopen(path, 'w');
    if fid < 0
        error('Run_PerovskiteECC_Article_Cycles:CannotWriteJson', ...
            'Cannot write JSON file: %s', path);
    end
    cleaner = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end

function value = get_field(s, field_name, fallback)
    if isstruct(s) && isfield(s, field_name)
        value = s.(field_name);
    else
        value = fallback;
    end
end

function s = set_field(s, field_name, value)
    s.(field_name) = value;
end
