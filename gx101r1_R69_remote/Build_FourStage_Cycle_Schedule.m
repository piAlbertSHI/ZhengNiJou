function [stage_descriptors, q_load_func] = Build_FourStage_Cycle_Schedule(options)
% Build the physical four-stage adiabatic/exchange cycle schedule.

    if nargin < 1 || isempty(options)
        options = struct();
    end

    options = normalize_schedule_options(options);
    q_load_func = @(t) four_stage_cycle_load(t, options);

    load_segments = build_scaled_loading_segments( ...
        options.loading_forward_points, ...
        options.strong_peak_window_refine, ...
        options.strong_grid_profile, ...
        0.0, 0.1);
    hold_vec = linspace(0.1, 0.5, max(12, round(options.full_hold_points)));
    unload_vec = build_scaled_unloading_grid(options.full_unload_points, 0.5, 0.6);
    cooldown_vec = linspace(0.6, 1.0, max(12, round(options.cooldown_exchange_points)));

    stage_descriptors = [ ...
        make_stage_descriptor( ...
            'load_adiabatic', 0.0, 0.1, load_segments, ...
            'loading', 'adiabatic', 'ramp_up', 0.0, options.P_max), ...
        make_stage_descriptor( ...
            'hold_exchange', 0.1, 0.5, {hold_vec}, ...
            'hold', 'exchange', 'hold_max', options.P_max, options.P_max), ...
        make_stage_descriptor( ...
            'unload_adiabatic', 0.5, 0.6, {unload_vec}, ...
            'unloading', 'adiabatic', 'ramp_down', options.P_max, 0.0), ...
        make_stage_descriptor( ...
            'cooldown_exchange', 0.6, 1.0, {cooldown_vec}, ...
            'idle', 'exchange', 'hold_zero', 0.0, 0.0)];
end

function options = normalize_schedule_options(options)
    options = set_default_field(options, 'P_max', 0.59e6);
    options = set_default_field(options, 'load_power', 5);
    options = set_default_field(options, 'unload_power', 1.0);
    options = set_default_field(options, 'loading_forward_points', 64);
    options = set_default_field(options, 'full_hold_points', 25);
    options = set_default_field(options, 'full_unload_points', 120);
    options = set_default_field(options, 'cooldown_exchange_points', options.full_hold_points);
    options = set_default_field(options, 'strong_peak_window_refine', false);
    options = set_default_field(options, 'strong_grid_profile', 'baseline');
end

function stage = make_stage_descriptor(stage_name, t_start, t_end, solver_time_segments, ...
                                      mechanical_mode, thermal_mode, pressure_mode, ...
                                      pressure_start_Pa, pressure_end_Pa)
    stage = struct( ...
        'stage_name', stage_name, ...
        't_start', t_start, ...
        't_end', t_end, ...
        'time_vec', merge_solver_time_segments(solver_time_segments), ...
        'solver_time_segments', {solver_time_segments}, ...
        'mechanical_mode', mechanical_mode, ...
        'thermal_mode', thermal_mode, ...
        'pressure_mode', pressure_mode, ...
        'pressure_start_Pa', pressure_start_Pa, ...
        'pressure_end_Pa', pressure_end_Pa);
end

