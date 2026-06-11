function result = Run_HeatDriveECC_SixthRound_Preflight(options)
% Run sixth-round structure, mechanical, and short Simscape branch preflights.

    if nargin < 1 || isempty(options)
        options = Build_HeatDriveECC_SixthRound_Defaults();
    else
        options = Build_HeatDriveECC_SixthRound_Defaults(options);
    end
    if ~isfolder(options.outputs_dir)
        mkdir(options.outputs_dir);
    end

    structure = Validate_HeatDriveECC_SixthRound_Structure(options);
    mechanical = run_mechanical_preflight(options);
    branch_short = run_branch_short_simscape_preflight(options);

    result = struct();
    result.schema_version = 'heatdrive_ecc_sixth_round_preflight_v1';
    result.options = options;
    result.structure = structure;
    result.mechanical = mechanical;
    result.branch_short = branch_short;
    result.passed = structure.ok && mechanical.passed && branch_short.passed;
    result.result_mat_path = fullfile(options.outputs_dir, 'sixth_round_preflight.mat');
    save(result.result_mat_path, 'result', '-v7.3');
end

function mechanical = run_mechanical_preflight(options)
    [params, ~] = Build_HeatDriveECC_SixthRound_SimParams(options);
    clear HeatDriveECC_SixthRound_MechanicalStep
    t = params.sixth_mechanical_preflight_input_ts.Time(:);
    u = params.sixth_mechanical_preflight_input_ts.Data;
    y = zeros(numel(t), 120);
    for idx = 1:numel(t)
        y(idx, :) = HeatDriveECC_SixthRound_MechanicalStep(u(idx, :));
    end
    mechanical = struct();
    mechanical.time_s = t;
    mechanical.audit = y;
    mechanical.xM_a_min = min(y(:, 5));
    mechanical.xM_a_final = y(end, 5);
    mechanical.xM_r_max = max(y(:, 6));
    mechanical.xM_r_final = y(end, 6);
    mechanical.max_eq6_scaled = max(abs(y(:, 7)));
    mechanical.max_eq7_scaled = max(abs(y(:, 8)));
    mechanical.max_sigma_r_Pa = max(y(:, 2));
    mechanical.passed = mechanical.xM_a_min < 0.99 && ...
        mechanical.xM_a_final > mechanical.xM_a_min && ...
        mechanical.xM_r_max > 1.0e-3 && ...
        mechanical.xM_r_final < mechanical.xM_r_max && ...
        mechanical.max_sigma_r_Pa > 1.0e6 && ...
        mechanical.max_eq6_scaled < options.validation.max_eq6_scaled && ...
        mechanical.max_eq7_scaled < options.validation.max_eq7_scaled;

    table_out = table(t, y(:,1), y(:,2), y(:,3), y(:,4), y(:,5), y(:,6), ...
        y(:,7), y(:,8), y(:,9), y(:,10), y(:,11), y(:,12), ...
        y(:,115), y(:,116), y(:,117), y(:,118), ...
        'VariableNames', {'time_s','sigma_a_Pa','sigma_r_Pa', ...
        'epsilon_a','epsilon_r','xM_a','xM_r','eq6_scaled','eq7_scaled', ...
        'qA_W','qR_W','mechA_W','mechR_W','pai_a','pai_r','rxi_a','rxi_r'});
    writetable(table_out, fullfile(options.outputs_dir, ...
        'sixth_round_mechanical_preflight.csv'));
end

function branch_short = run_branch_short_simscape_preflight(options)
    Build_HeatDriveECC_SixthRound_Model(options.force_rebuild_model);
    [params, ~] = Build_HeatDriveECC_SixthRound_SimParams(options);

    rows = repmat(empty_branch_row(), numel(options.branch_roles), 1);
    for idx = 1:numel(options.branch_roles)
        role = options.branch_roles{idx};
        key = lower(role.name);
        [sim_out, wall_time_s, error_message] = sim_one_role_branch(options, params, role);
        if isempty(error_message)
            rows(idx) = collect_branch_row(sim_out, key, role, wall_time_s, options);
        else
            rows(idx) = failed_branch_row(key, role, wall_time_s, error_message);
        end
    end
    branch_table = struct2table(rows);
    writetable(branch_table, fullfile(options.outputs_dir, ...
        'sixth_round_branch_short_preflight.csv'));
    branch_short = struct();
    branch_short.wall_time_s = max(branch_table.wall_time_s);
    branch_short.table = branch_table;
    branch_short.passed = all(branch_table.wall_time_s <= options.preflight.wall_time_limit_s) && ...
        all(strlength(branch_table.error_message) == 0) && ...
        all(branch_table.max_active_mdot_kgps > options.preflight.closed_route_threshold_kgps) && ...
        all(abs(branch_table.final_dT_in_minus_out_K) > options.preflight.min_temperature_delta_K);
