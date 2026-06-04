function batch_result = Run_GlobalXi_Cooled_Unloading_Prototype(options)
% Run GlobalXi unloading after applying a uniform temperature drop to a loading checkpoint.
% Only the nodal temperature entries in Y are modified; u, w, xi, state, grid, and params remain unchanged.
    if nargin < 1 || ~isstruct(options)
        options = struct();
    end
    options = apply_defaults(options);
    if ~isfield(options, 'initial_checkpoint') || isempty(options.initial_checkpoint)
        error('Run_GlobalXi_Cooled_Unloading_Prototype:MissingCheckpoint', ...
            'options.initial_checkpoint is required.');
    end

    base_checkpoint_path = char(string(options.initial_checkpoint));
    if ~exist(base_checkpoint_path, 'file')
        loading_options = options;
        loading_options.save_checkpoint_path = base_checkpoint_path;
        loading_options = rmfield_if_present(loading_options, 'initial_checkpoint');
        loading_options = rmfield_if_present(loading_options, 'cooled_checkpoint_path');
        loading_options = rmfield_if_present(loading_options, 'temperature_drop_K');
        loading_result = Run_GlobalXi_Time_Loading_Prototype(loading_options);
        if ~(isfield(loading_result, 'ok') && loading_result.ok)
            batch_result = loading_result;
            batch_result.ok = false;
            batch_result.failure_reason = 'cooled_unloading_checkpoint_build_failed';
            batch_result.summary = sprintf('cooled unloading skipped | checkpoint build failed | base=%s', base_checkpoint_path);
            return;
        end
    end

    cooled_checkpoint_path = get_cooled_checkpoint_path(options, base_checkpoint_path);
    make_cooled_checkpoint(base_checkpoint_path, cooled_checkpoint_path, options.temperature_drop_K);

    unload_options = options;
    unload_options.initial_checkpoint = cooled_checkpoint_path;
    batch_result = GlobalXi_TimeStep_Core('unloading', unload_options);
    batch_result.metrics.cooled_temperature_drop_K = options.temperature_drop_K;
    batch_result.metrics.cooled_checkpoint_path = cooled_checkpoint_path;
    batch_result.metrics.cooled_base_checkpoint_path = base_checkpoint_path;
    batch_result.summary_metrics = batch_result.metrics;
    batch_result.diagnostics_handle.cooled_temperature_drop_K = options.temperature_drop_K;
    batch_result.diagnostics_handle.cooled_checkpoint_path = cooled_checkpoint_path;
    batch_result.summary = sprintf('%s | cooled_drop=%.3f K | cooled_checkpoint=%s', ...
        batch_result.summary, options.temperature_drop_K, cooled_checkpoint_path);
end

function options = apply_defaults(options)
    options.N = get_field(options, 'N', 51);
    options.Nt = get_field(options, 'Nt', 960);
    options.Nt_unload = get_field(options, 'Nt_unload', options.Nt);
    options.Tr = get_field(options, 'Tr', 293);
    options.Hfor = get_field(options, 'Hfor', 1.1e6);
    options.Pmax = get_field(options, 'Pmax', 0.59e6);
    options.T_load = get_field(options, 'T_load', 0.1);
    options.T_unload = get_field(options, 'T_unload', 0.1);
    options.ds0 = get_field(options, 'ds0', -35);
    options.hc = get_field(options, 'hc', 0);
    options.temperature_drop_K = get_field(options, 'temperature_drop_K', 20);
end

function path_value = get_cooled_checkpoint_path(options, base_checkpoint_path)
    if isfield(options, 'cooled_checkpoint_path') && ~isempty(options.cooled_checkpoint_path)
        path_value = char(string(options.cooled_checkpoint_path));
        return;
    end
    [folder, name, ext] = fileparts(base_checkpoint_path);
    if isempty(folder)
        folder = fullfile('results', 'checkpoints');
    end
    drop_token = numeric_token(options.temperature_drop_K);
    path_value = fullfile(folder, sprintf('%s_cooldrop%sK%s', name, drop_token, ext));
end

function make_cooled_checkpoint(base_checkpoint_path, cooled_checkpoint_path, temperature_drop_K)
    data = load(base_checkpoint_path, 'checkpoint');
    checkpoint = data.checkpoint;
    N = checkpoint.grid.N;
    T_idx = 2 * N + (1:N);
    checkpoint.Y(T_idx) = checkpoint.Y(T_idx) - temperature_drop_K;
    checkpoint.cooled_temperature_drop_K = temperature_drop_K;
    checkpoint.base_checkpoint_path = base_checkpoint_path;
    checkpoint.path = cooled_checkpoint_path;
    checkpoint.created_at = char(datetime('now', 'TimeZone', 'local', 'Format', 'yyyy-MM-dd HH:mm:ssXXX'));
    checkpoint_dir = fileparts(cooled_checkpoint_path);
    if ~isempty(checkpoint_dir) && ~exist(checkpoint_dir, 'dir')
        mkdir(checkpoint_dir);
    end
    save(cooled_checkpoint_path, 'checkpoint');
end

function token = numeric_token(value)
    token = regexprep(sprintf('%.6g', value), '\.', 'p');
    token = regexprep(token, '-', 'm');
end

function s = rmfield_if_present(s, field_name)
    if isfield(s, field_name)
        s = rmfield(s, field_name);
    end
end

function value = get_field(s, name, default_value)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = default_value;
    end
end
