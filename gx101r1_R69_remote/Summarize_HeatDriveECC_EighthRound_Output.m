function summary = Summarize_HeatDriveECC_EighthRound_Output(Y, options)
% Recompute eighth-round physical metrics from raw output matrix.

    map = options.output;
    t = Y(:, map.time_s);
    stage = round(Y(:, map.stage_id));
    cycle = round(Y(:, map.cycle_index));
    ncycles = max(cycle);
    dt = [0; diff(t)];
    dt(dt < 0) = 0;
    eta_hr = options.system.eta_hr;
    mr = options.equilibrium.m_r_kg;
    cp_r = options.material.SE.cp_J_per_kgK;
    cold_lift_J = mr * cp_r * max(options.system.T0_K - options.system.Tc_K, 0.0);

    summary = struct();
    summary.samples = size(Y, 1);
    summary.stage_sample_min = min_stage_samples(stage, cycle);
    summary.max_Ta_spread_K = max(Y(:, map.Ta_max_K) - Y(:, map.Ta_min_K));
    summary.max_Tr_spread_K = max(Y(:, map.Tr_max_K) - Y(:, map.Tr_min_K));
    summary.max_abs_eq6_scaled = max(abs(Y(:, map.eq6_scaled)));
    summary.max_abs_eq7_scaled = max(abs(Y(:, map.eq7_scaled)));
    summary.max_sigma_r_Pa = max(Y(:, map.sigma_r_Pa));
    summary.max_Ta_mean_K = max(Y(:, map.Ta_mean_K));
    summary.max_xM_a_delta = max(Y(:, map.xM_a_mean)) - min(Y(:, map.xM_a_mean));
    summary.max_xM_r_delta = max(Y(:, map.xM_r_mean)) - min(Y(:, map.xM_r_mean));
    summary.cycle = repmat(empty_cycle(), ncycles, 1);
    for c = 1:ncycles
        idx = cycle == c;
        idx1 = idx & stage == 1;
        idx2 = idx & stage == 2;
        idx3 = idx & stage == 3;
        idx4 = idx & stage == 4;
        idx34 = idx3 | idx4;
        summary.cycle(c).cycle_index = c;
        summary.cycle(c).Qh_raw_loop_J = integrate_power(Y(:, map.Q_shex_boundary_W), dt, idx1);
        summary.cycle(c).Qr_raw_loop_J = integrate_power(Y(:, map.Q_chex_boundary_W), dt, idx4);
        summary.cycle(c).Qh_boundary_J = summary.cycle(c).Qh_raw_loop_J;
        summary.cycle(c).Qr_boundary_J = summary.cycle(c).Qr_raw_loop_J;
        summary.cycle(c).Qh_article_formula_J = ...
            (1.0 - eta_hr) * integrate_power(max(Y(:, map.SMA_sensible_W), 0.0), dt, idx1) + ...
            integrate_power(max(Y(:, map.latentA_W), 0.0), dt, idx1) + ...
            integrate_power(max(-Y(:, map.mechanicalR_W), 0.0), dt, idx1);
        summary.cycle(c).Qr_article_formula_J = ...
            integrate_power(max(Y(:, map.latentR_W) + Y(:, map.mechanicalR_W), 0.0), dt, idx34) - ...
            (1.0 - eta_hr) * cold_lift_J;
        summary.cycle(c).Qr_article_formula_J = max(summary.cycle(c).Qr_article_formula_J, 0.0);
        summary.cycle(c).Qh_formula_minus_raw_J = ...
            summary.cycle(c).Qh_article_formula_J - summary.cycle(c).Qh_raw_loop_J;
        summary.cycle(c).Qr_formula_minus_raw_J = ...
            summary.cycle(c).Qr_article_formula_J - summary.cycle(c).Qr_raw_loop_J;
        summary.cycle(c).THE_reject_J = -integrate_power( ...
            Y(:, map.Q_the_sma_boundary_W) + Y(:, map.Q_the_se_boundary_W), dt, idx2 | idx3);
        summary.cycle(c).SMA_sensible_J = integrate_power(Y(:, map.SMA_sensible_W), dt, idx);
        summary.cycle(c).SE_sensible_J = integrate_power(Y(:, map.SE_sensible_W), dt, idx);
        summary.cycle(c).latentA_J = integrate_power(Y(:, map.latentA_W), dt, idx);
        summary.cycle(c).latentR_J = integrate_power(Y(:, map.latentR_W), dt, idx);
        summary.cycle(c).mechanicalA_J = integrate_power(Y(:, map.mechanicalA_W), dt, idx);
        summary.cycle(c).mechanicalR_J = integrate_power(Y(:, map.mechanicalR_W), dt, idx);
        summary.cycle(c).branch_storage_J = integrate_power(Y(:, map.branch_storage_W), dt, idx);
        summary.cycle(c).energy_residual_J = integrate_power(Y(:, map.energy_residual_W), dt, idx);
        summary.cycle(c).max_Ta_spread_K = max(Y(idx, map.Ta_max_K) - Y(idx, map.Ta_min_K));
        summary.cycle(c).max_Tr_spread_K = max(Y(idx, map.Tr_max_K) - Y(idx, map.Tr_min_K));
        summary.cycle(c).xM_a_min = min(Y(idx, map.xM_a_mean));
        summary.cycle(c).xM_a_max = max(Y(idx, map.xM_a_mean));
        summary.cycle(c).xM_r_min = min(Y(idx, map.xM_r_mean));
        summary.cycle(c).xM_r_max = max(Y(idx, map.xM_r_mean));
        summary.cycle(c).sigma_r_max_Pa = max(Y(idx, map.sigma_r_Pa));
        summary.cycle(c).sigma_r_load_Pa = max(Y(idx & (stage == 1 | stage == 2), map.sigma_r_Pa));
        denom = abs(summary.cycle(c).Qh_boundary_J) + ...
            abs(summary.cycle(c).Qr_boundary_J) + ...
            abs(summary.cycle(c).THE_reject_J) + 1.0e-9;
        summary.cycle(c).energy_residual_fraction = ...
            abs(summary.cycle(c).energy_residual_J) / denom;
    end
    last = summary.cycle(end);
    summary.last_Qh_cycle_J = last.Qh_boundary_J;
    summary.last_Qr_cycle_J = last.Qr_boundary_J;
    summary.last_Qr_over_Qh = last.Qr_boundary_J / max(last.Qh_boundary_J, eps);
    summary.last_delta_xM_a = last.xM_a_max - last.xM_a_min;
    summary.last_delta_xM_r = last.xM_r_max - last.xM_r_min;
    summary.last_sigma_r_max_Pa = last.sigma_r_max_Pa;
    summary.last_sigma_r_load_Pa = last.sigma_r_load_Pa;
    summary.article_Qh_cycle_J = options.system.article_Qh_cycle_J;
    summary.article_Qr_cycle_J = options.system.article_Qr_cycle_J;
    summary.article_Qr_over_Qh = options.system.article_Qr_over_Qh;
    summary.article_delta_xM_a = options.equilibrium.delta_xM_a;
    summary.article_delta_xM_r = options.equilibrium.delta_xM_r;
    summary.article_sigma_r_Pa = options.equilibrium.sigma_r_Pa;
    summary.article_Th_K = options.equilibrium.T_h_K;
    summary.err_Qh_rel = relerr(summary.last_Qh_cycle_J, summary.article_Qh_cycle_J);
    summary.err_Qr_rel = relerr(summary.last_Qr_cycle_J, summary.article_Qr_cycle_J);
    summary.err_QrQh_rel = relerr(summary.last_Qr_over_Qh, summary.article_Qr_over_Qh);
    summary.err_delta_xM_a_rel = relerr(summary.last_delta_xM_a, summary.article_delta_xM_a);
    summary.err_delta_xM_r_rel = relerr(summary.last_delta_xM_r, summary.article_delta_xM_r);
    summary.err_sigma_r_rel = relerr(summary.last_sigma_r_load_Pa, summary.article_sigma_r_Pa);
    summary.err_Th_abs_K = abs(summary.max_Ta_mean_K - summary.article_Th_K);
    summary.all_finite = all(isfinite(Y(:)));
