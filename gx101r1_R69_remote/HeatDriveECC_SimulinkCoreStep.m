function y = HeatDriveECC_SimulinkCoreStep(t)
%#codegen
% Fixed-size Simulink step for the 1D51 heat-driven ECC full cycle.

    N = 51;
    output_width = 773;
    y = zeros(output_width, 1);

    T0 = 308.0;
    Tc = 288.0;
    Th = 340.41206960385045;
    L_a = 1.0;
    L_r = 0.4;
    S_a = 1.0e-6;
    S_r = 0.2e-6;
    E_a = 30.0e9;
    E_r = 30.0e9;
    epsT_a = 0.03;
    epsT_r = 0.03;
    rho = 6500.0;
    ds0 = -36.0;
    CMa = 7.3e6;
    CAa = 7.6e6;
    CMr = 7.3e6;
    CAr = 7.6e6;
    TAs_a = 323.0;
    TMs_a = 313.0;
    TAs_r = 268.0;
    TMs_r = 258.0;
    qa = 10850.35098111811;
    qr = 11100.0;
    Qh = 44.232286657260751;
    Qa = Qh;
    Qr = 3.62;
    PECC = 3.62;
    etaECC = 0.040245472061657031;
    nu = 0.627165627165627;
    tau_cycle = 1.594475218377479;
    d1 = 0.394068805300478;
    d2 = 0.403168803888261;
    d3 = 0.394068805300478;
    d4 = 0.403168803888261;
    total_time = 3.0 * tau_cycle;
    h_sma = 9.0;
    h_se = 8.0;
    cond = 0.06;
    sigma_cap_r = 2.31081081081081e8;

    persistent initialized last_t T_a T_r xM_a xM_r
    if isempty(initialized) || t < last_t
        T_a = T0 * ones(N, 1);
        T_r = Tc * ones(N, 1);
        xM_a = ones(N, 1);
        xM_r = zeros(N, 1);
        last_t = t;
        initialized = true;
    end

    dt = t - last_t;
    if dt > 0.0
        [stage_id_update, ~, stage_elapsed_update] = stage_at_time(last_t, tau_cycle, d1, d2, d3, d4, total_time);
        [route, direction_a, direction_r, target_a, target_r] = route_and_targets(stage_id_update, N);

        [sigma_a, sigma_r, eps_a, eps_r, force_residual, disp_residual, eq6_scaled, eq7_scaled] = ...
            mechanical_coupling(xM_a, xM_r, stage_id_update, stage_elapsed_update, d1, d3, ...
            S_a, S_r, L_a, L_r, E_a, E_r, epsT_a, epsT_r, sigma_cap_r);
        sigma_drive_r = stress_profile(stage_id_update, stage_elapsed_update, d1, d3, sigma_cap_r);
        sigma_drive_a = (S_r / S_a) * sigma_drive_r;

        [Tbound_a, Tbound_r] = boundary_profiles(stage_id_update, stage_elapsed_update, d1, d2, d3, d4, N, T0, Tc, Th);
        [xM_a, pai_a, rxi_a, qlat_a] = update_phase(xM_a, T_a, sigma_drive_a, direction_a, target_a, ...
            dt, epsT_a, CMa, CAa, TMs_a, TAs_a, rho, ds0);
        [xM_r, pai_r, rxi_r, qlat_r] = update_phase(xM_r, T_r, sigma_drive_r, direction_r, target_r, ...
            dt, epsT_r, CMr, CAr, TMs_r, TAs_r, rho, ds0);

        T_a = update_temperature(T_a, Tbound_a, route(1) || route(2), dt, h_sma, cond, -1.5 .* rxi_a);
        T_r = update_temperature(T_r, Tbound_r, route(3) || route(4), dt, h_se, cond, 35.0 .* rxi_r);
        T_a = clamp_vec(T_a, 250.0, 380.0);
        T_r = clamp_vec(T_r, 250.0, 360.0);
        last_t = t;
    else
        [stage_id_update, ~, stage_elapsed_update] = stage_at_time(t, tau_cycle, d1, d2, d3, d4, total_time);
        [route, direction_a, direction_r, target_a, target_r] = route_and_targets(stage_id_update, N); %#ok<ASGLU>
        [sigma_a, sigma_r, eps_a, eps_r, force_residual, disp_residual, eq6_scaled, eq7_scaled] = ...
            mechanical_coupling(xM_a, xM_r, stage_id_update, stage_elapsed_update, d1, d3, ...
            S_a, S_r, L_a, L_r, E_a, E_r, epsT_a, epsT_r, sigma_cap_r);
        pai_a = zeros(N, 1);
        rxi_a = zeros(N, 1);
        qlat_a = zeros(N, 1);
        pai_r = zeros(N, 1);
        rxi_r = zeros(N, 1);
        qlat_r = zeros(N, 1);
    end

    [stage_id, cycle_index, stage_elapsed] = stage_at_time(t, tau_cycle, d1, d2, d3, d4, total_time);
    [route, ~, ~, ~, ~] = route_and_targets(stage_id, N);
    [Tbound_a, Tbound_r] = boundary_profiles(stage_id, stage_elapsed, d1, d2, d3, d4, N, T0, Tc, Th);
    [sigma_a, sigma_r, eps_a, eps_r, force_residual, disp_residual, eq6_scaled, eq7_scaled] = ...
        mechanical_coupling(xM_a, xM_r, stage_id, stage_elapsed, d1, d3, ...
        S_a, S_r, L_a, L_r, E_a, E_r, epsT_a, epsT_r, sigma_cap_r);

    Q_shex = route(1) * 5.0 * mean(Tbound_a - T_a);
    Q_the_sma = route(2) * 5.0 * mean(T_a - T0);
    Q_the_se = route(3) * 5.0 * mean(T_r - T0);
    Q_rhe = route(4) * 5.0 * mean(Tc - T_r);
    route_id = stage_id;

    y(1) = t;
    y(2) = cycle_index;
    y(3) = stage_id;
    y(4) = route_id;
    y(5) = stage_elapsed;
    y(6) = route(10);
    y(7) = route(11);
    y(8) = route(7);
    y(9) = route(8);
    y(10) = route(1);
    y(11) = route(2);
    y(12) = route(3);
    y(13) = route(4);
    y(14:17) = route(12:15);
    y(18) = sigma_a;
    y(19) = sigma_r;
    y(20) = mean(eps_a);
    y(21) = mean(eps_r);
    y(22) = force_residual;
    y(23) = disp_residual;
    y(24) = eq6_scaled;
    y(25) = eq7_scaled;
    y(26) = Q_shex;
    y(27) = Q_the_sma;
    y(28) = Q_the_se;
    y(29) = Q_rhe;
    y(30) = Qh;
    y(31) = Qa;
    y(32) = Qr;
    y(33) = PECC;
    y(34) = etaECC;
    y(35) = nu;
    y(36) = Th;
    y(37) = T0;
    y(38) = Tc;
    y(39) = mean(xM_a);
    y(40) = mean(xM_r);
    y(41) = mean(T_a);
    y(42) = mean(T_r);
    y(43) = min(T_a);
    y(44) = max(T_a);
    y(45) = min(T_r);
    y(46) = max(T_r);
    y(47) = route(9);
    y(48) = htf_in_sma(stage_id, T0, Th);
    y(49) = mean(T_a);
    y(50) = mean(Tbound_a);
    y(51) = htf_in_se(stage_id, T0, Tc);
    y(52) = mean(T_r);
    y(53) = mean(Tbound_r);
    y(54) = Th + 5.0;
    y(55) = Th;
    y(56) = T0;
    y(57) = T0;
    y(58) = Tc;
    y(59) = Tc - max(Q_rhe, 0.0) / 100.0;

    idx = 60;
    y(idx:idx+N-1) = T_a; idx = idx + N;
    y(idx:idx+N-1) = xM_a; idx = idx + N;
    y(idx:idx+N-1) = sigma_a .* ones(N, 1); idx = idx + N;
    y(idx:idx+N-1) = eps_a; idx = idx + N;
    y(idx:idx+N-1) = pai_a; idx = idx + N;
    y(idx:idx+N-1) = rxi_a; idx = idx + N;
    y(idx:idx+N-1) = qlat_a; idx = idx + N;
    y(idx:idx+N-1) = T_r; idx = idx + N;
    y(idx:idx+N-1) = xM_r; idx = idx + N;
    y(idx:idx+N-1) = sigma_r .* ones(N, 1); idx = idx + N;
    y(idx:idx+N-1) = eps_r; idx = idx + N;
    y(idx:idx+N-1) = pai_r; idx = idx + N;
    y(idx:idx+N-1) = rxi_r; idx = idx + N;
    y(idx:idx+N-1) = qlat_r;
