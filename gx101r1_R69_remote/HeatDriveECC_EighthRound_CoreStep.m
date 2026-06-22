function [state, y, audit] = HeatDriveECC_EighthRound_CoreStep(state, options, t_s, dt_s)
% One physical eighth-round 21-node ECC step.

    [stage_id, cycle_index, stage_elapsed_s] = stage_from_time(t_s, options);
    state.stage_id = stage_id;

    roles = Build_HeatDriveECC_EighthRound_BranchRoles(options);
    branch_audits = initialize_branch_audits(state, roles, options);
    Q_sma = zeros(options.node_count, 1);
    Q_se = zeros(options.node_count, 1);

    role = roles([roles.active_stage] == stage_id);
    key = matlab.lang.makeValidName(role.name);
    if strcmp(role.solid, 'SMA')
        [state.branch.(key), branch_audits.(key)] = HeatDriveECC_AxialFVBranchStep51( ...
            state.branch.(key), role, state.Ta_21, dt_s, options, true);
        Q_sma = branch_audits.(key).Q_to_solid_21_W;
    else
        [state.branch.(key), branch_audits.(key)] = HeatDriveECC_AxialFVBranchStep51( ...
            state.branch.(key), role, state.Tr_21, dt_s, options, true);
        Q_se = branch_audits.(key).Q_to_solid_21_W;
    end

    [state, mech] = HeatDriveECC_ConstitutiveCompatibilityStep51( ...
        state, options, dt_s, stage_id);

    [Ta_next, solidA] = HeatDriveECC_AxialSolidThermalStep51( ...
        state.Ta_21, Q_sma, mech.latentA_W_21, mech.mechanicalA_W_21, ...
        options.material.SMA, options.geometry.L_a_m, options.geometry.S_a_m2, ...
        options.solid.k_sma_W_per_mK, dt_s, options);
    [Tr_next, solidR] = HeatDriveECC_AxialSolidThermalStep51( ...
        state.Tr_21, Q_se, mech.latentR_W_21, mech.mechanicalR_W_21, ...
        options.material.SE, options.geometry.L_r_m, options.geometry.S_r_m2, ...
        options.solid.k_se_W_per_mK, dt_s, options);
    state.Ta_21 = Ta_next;
    state.Tr_21 = Tr_next;
    state.Ta_51 = state.Ta_21;
    state.Tr_51 = state.Tr_21;
    state.time_s = t_s;

    audit = struct();
    audit.stage_id = stage_id;
    audit.cycle_index = cycle_index;
    audit.stage_elapsed_s = stage_elapsed_s;
    audit.branch = branch_audits;
    audit.mechanical = mech;
    audit.solidA = solidA;
    audit.solidR = solidR;
    audit.branch_storage_W = sum_branch_field(branch_audits, 'storage_W');
    audit.energy_residual_W = sum_branch_field(branch_audits, 'energy_residual_W') + ...
        solidA.energy_residual_W + solidR.energy_residual_W;

    y = HeatDriveECC_EighthRound_StateToOutput(state, audit, options);
end

function [stage_id, cycle_index, stage_elapsed_s] = stage_from_time(t_s, options)
    tau = options.schedule.tau_cycle_s;
    total_time = options.cycle_count * tau;
    t_eff = min(max(t_s, 0.0), max(total_time - 1.0e-12, 0.0));
    local_t = mod(t_eff, tau);
    cycle_index = min(floor(t_eff / tau) + 1, options.cycle_count);
    ends = options.schedule.stage_end_s(:).';
    stage_id = find(local_t <= ends + 1.0e-12, 1, 'first');
    if isempty(stage_id)
        stage_id = 4;
    end
    if stage_id == 1
        start_t = 0.0;
    else
        start_t = options.schedule.stage_end_s(stage_id - 1);
    end
    stage_elapsed_s = local_t - start_t;
end

function audits = initialize_branch_audits(state, roles, options)
    audits = struct();
    for idx = 1:numel(roles)
        key = matlab.lang.makeValidName(roles(idx).name);
        audits.(key) = inactive_audit(roles(idx), state.branch.(key), options);
    end
end

function audit = inactive_audit(role, branch_state, options)
    N = options.node_count;
    fluid = get_branch_vector(branch_state, 'T_fluid_21', 'T_fluid_51', N);
    audit = struct();
    audit.name = role.name;
    audit.m_dot_kgps = 0.0;
    audit.T_in_21 = fluid;
    audit.T_out_21 = fluid;
    audit.T_fluid_21 = fluid;
    audit.Q_advective_21_W = zeros(N, 1);
    audit.Q_inlet_boundary_W = 0.0;
    audit.Q_wall_boundary_21_W = zeros(N, 1);
    audit.Q_wall_boundary_W = 0.0;
    audit.Q_to_solid_21_W = zeros(N, 1);
    audit.Q_boundary_21_W = zeros(N, 1);
    audit.storage_21_W = zeros(N, 1);
    audit.T_in_51 = audit.T_in_21;
    audit.T_out_51 = audit.T_out_21;
    audit.T_fluid_51 = audit.T_fluid_21;
    audit.Q_advective_51_W = audit.Q_advective_21_W;
    audit.Q_wall_boundary_51_W = audit.Q_wall_boundary_21_W;
    audit.Q_to_solid_51_W = audit.Q_to_solid_21_W;
    audit.Q_boundary_51_W = audit.Q_boundary_21_W;
    audit.storage_51_W = audit.storage_21_W;
    audit.energy_residual_W = 0.0;
    audit.Q_to_solid_W = 0.0;
    audit.Q_boundary_W = 0.0;
    audit.storage_W = 0.0;
    audit.T_in_K = fluid(1);
    audit.T_out_K = fluid(end);
end

function value = sum_branch_field(branch_audits, field_name)
    value = 0.0;
    names = fieldnames(branch_audits);
    for idx = 1:numel(names)
        value = value + branch_audits.(names{idx}).(field_name);
    end
end

function values = get_branch_vector(branch_state, primary, legacy, N)
    if isfield(branch_state, primary)
        primary_values = branch_state.(primary);
        values = primary_values(:);
    elseif isfield(branch_state, legacy)
        legacy_values = branch_state.(legacy);
        values = legacy_values(:);
    else
        values = NaN(N, 1);
    end
    if numel(values) ~= N
        values = NaN(N, 1);
    end
end
