function outer = Run_HeatDriveECC_Table4_OuterSolve(settings)
% Mechanism-gated fixed-Tc outer solve for the zero-load Eq.10 root.
%
% Each candidate starts from the frozen C200 authority. A candidate may
% enter bracketing/interpolation only after periodic steady state and the
% declared flow, phase, energy and observability gates all pass.

    if nargin < 1
        settings = struct();
    end
    repo_root = fileparts(fileparts(mfilename('fullpath')));
    defaults = struct( ...
        'output_root', fullfile(repo_root, 'outputs', ...
            'qian_table4_zero_load_outer_solve_20260822'), ...
        'Tc_candidates_K', [275.5, 278.5], ...
        'target_SCP_W_per_g', 0.0, ...
        'root_SCP_tolerance_W_per_g', 0.01, ...
        'segment_cycles', 20, ...
        'maximum_additional_cycles', 80, ...
        'generate_intermediate_figures', false, ...
        'resume_existing_candidates', true, ...
        'run_candidates', true, ...
        'model_overrides', struct(), ...
        'branch_overrides', struct(), ...
        'authority_settings', struct());
    settings = merge_structs(defaults, settings);
    validate_settings(settings);
    authority = Resolve_HeatDriveECC_MainlineAuthority( ...
        settings.authority_settings);
    if ~exist(settings.output_root, 'dir')
        mkdir(settings.output_root);
    end

    records = frozen_baseline_record(authority);
    for idx = 1:numel(settings.Tc_candidates_K)
        Tc_K = settings.Tc_candidates_K(idx);
        if abs(Tc_K - records(1).Tc_K) <= 1.0e-12
            continue;
        end
        candidate_root = fullfile(settings.output_root, ...
            sprintf('Tc_%08.3fK', Tc_K));
        record_path = fullfile(candidate_root, 'outer_candidate_record.mat');
        state_path = fullfile(candidate_root, ...
            'steady_continuation_state.mat');
        if isfile(record_path)
            loaded = load(record_path, 'record');
            record = loaded.record;
        elseif isfile(state_path)
            loaded = load(state_path, 'state');
            if strcmp(loaded.state.status, 'running') && ...
                    logical(settings.run_candidates)
                state = run_candidate(Tc_K, candidate_root, authority, settings);
            else
                state = loaded.state;
            end
            record = evaluate_candidate(Tc_K, candidate_root, state);
            save(record_path, 'record', '-v7');
        elseif logical(settings.run_candidates)
            state = run_candidate(Tc_K, candidate_root, authority, settings);
            record = evaluate_candidate(Tc_K, candidate_root, state);
            save(record_path, 'record', '-v7');
        else
            record = pending_record(Tc_K, candidate_root);
        end
        if ~record.admissible && ~strcmp(record.status, 'pending')
            write_rejection_marker(candidate_root, record, authority);
        end
        records(end + 1, 1) = record; %#ok<AGROW>
        write_outer_outputs(settings.output_root, records, settings, authority);
    end

    outer = build_outer_result(records, settings, authority);
    write_outer_outputs(settings.output_root, records, settings, authority);
    save(fullfile(settings.output_root, 'outer_solve_result.mat'), ...
        'outer', 'settings', '-v7');
    fprintf(['OUTER_SOLVE status=%s accepted=%d rejected=%d ', ...
        'root_bracketed=%d root_Tc_K=%.12g\n'], outer.status, ...
        outer.accepted_count, outer.rejected_count, ...
        outer.root_bracketed, outer.root_Tc_K);
end

