function selected = HeatDriveECC_IsTemperatureSignal(names)
% Logged thermal probes use Kelvin; generic controller probes are not temperatures.
    selected = contains(names, 'temp', 'IgnoreCase', true) | ...
        endsWith(names, '_T_K', 'IgnoreCase', true);
end
