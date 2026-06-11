function [branch_state, audit] = HeatDriveECC_FiniteVolumeBranchStep( ...
        branch_state, role, solid_T_K, dt_s, options, active)
% Finite-volume branch step with boundary reheating/recooling and NTU outlet.

    if nargin < 6
        active = true;
    end
    cp = options.system.cp_fluid_J_per_kgK;
    m = options.branch.fluid_mass_kg;
    mdot = options.branch.m_dot_kg_per_s;
    UA = options.branch.UA_W_per_K;
    if isfield(options.branch, 'boundary_UA_W_per_K')
        boundary_UA = options.branch.boundary_UA_W_per_K;
    else
        boundary_UA = UA;
    end
    if ~active
        audit = inactive_audit(branch_state, role);
        return;
    end

    T_before = branch_state.T_fluid_K;
    Q_boundary_W = boundary_UA * (role.boundary_T_K - branch_state.T_fluid_K);
    branch_state.T_fluid_K = branch_state.T_fluid_K + ...
        Q_boundary_W * dt_s / max(m * cp, eps);

    T_in_K = branch_state.T_fluid_K;
    ntu = UA / max(abs(mdot) * cp, eps);
    T_out_K = solid_T_K + (T_in_K - solid_T_K) * exp(-ntu);
    Q_to_solid_W = mdot * cp * (T_in_K - T_out_K);

    branch_state.T_fluid_K = branch_state.T_fluid_K + ...
        mdot * dt_s / max(m, eps) * (T_out_K - branch_state.T_fluid_K);

    T_after = branch_state.T_fluid_K;
    storage_delta_W = (T_after - T_before) * m * cp / max(dt_s, eps);
    residual_W = Q_boundary_W - Q_to_solid_W - storage_delta_W;

    audit = struct();
    audit.branch = string(role.name);
    audit.m_dot_kgps = mdot;
    audit.T_boundary_K = role.boundary_T_K;
    audit.T_in_K = T_in_K;
    audit.T_out_K = T_out_K;
    audit.T_fluid_K = branch_state.T_fluid_K;
    audit.Q_boundary_W = Q_boundary_W;
    audit.Q_to_solid_W = Q_to_solid_W;
    audit.storage_delta_W = storage_delta_W;
    audit.energy_residual_W = residual_W;
end

function branch_state = initialize_branch_state(role, options)
% Initialize branch internal fluid state at its physical boundary.
    branch_state = struct();
    branch_state.name = role.name;
    branch_state.T_fluid_K = role.boundary_T_K;
    branch_state.fluid_mass_kg = options.branch.fluid_mass_kg;
end

function E = branch_storage_J(branch_state, options)
    E = options.branch.fluid_mass_kg * options.system.cp_fluid_J_per_kgK * ...
        branch_state.T_fluid_K;
end

function audit = inactive_audit(branch_state, role)
    audit = struct();
    audit.branch = string(role.name);
    audit.m_dot_kgps = 0.0;
    audit.T_boundary_K = role.boundary_T_K;
    audit.T_in_K = branch_state.T_fluid_K;
    audit.T_out_K = branch_state.T_fluid_K;
    audit.T_fluid_K = branch_state.T_fluid_K;
    audit.Q_boundary_W = 0.0;
    audit.Q_to_solid_W = 0.0;
    audit.storage_delta_W = 0.0;
    audit.energy_residual_W = 0.0;
end
