function stage_config = Resolve_Exchange_Stage_Config(stage_info, exchange_options)
% Resolve a deterministic Simulink configuration for one physical stage.

    if nargin < 2 || isempty(exchange_options)
        exchange_options = struct();
    end

    runtime = get_option_field(exchange_options, 'runtime', struct());
    model_path = get_option_field(runtime, 'model_path', '');
    if isempty(model_path)
        model_path = get_option_field(exchange_options, 'model_path', '');
    end
    if isempty(model_path)
        model_path = fullfile(fileparts(mfilename('fullpath')), ...
            'heatdrive_ecc_coupled_se21.slx');
    end
    [~, model_name] = fileparts(model_path);

    ambient_T_init = get_option_field(runtime, 'ambient_T_init', get_option_field(exchange_options, 'ambient_T_init', 293.0));
    hot_sink_temp_in = get_option_field(runtime, 'hot_sink_temp_current', get_option_field(exchange_options, 'hot_sink_T_init', ambient_T_init));
    cold_sink_temp_in = get_option_field(runtime, 'cold_sink_temp_current', get_option_field(exchange_options, 'cold_sink_T_init', ambient_T_init));
    chip_temp_in = get_option_field(runtime, 'cold_load_temp_current', ...
        get_option_field(runtime, 'chip_temp_current', ...
        get_option_field(exchange_options, 'cold_load_T_init', get_option_field(exchange_options, 'chip_T_init', 293.0))));
    hot_buffer_temp_in = get_option_field(runtime, 'hot_buffer_temp_current', hot_sink_temp_in);
    cold_buffer_temp_in = get_option_field(runtime, 'cold_buffer_temp_current', cold_sink_temp_in);
    closed_branch_flow_warning_threshold = get_option_field(exchange_options, 'closed_branch_flow_warning_threshold', 1.0e-2);
    closed_branch_flow_ideal_threshold = get_option_field(exchange_options, 'closed_branch_flow_ideal_threshold', 1.0e-3);

    stage_name = char(string(get_option_field(stage_info, 'stage_name', '')));
    stage_duration_s = get_stage_duration(stage_info);
    valve_names = {'V1_cold_inlet', 'V2_hot_return', 'V3_sma_to_hot', ...
        'V4_hot_inlet', 'V5_cold_return', 'V6_sma_to_chip_cold'};

    switch stage_name
        case {'load_adiabatic', 'sma_heat_load'}
            stage_kind = 'globalxi_adiabatic_closed';
            L_valve = zeros(1, 6);
            stop_time_s = stage_duration_s;
            flow_path_name = 'sma_stage1_shex_to_sma_to_shex';
            flow_path_description = ['SE-side V1-V6 valves closed; SMA-side route is controlled by ', ...
                'SMA_L_valve_command as SHEX buffer -> SMA pump -> SMA Conn1/Conn2 -> SHEX -> SHEX buffer.'];
            side_thermal_state_mode = 'frozen_side_state';
            apply_temperature_back_to_state = false;
            all_valves_closed = true;
            sma_stage13_active = true;
            sma_stage13_route_name = 'shex_buffer_to_sma_to_shex';

        case {'hold_exchange', 'se_reject_heat'}
            stage_kind = 'hotflush';
            L_valve = [1 1 1 0 0 0];
            stop_time_s = get_option_field(exchange_options, 'hotflush_stop_time_s', 0.4);
            flow_path_name = 'chex_to_se_to_hhex';
            flow_path_description = 'CHEX/cold-side fluid buffer -> V1 -> SE21 stage-2 segment -> V3 -> HHEX/hot sink; cold load is isolated from the active fluid path.';
            side_thermal_state_mode = 'active_exchange_stage_cold_load_isolated';
            apply_temperature_back_to_state = true;
            all_valves_closed = false;
            sma_stage13_active = false;
            sma_stage13_route_name = 'sma_stage13_inactive';

        case {'unload_adiabatic', 'sma_cool_unload'}
            stage_kind = 'globalxi_adiabatic_closed';
            L_valve = zeros(1, 6);
            stop_time_s = stage_duration_s;
            flow_path_name = 'sma_stage3_hhex_to_sma_to_hhex';
            flow_path_description = ['SE-side V1-V6 valves closed; SMA-side route is controlled by ', ...
                'SMA_L_valve_command as HHEX/hot buffer -> SMA pump -> SMA Conn3/Conn4 -> HHEX SMA branch -> hot buffer.'];
            side_thermal_state_mode = 'frozen_side_state';
            apply_temperature_back_to_state = false;
            all_valves_closed = true;
            sma_stage13_active = true;
            sma_stage13_route_name = 'hhex_buffer_to_sma_to_hhex';

        case {'cooldown_exchange', 'se_absorb_heat'}
            stage_kind = 'coldflush';
            L_valve = [0 0 0 1 1 1];
            stop_time_s = get_option_field(exchange_options, 'coldflush_stop_time_s', 0.4);
            flow_path_name = 'hhex_to_se_to_chex';
            flow_path_description = 'HHEX/hot-side fluid buffer -> V4 -> SE21 stage-4 segment -> V6 -> CHEX/ColdSinkPipe -> cold return; cold load couples thermally to CHEX without being in the fluid line.';
            side_thermal_state_mode = 'active_exchange_stage_cold_load_to_CHEX';
            apply_temperature_back_to_state = true;
            all_valves_closed = false;
            sma_stage13_active = false;
            sma_stage13_route_name = 'sma_stage13_inactive';

        otherwise
            error('Resolve_Exchange_Stage_Config:UnsupportedStage', ...
                'Unsupported exchange/thermal stage: %s', stage_name);
    end

    stage_config = struct( ...
        'stage_name', stage_name, ...
        'stage_kind', stage_kind, ...
        'L_valve', L_valve, ...
        'valve_names', {valve_names}, ...
        'stop_time_s', stop_time_s, ...
        'ambient_T_init', ambient_T_init, ...
        'hot_sink_T_in', hot_sink_temp_in, ...
        'cold_sink_T_in', cold_sink_temp_in, ...
        'chip_T_in', chip_temp_in, ...
        'cold_load_T_in', chip_temp_in, ...
        'hot_buffer_T_in', hot_buffer_temp_in, ...
        'cold_buffer_T_in', cold_buffer_temp_in, ...
        'hot_source_in', hot_sink_temp_in, ...
        'model_path', model_path, ...
        'model_name', model_name, ...
        'flow_path_name', flow_path_name, ...
        'flow_path_description', flow_path_description, ...
        'side_thermal_state_mode', side_thermal_state_mode, ...
        'closed_branch_flow_warning_threshold', closed_branch_flow_warning_threshold, ...
        'closed_branch_flow_ideal_threshold', closed_branch_flow_ideal_threshold, ...
        'all_valves_closed', all_valves_closed, ...
        'sma_stage13_active', sma_stage13_active, ...
        'sma_stage13_route_name', sma_stage13_route_name, ...
        'apply_temperature_back_to_state', apply_temperature_back_to_state);
end

function duration_s = get_stage_duration(stage_info)
    t_start = get_option_field(stage_info, 't_start', NaN);
    t_end = get_option_field(stage_info, 't_end', NaN);
    duration_s = t_end - t_start;
    if ~isfinite(duration_s) || duration_s <= 0
        duration_s = get_option_field(stage_info, 'stop_time_s', NaN);
    end
    if ~isfinite(duration_s) || duration_s <= 0
        duration_s = 0.1;
    end
end

function value = get_option_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
