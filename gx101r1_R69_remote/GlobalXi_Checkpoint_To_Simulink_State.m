function state_std = GlobalXi_Checkpoint_To_Simulink_State(checkpoint_input)
% Convert a GlobalXi checkpoint/state into the state shape expected by exchange code.

    checkpoint = load_checkpoint_like(checkpoint_input);
    validate_checkpoint(checkpoint);

    Y = checkpoint.Y(:);
    grid = checkpoint.grid;
    params = checkpoint.params;
    N = grid.N;
    u_idx = 1:N;
    w_idx = N + (1:N);
    T_idx = 2 * N + (1:N);
    xi_idx = 3 * N + (1:N);

    pressure_MPa = get_struct_field(checkpoint, 'pressure_MPa', NaN);
    if ~isfinite(pressure_MPa) && isfield(params, 'Pmax')
        pressure_MPa = params.Pmax / 1.0e6;
    end

    state_std = struct();
    state_std.source_kind = 'globalxi_checkpoint';
    state_std.checkpoint = checkpoint;
    state_std.Y = Y;
    state_std.state = checkpoint.state;
    state_std.grid = grid;
    state_std.params = params;
    state_std.N = N;
    state_std.u_idx = u_idx;
    state_std.w_idx = w_idx;
    state_std.T_idx = T_idx;
    state_std.xi_idx = xi_idx;
    state_std.u = Y(u_idx);
    state_std.w = Y(w_idx);
    state_std.T = Y(T_idx);
    state_std.xi = Y(xi_idx);
    state_std.pressure_MPa = pressure_MPa;
    state_std.time_s = get_struct_field(checkpoint, 'time_s', NaN);
    state_std.path = get_struct_field(checkpoint, 'path', '');
end

function checkpoint = load_checkpoint_like(input_value)
    if ischar(input_value) || isstring(input_value)
        path_value = char(string(input_value));
        data = load(path_value, 'checkpoint');
        checkpoint = data.checkpoint;
        if ~isfield(checkpoint, 'path') || isempty(checkpoint.path)
            checkpoint.path = path_value;
        end
        return;
    end

    if isstruct(input_value) && isfield(input_value, 'checkpoint')
        checkpoint = input_value.checkpoint;
        return;
    end

    if isstruct(input_value) && isfield(input_value, 'Y') && ...
            isfield(input_value, 'grid') && isfield(input_value, 'params')
        checkpoint = input_value;
        return;
    end

    if isstruct(input_value) && isfield(input_value, 'Y') && ...
            isfield(input_value, 'N') && isfield(input_value, 'T_idx')
        checkpoint = input_value.checkpoint;
        return;
    end

    error('GlobalXi_Checkpoint_To_Simulink_State:UnsupportedInput', ...
        'Input must be a checkpoint path, checkpoint struct, or standardized GlobalXi state.');
end

function validate_checkpoint(checkpoint)
    required_fields = {'Y', 'state', 'grid', 'params'};
    for idx = 1:numel(required_fields)
        if ~isstruct(checkpoint) || ~isfield(checkpoint, required_fields{idx})
            error('GlobalXi_Checkpoint_To_Simulink_State:MissingField', ...
                'Checkpoint is missing field "%s".', required_fields{idx});
        end
    end

    if ~isfield(checkpoint.grid, 'N') || isempty(checkpoint.grid.N)
        error('GlobalXi_Checkpoint_To_Simulink_State:MissingNodeCount', ...
            'checkpoint.grid.N is required.');
    end
    N = checkpoint.grid.N;
    if numel(checkpoint.Y) ~= 4 * N
        error('GlobalXi_Checkpoint_To_Simulink_State:InvalidYLength', ...
            'Expected Y length 4*N = %d, got %d.', 4 * N, numel(checkpoint.Y));
    end
    if N ~= 51
        error('GlobalXi_Checkpoint_To_Simulink_State:UnexpectedNodeCount', ...
            'Simulink exchange expects N=51, got N=%d.', N);
    end
    if any(~isfinite(checkpoint.Y(:)))
        error('GlobalXi_Checkpoint_To_Simulink_State:InvalidY', ...
            'Checkpoint Y contains non-finite values.');
    end
end

function value = get_struct_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
