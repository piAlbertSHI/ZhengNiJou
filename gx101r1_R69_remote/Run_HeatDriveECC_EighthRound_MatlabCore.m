function result = Run_HeatDriveECC_EighthRound_MatlabCore(overrides)
% MATLAB-only driver for debugging/calibrating the eighth-round physical core.
% Final validation uses Run_HeatDriveECC_EighthRound_Simulink_Cycles.

    if nargin < 1
        overrides = struct();
    end
    options = Build_HeatDriveECC_EighthRound_Defaults(overrides);
    dt = options.simulation.fixed_step_s;
    stop_time = options.cycle_count * options.schedule.tau_cycle_s;
    times = (0:dt:stop_time).';
    if times(end) < stop_time
        times(end + 1, 1) = stop_time;
    end

    state = Initialize_HeatDriveECC_EighthRound_State(options);
    Y = zeros(numel(times), options.output.output_width);
    last_t = times(1);
    for idx = 1:numel(times)
        t = times(idx);
        step_dt = max(t - last_t, 0.0);
        [state, y] = HeatDriveECC_EighthRound_CoreStep(state, options, t, step_dt);
        Y(idx, :) = y;
        last_t = t;
    end
    result = struct();
    result.options = options;
    result.time_s = times;
    result.Y = Y;
    result.summary = Summarize_HeatDriveECC_EighthRound_Output(Y, options);
end
