function [state, diag] = PerovskiteECC_D2ConstitutiveKernel(state, options, stage_name, dt_s, targets)
% d_2-inspired 51+51 constitutive state-update kernel.
%
% This migrates d_2 ideas: SMA/SE partitions, xi_state, coupled stress, pai,
% r_xi, latent q, and pump/valve signals. The rate is branch driven by pai,
% hardening, and a threshold; target xM values are only physical end stops.

    if nargin < 3 || isempty(stage_name)
        stage_name = state.stage_name;
    end
    if nargin < 4 || isempty(dt_s)
        dt_s = 1.0;
    end
    if nargin < 5
        targets = struct();
    end

    [state.SMA, diag_sma] = update_partition(state.SMA, options.material.SMA, ...
        options, dt_s, get_command(targets, 'SMA', state.SMA.xM_51));
    [state.SE, diag_se] = update_partition(state.SE, options.material.SE, ...
        options, dt_s, get_command(targets, 'SE', state.SE.xM_51));

    state.controls = controls_for_stage(stage_name, state, options);
    diag = struct();
    diag.schema_version = 'perovskite_ecc_d2_kernel_diag_v1';
    diag.stage_name = stage_name;
    diag.SMA = diag_sma;
    diag.SE = diag_se;
    diag.controls = state.controls;
end

function [part, diag] = update_partition(part, material, options, dt_s, command)
    kernel = options.d2_kernel;
    old_xM = part.xM_51;
    target_xM = min(max(command.target_xM_51(:), 0.0), 1.0);
    direction = command.direction;
    if numel(target_xM) ~= numel(old_xM)
        error('PerovskiteECC_D2ConstitutiveKernel:TargetSizeMismatch', ...
            'Target xM size must match the partition node count.');
    end

    hardening = kernel.X0_Pa + branch_hardening(kernel, direction) .* old_xM + ...
        kernel.H_shape_Pa .* old_xM .^ 2;
    pai = branch_pai(part, material, direction) - hardening;
    active_drive = max(direction .* pai - kernel.transformation_threshold_Pa, 0.0);
    normalized_drive = active_drive ./ max(kernel.transformation_threshold_Pa, 1.0);
    r_xi = direction .* kernel.rate_coefficient_1_per_s .* ...
        normalized_drive .^ kernel.rate_exponent;
    limit = kernel.rate_limit_1_per_s;
    r_xi = min(max(r_xi, -limit), limit);

    if direction > 0
        r_xi = min(r_xi, max((target_xM - old_xM) ./ max(dt_s, eps), 0.0));
    elseif direction < 0
        r_xi = max(r_xi, min((target_xM - old_xM) ./ max(dt_s, eps), 0.0));
    else
        r_xi(:) = 0.0;
    end

    new_xM = min(max(old_xM + dt_s .* r_xi, 0.0), 1.0);
    part.delta_xM_51 = new_xM - old_xM;
    part.xM_51 = new_xM;
    part.pai_Pa_51 = pai;
    part.r_xi_1_per_s_51 = r_xi;
    part.q_latent_W_per_m3_51 = -part.T_51 .* material.rho_kg_per_m3 .* ...
        kernel.entropy_change_J_per_kgK .* r_xi;

    diag = struct();
    diag.xM_mean = mean(part.xM_51);
    diag.xM_min = min(part.xM_51);
    diag.xM_max = max(part.xM_51);
    diag.pai_mean_Pa = mean(part.pai_Pa_51);
    diag.r_xi_mean_1_per_s = mean(part.r_xi_1_per_s_51);
    diag.q_latent_mean_W_per_m3 = mean(part.q_latent_W_per_m3_51);
    diag.direction = direction;
    diag.active_drive_mean_Pa = mean(active_drive);
end

function H = branch_hardening(kernel, direction)
    if direction < 0
        H = kernel.H_reverse_Pa;
    else
        H = kernel.H_forward_Pa;
    end
end

function pai = branch_pai(part, material, direction)
    sigma = part.sigma_Pa_51;
    T = part.T_51;
    if direction > 0
        forward_threshold = material.C_M_Pa_per_K .* (T - material.T_Ms_K);
        pai = sigma - forward_threshold;
    elseif direction < 0
        reverse_threshold = material.C_A_Pa_per_K .* (T - material.T_As_K);
        pai = sigma - reverse_threshold;
    else
        pai = zeros(size(sigma));
    end
end

function command = get_command(targets, prefix, fallback_xM)
    command = struct();
    target_field = [prefix, '_xM_51'];
    direction_field = [prefix, '_direction'];
    if isstruct(targets) && isfield(targets, target_field)
        command.target_xM_51 = targets.(target_field);
    else
        command.target_xM_51 = fallback_xM;
    end
    if isstruct(targets) && isfield(targets, direction_field)
        command.direction = targets.(direction_field);
    else
        command.direction = 0.0;
    end
end

function controls = controls_for_stage(stage_name, state, options)
    controls = struct();
    controls.pump_signal = double(mean(state.SMA.xM_51) > options.controls.pump_threshold_xM_sma);
    controls.valve_hot_signal = 0.0;
    controls.valve_cold_signal = 0.0;
    controls.valve_regenerator_signal = 0.0;

    switch lower(strtrim(stage_name))
        case {'sma_heat_load', 'stage1_sma_heat_load'}
            controls.valve_hot_signal = options.controls.stage_valve_open_signal;
            controls.valve_regenerator_signal = options.controls.stage_valve_closed_signal;
        case {'se_reject_heat', 'stage2_se_reject_heat'}
            controls.valve_hot_signal = options.controls.stage_valve_open_signal;
            controls.valve_regenerator_signal = options.controls.stage_valve_open_signal;
        case {'sma_cool_unload', 'stage3_sma_cool_unload'}
            controls.valve_cold_signal = options.controls.stage_valve_open_signal;
        case {'se_absorb_heat', 'stage4_se_absorb_heat'}
            controls.valve_cold_signal = options.controls.stage_valve_open_signal;
            controls.valve_regenerator_signal = options.controls.stage_valve_open_signal;
    end
end
