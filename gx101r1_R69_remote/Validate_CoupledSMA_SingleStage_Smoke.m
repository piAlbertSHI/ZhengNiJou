function summary = Validate_CoupledSMA_SingleStage_Smoke(options)
% Smoke validation for the coupled single-stage SMA cycle.

    user_options_provided = nargin >= 1 && ~isempty(options);
    if ~user_options_provided
        options = Build_CoupledSMA_Default_Options();
    end

    options.n_cycles = 1;
    if ~user_options_provided || ~isfield(options, 'outputs_dir') || isempty(options.outputs_dir)
        options.outputs_dir = fullfile(fileparts(mfilename('fullpath')), 'outputs_coupled_single_smoke');
    end
    options.save_checkpoints = true;
    options.save_plots = false;
    options.store_raw_simout = false;
    options.exchange_options.use_surrogate_exchange = true;
    options.exchange_options.surrogate_hold_delta_T_K = 6.0;
    options.exchange_options.surrogate_cooldown_delta_T_K = 4.0;
    options.refrigerant.solver_options.Nt = 60;
    options.refrigerant.solver_options.Nt_unload = 80;
    options.refrigerant.solver_options.enable_unload_retry = false;
    options.refrigerant.solver_options.skip_loading_jv_audit = true;
    options.stage_schedule.stage1_steps = 60;
    options.stage_schedule.stage3_steps = 80;
    options.stage_schedule.stage1_duration_s = 0.12;
    options.stage_schedule.stage3_duration_s = 0.45;

    result = Run_CoupledSMA_SingleStage_Cycles(options);
    summary = build_smoke_summary(result);
    write_json(fullfile(result.outputs_dir, 'coupled_smoke_summary.json'), summary);
    save(fullfile(result.outputs_dir, 'coupled_smoke_result.mat'), 'result', 'summary', '-v7.3');

    assert_smoke_ok(summary);
end

function summary = build_smoke_summary(result)
    cycles = reshape(get_field(result, 'cycle_results', struct([])), 1, []);
    if isempty(cycles)
        stage_reports = struct([]);
        load_stage = struct();
        unload_stage = struct();
    else
        stage_reports = reshape(get_field(cycles(1), 'stage_reports', struct([])), 1, []);
        load_stage = get_field(cycles(1), 'actuator_heat_load', struct());
        unload_stage = get_field(cycles(1), 'actuator_cool_unload', struct());
    end

    load_summary = get_field(load_stage, 'summary', struct());
    unload_summary = get_field(unload_stage, 'summary', struct());
    final_state = get_field(result, 'final_state', struct());
    final_T = get_field(final_state, 'T', NaN);
    final_xi = get_field(final_state, 'xi', NaN);
    coupled_summary = get_field(result, 'summary', struct());

    summary = struct();
    summary.ok = logical(get_field(result, 'ok', false));
    summary.failure_reason = get_field(result, 'failure_reason', '');
    summary.outputs_dir = get_field(result, 'outputs_dir', '');
    summary.result_mat = fullfile(summary.outputs_dir, 'coupled_result.mat');
    summary.smoke_result_mat = fullfile(summary.outputs_dir, 'coupled_smoke_result.mat');
    summary.stage_count = numel(stage_reports);
    summary.all_stage_ok = ~isempty(stage_reports) && all([stage_reports.ok]);
    summary.surrogate_exchange_used = logical(get_field(coupled_summary, 'surrogate_exchange_used', false));
    summary.exchange_backend_note = 'Smoke uses surrogate_temperature_v1 because the local Simulink baseline exceeded 10 minutes at stage 2.';

    summary.stage1_T_rises = get_field(load_summary, 'actuator_T_last_K', NaN) > ...
        get_field(load_summary, 'actuator_T_first_K', NaN);
    summary.stage1_xi_decreases = get_field(load_summary, 'actuator_xi_last', NaN) < ...
        get_field(load_summary, 'actuator_xi_first', NaN);
    summary.stage1_pressure_rises = get_field(load_summary, 'pressure_last_MPa', NaN) >= ...
        get_field(load_summary, 'pressure_first_MPa', NaN);
    summary.stage3_T_drops = get_field(unload_summary, 'actuator_T_last_K', NaN) < ...
        get_field(unload_summary, 'actuator_T_first_K', NaN);
    summary.stage3_xi_increases = get_field(unload_summary, 'actuator_xi_last', NaN) > ...
        get_field(unload_summary, 'actuator_xi_first', NaN);
    summary.stage3_pressure_drops = get_field(unload_summary, 'pressure_last_MPa', NaN) <= ...
        get_field(unload_summary, 'pressure_first_MPa', NaN);

    summary.final_refrigerant_T_finite = all(isfinite(final_T(:)));
    summary.final_refrigerant_xi_finite = all(isfinite(final_xi(:)));
    summary.coupling_residual_norm_median = get_field(coupled_summary, 'coupling_residual_norm_median', NaN);
    summary.coupling_residual_norm_max = get_field(coupled_summary, 'coupling_residual_norm_max', NaN);
    summary.pressure_max_MPa = get_field(coupled_summary, 'pressure_max_MPa', NaN);
    summary.pressure_min_MPa = get_field(coupled_summary, 'pressure_min_MPa', NaN);
    summary.actuator_heat_input_J = get_field(coupled_summary, 'actuator_heat_input_J', NaN);
    summary.actuator_latent_J = get_field(coupled_summary, 'actuator_latent_J', NaN);
    summary.actuator_mechanical_work_J = get_field(coupled_summary, 'actuator_mechanical_work_J', NaN);
    summary.hot_end_heat_J = get_field(coupled_summary, 'hot_end_heat_J', NaN);
    summary.cold_end_heat_J = get_field(coupled_summary, 'cold_end_heat_J', NaN);
    summary.pump_work_J = get_field(coupled_summary, 'pump_work_J', NaN);
    summary.COP_estimate = get_field(coupled_summary, 'COP_estimate', NaN);
    summary.energy_audit_finite = all(isfinite([summary.actuator_heat_input_J, ...
        summary.actuator_latent_J, summary.actuator_mechanical_work_J, ...
        summary.hot_end_heat_J, summary.cold_end_heat_J, summary.pump_work_J, ...
        summary.COP_estimate]));
    summary.physics_checks_ok = summary.ok && summary.all_stage_ok && ...
        summary.stage1_T_rises && summary.stage1_xi_decreases && summary.stage1_pressure_rises && ...
        summary.stage3_T_drops && summary.stage3_xi_increases && summary.stage3_pressure_drops && ...
        summary.final_refrigerant_T_finite && summary.final_refrigerant_xi_finite && ...
        isfinite(summary.coupling_residual_norm_median) && summary.coupling_residual_norm_median < 0.05 && ...
        isfinite(summary.coupling_residual_norm_max) && summary.coupling_residual_norm_max < 0.20 && ...
        summary.energy_audit_finite;
end

function assert_smoke_ok(summary)
    if ~summary.physics_checks_ok
        error('Validate_CoupledSMA_SingleStage_Smoke:PhysicsChecksFailed', ...
            'Coupled smoke validation failed. Summary: %s', jsonencode(summary));
    end
end

function value = get_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end

function write_json(path_value, value)
    fid = fopen(path_value, 'w', 'n', 'UTF-8');
    if fid < 0
        error('Validate_CoupledSMA_SingleStage_Smoke:JsonOpenFailed', ...
            'Could not write %s.', path_value);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
    clear cleaner
end
