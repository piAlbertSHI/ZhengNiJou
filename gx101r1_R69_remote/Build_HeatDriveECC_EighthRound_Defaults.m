function options = Build_HeatDriveECC_EighthRound_Defaults(overrides)
% Unified defaults for eighth-round 51-node Simulink ECC validation.
%
% The model is a one-dimensional axial SMA/SE representation using the paper
% length and generic area abstraction. It intentionally does not use the
% legacy circular plate w/u/radius model.

    if nargin < 1
        overrides = struct();
    end

    root_dir = fileparts(mfilename('fullpath'));
    article = Build_HeatDriveECC_Article_Defaults();

    options = struct();
    options.schema_version = 'heatdrive_ecc_eighth_round_defaults_v1';
    options.node_count = 51;
    options.cycle_count = 3;
    options.model_name = 'heatdrive_ecc_1d51_eighth_round';
    options.model_path = fullfile(root_dir, [options.model_name '.slx']);
    options.outputs_dir = fullfile(root_dir, 'outputs_heatdrive_ecc_eighth_round');
    options.report_path = fullfile(fileparts(root_dir), '项目文档', ...
        '修改报告', 'Agent2_第八轮真实51节点Simulink仿真报告.txt');

    options.system = article.system;
    options.system.Th_K = article.equilibrium.T_h_K;
    options.system.cp_fluid_J_per_kgK = 4180.0;
    options.system.article_Qh_W = article.equilibrium.Qh_W;
    options.system.article_Qr_W = article.equilibrium.Qr_W;
    options.system.article_Qh_cycle_J = article.equilibrium.Qh_W * ...
        article.equilibrium.tau_cycle_s;
    options.system.article_Qr_cycle_J = article.equilibrium.Qr_W * ...
        article.equilibrium.tau_cycle_s;
    options.system.article_Qr_over_Qh = article.equilibrium.Qr_W / ...
        article.equilibrium.Qh_W;
    options.system.article_PECC_W = article.equilibrium.PECC_W;
    options.system.article_etaECC = article.equilibrium.etaECC;
    options.system.article_tau_cycle_s = article.equilibrium.tau_cycle_s;

    options.geometry = article.geometry;
    options.material = article.material;
    options.equilibrium = article.equilibrium;
    options.schedule = article.schedule;

    options.simulation = struct();
    options.simulation.fixed_step_s = min(article.schedule.stage_durations_s) / 80.0;
    options.simulation.samples_per_stage = 80;
    options.simulation.solver = 'FixedStepDiscrete';
    options.simulation.stop_time_s = options.cycle_count * ...
        article.equilibrium.tau_cycle_s;
    options.simulation.output_variable = 'eighth_round_yout';

    options.branch = struct();
    options.branch.m_dot_kg_per_s = 0.022;
    options.branch.fluid_mass_total_kg = 0.018;
    options.branch.UA_sma_shex_W_per_K = 160.0;
    options.branch.UA_sma_the_W_per_K = 200.0;
    options.branch.UA_se_the_W_per_K = 6.0;
    options.branch.UA_se_rhe_W_per_K = 13.0;
    options.branch.boundary_UA_shex_W_per_K = 500.0;
    options.branch.boundary_UA_the_W_per_K = 500.0;
    options.branch.boundary_UA_rhe_W_per_K = 500.0;
    options.branch.source = 'eighth_round_calibrated_finite_volume_51node';
    options.branch.calibration_bounds = struct( ...
        'm_dot_kg_per_s', [0.005, 0.06], ...
        'UA_sma_shex_W_per_K', [5.0, 70.0], ...
        'UA_se_rhe_W_per_K', [3.0, 50.0], ...
        'boundary_UA_W_per_K', [80.0, 5000.0]);

    options.solid = struct();
    options.solid.k_sma_W_per_mK = 18.0;
    options.solid.k_se_W_per_mK = 18.0;
    options.solid.axial_conduction_enabled = true;
    options.solid.boundary_condition = 'adiabatic_ends';
    options.solid.heat_recovery_efficiency = options.system.eta_hr;

    options.constitutive = struct();
    options.constitutive.rate_a_to_A_1_per_s = 95.0;
    options.constitutive.rate_a_to_M_1_per_s = 300.0;
    options.constitutive.rate_r_load_1_per_s = 260.0;
    options.constitutive.rate_r_stage3_unload_1_per_s = 300.0;
    options.constitutive.rate_r_stage4_unload_1_per_s = 300.0;
    options.constitutive.max_rate_1_per_s = 800.0;
    options.constitutive.se_load_hardening_Pa = 0.0;
    options.constitutive.se_unload_assist_Pa = 60.0e6;
    options.constitutive.drive_width_a_Pa = ...
        options.material.SMA.C_M_Pa_per_K * ...
        (options.material.SMA.T_Af_K - options.material.SMA.T_As_K);
    options.constitutive.drive_width_r_Pa = ...
        options.material.SE.C_A_Pa_per_K * ...
        (options.material.SE.T_Af_K - options.material.SE.T_As_K);
    options.constitutive.se_loading_work_J_per_kg = options.material.SE.w_ld_J_per_kg;
    options.constitutive.se_unloading_work_J_per_kg = options.material.SE.w_uld_J_per_kg;
    options.constitutive.source = 'single_parameter_set_for_constitutive_cycles_and_simulink';

    options.validation = struct();
    options.validation.min_samples_per_stage = 50;
    options.validation.max_eq6_scaled = 1.0e-6;
    options.validation.max_eq7_scaled = 1.0e-3;
    options.validation.min_node_spread_K = 0.05;
    options.validation.max_qh_rel_error = 0.30;
    options.validation.max_qr_rel_error = 0.30;
    options.validation.max_qr_qh_rel_error = 0.30;
    options.validation.max_delta_xM_a_rel_error = 0.30;
    options.validation.max_delta_xM_r_rel_error = 0.30;
    options.validation.min_delta_xM_r = 0.70;
    options.validation.max_sigma_r_rel_error = 0.30;
    options.validation.max_Th_abs_error_K = 3.0;
    options.validation.max_energy_residual_fraction = 0.05;

    options.output = build_output_map(options.node_count);
    options = merge_structs(options, overrides);
    options.schedule.total_time_s = options.cycle_count * options.schedule.tau_cycle_s;
    options.simulation.stop_time_s = options.cycle_count * options.schedule.tau_cycle_s;
    options.output = build_output_map(options.node_count);
