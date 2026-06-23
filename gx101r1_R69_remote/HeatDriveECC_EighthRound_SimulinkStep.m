function y = HeatDriveECC_EighthRound_SimulinkStep(t_s)
% Simulink-interpreted one-step wrapper for the eighth-round 21-node model.
%
% The persistent state is advanced only from Simulink time. MATLAB runners
% configure options and launch sim(), but do not loop over cycle time.

    persistent state options last_t_s signature

    if ischar(t_s) || isstring(t_s)
        state = [];
        options = [];
        last_t_s = [];
        signature = '';
        y = [];
        return;
    end

    next_options = get_options_from_base();
    next_signature = make_signature(next_options);
    if isempty(state) || isempty(options) || t_s == 0 || ...
            ~strcmp(signature, next_signature)
        options = next_options;
        state = Initialize_HeatDriveECC_EighthRound_State(options);
        last_t_s = 0.0;
        signature = next_signature;
    end

    dt_s = max(t_s - last_t_s, 0.0);
    [state, y_row] = HeatDriveECC_EighthRound_CoreStep(state, options, t_s, dt_s);
    last_t_s = t_s;
    y = y_row(:).';
end

function options = get_options_from_base()
    if evalin('base', 'exist(''EIGHTH_ROUND_OPTIONS'', ''var'')')
        options = evalin('base', 'EIGHTH_ROUND_OPTIONS');
    else
        options = Build_HeatDriveECC_EighthRound_Defaults();
    end
end

function signature = make_signature(options)
    signature = sprintf('%s|%d|%.15g|%.15g|%.15g|%.15g|%.15g|%.15g|%.15g', ...
        options.schema_version, options.cycle_count, ...
        options.simulation.fixed_step_s, options.schedule.total_time_s, ...
        options.branch.UA_sma_shex_W_per_K, options.branch.UA_sma_the_W_per_K, ...
        options.system.hot_sink_C_J_per_K, options.system.cold_sink_C_J_per_K, ...
        options.system.cold_load_heat_W);
end