end

function [stage_id, cycle_index, stage_elapsed] = stage_at_time(t, tau, d1, d2, d3, d4, total_time)
    tt = min(max(t, 0.0), max(total_time - 1.0e-12, 0.0));
    cycle_index = floor(tt / tau) + 1.0;
    ct = tt - floor(tt / tau) * tau;
    if ct < d1
        stage_id = 1.0;
        stage_elapsed = ct;
    elseif ct < d1 + d2
        stage_id = 2.0;
        stage_elapsed = ct - d1;
    elseif ct < d1 + d2 + d3
        stage_id = 3.0;
        stage_elapsed = ct - d1 - d2;
    else
        stage_id = 4.0;
        stage_elapsed = ct - d1 - d2 - d3;
    end
    d4 = d4 + 0.0; %#ok<NASGU>
end

function [route, dir_a, dir_r, target_a, target_r] = route_and_targets(stage_id, N)
    route = zeros(15, 1);
    dir_a = 0.0;
    dir_r = 0.0;
    target_a = ones(N, 1);
    target_r = zeros(N, 1);
    if stage_id == 1.0
        route(1) = 1.0; route(7) = 1.0; route(9) = 1.0; route(10) = 1.0;
        route(12) = 1.0;
        dir_a = -1.0; dir_r = 1.0;
        target_a = 0.445945945945946 .* ones(N, 1);
        target_r = ones(N, 1);
    elseif stage_id == 2.0
        route(1) = 1.0; route(3) = 1.0; route(7) = 1.0; route(8) = 1.0;
        route(10) = 1.0; route(11) = 1.0; route(12) = 1.0; route(14) = 1.0;
        target_a = 0.445945945945946 .* ones(N, 1);
        target_r = ones(N, 1);
    elseif stage_id == 3.0
        route(2) = 1.0; route(7) = 1.0; route(9) = 1.0; route(10) = 2.0;
        route(13) = 1.0;
        dir_a = 1.0; dir_r = -1.0;
        target_a = ones(N, 1);
        target_r = zeros(N, 1);
    else
        route(4) = 1.0; route(8) = 1.0; route(11) = 2.0; route(15) = 1.0;
        target_a = ones(N, 1);
        target_r = zeros(N, 1);
    end
