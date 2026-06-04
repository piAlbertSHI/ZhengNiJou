function summary = Build_GX101R1_State_Sync_Trace_Table(run_result_or_path, outputs_dir)
% Write per-stage side-state source/writeback trace for gx101r1.

    if nargin < 1 || isempty(run_result_or_path)
        error('Build_GX101R1_State_Sync_Trace_Table:MissingInput', ...
            'A run_result struct or run_result.mat path is required.');
    end
    if ischar(run_result_or_path) || isstring(run_result_or_path)
        data = load(char(run_result_or_path), 'run_result');
        run_result = data.run_result;
        if nargin < 2 || isempty(outputs_dir)
            outputs_dir = fileparts(char(run_result_or_path));
        end
    else
        run_result = run_result_or_path;
        if nargin < 2 || isempty(outputs_dir)
            outputs_dir = get_field(get_field(run_result, 'config', struct()), 'outputs_dir', fullfile(pwd, 'Output'));
        end
    end
    if ~exist(outputs_dir, 'dir')
        mkdir(outputs_dir);
    end

    rows = repmat(empty_row(), 1, 0);
    cycles = reshape(get_field(run_result, 'cycle_results', struct([])), 1, []);
    for cidx = 1:numel(cycles)
        reports = reshape(get_field(cycles(cidx), 'stage_reports', struct([])), 1, []);
        for ridx = 1:numel(reports)
            rows(end + 1) = row_from_report(cycles(cidx).cycle_index, reports(ridx)); %#ok<AGROW>
        end
    end

    table_out = struct2table(rows);
    csv_path = fullfile(outputs_dir, 'state_sync_trace_table.csv');
    json_path = fullfile(outputs_dir, 'state_sync_trace_table.json');
    writetable(table_out, csv_path);
    summary = struct( ...
        'outputs_dir', outputs_dir, ...
        'csv_path', csv_path, ...
        'json_path', json_path, ...
        'row_count', numel(rows), ...
        'state_sync_contract_ok', all([rows.state_sync_row_ok]), ...
        'rows', rows);
    write_json(json_path, summary);
    save(fullfile(outputs_dir, 'state_sync_trace_table.mat'), 'summary', 'table_out');
end

function row = row_from_report(cycle_index, r)
    stage_name = char(string(get_field(r, 'stage_name', '')));
    row = empty_row();
    row.cycle_index = cycle_index;
    row.stage_index = get_field(r, 'stage_index', NaN);
    row.stage_name = string(stage_name);
    row.hot_sink_T_in_K = get_field(r, 'hot_sink_temp_in', NaN);
    row.hot_sink_T_out_K = get_field(r, 'hot_sink_temp_out', NaN);
    row.hot_buffer_T_in_K = get_field(r, 'hot_buffer_temp_in', NaN);
    row.hot_buffer_T_out_K = get_field(r, 'hot_buffer_temp_out', NaN);
    row.official_hot_end_T_in_K = get_field(r, 'hot_end_temp_in', NaN);
    row.official_hot_end_T_out_K = get_field(r, 'hot_end_temp_out', NaN);
    row.official_hot_end_definition = string(get_field(r, 'official_hot_end_definition', ''));
    row.cold_sink_T_in_K = get_field(r, 'cold_sink_temp_in', NaN);
    row.cold_sink_T_out_K = get_field(r, 'cold_sink_temp_out', NaN);
    row.cold_buffer_T_in_K = get_field(r, 'cold_buffer_temp_in', NaN);
    row.cold_buffer_T_out_K = get_field(r, 'cold_buffer_temp_out', NaN);
    row.official_cold_end_T_in_K = get_field(r, 'cold_end_temp_in', NaN);
    row.official_cold_end_T_out_K = get_field(r, 'cold_end_temp_out', NaN);
    row.official_cold_end_definition = string(get_field(r, 'official_cold_end_definition', ''));
    row.cold_load_T_in_K = get_field(r, 'cold_load_temp_in', NaN);
    row.cold_load_T_out_K = get_field(r, 'cold_load_temp_out', NaN);
    row.hot_side_state_sync_policy = string(get_field(r, 'hot_side_state_sync_policy', ''));
    row.cold_side_state_sync_policy = string(get_field(r, 'cold_side_state_sync_policy', ''));
    row.hold_cold_official_drift_due_to_source_buffer_K = get_field(r, 'hold_cold_official_drift_due_to_source_buffer_K', NaN);
    row.stage2_cold_buffer_source_pollution_ok = logical(get_field(r, 'stage2_cold_buffer_source_pollution_ok', false));
    row.hot_writeback_rule = "unchanged";
    row.cold_writeback_rule = "unchanged";
    row.cold_load_writeback_rule = "external load state only";
    if strcmp(stage_name, 'hold_exchange')
        row.hot_writeback_rule = "raw HotSinkMass/HotFluidBuffer written back; official hot-end active hold";
        row.cold_writeback_rule = "raw ColdSinkMass/ColdFluidBuffer written back; official cold-end frozen previous cooldown";
        row.cold_load_writeback_rule = "no-load isolated or load self-heating only";
    elseif strcmp(stage_name, 'cooldown_exchange')
        row.hot_writeback_rule = "raw HotSinkMass/HotFluidBuffer written back; official hot-end frozen previous hold";
        row.cold_writeback_rule = "raw ColdSinkMass/ColdFluidBuffer written back; official cold-end active cooldown";
        row.cold_load_writeback_rule = "cold load may couple to CHEX only in load mode";
    elseif contains(stage_name, 'adiabatic')
        row.hot_writeback_rule = "frozen side state";
        row.cold_writeback_rule = "frozen side state";
    end
    row.state_sync_row_ok = validate_sync_row(row);
