function observation = Evaluate_HeatDriveECC_Periodicity(physical, options)
% Production temperature/phase statistics, independent of energy-boundary availability.
    ncycles = options.cycle_count;
    assert(ncycles >= 1 && ncycles == round(ncycles), 'Require complete cycles.');
    cycle = physical.cycle_index(:);
    sma_mean = mean(physical.SMA_T_21_K, 2);
    se_mean = mean(physical.SE_T_21_K, 2);
    xA_mean = mean(physical.xM_SMA_21, 2);
    xR_mean = mean(physical.xM_SE_21, 2);
    cycles = repmat(struct(), ncycles, 1);
    for c = 1:ncycles
        idx = cycle == c;
        last = find(idx, 1, 'last');
        assert(~isempty(last), 'Missing periodic observation cycle.');
        cycles(c).SMA_end_K = sma_mean(last);
        cycles(c).SE_end_K = se_mean(last);
        cycles(c).SHEX_end_K = physical.SHEX_T_K(last);
        cycles(c).HHEX_end_K = physical.HHEX_T_K(last);
        cycles(c).CHEX_end_K = physical.CHEX_T_K(last);
        cycles(c).xM_SMA_min = min(xA_mean(idx));
        cycles(c).xM_SMA_max = max(xA_mean(idx));
        cycles(c).xM_SE_min = min(xR_mean(idx));
        cycles(c).xM_SE_max = max(xR_mean(idx));
    end
    observation = struct();
    observation.periodic_window_cycles = min(numel(cycles), 10);
    if observation.periodic_window_cycles >= 2
        periodic_cycles = cycles((end - observation.periodic_window_cycles + 1):end);
        previous = cycles(end - 1);
        last = cycles(end);
        endpoint_history = [[periodic_cycles.SMA_end_K].', ...
            [periodic_cycles.SE_end_K].', [periodic_cycles.SHEX_end_K].', ...
            [periodic_cycles.HHEX_end_K].', [periodic_cycles.CHEX_end_K].'];
        observation.last_cycle_endpoint_drift_K = max(abs(diff(endpoint_history, 1, 1)), [], 'all');
        observation.last_cycle_CHEX_drift_K = last.CHEX_end_K - previous.CHEX_end_K;
        observation.last_cycle_HHEX_drift_K = last.HHEX_end_K - previous.HHEX_end_K;
        phase_history = [[periodic_cycles.xM_SMA_min].', ...
            [periodic_cycles.xM_SMA_max].', [periodic_cycles.xM_SE_min].', ...
            [periodic_cycles.xM_SE_max].'];
        observation.last_cycle_phase_drift = max(abs(diff(phase_history, 1, 1)), [], 'all');
        temperature_drift = same_phase_drift_statistics(physical, options, ...
            observation.periodic_window_cycles, ...
            {'SMA_T_21_K','SE_T_21_K','SHEX_T_K','HHEX_T_K','CHEX_T_K'});
        phase_drift = same_phase_drift_statistics(physical, options, ...
            observation.periodic_window_cycles, {'xM_SMA_21','xM_SE_21'});
        observation.last_cycle_same_phase_temperature_drift_K = temperature_drift.maximum;
        observation.last_cycle_same_phase_temperature_p99_drift_K = temperature_drift.percentile_99;
        observation.last_cycle_same_phase_temperature_rms_drift_K = temperature_drift.rms;
        observation.last_cycle_same_phase_phase_drift = phase_drift.maximum;
        observation.last_cycle_same_phase_phase_p99_drift = phase_drift.percentile_99;
        observation.last_cycle_same_phase_phase_rms_drift = phase_drift.rms;
    else
        fields = {'last_cycle_endpoint_drift_K','last_cycle_CHEX_drift_K','last_cycle_HHEX_drift_K', ...
            'last_cycle_phase_drift','last_cycle_same_phase_temperature_drift_K', ...
            'last_cycle_same_phase_temperature_p99_drift_K','last_cycle_same_phase_temperature_rms_drift_K', ...
            'last_cycle_same_phase_phase_drift','last_cycle_same_phase_phase_p99_drift', ...
            'last_cycle_same_phase_phase_rms_drift'};
        for k = 1:numel(fields), observation.(fields{k}) = Inf; end
    end
    observation.periodic_endpoint_limit_K = get_validation_limit(options, 'max_periodic_endpoint_drift_K', 0.05);
    observation.periodic_same_phase_temperature_limit_K = get_validation_limit(options, ...
        'max_periodic_same_phase_temperature_drift_K', 0.05);
    observation.periodic_same_phase_temperature_p99_limit_K = get_validation_limit(options, ...
        'max_periodic_same_phase_temperature_p99_drift_K', 0.05);
    observation.periodic_same_phase_temperature_rms_limit_K = get_validation_limit(options, ...
        'max_periodic_same_phase_temperature_rms_drift_K', 0.01);
    observation.periodic_phase_limit = get_validation_limit(options, 'max_periodic_phase_drift', 1.0e-4);
    observation.periodic_same_phase_phase_p99_limit = get_validation_limit(options, ...
        'max_periodic_same_phase_phase_p99_drift', 2.0e-3);
    observation.periodic_same_phase_phase_rms_limit = get_validation_limit(options, ...
        'max_periodic_same_phase_phase_rms_drift', 4.0e-4);
    observation.periodic_steady_state = options.cycle_count >= 10 && ...
        observation.last_cycle_endpoint_drift_K <= observation.periodic_endpoint_limit_K && ...
        observation.last_cycle_same_phase_temperature_p99_drift_K <= observation.periodic_same_phase_temperature_p99_limit_K && ...
        observation.last_cycle_same_phase_temperature_rms_drift_K <= observation.periodic_same_phase_temperature_rms_limit_K && ...
        observation.last_cycle_phase_drift <= observation.periodic_phase_limit && ...
        observation.last_cycle_same_phase_phase_p99_drift <= observation.periodic_same_phase_phase_p99_limit && ...
        observation.last_cycle_same_phase_phase_rms_drift <= observation.periodic_same_phase_phase_rms_limit;
end

function statistics = same_phase_drift_statistics(physical, options, window_cycles, fields)
    tau = options.schedule.tau_cycle_s;
    phase = linspace(0.0, tau, 401).';
    differences = zeros(0, 1);
    first_cycle = options.cycle_count - window_cycles + 1;
    for cycle_idx = (first_cycle + 1):options.cycle_count
        previous_start = (cycle_idx - 2) * tau;
        current_start = (cycle_idx - 1) * tau;
        for field_idx = 1:numel(fields)
            values = physical.(fields{field_idx});
            previous_values = interp1(physical.time_s, values, previous_start + phase, 'linear', 'extrap');
            current_values = interp1(physical.time_s, values, current_start + phase, 'linear', 'extrap');
            differences = [differences; abs(current_values(:) - previous_values(:))]; %#ok<AGROW>
        end
    end
    differences = sort(differences);
    statistics = struct('maximum', differences(end), ...
        'percentile_99', differences(max(1, ceil(0.99 * numel(differences)))), ...
        'rms', sqrt(mean(differences .^ 2)));
end

function result = get_validation_limit(options, field, fallback)
    result = fallback;
    if isfield(options, 'validation') && isfield(options.validation, field) && ...
            ~isempty(options.validation.(field)), result = options.validation.(field); end
end