function state = run_candidate(Tc_K, candidate_root, authority, settings)
    candidate_settings = struct( ...
        'Tchex_K', Tc_K, ...
        'output_root', candidate_root, ...
        'segment_cycles', settings.segment_cycles, ...
        'maximum_cycles', authority.completed_cycles + ...
            settings.maximum_additional_cycles, ...
        'required_consecutive_near_segments', intmax('int32'), ...
        'generate_intermediate_figures', ...
            settings.generate_intermediate_figures, ...
        'resume_existing_state', settings.resume_existing_candidates, ...
        'initial_prior_result_path', authority.result_path, ...
        'initial_checkpoint_path', authority.checkpoint_path, ...
        'initial_state_policy', 'frozen_c200_only', ...
        'mainline_contract_path', authority.contract_path, ...
        'model_overrides', settings.model_overrides, ...
        'branch_overrides', settings.branch_overrides);
    state = Run_HeatDriveECC_Table4_FixedReservoirPoint( ...
        candidate_settings);
end

function record = frozen_baseline_record(authority)
    progress = readtable(authority.progress_path, 'TextType', 'string');
    last = progress(end, :);
    report = fileread(authority.report_path);
    gates = required_gate_results(report);
    record = record_template();
    record.Tc_K = 276.95;
    record.status = 'accepted_frozen_baseline';
    record.source = 'frozen_c200_authority';
    record.attempted_cycles = authority.completed_cycles;
    record.validated_cycles = authority.completed_cycles;
    record.mechanism_pass = authority.mechanism_pass;
    record.periodic_steady_state = authority.periodic_steady_state;
    record.flow_gates_pass = gates.flow;
    record.phase_gates_pass = gates.phase;
    record.energy_gates_pass = gates.energy;
    record.observability_gates_pass = gates.observability;
    record.admissible = all([record.mechanism_pass, ...
        record.periodic_steady_state, record.flow_gates_pass, ...
        record.phase_gates_pass, record.energy_gates_pass, ...
        record.observability_gates_pass]);
    record.eq9_lift_K = last.eq9_lift_K;
    record.eq10_SCP_W_per_g = last.eq10_SCP_W_per_g;
    record.endpoint_drift_K = last.endpoint_drift_K;
    record.same_phase_temperature_drift_K = ...
        last.same_phase_temperature_drift_K;
    record.same_phase_phase_drift = last.same_phase_phase_drift;
    record.result_path = authority.result_path;
    record.checkpoint_path = authority.checkpoint_path;
    record.report_path = authority.report_path;
    record.output_root = fileparts(authority.progress_path);
end

function record = evaluate_candidate(Tc_K, candidate_root, state)
    record = record_template();
    record.Tc_K = Tc_K;
    record.status = char(string(state.status));
    record.source = 'frozen_c200_continuation_candidate';
    record.output_root = candidate_root;
    record.validated_cycles = state.current_cycles;
    record.attempted_cycles = get_field(state, 'last_attempt_cycles', ...
        state.current_cycles);
    if isempty(state.rows)
        return;
    end
    row = state.rows(end, :);
    record.mechanism_pass = logical(row.mechanism_pass);
    record.periodic_steady_state = logical(row.periodic_steady_state);
    record.eq9_lift_K = row.eq9_lift_K;
    record.eq10_SCP_W_per_g = row.eq10_SCP_W_per_g;
    record.endpoint_drift_K = row.endpoint_drift_K;
    record.same_phase_temperature_drift_K = ...
        row.same_phase_temperature_drift_K;
    record.same_phase_phase_drift = row.same_phase_phase_drift;
    record.result_path = char(string(row.output_mat));
    record.checkpoint_path = char(string(row.checkpoint_path));
    record.report_path = fullfile(char(string(row.output_dir)), ...
        'physical_validation_report.txt');
    if isfile(record.report_path)
        gates = required_gate_results(fileread(record.report_path));
        record.flow_gates_pass = gates.flow;
        record.phase_gates_pass = gates.phase;
        record.energy_gates_pass = gates.energy;
        record.observability_gates_pass = gates.observability;
    end
    record.admissible = strcmp(state.status, 'periodic_steady_state') && ...
        all([record.mechanism_pass, record.periodic_steady_state, ...
        record.flow_gates_pass, record.phase_gates_pass, ...
        record.energy_gates_pass, record.observability_gates_pass]);
    if ~record.admissible
        record.checkpoint_path = '';
    end