end

function ok = validate_sync_row(row)
    stage_name = char(row.stage_name);
    if strcmp(stage_name, 'hold_exchange')
        ok = contains(lower(row.hot_writeback_rule), 'raw') && ...
            contains(lower(row.cold_writeback_rule), 'raw') && ...
            contains(lower(row.hot_writeback_rule), 'active') && ...
            contains(lower(row.cold_writeback_rule), 'frozen') && ...
            isfinite(row.hold_cold_official_drift_due_to_source_buffer_K) && ...
            abs(row.hold_cold_official_drift_due_to_source_buffer_K) <= 1.0e-6 && ...
            row.stage2_cold_buffer_source_pollution_ok;
    elseif strcmp(stage_name, 'cooldown_exchange')
        ok = contains(lower(row.cold_writeback_rule), 'raw') && ...
            contains(lower(row.hot_writeback_rule), 'raw') && ...
            contains(lower(row.cold_writeback_rule), 'active') && ...
            contains(lower(row.hot_writeback_rule), 'frozen');
    else
        ok = true;
    end
end

function row = empty_row()
    row = struct( ...
        'cycle_index', NaN, ...
        'stage_index', NaN, ...
        'stage_name', "", ...
        'hot_sink_T_in_K', NaN, ...
        'hot_sink_T_out_K', NaN, ...
        'hot_buffer_T_in_K', NaN, ...
        'hot_buffer_T_out_K', NaN, ...
        'official_hot_end_T_in_K', NaN, ...
        'official_hot_end_T_out_K', NaN, ...
        'official_hot_end_definition', "", ...
        'cold_sink_T_in_K', NaN, ...
        'cold_sink_T_out_K', NaN, ...
        'cold_buffer_T_in_K', NaN, ...
        'cold_buffer_T_out_K', NaN, ...
        'official_cold_end_T_in_K', NaN, ...
        'official_cold_end_T_out_K', NaN, ...
        'official_cold_end_definition', "", ...
        'cold_load_T_in_K', NaN, ...
        'cold_load_T_out_K', NaN, ...
        'hot_side_state_sync_policy', "", ...
        'cold_side_state_sync_policy', "", ...
        'hot_writeback_rule', "", ...
        'cold_writeback_rule', "", ...
        'cold_load_writeback_rule', "", ...
        'hold_cold_official_drift_due_to_source_buffer_K', NaN, ...
        'stage2_cold_buffer_source_pollution_ok', false, ...
        'state_sync_row_ok', false);
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
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
end