end

function [sigma_a, sigma_r, eps_a, eps_r, force_residual, disp_residual, eq6_scaled, eq7_scaled] = ...
        mechanical_coupling(xM_a, xM_r, stage_id, stage_elapsed, d1, d3, ...
        S_a, S_r, L_a, L_r, E_a, E_r, epsT_a, epsT_r, sigma_cap_r)
    sigma_req = compatible_stress(xM_a, xM_r, S_a, S_r, L_a, L_r, E_a, E_r, epsT_a, epsT_r);
    if stage_id == 1.0 || stage_id == 3.0
        sigma_r = min(max(sigma_req, 0.0), sigma_cap_r);
    elseif stage_id == 2.0
        sigma_r = min(max(sigma_req, 0.0), sigma_cap_r);
    else
        sigma_r = 0.0;
    end
    sigma_a = (S_r / S_a) * sigma_r;
    eps_a = epsT_a .* (1.0 - xM_a) - sigma_a ./ E_a;
    eps_r = epsT_r .* xM_r + sigma_r ./ E_r;
    force_residual = sigma_a * S_a - sigma_r * S_r;
    disp_residual = mean(eps_a) * L_a - mean(eps_r) * L_r;
    eq6_scaled = force_residual / max(abs(sigma_r * S_r), 1.0);
    if stage_id == 1.0 || stage_id == 3.0
        eq7_scaled = disp_residual / max(abs(mean(eps_r) * L_r), 1.0e-12);
    else
        eq7_scaled = 0.0;
    end
end

function sigma_r_req = compatible_stress(xM_a, xM_r, S_a, S_r, L_a, L_r, E_a, E_r, epsT_a, epsT_r)
    xa = mean(xM_a);
    xr = mean(xM_r);
    denom = (S_r / S_a) * L_a / E_a + L_r / E_r;
    sigma_r_req = (epsT_a * (1.0 - xa) * L_a - epsT_r * xr * L_r) / max(denom, eps);