end

function gates = required_gate_results(report)
    flow_names = {'SMA_settled_instantaneous_flow_target', ...
        'SE_last_cycle_settled_flow_no_reversal', ...
        'SE_last_cycle_settled_instantaneous_flow_target', ...
        'SE_last_cycle_settled_flow_RMS_target', ...
        'qian_active_flow_targets', 'route_flow_direction'};
    phase_names = {'constitutive_phase_direction', 'SMA_phase_swing', ...
        'SE_phase_swing', 'qian_table4_half_cycle_phase_completion', ...
        'qian_table4_compatibility_stress'};
    energy_names = {'pump_work_nonnegative', 'SMA_solid_energy_balance', ...
        'SE_solid_energy_balance', ...
        'stage_constitutive_energy_decomposition', ...
        'internal_mechanical_work_transfer'};
    observability_names = {'qian_eq9_eq10_observability', ...
        'fixed_chex_temperature_authority'};
    gates = struct( ...
        'flow', report_checks_pass(report, flow_names), ...
        'phase', report_checks_pass(report, phase_names), ...
        'energy', report_checks_pass(report, energy_names), ...
        'observability', report_checks_pass(report, observability_names));
end

function tf = report_checks_pass(report, names)
    tf = true;
    for idx = 1:numel(names)
        pattern = sprintf('(?m)^\\s*%s\\s+1\\s*$', ...
            regexptranslate('escape', names{idx}));
        tf = tf && ~isempty(regexp(report, pattern, 'once'));
    end
end

function outer = build_outer_result(records, settings, authority)
    admitted = records([records.admissible]);
    [~, order] = sort([admitted.Tc_K]);
    admitted = admitted(order);
    response = [admitted.eq10_SCP_W_per_g] - ...
        settings.target_SCP_W_per_g;
    bracket = [];
    for idx = 1:(numel(admitted) - 1)
        if response(idx) == 0 || response(idx) * response(idx + 1) <= 0
            bracket = idx:(idx + 1);
            break;
        end
    end
    root_Tc_K = NaN;
    root_bracketed = ~isempty(bracket);
    if root_bracketed
        x = [admitted(bracket).Tc_K];
        y = response(bracket);
        if abs(diff(y)) > eps
            root_Tc_K = x(1) - y(1) * diff(x) / diff(y);
        else
            root_Tc_K = mean(x);
        end
    end
    root_records = admitted(abs(response) <= ...
        settings.root_SCP_tolerance_W_per_g);
    if ~isempty(root_records)
        [~, best] = min(abs([root_records.eq10_SCP_W_per_g] - ...
            settings.target_SCP_W_per_g));
        root_Tc_K = root_records(best).Tc_K;
        status = 'accepted_zero_load_root';
    elseif root_bracketed
        status = 'valid_bracket_requires_next_candidate';
    else
        status = 'no_valid_bracket';
    end
    outer = struct();
    outer.schema = 'heatdrive_ecc_mechanism_gated_outer_solve_v1';
    outer.generated_at = char(datetime('now', 'TimeZone', 'local'));
    outer.status = status;
    outer.target_SCP_W_per_g = settings.target_SCP_W_per_g;
    outer.root_tolerance_W_per_g = settings.root_SCP_tolerance_W_per_g;
    outer.root_bracketed = root_bracketed;
    outer.root_Tc_K = root_Tc_K;
    outer.accepted_count = nnz([records.admissible]);
    outer.rejected_count = nnz(~[records.admissible] & ...
        ~strcmp({records.status}, 'pending'));
    outer.pending_count = nnz(strcmp({records.status}, 'pending'));
    outer.records = records;
    outer.authority_contract_path = authority.contract_path;
    outer.interpolation_policy = [ ...
        'Only periodic candidates passing mechanism, flow, phase, energy ', ...
        'and observability gates are admitted.'];
end

