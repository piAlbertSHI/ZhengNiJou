function branches = Initialize_HeatDriveECC_EighthRound_Branches(options)
% Initialize independent 21-node finite-volume branch states.

    roles = Build_HeatDriveECC_EighthRound_BranchRoles(options);
    N = options.node_count;
    branches = struct();
    for idx = 1:numel(roles)
        key = matlab.lang.makeValidName(roles(idx).name);
        branches.(key) = struct();
        branches.(key).T_fluid_21 = roles(idx).boundary_T_K * ones(N, 1);
        branches.(key).T_fluid_51 = branches.(key).T_fluid_21;
        branches.(key).last_audit = inactive_branch_audit(roles(idx), options);
    end
end

function audit = inactive_branch_audit(role, options)
    N = options.node_count;
    audit = struct();
    audit.name = role.name;
    audit.m_dot_kgps = 0.0;
    audit.T_in_21 = NaN(N, 1);
    audit.T_out_21 = NaN(N, 1);
    audit.T_fluid_21 = NaN(N, 1);
    audit.Q_to_solid_21_W = zeros(N, 1);
    audit.Q_boundary_21_W = zeros(N, 1);
    audit.storage_21_W = zeros(N, 1);
    audit.T_in_51 = audit.T_in_21;
    audit.T_out_51 = audit.T_out_21;
    audit.T_fluid_51 = audit.T_fluid_21;
    audit.Q_to_solid_51_W = audit.Q_to_solid_21_W;
    audit.Q_boundary_51_W = audit.Q_boundary_21_W;
    audit.storage_51_W = audit.storage_21_W;
    audit.energy_residual_W = 0.0;
    audit.Q_to_solid_W = 0.0;
    audit.Q_boundary_W = 0.0;
    audit.storage_W = 0.0;
    audit.T_in_K = NaN;
    audit.T_out_K = NaN;
end
