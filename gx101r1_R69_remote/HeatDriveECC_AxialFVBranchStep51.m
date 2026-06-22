function [branch_state, audit] = HeatDriveECC_AxialFVBranchStep51( ...
        branch_state, role, solid_T_21, dt_s, options, active)
% Advance one 21-node axial finite-volume fluid branch.
%
% Each control volume satisfies an explicit upwind balance:
%   m_i cp dTf_i/dt = mdot cp (Tup_i - Tf_i)
%                   + UA_b,i (Tb - Tf_i)
%                   - UA_s,i (Tf_i - Tsolid_i)
% where Tup_i is the boundary inlet for node 1 and the upstream fluid state
% for downstream nodes. This keeps downstream fluid states in the dynamics
% instead of reconstructing the branch from a single plug-flow recursion.

    if nargin < 6
        active = true;
    end
    N = options.node_count;
    if ~active
        audit = inactive_audit(role, branch_state, options);
        return;
    end

    solid_T_21 = solid_T_21(:);
    cp = options.system.cp_fluid_J_per_kgK;
    if isfield(role, 'm_dot_kg_per_s') && ~isempty(role.m_dot_kg_per_s)
        mdot = role.m_dot_kg_per_s;
    else
        mdot = options.branch.m_dot_kg_per_s;
    end
    m_node = options.branch.fluid_mass_total_kg / N;
    UA_node = role.UA_W_per_K / N;
    boundary_UA_node = role.boundary_UA_W_per_K / N;
    T_in = zeros(N, 1);
    T_out = zeros(N, 1);
    old_T = get_branch_vector(branch_state, 'T_fluid_21', 'T_fluid_51', N);
    upstream_T = [role.boundary_T_K; old_T(1:end-1)];
    T_in(:) = upstream_T;

    Q_advective = mdot * cp .* (upstream_T - old_T);
    Q_inlet_boundary = Q_advective(1);
    Q_boundary = boundary_UA_node .* (role.boundary_T_K - old_T);
    Q_to_solid = zeros(N, 1);
    Q_to_solid(:) = UA_node .* (old_T - solid_T_21);
    net_fluid_W = Q_advective + Q_boundary - Q_to_solid;
    new_T = old_T + net_fluid_W .* dt_s ./ max(m_node * cp, eps);
    T_out(:) = new_T;
    branch_state.T_fluid_21 = new_T;
    branch_state.T_fluid_51 = new_T;
    storage_W = (new_T - old_T) .* m_node .* cp ./ max(dt_s, eps);
    residual_W = sum(Q_advective) + sum(Q_boundary) - ...
        sum(Q_to_solid) - sum(storage_W);

    audit = struct();
    audit.name = role.name;
    audit.m_dot_kgps = mdot;
    audit.T_in_21 = T_in;
    audit.T_out_21 = T_out;
    audit.T_fluid_21 = new_T;
    audit.Q_advective_21_W = Q_advective;
    audit.Q_inlet_boundary_W = Q_inlet_boundary;
    audit.Q_wall_boundary_21_W = Q_boundary;
    audit.Q_wall_boundary_W = sum(Q_boundary);
    audit.Q_to_solid_21_W = Q_to_solid;
    audit.Q_boundary_21_W = Q_boundary;
    audit.storage_21_W = storage_W;
    audit.T_in_51 = audit.T_in_21;
    audit.T_out_51 = audit.T_out_21;
    audit.T_fluid_51 = audit.T_fluid_21;
    audit.Q_advective_51_W = audit.Q_advective_21_W;
    audit.Q_wall_boundary_51_W = audit.Q_wall_boundary_21_W;
    audit.Q_to_solid_51_W = audit.Q_to_solid_21_W;
    audit.Q_boundary_51_W = audit.Q_boundary_21_W;
    audit.storage_51_W = audit.storage_21_W;
    audit.energy_residual_W = residual_W;
    audit.Q_advective_W = sum(Q_advective);
    audit.Q_to_solid_W = sum(Q_to_solid);
    audit.Q_boundary_W = sum(Q_boundary) + Q_inlet_boundary;
    audit.storage_W = sum(storage_W);
    audit.T_in_K = T_in(1);
    audit.T_out_K = T_out(end);
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
    audit.Q_advective_W = 0.0;
    audit.Q_to_solid_W = 0.0;
    audit.Q_boundary_W = 0.0;
    audit.storage_W = 0.0;
    audit.T_in_K = fluid(1);
    audit.T_out_K = fluid(end);
end

function values = get_branch_vector(branch_state, primary_name, legacy_name, expected_count)
    if isstruct(branch_state) && isfield(branch_state, primary_name) && ...
            ~isempty(branch_state.(primary_name))
        primary_values = branch_state.(primary_name);
        values = primary_values(:);
    elseif isstruct(branch_state) && isfield(branch_state, legacy_name) && ...
            ~isempty(branch_state.(legacy_name))
        legacy_values = branch_state.(legacy_name);
        values = legacy_values(:);
    else
        values = NaN(expected_count, 1);
    end
    if numel(values) ~= expected_count
        error('HeatDriveECC_AxialFVBranchStep51:UnexpectedNodeCount', ...
            'Expected %d fluid nodes, got %d.', expected_count, numel(values));
    end
end
