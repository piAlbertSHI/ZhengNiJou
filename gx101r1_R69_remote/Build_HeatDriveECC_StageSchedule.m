function schedule = Build_HeatDriveECC_StageSchedule(options)
% Build the four continuous Simulink stages from Qian 2019 Fig. 3/Table 4.

    reference = options.reference;
    tau_cycle = 1.0 / reference.cycle_frequency_Hz;
    durations = [ ...
        reference.sma_heating_time_s - reference.se_exchange_time_s, ...
        reference.se_exchange_time_s, ...
        reference.sma_cooling_time_s - reference.se_exchange_time_s, ...
        reference.se_exchange_time_s];
    if abs(sum(durations) - tau_cycle) > 1.0e-10 || any(durations <= 0.0)
        error('HeatDriveECC:QianScheduleContract', ...
            'Qian Fig. 3/Table 4 stage durations must sum to 10 s.');
    end

    schedule = struct();
    schedule.schema_version = 'heatdrive_ecc_qian2019_fig3_schedule_v2';
    schedule.stage_names = {'sma_heat_load', 'se_reject_heat', ...
        'sma_cool_unload', 'se_absorb_heat'};
    schedule.stage_ids = 1:4;
    schedule.stage_durations_s = durations(:).';
    schedule.stage_start_s = [0.0, cumsum(durations(1:3))];
    schedule.stage_end_s = cumsum(durations);
    schedule.tau_cycle_s = tau_cycle;
    schedule.total_time_s = tau_cycle * options.cycle_count;
    schedule.frequency_Hz = reference.cycle_frequency_Hz;
    schedule.loading_delay_s = 0.5;
    schedule.loading_transform_s = 0.9;
    schedule.unloading_delay_s = 1.1;
    schedule.unloading_transform_s = 1.9;
    schedule.source = [ ...
        'Qian2019 Fig.3/Table4: 0.5+0.9+2.1+1.5+1.1+1.9+', ...
        '0.5+1.5 = 10 s; exchange stages remain continuous Simulink stages.'];
    schedule.not_legacy_timing = true;
end
