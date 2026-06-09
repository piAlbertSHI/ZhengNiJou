function schedule = Build_HeatDriveECC_StageSchedule(options)
% Build stage durations from Eq.24 cycle frequency and heat-duty partition.

    eq = options.equilibrium;
    tau_cycle = eq.tau_cycle_s;
    heat_duty_weights = [eq.qa_J_per_kg, eq.qr_J_per_kg, ...
        eq.qa_J_per_kg, eq.qr_J_per_kg];
    heat_duty_weights = heat_duty_weights ./ sum(heat_duty_weights);
    durations = tau_cycle .* heat_duty_weights;

    schedule = struct();
    schedule.schema_version = 'heatdrive_ecc_stage_schedule_v1';
    schedule.stage_names = {'sma_heat_load', 'se_reject_heat', ...
        'sma_cool_unload', 'se_absorb_heat'};
    schedule.stage_ids = 1:4;
    schedule.stage_durations_s = durations(:).';
    schedule.stage_start_s = [0.0, cumsum(durations(1:3))];
    schedule.stage_end_s = cumsum(durations);
    schedule.tau_cycle_s = tau_cycle;
    schedule.total_time_s = tau_cycle * options.cycle_count;
    schedule.source = ['tau_cycle from Eq.24: ma*qa/Qh; stage durations ', ...
        'partitioned by article heat duties [qa, qr, qa, qr].'];
    schedule.not_legacy_timing = true;
end

