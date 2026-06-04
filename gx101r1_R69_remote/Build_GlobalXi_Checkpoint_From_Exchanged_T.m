function [checkpoint, checkpoint_path, report] = Build_GlobalXi_Checkpoint_From_Exchanged_T( ...
        checkpoint_input, T51_after_exchange, output_path, metadata)
% Build a GlobalXi restart checkpoint by replacing only the 51-node T segment.

    if nargin < 3
        output_path = '';
    end
    if nargin < 4 || isempty(metadata)
        metadata = struct();
    end

    state_std = GlobalXi_Checkpoint_To_Simulink_State(checkpoint_input);
    checkpoint = state_std.checkpoint;
    T51_after_exchange = T51_after_exchange(:);
    N = state_std.N;
    if numel(T51_after_exchange) ~= N || any(~isfinite(T51_after_exchange))
        error('Build_GlobalXi_Checkpoint_From_Exchanged_T:InvalidTemperature', ...
            'Expected %d finite temperature values, got %d.', N, numel(T51_after_exchange));
    end

    Y_old = checkpoint.Y(:);
    T_old = Y_old(state_std.T_idx);
    Y_new = Y_old;
    Y_new(state_std.T_idx) = T51_after_exchange;

    checkpoint.Y = Y_new;
    checkpoint.pressure_MPa = get_struct_field(metadata, 'pressure_MPa', state_std.pressure_MPa);
    checkpoint.time_s = get_struct_field(metadata, 'time_s', state_std.time_s);
    checkpoint.exchange_stage_name = get_struct_field(metadata, 'stage_name', '');
    checkpoint.exchange_source_checkpoint = state_std.path;
    checkpoint.created_at = char(datetime('now', 'TimeZone', 'local', 'Format', 'yyyy-MM-dd HH:mm:ssXXX'));
    if ~isempty(output_path)
        checkpoint.path = char(string(output_path));
    else
        checkpoint.path = state_std.path;
    end
    checkpoint.latent_area_avg_J_m3 = compute_latent_area_avg(checkpoint, N, state_std.xi_idx, state_std.T_idx);

    checkpoint_path = '';
    if ~isempty(output_path)
        checkpoint_path = char(string(output_path));
        checkpoint_dir = fileparts(checkpoint_path);
        if ~isempty(checkpoint_dir) && ~exist(checkpoint_dir, 'dir')
            mkdir(checkpoint_dir);
        end
        save(checkpoint_path, 'checkpoint');
    end

    report = struct( ...
        'source_checkpoint_path', state_std.path, ...
        'output_checkpoint_path', checkpoint_path, ...
        'node_count', N, ...
        'temperature_only_update', true, ...
        'max_abs_delta_T_K', max(abs(T51_after_exchange - T_old)), ...
        'mean_delta_T_K', mean(T51_after_exchange - T_old), ...
        'u_unchanged', isequaln(Y_old(state_std.u_idx), Y_new(state_std.u_idx)), ...
        'w_unchanged', isequaln(Y_old(state_std.w_idx), Y_new(state_std.w_idx)), ...
        'xi_unchanged', isequaln(Y_old(state_std.xi_idx), Y_new(state_std.xi_idx)), ...
        'state_preserved', true, ...
        'grid_preserved', true, ...
        'params_preserved', true);
end

function value = compute_latent_area_avg(checkpoint, N, xi_idx, T_idx)
    value = NaN;
    if ~isfield(checkpoint, 'params') || ~isfield(checkpoint, 'grid')
        return;
    end
    params = checkpoint.params;
    grid = checkpoint.grid;
    required = {'rho', 'ds0'};
    for idx = 1:numel(required)
        if ~isfield(params, required{idx})
            return;
        end
    end
    if ~isfield(grid, 'r') || ~isfield(grid, 'dr') || numel(grid.r) ~= N
        return;
    end
    T = checkpoint.Y(T_idx);
    xi = checkpoint.Y(xi_idx);
    value = area_average(abs(params.rho * params.ds0) * T .* xi, grid);
end

function avg = area_average(values, grid)
    r = grid.r(:);
    weights = r;
    weights(1) = grid.dr / 4;
    if sum(weights) <= 0
        avg = mean(values(:));
    else
        avg = sum(values(:) .* weights(:)) / sum(weights);
    end
end

function value = get_struct_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