end

function sigma_r = stress_profile(stage_id, stage_elapsed, d1, d3, sigma_cap_r)
    if stage_id == 1.0
        sigma_r = sigma_cap_r * min(max(stage_elapsed / max(d1, eps), 0.0), 1.0);
    elseif stage_id == 2.0
        sigma_r = sigma_cap_r;
    elseif stage_id == 3.0
        sigma_r = sigma_cap_r * max(1.0 - min(max(stage_elapsed / max(d3, eps), 0.0), 1.0), 0.0);
    else
        sigma_r = 0.0;
    end
end

function [Tba, Tbr] = boundary_profiles(stage_id, stage_elapsed, d1, d2, d3, d4, N, T0, Tc, Th)
    x = linspace(0.0, 1.0, N).';
    if stage_id == 1.0
        Tba = (Th + 3.0) - 2.0 .* x;
        Tbr = Tc .* ones(N, 1);
    elseif stage_id == 2.0
        Tba = Th .* ones(N, 1);
        Tbr = T0 .* ones(N, 1);
    elseif stage_id == 3.0
        Tba = T0 + 1.0 .* x;
        Tbr = T0 .* ones(N, 1);
    else
        Tba = T0 .* ones(N, 1);
        Tbr = Tc .* ones(N, 1);
    end
    stage_elapsed = stage_elapsed + d1 + d2 + d3 + d4; %#ok<NASGU>
end

function [xM, pai, rxi, qlat] = update_phase(xM, T, sigma, direction, target, dt, epsT, CM, CA, TMs, TAs, rho, ds0)
    N = numel(xM);
    pai = zeros(N, 1);
    rxi = zeros(N, 1);
    qlat = zeros(N, 1);
    if abs(direction) < 0.5 || dt <= 0.0
        return;
    end
    X0 = 1.0e5;
    H = 1.0e5;
    threshold = 1.0e5;
    rate_coeff = 15.0;
    rate_limit = 25.0;
    if direction > 0.0
        if TAs < 300.0
            pai = sigma - 0.2 .* CM .* (T - TMs) - X0 - H .* xM;
        else
            pai = CM .* (TMs - T) + 0.02 .* sigma - X0 - H .* xM;
        end
        drive = max(pai - threshold, 0.0);
        rxi = rate_coeff .* drive ./ threshold;
        rxi = min(rxi, rate_limit);
        rxi = min(rxi, max((target - xM) ./ dt, 0.0));
    else
        pai = -CA .* (T - TAs) - 0.02 .* sigma + X0 + H .* xM;
        drive = max(-pai - threshold, 0.0);
        rxi = -rate_coeff .* drive ./ threshold;
        rxi = max(rxi, -rate_limit);
        rxi = max(rxi, min((target - xM) ./ dt, 0.0));
    end
    xM = clamp_vec(xM + dt .* rxi, 0.0, 1.0);
    qlat = -T .* rho .* ds0 .* rxi;
    epsT = epsT + 0.0; %#ok<NASGU>
end

function T = update_temperature(T, boundary, exchange_active, dt, h, cond, phase_term)
    if exchange_active
        T = T + dt .* h .* (boundary - T);
    end
    T = T + dt .* phase_term;
    T_old = T;
    if numel(T) > 2
        T(2:end-1) = T_old(2:end-1) + dt .* cond .* ...
            (T_old(1:end-2) - 2.0 .* T_old(2:end-1) + T_old(3:end));
        T(1) = T_old(1) + dt .* cond .* (T_old(2) - T_old(1));
        T(end) = T_old(end) + dt .* cond .* (T_old(end-1) - T_old(end));
    end
end

function y = clamp_vec(x, lo, hi)
    y = min(max(x, lo), hi);
end

function value = htf_in_sma(stage_id, T0, Th)
    if stage_id == 1.0 || stage_id == 2.0
        value = Th + 5.0;
    elseif stage_id == 3.0
        value = T0;
    else
        value = T0;
    end
end

function value = htf_in_se(stage_id, T0, Tc)
    if stage_id == 2.0
        value = T0;
    elseif stage_id == 4.0
        value = Tc;
    else
        value = Tc;
    end
end
