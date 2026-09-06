function [cycle_index, stage_id, stage_elapsed_s] = ...
        HeatDriveECC_CycleStageFromTime(time_s, options)
    tau = options.schedule.tau_cycle_s;
    ncycles = options.cycle_count;
    final_time = ncycles * tau;
    cycle_index = floor(time_s ./ tau) + 1;
    cycle_index = min(max(cycle_index, 1), ncycles);
    local_time = time_s - (cycle_index - 1) .* tau;
    final_mask = time_s >= final_time - 10.0 * eps(max(final_time, 1.0));
    local_time(final_mask) = tau;

    stage_id = 4 * ones(size(time_s));
    stage_elapsed_s = zeros(size(time_s));
    starts = options.schedule.stage_start_s(:).';
    ends = options.schedule.stage_end_s(:).';
    for stage = 1:4
        if stage < 4
            mask = local_time >= starts(stage) & local_time < ends(stage);
        else
            mask = local_time >= starts(stage) & local_time <= ends(stage) + eps(tau);
        end
        stage_id(mask) = stage;
        stage_elapsed_s(mask) = local_time(mask) - starts(stage);
    end
end