end

function value = integrate_power(x, dt, idx)
    if ~any(idx)
        value = 0.0;
        return;
    end
    value = sum(x(idx) .* dt(idx));
end

function n = min_stage_samples(stage, cycle)
    keys = unique([cycle(:), stage(:)], 'rows');
    counts = zeros(size(keys, 1), 1);
    for idx = 1:size(keys, 1)
        counts(idx) = nnz(cycle == keys(idx, 1) & stage == keys(idx, 2));
    end
    n = min(counts);
end

function c = empty_cycle()
    c = struct('cycle_index', 0, 'Qh_boundary_J', NaN, 'Qr_boundary_J', NaN, ...
        'Qh_raw_loop_J', NaN, 'Qr_raw_loop_J', NaN, ...
        'Qh_article_formula_J', NaN, 'Qr_article_formula_J', NaN, ...
        'Qh_formula_minus_raw_J', NaN, 'Qr_formula_minus_raw_J', NaN, ...
        'THE_reject_J', NaN, 'SMA_sensible_J', NaN, 'SE_sensible_J', NaN, ...
        'latentA_J', NaN, 'latentR_J', NaN, ...
        'mechanicalA_J', NaN, 'mechanicalR_J', NaN, ...
        'branch_storage_J', NaN, 'energy_residual_J', NaN, ...
        'energy_residual_fraction', NaN, 'max_Ta_spread_K', NaN, ...
        'max_Tr_spread_K', NaN, 'xM_a_min', NaN, 'xM_a_max', NaN, ...
        'xM_r_min', NaN, 'xM_r_max', NaN, 'sigma_r_max_Pa', NaN, ...
        'sigma_r_load_Pa', NaN);
end

function e = relerr(value, target)
    e = abs(value - target) / max(abs(target), eps);
end
