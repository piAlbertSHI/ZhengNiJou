function [branch_state, audit] = HeatDriveECC_AxialFVBranchStep51( ...
        branch_state, role, solid_T_51, dt_s, options, active)
% Advance one 51-node axial finite-volume fluid branch.
%
% Uses plug-flow / NTU recursion per node:
%   Tin_i = upstream outlet
%   Tout_i = Tsolid_i + (Tin_i - Tsolid_i)*exp(-NTU_i)
%   Q_i = mdot*cp*(Tin_i - Tout_i)
% Branch internal fluid nodes store boundary reheating/recooling and local
% exchange energy; they are not a post-processed target curve.

    if nargin < 6
        active = true;
    end
    N = options.node_count;
    if ~active
        audit = inactive_audit(role, branch_state, options);
        return;
    end

    solid_T_51 = solid_T_51(:);
    cp = options.system.cp_fluid_J_per_kgK;
    mdot = options.branch.m_dot_kg_per_s;
    m_node = options.branch.fluid_mass_total_kg / N;
    UA_node = role.UA_W_per_K / N;
    boundary_UA_node = role.boundary_UA_W_per_K / N;
    old_T = branch_state.T_fluid_51(:);

    Q_boundary = boundary_UA_node .* (role.boundary_T_K - old_T);
    T_after_boundary = old_T + Q_boundary .* dt_s ./ max(m_node * cp, eps);

    T_in = zeros(N, 1);
    T_out = zeros(N, 1);
    Q_to_solid = zeros(N, 1);
    upstream = T_after_boundary(1);
    ntu = UA_node / max(abs(mdot) * cp, eps);
    for idx = 1:N
        T_in(idx) = upstream;
        T_out(idx) = solid_T_51(idx) + ...
            (T_in(idx) - solid_T_51(idx)) .* exp(-ntu);
        Q_to_solid(idx) = mdot * cp * (T_in(idx) - T_out(idx));
        upstream = T_out(idx);
    end

    new_T = T_after_boundary - Q_to_solid .* dt_s ./ max(m_node * cp, eps);
    branch_state.T_fluid_51 = new_T;
    storage_W = (new_T - old_T) .* m_node .* cp ./ max(dt_s, eps);
    residual_W = sum(Q_boundary) - sum(Q_to_solid) - sum(storage_W);

    audit = struct();
    audit.name = role.name;
    audit.m_dot_kgps = mdot;
    audit.T_in_51 = T_in;
    audit.T_out_51 = T_out;
    audit.T_fluid_51 = new_T;
    audit.Q_to_solid_51_W = Q_to_solid;
    audit.Q_boundary_51_W = Q_boundary;
    audit.storage_51_W = storage_W;
    audit.energy_residual_W = residual_W;
    audit.Q_to_solid_W = sum(Q_to_solid);
    audit.Q_boundary_W = sum(Q_boundary);
    audit.storage_W = sum(storage_W);
    audit.T_in_K = T_in(1);
    audit.T_out_K = T_out(end);
end

function audit = inactive_audit(role, branch_state, options)
    N = options.node_count;
    fluid = branch_state.T_fluid_51(:);
    audit = struct();
    audit.name = role.name;
    audit.m_dot_kgps = 0.0;
    audit.T_in_51 = fluid;
    audit.T_out_51 = fluid;
    audit.T_fluid_51 = fluid;
    audit.Q_to_solid_51_W = zeros(N, 1);
    audit.Q_boundary_51_W = zeros(N, 1);
    audit.storage_51_W = zeros(N, 1);
    audit.energy_residual_W = 0.0;
    audit.Q_to_solid_W = 0.0;
    audit.Q_boundary_W = 0.0;
    audit.storage_W = 0.0;
    audit.T_in_K = fluid(1);
    audit.T_out_K = fluid(end);
end
