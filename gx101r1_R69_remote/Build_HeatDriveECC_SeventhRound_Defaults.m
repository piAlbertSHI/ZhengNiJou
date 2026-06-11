function options = Build_HeatDriveECC_SeventhRound_Defaults(overrides)
% Defaults for seventh-round constitutive and lightweight branch closure.
%
% The physical model uses the paper-aligned one-dimensional axial SMA/SE
% abstraction: length L and generic cross-sectional area S. No plate or
% legacy radius/diameter surrogate is used here.

    if nargin < 1
        overrides = struct();
    end

    root_dir = fileparts(mfilename('fullpath'));
    article = Build_HeatDriveECC_Article_Defaults();

    options = struct();
    options.schema_version = 'heatdrive_ecc_seventh_round_defaults_v1';
    options.node_count = 51;
    options.cycle_count = 3;
    options.outputs_dir = fullfile(root_dir, 'outputs_heatdrive_ecc_seventh_round');
    options.report_path = fullfile(fileparts(root_dir), '项目文档', ...
        '修改报告', 'Agent2_第七轮本构与四支路闭合报告.txt');

    options.system = article.system;
    options.system.Th_K = article.equilibrium.T_h_K;
    options.system.article_Qh_W = article.equilibrium.Qh_W;
    options.system.article_Qr_W = article.equilibrium.Qr_W;
    options.system.article_PECC_W = article.equilibrium.PECC_W;
    options.system.article_etaECC = article.equilibrium.etaECC;
    options.system.article_nu_Hz = article.equilibrium.nu_Hz;
    options.system.article_tau_cycle_s = article.equilibrium.tau_cycle_s;
    options.system.article_qa_J_per_kg = article.equilibrium.qa_J_per_kg;
    options.system.article_qr_J_per_kg = article.equilibrium.qr_J_per_kg;
    options.system.cp_fluid_J_per_kgK = 4180.0;

    options.geometry = article.geometry;
    options.material = article.material;
    options.equilibrium = article.equilibrium;
    options.schedule = article.schedule;

    options.constitutive = struct();
    options.constitutive.rate_a_to_A_1_per_s = 7.5;
    options.constitutive.rate_a_to_M_1_per_s = 5.5;
    options.constitutive.rate_r_load_1_per_s = 8.0;
    options.constitutive.rate_r_unload_1_per_s = 7.0;
    options.constitutive.max_rate_1_per_s = 18.0;
    options.constitutive.drive_width_a_Pa = ...
        options.material.SMA.C_M_Pa_per_K * ...
        (options.material.SMA.T_Af_K - options.material.SMA.T_As_K);
    options.constitutive.drive_width_r_Pa = ...
        options.material.SE.C_A_Pa_per_K * ...
        (options.material.SE.T_Af_K - options.material.SE.T_As_K);
    options.constitutive.se_load_hardening_Pa = 4.0e6;
    options.constitutive.se_unload_hysteresis_Pa = 10.0e6;
    options.constitutive.adiabatic_se_temperature_enabled = true;
    options.constitutive.se_loading_work_J_per_kg = options.material.SE.w_ld_J_per_kg;
    options.constitutive.se_unloading_work_J_per_kg = options.material.SE.w_uld_J_per_kg;

    options.validation = struct();
    options.validation.constitutive_samples_per_stage = 260;
    options.validation.cycle_samples_per_stage = 72;
    options.validation.max_eq6_scaled = 1.0e-6;
    options.validation.max_eq7_scaled = 1.0e-3;
    options.validation.min_loading_xM_a_delta = -0.2;
    options.validation.min_loading_xM_r_delta = 0.5;
    options.validation.min_unloading_xM_a_delta = 0.2;
    options.validation.max_unloading_xM_r_delta = -0.5;
    options.validation.min_max_sigma_r_Pa = 1.0e6;

    options.branch = struct();
    options.branch.strategy = 'finite_volume_equivalent';
    options.branch.fluid_mass_kg = 0.035;
    options.branch.m_dot_kg_per_s = 0.04;
    options.branch.UA_W_per_K = 45.0;
    options.branch.boundary_UA_W_per_K = 3500.0;
    options.branch.wall_time_limit_s = 5.0;
    options.branch.closed_route_threshold_kgps = 1.0e-5;
    options.branch.min_temperature_delta_K = 1.0e-3;

    options = merge_structs(options, overrides);
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
