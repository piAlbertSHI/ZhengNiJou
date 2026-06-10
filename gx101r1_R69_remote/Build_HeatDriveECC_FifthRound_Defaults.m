function options = Build_HeatDriveECC_FifthRound_Defaults(overrides)
% Defaults for the mature-loop fifth-round heat-driven ECC model.

    if nargin < 1
        overrides = struct();
    end
    root_dir = fileparts(mfilename('fullpath'));
    options = struct();
    options.schema_version = 'heatdrive_ecc_fifth_round_defaults_v1';
    options.model_name = 'heatdrive_ecc_reconfigured_from_solver101';
    options.model_path = fullfile(root_dir, [options.model_name '.slx']);
    options.cycle_count = 3;
    options.stage_names = {'sma_heat_load','se_reject_heat', ...
        'sma_cool_unload','se_absorb_heat'};
    article = Build_HeatDriveECC_Article_Defaults();
    options.stage_max_duration_s = article.schedule.stage_durations_s;
    options.command_ramp_s = 0.005;
    options.stage_switch_mode = 'event_guarded_with_article_eq24_maximum';
    options.event_guards = {
        'SMA temperature/phase drive and SE loading feasible'
        'SE outlet approaches HHEX/T0 or reject heat target reached'
        'SMA cooling and compatible SE low-load state reached'
        'SE outlet approaches CHEX/Tc or cold-load heat target reached'};
    options.system = struct('T0_K',308.0,'Tc_K',288.0,'Th_K',article.equilibrium.T_h_K, ...
        'cp_fluid_J_per_kgK',4180.0,'article_Qh_W',article.equilibrium.Qh_W, ...
        'article_Qr_W',article.equilibrium.Qr_W,'article_PECC_W',article.equilibrium.PECC_W, ...
        'article_etaECC',article.equilibrium.etaECC,'article_nu_Hz',article.equilibrium.nu_Hz, ...
        'article_qa_J_per_kg',article.equilibrium.qa_J_per_kg, ...
        'article_qr_J_per_kg',article.equilibrium.qr_J_per_kg);
    options.geometry = struct('L_a_m',1.0,'S_a_m2',1.0e-6, ...
        'L_r_m',0.4,'S_r_m2',0.2e-6);
    options.material = struct('rho_kg_per_m3',6500.0,'cp_J_per_kgK',500.0, ...
        'k_W_per_mK',18.0,'latent_J_per_kg',1.0e4);
    options.outputs_dir = fullfile(root_dir, 'outputs_heatdrive_ecc_fifth_round_3cycle');
    options.force_rebuild_model = false;
    options.validation = struct('max_eq6_scaled',1.0e-8,'max_eq7_scaled',1.0e-3, ...
        'max_stage_energy_residual_fraction',0.05,'max_cycle_energy_residual_fraction',0.05, ...
        'closed_route_flow_kgps',1.0e-5,'minimum_probe_delta_K',1.0e-4);
    options = merge_struct(options, overrides);
end

function out = merge_struct(out, overrides)
    if ~isstruct(overrides)
        return;
    end
    names = fieldnames(overrides);
    for idx = 1:numel(names)
        name = names{idx};
        if isfield(out, name) && isstruct(out.(name)) && ...
                isstruct(overrides.(name)) && isscalar(overrides.(name))
            out.(name) = merge_struct(out.(name), overrides.(name));
        else
            out.(name) = overrides.(name);
        end
    end
end
