function result = Run_HeatDriveECC_BranchUnit_Preflight(overrides)
% Preflight four seventh-round finite-volume branch units.
%
% This is strategy C from the seventh-round task book. The branch units use
% finite fluid mass, m_dot, cp, UA, boundary temperature, inlet/outlet
% transport, and branch storage. They do not use prescribed heat targets.

    if nargin < 1
        overrides = struct();
    end
    options = Build_HeatDriveECC_SeventhRound_Defaults(overrides);
    output_dir = fullfile(options.outputs_dir, 'branch_preflight');
    if ~isfolder(output_dir)
        mkdir(output_dir);
    end

    roles = branch_roles(options);
    rows = repmat(empty_row(), numel(roles) * 3, 1);
    row_idx = 0;
    for role_idx = 1:numel(roles)
        role = roles(role_idx);
        durations = [0.02, 0.1, options.schedule.stage_durations_s(role.active_stage)];
        for duration_idx = 1:numel(durations)
            duration_s = durations(duration_idx);
            row_idx = row_idx + 1;
            rows(row_idx) = run_one_preflight(role, duration_s, options);
        end
    end

    table_out = struct2table(rows);
    csv_path = fullfile(output_dir, 'branch_unit_preflight.csv');
    writetable(table_out, csv_path);

    result = struct();
    result.schema_version = 'heatdrive_ecc_branch_preflight_v1';
    result.strategy = options.branch.strategy;
    result.output_dir = output_dir;
    result.csv_path = csv_path;
    result.table = table_out;
    result.passed = all(table_out.passed);
    result.roles = roles;
    result.options = options;
    write_json(fullfile(output_dir, 'branch_unit_preflight_summary.json'), ...
        rmfield(result, {'table','options'}));
    save(fullfile(output_dir, 'branch_unit_preflight_result.mat'), ...
        'result', '-v7.3');
end

function row = run_one_preflight(role, duration_s, options)
    dt_s = min(duration_s / 120.0, 5.0e-4);
    steps = max(ceil(duration_s / dt_s), 1);
    dt_s = duration_s / steps;
    branch_state = Initialize_HeatDriveECC_FiniteVolumeBranchState(role, options);
    solid_T_K = role.preflight_solid_T_K;
    q_to_solid_J = 0.0;
    q_boundary_J = 0.0;
    storage0_J = HeatDriveECC_BranchStorageJ(branch_state, options);
    tic;
    last = struct();
    for idx = 1:steps
        [branch_state, last] = HeatDriveECC_FiniteVolumeBranchStep( ...
            branch_state, role, solid_T_K, dt_s, options, true);
        q_to_solid_J = q_to_solid_J + last.Q_to_solid_W * dt_s;
        q_boundary_J = q_boundary_J + last.Q_boundary_W * dt_s;
    end
    wall_time_s = toc;
    storage1_J = HeatDriveECC_BranchStorageJ(branch_state, options);
    residual_J = q_boundary_J - q_to_solid_J - (storage1_J - storage0_J);

    row = empty_row();
    row.branch = string(role.name);
    row.active_stage = role.active_stage;
    row.duration_s = duration_s;
    row.wall_time_s = wall_time_s;
    row.m_dot_kgps = last.m_dot_kgps;
    row.T_in_K = last.T_in_K;
    row.T_out_K = last.T_out_K;
    row.dT_in_minus_out_K = last.T_in_K - last.T_out_K;
    row.Q_to_solid_J = q_to_solid_J;
    row.Q_boundary_J = q_boundary_J;
    row.storage_delta_J = storage1_J - storage0_J;
    row.energy_residual_J = residual_J;
    row.energy_residual_fraction = abs(residual_J) / ...
        max(abs(q_boundary_J) + abs(q_to_solid_J) + abs(storage1_J - storage0_J), 1.0e-9);
    row.passed = wall_time_s <= options.branch.wall_time_limit_s && ...
        abs(last.m_dot_kgps) > options.branch.closed_route_threshold_kgps && ...
        branch_sign_ok(role, last, q_to_solid_J);
end

function ok = branch_sign_ok(role, last, q_to_solid_J)
    switch role.name
        case 'SMA_SHEX'
            ok = last.T_in_K > last.T_out_K && q_to_solid_J > 0;
        case {'SMA_THE','SE_THE'}
            ok = last.T_out_K > last.T_in_K && q_to_solid_J < 0;
        case 'SE_RHE'
            ok = last.T_in_K > last.T_out_K && q_to_solid_J > 0;
        otherwise
            ok = false;
    end
end

function roles = branch_roles(options)
    T0 = options.system.T0_K;
    Tc = options.system.Tc_K;
    Th = options.system.Th_K;
    roles = [
        role_struct('SMA_SHEX', 1, 'SMA', Th, T0, 'source_to_solid')
        role_struct('SMA_THE', 3, 'SMA', T0, Th - 3.0, 'solid_to_sink')
        role_struct('SE_THE', 2, 'SE', T0, T0 + 7.0, 'solid_to_sink')
        role_struct('SE_RHE', 4, 'SE', Tc, Tc - 5.0, 'source_to_solid')];
end

function role = role_struct(name, active_stage, solid, boundary_T_K, preflight_solid_T_K, heat_role)
    role = struct('name', name, 'active_stage', active_stage, ...
        'solid', solid, 'boundary_T_K', boundary_T_K, ...
        'preflight_solid_T_K', preflight_solid_T_K, ...
        'heat_role', heat_role);
end

function row = empty_row()
    row = struct('branch', "", 'active_stage', 0, 'duration_s', NaN, ...
        'wall_time_s', NaN, 'm_dot_kgps', NaN, 'T_in_K', NaN, ...
        'T_out_K', NaN, 'dT_in_minus_out_K', NaN, ...
        'Q_to_solid_J', NaN, 'Q_boundary_J', NaN, ...
        'storage_delta_J', NaN, 'energy_residual_J', NaN, ...
        'energy_residual_fraction', NaN, 'passed', false);
end

function write_json(path_value, s)
    try
        text = jsonencode(s, 'PrettyPrint', true);
    catch
        text = jsonencode(s);
    end
    fid = fopen(path_value, 'w');
    cleanup = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end
