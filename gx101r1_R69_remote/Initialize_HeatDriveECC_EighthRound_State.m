function state = Initialize_HeatDriveECC_EighthRound_State(options)
% Initialize the eighth-round 51+51 axial SMA/SE state.

    N = options.node_count;
    state = struct();
    state.time_s = 0.0;
    state.stage_id = 1;
    state.Ta_51 = options.system.T0_K * ones(N, 1);
    state.Tr_51 = options.system.Tc_K * ones(N, 1);
    state.xM_a_51 = ones(N, 1);
    state.xM_r_51 = zeros(N, 1);
    state.sigma_a_51 = zeros(N, 1);
    state.sigma_r_51 = zeros(N, 1);
    state.epsilon_a_51 = zeros(N, 1);
    state.epsilon_r_51 = zeros(N, 1);
    state.pai_a_51 = zeros(N, 1);
    state.pai_r_51 = zeros(N, 1);
    state.r_xi_a_51 = zeros(N, 1);
    state.r_xi_r_51 = zeros(N, 1);
    state.branch = Initialize_HeatDriveECC_EighthRound_Branches(options);
    state.energy = struct();
end
