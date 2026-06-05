function result = Run_PerovskiteECC_SingleStage_Cycles(options)
% Run the paper Eq. 6-21 single-stage axial ECC cycle.

    if nargin < 1 || isempty(options)
        options = Build_PerovskiteECC_Default_Options();
    else
        options = Build_PerovskiteECC_Default_Options(options);
    end

    if options.node_count ~= 51
        error('Run_PerovskiteECC_SingleStage_Cycles:InvalidNodeCount', ...
            'Second-round PerovskiteECC runner requires 51 SMA nodes and 51 SE nodes.');
    end

    coupling = PerovskiteECC_CouplingEquations(options);
    constitutive = PerovskiteECC_Constitutive(options, coupling);
    energy = PerovskiteECC_EnergyModel(options, coupling);
    state = Initialize_PerovskiteECC_State(options);

    stage_names = {'sma_heat_load', 'se_reject_heat', 'sma_cool_unload', 'se_absorb_heat'};
    stage_reports = [];
    state_history = {};

    for cycle_idx = 1:options.cycle_count
        for stage_idx = 1:numel(stage_names)
            state.cycle_index = cycle_idx;
            [state, stage_report] = PerovskiteECC_ThermalStep51( ...
                state, options, stage_names{stage_idx}, coupling, constitutive, energy);
            stage_report.cycle_index = cycle_idx;
            if isempty(stage_reports)
                stage_reports = stage_report;
            else
                stage_reports(end + 1) = stage_report; %#ok<AGROW>
            end
            state_history{end + 1, 1} = compact_state_snapshot(state); %#ok<AGROW>
        end
    end

    summary = build_run_summary(options, coupling, energy, state, stage_reports);

    result = struct();
    result.schema_version = 'perovskite_ecc_single_stage_run_v1';
    result.options = options;
    result.coupling = coupling;
    result.constitutive = constitutive;
    result.energy = energy;
    result.stage_reports = stage_reports;
    result.state_history = state_history;
    result.final_state = state;
    result.summary = summary;
    result.node_outputs = build_node_outputs(state);

    if options.write_outputs
        result = write_outputs(result, options);
    end
end

function snapshot = compact_state_snapshot(state)
    snapshot = struct();
    snapshot.stage_name = state.stage_name;
    snapshot.cycle_index = state.cycle_index;
    snapshot.time_s = state.time_s;
    snapshot.controls = state.controls;
    snapshot.SMA = state.SMA;
    snapshot.SE = state.SE;
    snapshot.coupling_residual = get_field(state.coupling, 'max_scaled_residual', NaN);
    snapshot.qa_J_per_kg = get_field(state.energy, 'qa_J_per_kg', NaN);
    snapshot.qr_J_per_kg = get_field(state.energy, 'qr_J_per_kg', NaN);
    snapshot.Qa_W = get_field(state.energy, 'Qa_W', NaN);
    snapshot.Qr_W = get_field(state.energy, 'Qr_W', NaN);
    snapshot.PECC_W = get_field(state.energy, 'PECC_W', NaN);
    snapshot.etaECC = get_field(state.energy, 'etaECC', NaN);
end

function summary = build_run_summary(options, coupling, energy, state, stage_reports)
    summary = struct();
    summary.schema_version = 'perovskite_ecc_run_summary_v1';
    summary.model_route = 'paper_eq6_21_axial_51_sma_51_se';
    summary.deprecated_first_round_route_used = false;
    summary.node_count_sma = numel(state.SMA.T_51);
    summary.node_count_se = numel(state.SE.T_51);
    summary.cycle_count = options.cycle_count;
    summary.stage_count = numel(stage_reports);
    summary.stage_names = {stage_reports.stage_name};
    summary.cross_section_shape = options.geometry.cross_section_shape;
    summary.L_r_over_L_a = options.geometry.L_r_over_L_a;
    summary.S_r_over_S_a = options.geometry.S_r_over_S_a;
    summary.T_h_K = coupling.T_h_K;
    summary.T0_K = options.system.T0_K;
    summary.T_c_K = options.system.T_c_K;
    summary.MDTD_K = coupling.MDTD_K;
    summary.delta_xM_a = coupling.delta_xM_a;
    summary.delta_xM_r = coupling.delta_xM_r;
    summary.sigma_r_ld_Pa = coupling.sigma_r_ld_Pa;
    summary.sigma_r_uld_Pa = coupling.sigma_r_uld_Pa;
    summary.sigma_a_ld_Pa = coupling.sigma_a_ld_Pa;
    summary.sigma_a_uld_Pa = coupling.sigma_a_uld_Pa;
    summary.coupling_residual = coupling.max_scaled_residual;
    summary.coupling_audit_residual = coupling.audit_max_scaled_residual;
    summary.coupling_ok = coupling.ok;
    summary.qa_J_per_kg = energy.qa_J_per_kg;
    summary.qr_J_per_kg = energy.qr_J_per_kg;
    summary.Qa_W = energy.Qa_W;
    summary.Qr_W = energy.Qr_W;
    summary.PECC_W = energy.PECC_W;
    summary.etaECC = energy.etaECC;
    summary.m_a_kg = energy.m_a_kg;
    summary.m_r_kg = energy.m_r_kg;
    summary.nu_Hz = energy.nu_Hz;
    summary.final_xM_SMA_mean = mean(state.SMA.xM_51);
    summary.final_xM_SE_mean = mean(state.SE.xM_51);
    summary.final_T_SMA_mean_K = mean(state.SMA.T_51);
    summary.final_T_SE_mean_K = mean(state.SE.T_51);
end

function node_outputs = build_node_outputs(state)
    node_outputs = struct();
    node_outputs.SMA_T_51_K = state.SMA.T_51;
    node_outputs.SMA_sigma_51_Pa = state.SMA.sigma_Pa_51;
    node_outputs.SMA_epsilon_51 = state.SMA.epsilon_51;
    node_outputs.SMA_xM_51 = state.SMA.xM_51;
    node_outputs.SMA_pai_51_Pa = state.SMA.pai_Pa_51;
    node_outputs.SMA_r_xi_51_1_per_s = state.SMA.r_xi_1_per_s_51;
    node_outputs.SMA_q_latent_51_W_per_m3 = state.SMA.q_latent_W_per_m3_51;
    node_outputs.SE_T_51_K = state.SE.T_51;
    node_outputs.SE_sigma_51_Pa = state.SE.sigma_Pa_51;
    node_outputs.SE_epsilon_51 = state.SE.epsilon_51;
    node_outputs.SE_xM_51 = state.SE.xM_51;
    node_outputs.SE_pai_51_Pa = state.SE.pai_Pa_51;
    node_outputs.SE_r_xi_51_1_per_s = state.SE.r_xi_1_per_s_51;
    node_outputs.SE_q_latent_51_W_per_m3 = state.SE.q_latent_W_per_m3_51;
end

function result = write_outputs(result, options)
    if ~exist(options.outputs_dir, 'dir')
        mkdir(options.outputs_dir);
    end
    result_path = fullfile(options.outputs_dir, 'perovskite_ecc_result.mat');
    summary_path = fullfile(options.outputs_dir, 'perovskite_ecc_summary.json');
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
        error('Run_PerovskiteECC_SingleStage_Cycles:CannotWriteJson', ...
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

