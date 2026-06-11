function y = HeatDriveECC_SixthRound_MechanicalStep(u)
% Sixth-round SMA/SE mechanical compatibility and constitutive step.
%
% Input row vector:
%   [time_s, stage_id, Ta_mean_K, Tr_mean_K]
%
% Output row vector length 120:
%   1..12   scalar audit
%   13..63  xM_a(51)
%   64..114 xM_r(51)
%   115..120 pai/rate summary

    persistent xA xR last_t

    N = 51;
    if isempty(xA)
        xA = ones(1, N);
        xR = zeros(1, N);
        last_t = NaN;
    end

    u = u(:).';
    if numel(u) < 4
        error('HeatDriveECC_SixthRound_MechanicalStep:BadInput', ...
            'Expected [time_s, stage_id, Ta_K, Tr_K].');
    end
    t = u(1);
    stage_id = round(u(2));
    Ta = u(3);
    Tr = u(4);
    if ~isfinite(t) || t < 0 || (~isnan(last_t) && t < last_t)
        xA = ones(1, N);
        xR = zeros(1, N);
        last_t = t;
    end
    if isnan(last_t)
        dt = 0.0;
    else
        dt = max(t - last_t, 0.0);
    end

    p = material_parameters();
    xa = mean(xA);
    xr = mean(xR);
    [sigma_a, sigma_r, eps_a, eps_r, eq6_scaled, eq7_scaled] = ...
        compatible_state(xa, xr, p);

    [pai_a, pai_r, rxi_a, rxi_r] = phase_driving_rates( ...
        stage_id, Ta, Tr, sigma_a, sigma_r, xa, xr, p);

    if dt > 0
        xA = min(max(xA + dt * rxi_a, 0.0), 1.0);
        xR = min(max(xR + dt * rxi_r, 0.0), 1.0);
    end

    xa_new = mean(xA);
    xr_new = mean(xR);
    [sigma_a, sigma_r, eps_a, eps_r, eq6_scaled, eq7_scaled] = ...
        compatible_state(xa_new, xr_new, p);

    mA_node = p.rho * p.Sa * p.La / N;
    mR_node = p.rho * p.Sr * p.Lr / N;
    qA_total_W = sum(mA_node * p.latent * rxi_a * ones(1, N));
    qR_total_W = sum(mR_node * p.latent * rxi_r * ones(1, N));
    mechA_W = sigma_a * p.Sa * p.La * p.epsT * (-rxi_a);
    mechR_W = sigma_r * p.Sr * p.Lr * p.epsT * rxi_r;

    scalar = zeros(1, 12);
    scalar(1) = sigma_a;
    scalar(2) = sigma_r;
    scalar(3) = eps_a;
    scalar(4) = eps_r;
    scalar(5) = xa_new;
    scalar(6) = xr_new;
    scalar(7) = eq6_scaled;
    scalar(8) = eq7_scaled;
    scalar(9) = qA_total_W;
    scalar(10) = qR_total_W;
    scalar(11) = mechA_W;
    scalar(12) = mechR_W;
    tail = [pai_a, pai_r, rxi_a, rxi_r, xa_new - xa, xr_new - xr];
    y = [scalar, xA, xR, tail];
    last_t = t;
end

function p = material_parameters()
    p = struct();
    p.La = 1.0;
    p.Sa = 1.0e-6;
    p.Lr = 0.4;
    p.Sr = 0.2e-6;
    p.rho = 6500.0;
    p.E = 30.0e9;
    p.epsT = 0.03;
    p.latent = 1.0e4;
    p.CM = 7.3e6;
    p.CA = 7.6e6;
    p.SMA_As = 323.0;
    p.SMA_Af = 343.0;
    p.SMA_Ms = 313.0;
    p.SMA_Mf = 293.0;
    p.SE_As = 268.0;
    p.SE_Af = 288.0;
    p.SE_Ms = 258.0;
    p.SE_Mf = 238.0;
    p.rate_tau_s = 0.08;
end

function [sigma_a, sigma_r, eps_a, eps_r, eq6_scaled, eq7_scaled] = ...
        compatible_state(xa, xr, p)
    force_ratio = p.Sr / p.Sa;
    den = force_ratio * p.La / p.E + p.Lr / p.E;
    free_contraction = p.epsT * (1.0 - xa) * p.La;
    se_transform_extension = p.epsT * xr * p.Lr;
    sigma_r = (free_contraction - se_transform_extension) / max(den, eps);
    sigma_r = max(sigma_r, 0.0);
    sigma_a = force_ratio * sigma_r;
    eps_a = p.epsT * (1.0 - xa) - sigma_a / p.E;
    eps_r = p.epsT * xr + sigma_r / p.E;
    eq6_scaled = (sigma_a * p.Sa - sigma_r * p.Sr) / ...
        max(abs(sigma_r * p.Sr), 1.0e-9);
    eq7_scaled = (eps_a * p.La - eps_r * p.Lr) / ...
        max(abs(eps_r * p.Lr), 1.0e-9);
end

function [pai_a, pai_r, rxi_a, rxi_r] = phase_driving_rates( ...
        stage_id, Ta, Tr, sigma_a, sigma_r, xa, xr, p)
    rxi_a = 0.0;
    rxi_r = 0.0;

    Astart_a = p.SMA_As + sigma_a / p.CM;
    Afinish_a = p.SMA_Af + sigma_a / p.CM;
    Mstart_a = p.SMA_Ms + sigma_a / p.CA;
    Mfinish_a = p.SMA_Mf + sigma_a / p.CA;
    Astart_r = p.SE_As + sigma_r / p.CM;
    Afinish_r = p.SE_Af + sigma_r / p.CM;
    Mstart_r = p.SE_Ms + sigma_r / p.CA;
    Mfinish_r = p.SE_Mf + sigma_r / p.CA;

    heat_drive = normalized_interval(Ta, Astart_a, Afinish_a);
    cool_drive = normalized_interval(Mstart_a, Ta, Mstart_a - Mfinish_a);
    se_load_drive = normalized_interval(Tr, Mstart_r, Mfinish_r);
    se_unload_drive = normalized_interval(Astart_r, Tr, Afinish_r - Astart_r);

    pai_a = 0.0;
    pai_r = 0.0;
    if stage_id == 1
        pai_a = heat_drive;
        pai_r = se_load_drive;
        rxi_a = -min(max(heat_drive, 0.0), 1.5) * max(xa, 0.0) / p.rate_tau_s;
        rxi_r = min(max(se_load_drive, 0.0), 1.5) * max(1.0 - xr, 0.0) / p.rate_tau_s;
    elseif stage_id == 3
        pai_a = cool_drive;
        pai_r = se_unload_drive;
        rxi_a = min(max(cool_drive, 0.0), 1.5) * max(1.0 - xa, 0.0) / p.rate_tau_s;
        rxi_r = -min(max(se_unload_drive, 0.0), 1.5) * max(xr, 0.0) / p.rate_tau_s;
    end
end

function x = normalized_interval(value, start_value, width_value)
    width_value = max(abs(width_value), 1.0e-9);
    x = (value - start_value) / width_value;
end
