function y = HeatDriveECC_FifthRound_MechanicalStep(u)
% Simulink-step mechanical/constitutive kernel for the fifth-round model.
% Fluid transport, pumps, valves, pipes, and heat exchangers remain Simscape.

    Ta_51 = u(1:51);
    Tr_51 = u(52:102);
    stage_id = round(u(103));
    t = u(104);

    persistent xM_a xM_r last_t
    if isempty(last_t) || t < last_t
        xM_a = ones(51, 1);
        xM_r = zeros(51, 1);
        last_t = t;
    end
    dt = max(t - last_t, 0.0);

    Sa = 1.0e-6;
    Sr = 0.2e-6;
    La = 1.0;
    Lr = 0.4;
    E_a = 30.0e9;
    E_r = 30.0e9;
    epsT_a = 0.03;
    epsT_r = 0.03;
    rho = 6500.0;
    dh = 1.0e4;
    tau_phase = 0.08;

    xa = mean(xM_a);
    xr = mean(xM_r);
    denominator = (Sr / Sa) * La / E_a + Lr / E_r;
    sigma_r = (epsT_a * (1.0 - xa) * La - epsT_r * xr * Lr) / denominator;
    sigma_a = (Sr / Sa) * sigma_r;

    eq_a = xa;
    eq_r = xr;
    if stage_id == 1
        eq_a = clamp((343.0 + sigma_a / 7.6e6 - mean(Ta_51)) / 20.0, 0.0, 1.0);
        eq_r = clamp((sigma_r - 7.3e6 * (mean(Tr_51) - 258.0)) / ...
            (7.3e6 * 20.0), 0.0, 1.0);
    elseif stage_id == 3
        eq_a = clamp((313.0 + sigma_a / 7.3e6 - mean(Ta_51)) / 20.0, 0.0, 1.0);
        eq_r = clamp((sigma_r - 7.6e6 * (mean(Tr_51) - 268.0)) / ...
            (7.6e6 * 20.0), 0.0, 1.0);
    end

    dx_a = zeros(51, 1);
    dx_r = zeros(51, 1);
    if dt > 0.0 && (stage_id == 1 || stage_id == 3)
        dx_a = clamp_vec((eq_a - xM_a) / tau_phase, -20.0, 20.0);
        dx_r = clamp_vec((eq_r - xM_r) / tau_phase, -20.0, 20.0);
        if stage_id == 1
            dx_a = min(dx_a, 0.0);
            dx_r = max(dx_r, 0.0);
        else
            dx_a = max(dx_a, 0.0);
            dx_r = min(dx_r, 0.0);
        end
        xM_a = clamp_vec(xM_a + dt .* dx_a, 0.0, 1.0);
        xM_r = clamp_vec(xM_r + dt .* dx_r, 0.0, 1.0);
    end

    m_a = rho * Sa * La;
    m_r = rho * Sr * Lr;
    xa = mean(xM_a);
    xr = mean(xM_r);
    sigma_r = (epsT_a * (1.0 - xa) * La - epsT_r * xr * Lr) / denominator;
    sigma_a = (Sr / Sa) * sigma_r;
    mech_a_W = sigma_a * Sa * La * (-epsT_a * mean(dx_a));
    mech_r_W = sigma_r * Sr * Lr * (epsT_r * mean(dx_r));
    q_a = (m_a / 51.0) * dh .* dx_a + mech_a_W / 51.0;
    q_r = (m_r / 51.0) * dh .* dx_r + mech_r_W / 51.0;

    epsilon_a = epsT_a * (1.0 - mean(xM_a)) - sigma_a / E_a;
    epsilon_r = epsT_r * mean(xM_r) + sigma_r / E_r;
    eq6_scaled = (sigma_a * Sa - sigma_r * Sr) / max(abs(sigma_r * Sr), 1.0);
    eq7_scaled = (epsilon_a * La - epsilon_r * Lr) / ...
        max(abs(epsilon_r * Lr), 1.0e-12);
    audit = [sigma_a; sigma_r; epsilon_a; epsilon_r; mean(xM_a); ...
        mean(xM_r); eq6_scaled; eq7_scaled; sum(q_a); sum(q_r); ...
        mech_a_W; mech_r_W];
    y = [q_a; q_r; audit];
    last_t = t;
end

function value = clamp(value, lower, upper)
    value = min(max(value, lower), upper);
end

function value = clamp_vec(value, lower, upper)
    value = min(max(value, lower), upper);
end