function write_outer_outputs(output_root, records, settings, authority)
    summary = struct2table(records);
    writetable(summary, fullfile(output_root, 'outer_candidate_summary.csv'));
    outer = build_outer_result(records, settings, authority);
    json_path = fullfile(output_root, 'outer_solve_summary.json');
    fid = fopen(json_path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'HeatDriveECC:OuterSummaryOpenFailed', ...
        'Cannot write %s.', json_path);
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(outer, 'PrettyPrint', true));
    clear cleaner
end

function write_rejection_marker(candidate_root, record, authority)
    if ~exist(candidate_root, 'dir')
        mkdir(candidate_root);
    end
    path = fullfile(candidate_root, 'REJECTED_DO_NOT_RESUME.txt');
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'HeatDriveECC:OuterRejectMarkerOpenFailed', ...
        'Cannot write %s.', path);
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, 'status=rejected_not_admissible_for_outer_solve\n');
    fprintf(fid, 'Tc_K=%.12g\n', record.Tc_K);
    fprintf(fid, 'attempt_status=%s\n', record.status);
    fprintf(fid, 'mechanism_pass=%d\n', record.mechanism_pass);
    fprintf(fid, 'periodic_steady_state=%d\n', record.periodic_steady_state);
    fprintf(fid, 'flow_gates_pass=%d\n', record.flow_gates_pass);
    fprintf(fid, 'phase_gates_pass=%d\n', record.phase_gates_pass);
    fprintf(fid, 'energy_gates_pass=%d\n', record.energy_gates_pass);
    fprintf(fid, 'observability_gates_pass=%d\n', ...
        record.observability_gates_pass);
    fprintf(fid, 'failed_result_may_resume=0\n');
    fprintf(fid, 'failed_result_may_interpolate=0\n');
    fprintf(fid, 'sole_recovery_path=%s\n', authority.checkpoint_path);
    clear cleaner
end

function record = pending_record(Tc_K, candidate_root)
    record = record_template();
    record.Tc_K = Tc_K;
    record.status = 'pending';
    record.source = 'not_run';
    record.output_root = candidate_root;
end

function record = record_template()
    record = struct( ...
        'Tc_K', NaN, 'status', '', 'source', '', ...
        'attempted_cycles', 0, 'validated_cycles', 0, ...
        'mechanism_pass', false, 'periodic_steady_state', false, ...
        'flow_gates_pass', false, 'phase_gates_pass', false, ...
        'energy_gates_pass', false, ...
        'observability_gates_pass', false, 'admissible', false, ...
        'eq9_lift_K', NaN, 'eq10_SCP_W_per_g', NaN, ...
        'endpoint_drift_K', NaN, ...
        'same_phase_temperature_drift_K', NaN, ...
        'same_phase_phase_drift', NaN, 'result_path', '', ...
        'checkpoint_path', '', 'report_path', '', 'output_root', '');
end

function value = get_field(s, name, fallback)
    if isfield(s, name)
        value = s.(name);
    else
        value = fallback;
    end
end

function validate_settings(settings)
    candidates = settings.Tc_candidates_K;
    assert(isnumeric(candidates) && isvector(candidates) && ...
        all(isfinite(candidates)) && all(candidates >= 255.05) && ...
        all(candidates <= 303.15), ...
        'HeatDriveECC:OuterInvalidCandidates', ...
        'Tc candidates must remain inside the declared SE-fluid range.');
    assert(settings.maximum_additional_cycles > 0 && ...
        settings.maximum_additional_cycles == ...
        round(settings.maximum_additional_cycles), ...
        'HeatDriveECC:OuterInvalidMaximumCycles', ...
        'maximum_additional_cycles must be a positive integer.');
end

function out = merge_structs(out, overrides)
    names = fieldnames(overrides);
    for idx = 1:numel(names)
        name = names{idx};
        if isfield(out, name) && isstruct(out.(name)) && ...
                isstruct(overrides.(name))
            out.(name) = merge_structs(out.(name), overrides.(name));
        else
            out.(name) = overrides.(name);
        end
    end
end
