function timeline = Build_GX101R1_Continuous_Probe_Timeline(run_result, probe_spec)
% Build one continuous global-time curve for a fixed probe or active-path alias.

    if ischar(probe_spec) || isstring(probe_spec)
        probe_spec = struct('field', char(probe_spec));
    end
    field_name = char(string(get_field(probe_spec, 'field', '')));
    scalar_field = char(string(get_field(probe_spec, 'scalar_field', field_name)));
    display_name = char(string(get_field(probe_spec, 'display_name', field_name)));
    semantics = char(string(get_field(probe_spec, 'semantics', '')));

    timeline = struct( ...
        'field', field_name, ...
        'scalar_field', scalar_field, ...
        'display_name', display_name, ...
        'semantics', semantics, ...
        'time_s', [], ...
        'value', [], ...
        'cycle_index', [], ...
        'stage_index', [], ...
        'stage_name', {{}}, ...
        'source_kind', {{}}, ...
        'ok', false);

    reports = collect_ordered_stage_reports(run_result);
    last_t = NaN;
    last_y = NaN;
    for idx = 1:numel(reports)
        report = reports(idx);
        [t_segment, y_segment, source_kind] = extract_probe_segment(report, field_name, scalar_field);
        if isempty(t_segment) || isempty(y_segment)
            continue;
        end
        t_segment = t_segment(:);
        y_segment = y_segment(:);
        valid = isfinite(t_segment) & isfinite(y_segment);
        t_segment = t_segment(valid);
        y_segment = y_segment(valid);
        if isempty(t_segment)
            continue;
        end

        if isfinite(last_t) && isfinite(last_y) && t_segment(1) > last_t
            timeline = append_point(timeline, t_segment(1), last_y, report, 'held_across_no_exchange_stage');
        end
        for j = 1:numel(t_segment)
            if ~isempty(timeline.time_s) && t_segment(j) == timeline.time_s(end) && y_segment(j) == timeline.value(end)
                continue;
            end
            timeline = append_point(timeline, t_segment(j), y_segment(j), report, source_kind);
        end
        last_t = t_segment(end);
        last_y = y_segment(end);
    end

    if ~isempty(timeline.time_s)
        [timeline.time_s, order] = sort(timeline.time_s(:).');
        timeline.value = timeline.value(order);
        timeline.cycle_index = timeline.cycle_index(order);
        timeline.stage_index = timeline.stage_index(order);
        timeline.stage_name = timeline.stage_name(order);
        timeline.source_kind = timeline.source_kind(order);
        timeline.ok = any(isfinite(timeline.value));
    end
end

function [t, y, source_kind] = extract_probe_segment(report, field_name, scalar_field)
    t = [];
    y = [];
    source_kind = '';
    if isfield(report, field_name) && isnumeric(report.(field_name)) && numel(report.(field_name)) > 1
        y = report.(field_name)(:);
        t = probe_time(report, numel(y));
        source_kind = 'resampled_stage_timeseries';
        return;
    end
    if isfield(report, scalar_field) && isnumeric(report.(scalar_field)) && ~isempty(report.(scalar_field))
        y = report.(scalar_field)(end);
        t = scalar_time(report);
        source_kind = 'stage_terminal_scalar';
    end
end

function t = probe_time(report, n)
    if isfield(report, 'probe_time_global_s') && isnumeric(report.probe_time_global_s) && numel(report.probe_time_global_s) == n
        t = report.probe_time_global_s(:);
    elseif isfield(report, 'probe_time_local_s') && isnumeric(report.probe_time_local_s) && numel(report.probe_time_local_s) == n
        t = report.probe_time_local_s(:);
    else
        t0 = scalar_time(report);
        t = linspace(max(t0 - 1, 0), t0, n).';
    end
end

function t = scalar_time(report)
    if isfield(report, 'probe_time_global_s') && isnumeric(report.probe_time_global_s) && ~isempty(report.probe_time_global_s)
        t = report.probe_time_global_s(end);
    else
        t = get_field(report, 'time_s', NaN);
    end
    if ~isfinite(t)
        t = get_field(report, 'stage_index', 0);
    end
end

function timeline = append_point(timeline, t, y, report, source_kind)
    timeline.time_s(end + 1) = t;
    timeline.value(end + 1) = y;
    timeline.cycle_index(end + 1) = get_field(report, 'cycle_index', NaN);
    timeline.stage_index(end + 1) = get_field(report, 'stage_index', NaN);
    timeline.stage_name{end + 1} = char(string(get_field(report, 'stage_name', '')));
    timeline.source_kind{end + 1} = source_kind;
end

function reports = collect_ordered_stage_reports(run_result)
    reports = struct([]);
    cycles = reshape(get_field(run_result, 'cycle_results', struct([])), 1, []);
    for cidx = 1:numel(cycles)
        stage_reports = reshape(get_field(cycles(cidx), 'stage_reports', struct([])), 1, []);
        for sidx = 1:numel(stage_reports)
            if is_exchange_stage(stage_reports(sidx))
                if isempty(reports)
                    reports = stage_reports(sidx);
                else
                    reports(end + 1) = stage_reports(sidx); %#ok<AGROW>
                end
            end
        end
    end
end

function tf = is_exchange_stage(report)
    stage_name = char(string(get_field(report, 'stage_name', '')));
    tf = strcmp(stage_name, 'hold_exchange') || strcmp(stage_name, 'cooldown_exchange');
end

function value = get_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
