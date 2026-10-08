function observation = Slice_HeatDriveECC_SavedMechanismObservation(saved, start_s, stop_s, dt)
% Exact saved samples only: never extrapolate, synthesize or resimulate a window.
    assert(saved.thermal_boundary_signals.extraction_pass, 'Native boundary extraction failed.');
    assert(stop_s > start_s && dt > 0, 'Invalid observation window.');
    observation = struct('schema', 'heatdrive_ecc_saved_mechanism_observation_v1', ...
        'read_only', true, 'simulation_executed', false, ...
        'production_recovery_allowed', false, 'signals', struct(), ...
        'thermal_boundary_signals', saved.thermal_boundary_signals);
    names = fieldnames(saved.signals);
    reference = [];
    for k = 1:numel(names)
        row = slice(saved.signals.(names{k}), start_s, stop_s, dt);
        if isempty(reference), reference = row.time_s(:); end
        assert(isequal(row.time_s(:), reference), 'Saved public clocks disagree: %s', names{k});
        observation.signals.(names{k}) = row;
    end
    assert(~isempty(reference), 'Missing saved public observations.');
    boundary = saved.thermal_boundary_signals;
    boundary.time_s = reference;
    fields = fieldnames(boundary.fields);
    for k = 1:numel(fields)
        row = slice(boundary.fields.(fields{k}), start_s, stop_s, dt);
        assert(isequal(row.time_s(:), reference), 'Native/public clocks disagree: %s', fields{k});
        boundary.fields.(fields{k}) = row;
    end
    observation.thermal_boundary_signals = boundary;
end

function row = slice(row, start_s, stop_s, dt)
    t = row.time_s(:);
    tolerance = 16 * eps(max([abs(start_s), abs(stop_s), 1]));
    assert(all(isfinite(t)) && all(diff(t) > 0), 'Ambiguous source clock.');
    selected = t >= start_s - tolerance & t <= stop_s + tolerance;
    t = t(selected);
    assert(numel(t) == round((stop_s-start_s)/dt)+1 && ...
        abs(t(1)-start_s) <= tolerance && abs(t(end)-stop_s) <= tolerance && ...
        all(abs(diff(t)-dt) <= tolerance), 'Incomplete exact saved mechanism window.');
    assert(size(row.values, 1) == numel(selected), 'Source value/clock mismatch.');
    row.time_s = t;
    row.values = row.values(selected, :);
end
