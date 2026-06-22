function state = Initialize_HeatDriveECC_EighthRound_State(options)
% Initialize the eighth-round 21+21 axial SMA/SE state.

    N = options.node_count;
    state = struct();
    state.time_s = 0.0;
    state.stage_id = 1;
    state.Ta_21 = options.system.T0_K * ones(N, 1);
    state.Tr_21 = options.system.Tc_K * ones(N, 1);
    state.xM_a_21 = ones(N, 1);
    state.xM_r_21 = zeros(N, 1);
    state.sigma_a_21 = zeros(N, 1);
    state.sigma_r_21 = zeros(N, 1);
    state.epsilon_a_21 = zeros(N, 1);
    state.epsilon_r_21 = zeros(N, 1);
    state.pai_a_21 = zeros(N, 1);
    state.pai_r_21 = zeros(N, 1);
    state.r_xi_a_21 = zeros(N, 1);
    state.r_xi_r_21 = zeros(N, 1);
    state = sync_legacy_51_aliases(state);
    state.branch = Initialize_HeatDriveECC_EighthRound_Branches(options);
    state.energy = struct();
end

function state = sync_legacy_51_aliases(state)
    state.Ta_51 = state.Ta_21;
    state.Tr_51 = state.Tr_21;
    state.xM_a_51 = state.xM_a_21;
    state.xM_r_51 = state.xM_r_21;
    state.sigma_a_51 = state.sigma_a_21;
    state.sigma_r_51 = state.sigma_r_21;
    state.epsilon_a_51 = state.epsilon_a_21;
    state.epsilon_r_51 = state.epsilon_r_21;
    state.pai_a_51 = state.pai_a_21;
    state.pai_r_51 = state.pai_r_21;
    state.r_xi_a_51 = state.r_xi_a_21;
    state.r_xi_r_51 = state.r_xi_r_21;
end
