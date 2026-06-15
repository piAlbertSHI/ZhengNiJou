function y = HeatDriveECC_EighthRound_StateToOutput(state, audit, options)
% Pack eighth-round state/audit into a fixed-width numeric output vector.

    map = options.output;
    N = options.node_count;
    y = zeros(1, map.output_width);
    put('time_s', state.time_s);
    put('cycle_index', audit.cycle_index);
    put('stage_id', audit.stage_id);
    put('stage_elapsed_s', audit.stage_elapsed_s);
    put('Ta_mean_K', mean(state.Ta_51));
    put('Ta_min_K', min(state.Ta_51));
    put('Ta_max_K', max(state.Ta_51));
    put('Tr_mean_K', mean(state.Tr_51));
    put('Tr_min_K', min(state.Tr_51));
    put('Tr_max_K', max(state.Tr_51));
    put('xM_a_mean', mean(state.xM_a_51));
    put('xM_r_mean', mean(state.xM_r_51));
    put('sigma_a_Pa', audit.mechanical.sigma_a_Pa);
    put('sigma_r_Pa', audit.mechanical.sigma_r_Pa);
    put('epsilon_a_mean', audit.mechanical.epsilon_a_mean);
    put('epsilon_r_mean', audit.mechanical.epsilon_r_mean);
    put('eq6_scaled', audit.mechanical.eq6_scaled);
    put('eq7_scaled', audit.mechanical.eq7_scaled);

    branch_names = {'SMA_SHEX','SMA_THE','SE_THE','SE_CHEX'};
    q_fields = {'Q_sma_shex_W','Q_sma_the_W','Q_se_the_W','Q_se_chex_W'};
    qb_fields = {'Q_shex_boundary_W','Q_the_sma_boundary_W', ...
        'Q_the_se_boundary_W','Q_chex_boundary_W'};
    mdot_fields = {'SMA_SHEX_mdot','SMA_THE_mdot','SE_THE_mdot','SE_CHEX_mdot'};
    tin_fields = {'SMA_SHEX_Tin_K','SMA_THE_Tin_K','SE_THE_Tin_K','SE_CHEX_Tin_K'};
    tout_fields = {'SMA_SHEX_Tout_K','SMA_THE_Tout_K','SE_THE_Tout_K','SE_CHEX_Tout_K'};
    for idx = 1:numel(branch_names)
        key = branch_names{idx};
        b = audit.branch.(key);
        put(q_fields{idx}, b.Q_to_solid_W);
        put(qb_fields{idx}, b.Q_boundary_W);
        put(mdot_fields{idx}, b.m_dot_kgps);
        put(tin_fields{idx}, b.T_in_K);
        put(tout_fields{idx}, b.T_out_K);
    end
    put('latentA_W', audit.mechanical.latentA_W);
    put('latentR_W', audit.mechanical.latentR_W);
    put('mechanicalA_W', audit.mechanical.mechanicalA_W);
    put('mechanicalR_W', audit.mechanical.mechanicalR_W);
    put('SMA_sensible_W', audit.solidA.sensible_W);
    put('SE_sensible_W', audit.solidR.sensible_W);
    put('branch_storage_W', audit.branch_storage_W);
    put('energy_residual_W', audit.energy_residual_W);

    put_array('Ta_51', state.Ta_51);
    put_array('Tr_51', state.Tr_51);
    put_array('xM_a_51', state.xM_a_51);
    put_array('xM_r_51', state.xM_r_51);
    put_array('sigma_a_51', state.sigma_a_51);
    put_array('sigma_r_51', state.sigma_r_51);
    put_array('epsilon_a_51', state.epsilon_a_51);
    put_array('epsilon_r_51', state.epsilon_r_51);
    put_array('pai_a_51', state.pai_a_51);
    put_array('pai_r_51', state.pai_r_51);
    put_array('r_xi_a_51', state.r_xi_a_51);
    put_array('r_xi_r_51', state.r_xi_r_51);
    for idx = 1:numel(branch_names)
        key = branch_names{idx};
        b = audit.branch.(key);
        put_array([key '_Tin_51'], fill_nan(b.T_in_51, N));
        put_array([key '_Tout_51'], fill_nan(b.T_out_51, N));
        put_array([key '_Tfluid_51'], fill_nan(b.T_fluid_51, N));
        put_array([key '_Q_51'], b.Q_to_solid_51_W);
    end

    function put(name, value)
        y(map.(name)) = value;
    end
    function put_array(name, values)
        y(map.(name)) = reshape(values, 1, []);
    end
end

function values = fill_nan(values, N)
    values = values(:);
    if numel(values) ~= N
        values = NaN(N, 1);
    end
end
