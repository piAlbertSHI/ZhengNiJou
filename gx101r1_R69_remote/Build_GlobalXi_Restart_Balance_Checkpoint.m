function [balanced_checkpoint, balanced_checkpoint_path, report] = Build_GlobalXi_Restart_Balance_Checkpoint( ...
        source_checkpoint_input, exchange_checkpoint_input, balanced_checkpoint_path, metadata)
% Build a physically reconciled internal restart checkpoint after exchange.
% Stage 2 and stage 4 intentionally use different boundary assumptions.

    if nargin < 3
        balanced_checkpoint_path = '';
    end
    if nargin < 4 || isempty(metadata)
        metadata = struct();
    end

    source_state = GlobalXi_Checkpoint_To_Simulink_State(source_checkpoint_input);
    exchange_state = GlobalXi_Checkpoint_To_Simulink_State(exchange_checkpoint_input);
    assert_same_contract(source_state, exchange_state);

    stage_name = char(string(get_struct_field(metadata, 'stage_name', '')));
    metadata.balance_boundary_kind = get_struct_field(metadata, 'balance_boundary_kind', ...
        infer_balance_boundary_kind(stage_name));
    metadata.target_pressure_MPa = get_struct_field(metadata, 'target_pressure_MPa', ...
        default_target_pressure(stage_name, metadata, exchange_state));
    balance_options = get_struct_field(metadata, 'balance_options', struct());

    [balanced_checkpoint, balanced_checkpoint_path, report, result] = ...
        Solve_GlobalXi_Exchange_Restart_Balance(source_checkpoint_input, ...
        exchange_checkpoint_input, balanced_checkpoint_path, metadata, balance_options);

    source_to_exchange = compute_checkpoint_delta(source_state.checkpoint, exchange_state.checkpoint);
    exchange_to_balanced = compute_checkpoint_delta(exchange_state.checkpoint, balanced_checkpoint);
    source_to_balanced = compute_checkpoint_delta(source_state.checkpoint, balanced_checkpoint);

    report.source_checkpoint_path = source_state.path;
    report.exchange_checkpoint_path = exchange_state.path;
    report.balanced_checkpoint_path = balanced_checkpoint_path;
    report.restart_checkpoint_path = balanced_checkpoint_path;
    report.stage_name = stage_name;
    report.node_count = source_state.N;
    report.source_to_exchange_max_abs_delta_u = source_to_exchange.max_abs_delta_u;
    report.source_to_exchange_max_abs_delta_w = source_to_exchange.max_abs_delta_w;
    report.source_to_exchange_max_abs_delta_T = source_to_exchange.max_abs_delta_T;
    report.source_to_exchange_max_abs_delta_xi = source_to_exchange.max_abs_delta_xi;
    report.exchange_to_restart_max_abs_delta_Y = exchange_to_balanced.max_abs_delta_Y;
    report.exchange_to_restart_max_abs_delta_u = exchange_to_balanced.max_abs_delta_u;
    report.exchange_to_restart_max_abs_delta_w = exchange_to_balanced.max_abs_delta_w;
    report.exchange_to_restart_max_abs_delta_T = exchange_to_balanced.max_abs_delta_T;
    report.exchange_to_restart_max_abs_delta_xi = exchange_to_balanced.max_abs_delta_xi;
    report.source_to_restart_max_abs_delta_Y = source_to_balanced.max_abs_delta_Y;
    report.source_to_restart_max_abs_delta_u = source_to_balanced.max_abs_delta_u;
    report.source_to_restart_max_abs_delta_w = source_to_balanced.max_abs_delta_w;
    report.source_to_restart_max_abs_delta_T = source_to_balanced.max_abs_delta_T;
    report.source_to_restart_max_abs_delta_xi = source_to_balanced.max_abs_delta_xi;
    report.temperature_only_update = false;
    report.u_preserved_from_source = source_to_balanced.max_abs_delta_u == 0;
    report.w_preserved_from_source = source_to_balanced.max_abs_delta_w == 0;
    report.xi_preserved_from_source = source_to_balanced.max_abs_delta_xi == 0;
    report.state_preserved_from_exchange = isequaln(exchange_state.checkpoint.state, balanced_checkpoint.state);
    report.grid_preserved_from_exchange = isequaln(exchange_state.checkpoint.grid, balanced_checkpoint.grid);
    report.params_preserved_from_exchange = isequaln(exchange_state.checkpoint.params, balanced_checkpoint.params);

    if ~(isfield(result, 'ok') && result.ok)
        error('Build_GlobalXi_Restart_Balance_Checkpoint:BalanceFailed', ...
            'Restart balance failed for %s: %s', stage_name, get_struct_field(report, 'balance_failure_reason', 'unknown'));
    end
end

function boundary_kind = infer_balance_boundary_kind(stage_name)
    switch stage_name
        case 'hold_exchange'
            boundary_kind = 'hold_closed_hydraulic_volume_simplified';
        case 'cooldown_exchange'
            boundary_kind = 'cooldown_zero_pressure_free_recovery';
        otherwise
            error('Build_GlobalXi_Restart_Balance_Checkpoint:UnknownStage', ...
                'Restart balance only supports hold_exchange/cooldown_exchange, got "%s".', stage_name);
    end
end

function target_pressure_MPa = default_target_pressure(stage_name, metadata, exchange_state)
    if strcmp(stage_name, 'cooldown_exchange')
        target_pressure_MPa = 0.0;
        return;
    end
    target_pressure_MPa = get_struct_field(metadata, 'pressure_MPa', exchange_state.pressure_MPa);
end

function assert_same_contract(source_state, exchange_state)
    if source_state.N ~= exchange_state.N
        error('Build_GlobalXi_Restart_Balance_Checkpoint:NodeCountMismatch', ...
            'Source N=%d, exchange N=%d.', source_state.N, exchange_state.N);
    end
    if numel(source_state.Y) ~= numel(exchange_state.Y)
        error('Build_GlobalXi_Restart_Balance_Checkpoint:YLengthMismatch', ...
            'Source Y length %d, exchange Y length %d.', numel(source_state.Y), numel(exchange_state.Y));
    end
    if any(~isfinite(exchange_state.Y(:)))
        error('Build_GlobalXi_Restart_Balance_Checkpoint:InvalidExchangeY', ...
            'Exchange checkpoint Y contains non-finite values.');
    end
end

function delta = compute_checkpoint_delta(a_checkpoint, b_checkpoint)
    a_state = GlobalXi_Checkpoint_To_Simulink_State(a_checkpoint);
    b_state = GlobalXi_Checkpoint_To_Simulink_State(b_checkpoint);
    dY = b_state.Y(:) - a_state.Y(:);
    delta = struct( ...
        'max_abs_delta_Y', max(abs(dY)), ...
        'max_abs_delta_u', max(abs(dY(a_state.u_idx))), ...
        'max_abs_delta_w', max(abs(dY(a_state.w_idx))), ...
        'max_abs_delta_T', max(abs(dY(a_state.T_idx))), ...
        'max_abs_delta_xi', max(abs(dY(a_state.xi_idx))));
end

function value = get_struct_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
