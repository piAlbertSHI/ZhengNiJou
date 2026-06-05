function [state, report] = PerovskiteECC_ThermalStep51(state, options, stage_name, coupling, constitutive, energy)
% Apply one paper-aligned thermal/mechanical stage to the 51+51 axial state.

    if nargin < 4 || isempty(coupling)
        coupling = PerovskiteECC_CouplingEquations(options);
    end
    if nargin < 5 || isempty(constitutive)
        constitutive = PerovskiteECC_Constitutive(options, coupling);
    end
    if nargin < 6 || isempty(energy)
        energy = PerovskiteECC_EnergyModel(options, coupling);
    end

    N = options.node_count;
    dt_s = 1.0 / max(options.stage_steps, 1);
    old_state = state;

    switch lower(strtrim(stage_name))
        case {'sma_heat_load', 'stage1_sma_heat_load'}
            stage_index = 1;
            state.stage_name = 'sma_heat_load';
            state.SMA.sigma_Pa_51 = constitutive.loading.SMA.sigma_Pa * ones(N, 1);
            state.SE.sigma_Pa_51 = constitutive.loading.SE.sigma_Pa * ones(N, 1);
            state.SMA.T_51 = axial_profile(coupling.T_h_K - 2.0, coupling.T_h_K, N);
            state.SE.T_51 = axial_profile(options.system.T_c_K, options.system.T_c_K + 0.2, N);
            targets.SMA_xM_51 = (1.0 - coupling.delta_xM_a) * ones(N, 1);
            targets.SMA_direction = -1.0;
            targets.SE_xM_51 = coupling.delta_xM_r * ones(N, 1);
            targets.SE_direction = 1.0;
        case {'se_reject_heat', 'stage2_se_reject_heat'}
            stage_index = 2;
            state.stage_name = 'se_reject_heat';
            state.SMA.T_51 = axial_profile(coupling.T_h_K - 0.5, coupling.T_h_K, N);
            state.SE.T_51 = axial_profile(options.system.T_c_K, options.system.T0_K, N);
            targets.SMA_xM_51 = state.SMA.xM_51;
            targets.SMA_direction = 0.0;
            targets.SE_xM_51 = ones(N, 1);
            targets.SE_direction = 0.0;
        case {'sma_cool_unload', 'stage3_sma_cool_unload'}
            stage_index = 3;
            state.stage_name = 'sma_cool_unload';
            state.SMA.sigma_Pa_51 = constitutive.unloading.SMA.sigma_Pa * ones(N, 1);
            state.SE.sigma_Pa_51 = constitutive.unloading.SE.sigma_Pa * ones(N, 1);
            state.SMA.T_51 = axial_profile(options.system.T0_K, options.system.T0_K + 2.0, N);
            state.SE.T_51 = axial_profile(options.system.T0_K, options.system.T_c_K, N);
            targets.SMA_xM_51 = ones(N, 1);
            targets.SMA_direction = 1.0;
            targets.SE_xM_51 = ones(N, 1);
            targets.SE_direction = 0.0;
        case {'se_absorb_heat', 'stage4_se_absorb_heat'}
            stage_index = 4;
            state.stage_name = 'se_absorb_heat';
            state.SMA.sigma_Pa_51 = zeros(N, 1);
            state.SE.sigma_Pa_51 = zeros(N, 1);
            state.SMA.T_51 = axial_profile(options.system.T0_K + 0.5, options.system.T0_K, N);
            state.SE.T_51 = axial_profile(options.system.T0_K, options.system.T_c_K, N);
            targets.SMA_xM_51 = ones(N, 1);
            targets.SMA_direction = 0.0;
            targets.SE_xM_51 = zeros(N, 1);
            targets.SE_direction = -1.0;
        otherwise
            error('PerovskiteECC_ThermalStep51:InvalidStage', ...
                'Unknown ECC stage: %s', stage_name);
    end

    kernel_diag = struct();
    accum.SMA_r = zeros(N, 1);
    accum.SE_r = zeros(N, 1);
    accum.SMA_q = zeros(N, 1);
    accum.SE_q = zeros(N, 1);
    for substep = 1:max(options.stage_steps, 1)
        [state, kernel_diag] = PerovskiteECC_D2ConstitutiveKernel( ...
            state, options, state.stage_name, dt_s, targets);
        accum.SMA_r = accum.SMA_r + state.SMA.r_xi_1_per_s_51;
        accum.SE_r = accum.SE_r + state.SE.r_xi_1_per_s_51;
        accum.SMA_q = accum.SMA_q + state.SMA.q_latent_W_per_m3_51;
        accum.SE_q = accum.SE_q + state.SE.q_latent_W_per_m3_51;
        state = update_strain_from_current_xM(state, options, coupling);
    end
    substeps = max(options.stage_steps, 1);
    state.SMA.r_xi_1_per_s_51 = accum.SMA_r ./ substeps;
    state.SE.r_xi_1_per_s_51 = accum.SE_r ./ substeps;
    state.SMA.q_latent_W_per_m3_51 = accum.SMA_q ./ substeps;
    state.SE.q_latent_W_per_m3_51 = accum.SE_q ./ substeps;
    kernel_diag.substeps = substeps;
    kernel_diag.SMA.r_xi_mean_1_per_s = mean(state.SMA.r_xi_1_per_s_51);
    kernel_diag.SE.r_xi_mean_1_per_s = mean(state.SE.r_xi_1_per_s_51);
    kernel_diag.SMA.q_latent_mean_W_per_m3 = mean(state.SMA.q_latent_W_per_m3_51);
    kernel_diag.SE.q_latent_mean_W_per_m3 = mean(state.SE.q_latent_W_per_m3_51);
    state.time_s = old_state.time_s + 1.0;
    state.coupling = coupling;
    state.energy = energy;

    report = build_report(stage_index, old_state, state, coupling, energy, kernel_diag);