end

function map = build_output_map(N)
    scalar_names = {'time_s','cycle_index','stage_id','stage_elapsed_s', ...
        'Ta_mean_K','Ta_min_K','Ta_max_K','Tr_mean_K','Tr_min_K','Tr_max_K', ...
        'xM_a_mean','xM_r_mean','sigma_a_Pa','sigma_r_Pa', ...
        'epsilon_a_mean','epsilon_r_mean','eq6_scaled','eq7_scaled', ...
        'Q_sma_shex_W','Q_sma_the_W','Q_se_the_W','Q_se_rhe_W', ...
        'Q_shex_boundary_W','Q_the_sma_boundary_W', ...
        'Q_the_se_boundary_W','Q_rhe_boundary_W', ...
        'latentA_W','latentR_W','mechanicalA_W','mechanicalR_W', ...
        'SMA_SHEX_mdot','SMA_THE_mdot','SE_THE_mdot','SE_RHE_mdot', ...
        'SMA_SHEX_Tin_K','SMA_SHEX_Tout_K','SMA_THE_Tin_K','SMA_THE_Tout_K', ...
        'SE_THE_Tin_K','SE_THE_Tout_K','SE_RHE_Tin_K','SE_RHE_Tout_K', ...
        'SMA_sensible_W','SE_sensible_W','branch_storage_W','energy_residual_W'};
    map = struct();
    for idx = 1:numel(scalar_names)
        map.(scalar_names{idx}) = idx;
    end
    start = numel(scalar_names) + 1;
    array_names = {'Ta_51','Tr_51','xM_a_51','xM_r_51', ...
        'sigma_a_51','sigma_r_51','epsilon_a_51','epsilon_r_51', ...
        'pai_a_51','pai_r_51','r_xi_a_51','r_xi_r_51', ...
        'SMA_SHEX_Tin_51','SMA_SHEX_Tout_51','SMA_SHEX_Tfluid_51','SMA_SHEX_Q_51', ...
        'SMA_THE_Tin_51','SMA_THE_Tout_51','SMA_THE_Tfluid_51','SMA_THE_Q_51', ...
        'SE_THE_Tin_51','SE_THE_Tout_51','SE_THE_Tfluid_51','SE_THE_Q_51', ...
        'SE_RHE_Tin_51','SE_RHE_Tout_51','SE_RHE_Tfluid_51','SE_RHE_Q_51'};
    for idx = 1:numel(array_names)
        map.(array_names{idx}) = start:(start + N - 1);
        start = start + N;
    end
    map.scalar_names = scalar_names;
    map.array_names = array_names;
    map.output_width = start - 1;
end

function out = merge_structs(out, overrides)
    if ~isstruct(overrides) || isempty(fieldnames(overrides))
        return;
    end
    names = fieldnames(overrides);
    for idx = 1:numel(names)
        key = names{idx};
        if isfield(out, key) && isstruct(out.(key)) && isstruct(overrides.(key))
            out.(key) = merge_structs(out.(key), overrides.(key));
        else
            out.(key) = overrides.(key);
        end
    end
end