function time_vec = merge_solver_time_segments(solver_time_segments)
    time_vec = [];
    for seg_id = 1:numel(solver_time_segments)
        time_vec = [time_vec, solver_time_segments{seg_id}(:).']; %#ok<AGROW>
    end
    time_vec = unique(time_vec, 'stable');
end

function q = four_stage_cycle_load(t, options)
    q = zeros(size(t));

    mask_load = (t >= 0.0) & (t <= 0.1);
    tau_load = clamp01(t(mask_load) / 0.1);
    q(mask_load) = options.P_max .* tau_load .^ options.load_power;

    mask_hold = (t > 0.1) & (t <= 0.5);
    q(mask_hold) = options.P_max;

    mask_unload = (t > 0.5) & (t <= 0.6);
    tau_unload = clamp01((t(mask_unload) - 0.5) / 0.1);
    q(mask_unload) = options.P_max .* max(0.0, 1.0 - tau_unload) .^ options.unload_power;

    mask_cooldown = (t > 0.6);
    q(mask_cooldown) = 0.0;
end

function time_segments = build_scaled_loading_segments(point_count, strong_peak_window_refine, grid_profile, t_start, t_end)
    if strong_peak_window_refine
        base_segments = build_strong_loading_segments(point_count, grid_profile);
    else
        base_segments = build_forward_loading_segments(point_count);
    end
    time_segments = scale_time_segments(base_segments, t_start, t_end);
end

function time_segments = build_forward_loading_segments(point_count)
    point_count = max(36, round(point_count));

    n1 = max(8, round(0.18 * point_count));
    n2 = max(8, round(0.20 * point_count));
    n3 = max(10, round(0.26 * point_count));
    n4 = max(10, round(0.20 * point_count));
    n5 = max(8, point_count - n1 - n2 - n3 - n4 + 4);

    time_segments = { ...
        linspace(0.0, 0.65, n1), ...
        linspace(0.65, 0.80, n2), ...
        linspace(0.80, 0.88, n3), ...
        linspace(0.88, 0.92, n4), ...
        linspace(0.92, 1.00, n5)};
end

function time_segments = build_strong_loading_segments(point_count, grid_profile)
    point_count = max(60, round(point_count));
    grid_profile = lower(string(grid_profile));

    mins = [8, 8, 10, 10, 10, 12, 10];
    switch grid_profile
        case "baseline"
            weights = [0.12, 0.10, 0.16, 0.14, 0.12, 0.18, 0.18];
        case "early_dense"
            weights = [0.11, 0.12, 0.19, 0.13, 0.11, 0.17, 0.17];
        case "tail_dense"
            weights = [0.12, 0.09, 0.14, 0.13, 0.12, 0.19, 0.21];
        otherwise
            error('Build_FourStage_Cycle_Schedule:UnknownStrongGridProfile', ...
                'Unknown strong_grid_profile: %s', char(grid_profile));
    end

    counts = allocate_segment_counts(point_count, weights, mins);
    time_segments = { ...
        linspace(0.0, 0.65, counts(1)), ...
        linspace(0.65, 0.72, counts(2)), ...
        linspace(0.72, 0.82, counts(3)), ...
        linspace(0.82, 0.90, counts(4)), ...
        linspace(0.90, 0.94, counts(5)), ...
        linspace(0.94, 0.98, counts(6)), ...
        linspace(0.98, 1.00, counts(7))};
end

function unload_vec = build_scaled_unloading_grid(point_count, t_start, t_end)
    point_count = max(70, round(point_count));
    n1 = max(18, round(0.24 * point_count));
    n2 = max(24, round(0.40 * point_count));
    n3 = max(20, point_count - n1 - n2 + 2);

    base_vec = unique([ ...
        linspace(0.0, 0.18, n1), ...
        linspace(0.18, 0.55, n2), ...
        linspace(0.55, 1.00, n3)]);
    unload_vec = t_start + (t_end - t_start) .* base_vec;
end

function scaled_segments = scale_time_segments(base_segments, t_start, t_end)
    scaled_segments = cell(size(base_segments));
    for seg_id = 1:numel(base_segments)
        scaled_segments{seg_id} = t_start + (t_end - t_start) .* base_segments{seg_id};
    end
end

function counts = allocate_segment_counts(total_points, weights, mins)
    total_points = max(sum(mins), round(total_points));
    weights = weights(:).';
    mins = mins(:).';

    raw = total_points * weights;
    counts = max(mins, floor(raw));
    remainder = total_points - sum(counts);

    if remainder > 0
        priority = raw - counts;
        while remainder > 0
            [~, idx] = max(priority);
            counts(idx) = counts(idx) + 1;
            priority(idx) = priority(idx) - 1.0;
            remainder = remainder - 1;
        end
    elseif remainder < 0
        slack = counts - mins;
        priority = (raw - counts) + 1.0e-6 * slack;
        while remainder < 0
            eligible = find(slack > 0);
            if isempty(eligible)
                break;
            end
            [~, local_idx] = min(priority(eligible));
            idx = eligible(local_idx);
            counts(idx) = counts(idx) - 1;
            slack(idx) = slack(idx) - 1;
            priority(idx) = priority(idx) + 1.0;
            remainder = remainder + 1;
        end
    end
end

function values = clamp01(values)
    values = max(0.0, min(1.0, values));
end

function s = set_default_field(s, field_name, default_value)
    if ~isfield(s, field_name) || isempty(s.(field_name))
        s.(field_name) = default_value;
    end
end