end

function values = axial_profile(left_value, right_value, N)
    values = linspace(left_value, right_value, N).';
end

function state = update_strain_from_current_xM(state, options, coupling)
    sma = options.material.SMA;
    se = options.material.SE;
    delta_a = max(1.0 - state.SMA.xM_51, 0.0);
    delta_r = state.SE.xM_51;
    state.SMA.epsilon_51 = sma.epsilon_T .* delta_a - state.SMA.sigma_Pa_51 ./ sma.E_m_Pa;
    state.SE.epsilon_51 = se.epsilon_T .* delta_r + state.SE.sigma_Pa_51 ./ se.E_m_Pa;

    if strcmp(state.stage_name, 'sma_cool_unload')
        state.SMA.epsilon_51 = sma.epsilon_T .* coupling.delta_xM_a - ...
            state.SMA.sigma_Pa_51 ./ sma.E_m_Pa;
        state.SE.epsilon_51 = se.epsilon_T .* coupling.delta_xM_r + ...
            state.SE.sigma_Pa_51 ./ se.E_m_Pa;
    elseif strcmp(state.stage_name, 'se_absorb_heat')
        state.SMA.epsilon_51 = zeros(size(state.SMA.epsilon_51));
        state.SE.epsilon_51 = se.epsilon_T .* state.SE.xM_51 + ...
            state.SE.sigma_Pa_51 ./ se.E_m_Pa;
    end
end

function report = build_report(stage_index, old_state, state, coupling, energy, kernel_diag)
    report = struct();
    report.schema_version = 'perovskite_ecc_stage_report_v1';
    report.stage_index = stage_index;
    report.stage_name = state.stage_name;
    report.time_s = state.time_s;
    report.T_SMA_mean_K = mean(state.SMA.T_51);
    report.T_SE_mean_K = mean(state.SE.T_51);
    report.sigma_SMA_mean_Pa = mean(state.SMA.sigma_Pa_51);
    report.sigma_SE_mean_Pa = mean(state.SE.sigma_Pa_51);
    report.epsilon_SMA_mean = mean(state.SMA.epsilon_51);
    report.epsilon_SE_mean = mean(state.SE.epsilon_51);
    report.xM_SMA_mean = mean(state.SMA.xM_51);
    report.xM_SE_mean = mean(state.SE.xM_51);
    report.delta_xM_SMA_mean = report.xM_SMA_mean - mean(old_state.SMA.xM_51);
    report.delta_xM_SE_mean = report.xM_SE_mean - mean(old_state.SE.xM_51);
    report.q_latent_SMA_mean_W_per_m3 = mean(state.SMA.q_latent_W_per_m3_51);
    report.q_latent_SE_mean_W_per_m3 = mean(state.SE.q_latent_W_per_m3_51);
    report.coupling_residual = coupling.max_scaled_residual;
    report.qa_J_per_kg = energy.qa_J_per_kg;
    report.qr_J_per_kg = energy.qr_J_per_kg;
    report.Qa_W = energy.Qa_W;
    report.Qr_W = energy.Qr_W;
    report.PECC_W = energy.PECC_W;
    report.etaECC = energy.etaECC;
    report.kernel_diag = kernel_diag;
end
