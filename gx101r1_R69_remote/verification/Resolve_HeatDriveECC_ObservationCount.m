function count=Resolve_HeatDriveECC_ObservationCount(value)
% Simscape history is numeric; the Simulink state-history parameter is text.
    if isnumeric(value)
        count=double(value);
    else
        assert(ischar(value) || (isstring(value) && isscalar(value)),'Expected scalar count or text.');
        count=str2double(value);
    end
    assert(isscalar(count) && isreal(count) && isfinite(count) && count>=1 && count==fix(count), ...
        'Observation capacity must be a positive finite integer.');
end