end

function [sim_out, wall_time_s, error_message] = sim_one_role_branch(options, params, role)
    sim_out = [];
    error_message = "";
    model_name = options.model_name;
    load_system(model_name);
    cleanup = onCleanup(@() close_system(model_name, 0));
    for idx = 1:numel(options.branch_roles)
        other = options.branch_roles{idx};
        state = 'on';
        if strcmp(other.name, role.name)
            state = 'off';
        end
        set_param([model_name '/' other.name], 'Commented', state);
    end

    sim_in = Simulink.SimulationInput(model_name);
    names = fieldnames(params);
    for idx = 1:numel(names)
        sim_in = sim_in.setVariable(names{idx}, params.(names{idx}));
    end
    sim_in = sim_in.setModelParameter( ...
        'StopTime', sprintf('%.15g', options.preflight.short_stop_s), ...
        'ReturnWorkspaceOutputs', 'on', ...
        'SimscapeLogType', 'none');
    try
        tic;
        sim_out = sim(sim_in);
        wall_time_s = toc;
    catch ME
        wall_time_s = toc;
        error_message = string(ME.message);
    end
end

function row = collect_branch_row(sim_out, key, role, wall_time_s, options)
    row = empty_branch_row();
    row.branch = string(upper(key));
    row.active_stage = role.active_stage;
    row.active_path = string(role.active_path);
    row.wall_time_s = wall_time_s;
    if strcmpi(role.active_path, 'hold')
        mdot_name = [key '_mass_flow_v1_cold_inlet_kgps'];
        tin_name = [key '_sma_hold_inlet_fluid_temp_out'];
        tout_name = [key '_sma_hold_outlet_fluid_temp_out'];
    else
        mdot_name = [key '_mass_flow_v4_hot_inlet_kgps'];
        tin_name = [key '_sma_cooldown_inlet_fluid_temp_out'];
        tout_name = [key '_sma_cooldown_outlet_fluid_temp_out'];
    end
    mdot = read_signal(sim_out, mdot_name);
    tin = read_signal(sim_out, tin_name);
    tout = read_signal(sim_out, tout_name);
    row.max_active_mdot_kgps = max(abs(mdot.values));
    row.T_in_start_K = tin.values(1);
    row.T_in_end_K = tin.values(end);
    row.T_out_start_K = tout.values(1);
    row.T_out_end_K = tout.values(end);
    row.final_dT_in_minus_out_K = row.T_in_end_K - row.T_out_end_K;
    row.final_q_fluid_W = row.max_active_mdot_kgps * ...
        options.system.cp_fluid_J_per_kgK * row.final_dT_in_minus_out_K;
end

function row = failed_branch_row(key, role, wall_time_s, error_message)
    row = empty_branch_row();
    row.branch = string(upper(key));
    row.active_stage = role.active_stage;
    row.active_path = string(role.active_path);
    row.wall_time_s = wall_time_s;
    row.error_message = string(error_message);
end

function s = read_signal(sim_out, name)
    raw = sim_out.get(name);
    s = struct('time_s', raw.time(:), ...
        'values', squeeze(raw.signals.values));
    if ~isvector(s.values)
        s.values = s.values(:, 1);
    end
    s.values = s.values(:);
end

function row = empty_branch_row()
    row = struct('branch', "", 'active_stage', 0, 'active_path', "", ...
        'wall_time_s', NaN, ...
        'max_active_mdot_kgps', NaN, ...
        'T_in_start_K', NaN, 'T_in_end_K', NaN, ...
        'T_out_start_K', NaN, 'T_out_end_K', NaN, ...
        'final_dT_in_minus_out_K', NaN, ...
        'final_q_fluid_W', NaN, ...
        'error_message', "");
end
