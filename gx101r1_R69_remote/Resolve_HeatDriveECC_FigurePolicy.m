function enabled = Resolve_HeatDriveECC_FigurePolicy(overrides)
% Keep postprocessing flags outside the checksum-sensitive model output map.
    enabled = true;
    if isfield(overrides, 'output') && isstruct(overrides.output) && ...
            isfield(overrides.output, 'generate_figures')
        enabled = overrides.output.generate_figures;
    end
    assert(isscalar(enabled) && (islogical(enabled) || ...
        (isnumeric(enabled) && isfinite(enabled) && ismember(enabled, [0 1]))), ...
        'HeatDriveECC:InvalidFigurePolicy', 'generate_figures must be scalar true or false.');
    enabled = logical(enabled);
end
