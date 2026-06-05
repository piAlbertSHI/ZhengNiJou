function state = Initialize_PerovskiteECC_State(options)
% Initialize 51-node SMA/SE axial ECC state.

    if nargin < 1 || isempty(options)
        options = Build_PerovskiteECC_Default_Options();
    end

    N = options.node_count;
    require_node_count(N);

    state = struct();
    state.schema_version = 'perovskite_ecc_state51_v1';
    state.model_family = options.model_family;
    state.stage_name = 'initial_R1_A1';
    state.cycle_index = 0;
    state.time_s = 0.0;
    state.coupling = struct();
    state.energy = struct();

    state.SMA = init_partition('SMA', N, options.geometry.L_a_m, ...
        options.system.T0_K, ones(N, 1));
    state.SE = init_partition('SE', N, options.geometry.L_r_m, ...
        options.system.T_c_K, zeros(N, 1));

    state.controls = struct( ...
        'pump_signal', 0.0, ...
        'valve_hot_signal', 0.0, ...
        'valve_cold_signal', 1.0, ...
        'valve_regenerator_signal', 0.0);
end

function part = init_partition(name, N, length_m, T_K, xM_51)
    part = struct();
    part.name = name;
    part.node_count = N;
    part.x_m_51 = linspace(0.0, length_m, N).';
    part.T_51 = T_K * ones(N, 1);
    part.sigma_Pa_51 = zeros(N, 1);
    part.epsilon_51 = zeros(N, 1);
    part.xM_51 = min(max(xM_51(:), 0.0), 1.0);
    part.delta_xM_51 = zeros(N, 1);
    part.pai_Pa_51 = zeros(N, 1);
    part.r_xi_1_per_s_51 = zeros(N, 1);
    part.q_latent_W_per_m3_51 = zeros(N, 1);
end

function require_node_count(N)
    if N ~= 51
        error('Initialize_PerovskiteECC_State:InvalidNodeCount', ...
            'Second-round paper ECC model requires 51 SMA nodes and 51 SE nodes.');
    end
end

