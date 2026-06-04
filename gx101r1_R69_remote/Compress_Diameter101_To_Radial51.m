function [T_r, compression_report] = Compress_Diameter101_To_Radial51(T_x, geometry, compression_options)
% Compress a 101-strip diameter field back to the 51-point radial solver grid.

    if nargin < 2 || isempty(geometry)
        geometry = Build_Diameter_Strip_Geometry();
    end
    if nargin < 3 || isempty(compression_options)
        compression_options = struct();
    end

    T_x = T_x(:);
    if numel(T_x) ~= geometry.strip_count
        error('Compress_Diameter101_To_Radial51:NodeCountMismatch', ...
            'Expected %d strip values, got %d.', geometry.strip_count, numel(T_x));
    end
    if any(~isfinite(T_x))
        error('Compress_Diameter101_To_Radial51:InvalidTemperature', ...
            'T_x must contain only finite values.');
    end

    theta_count = get_option_field(compression_options, 'theta_count', 8);
    average_mode = char(string(get_option_field( ...
        compression_options, 'average_mode', geometry.default_average_mode)));
    cp_reference = get_option_field(compression_options, 'cp_reference', geometry.default_cp_J_per_kgK);
    input_contract_kind = char(string(get_option_field( ...
        compression_options, 'input_contract_kind', 'unspecified')));
    enforce_energy_conservation = logical(get_option_field( ...
        compression_options, 'enforce_energy_conservation', true));
    T_r_reference = numeric_vector_or_empty(get_option_field( ...
        compression_options, 'energy_reference_radial_T', []));
    T_x_reference = numeric_vector_or_empty(get_option_field( ...
        compression_options, 'energy_reference_strip_T', []));

    if theta_count < 2 || floor(theta_count) ~= theta_count
        error('Compress_Diameter101_To_Radial51:InvalidThetaCount', ...
            'theta_count must be an integer >= 2.');
    end
    if ~(isnumeric(cp_reference) && isscalar(cp_reference) && isfinite(cp_reference) && cp_reference > 0.0)
        error('Compress_Diameter101_To_Radial51:InvalidCpReference', ...
            'cp_reference must be a finite positive scalar.');
    end

    theta_grid_rad = (2.0 * pi / theta_count) * (0:theta_count - 1);
    r_nodes_m = geometry.r_nodes_m(:);
    T_r_uncorrected = zeros(geometry.radial_node_count, 1);

    positive_axis_T = T_x(geometry.positive_strip_indices).';
    sample_matrix = zeros(geometry.radial_node_count, theta_count);

    for idx = 1:geometry.radial_node_count
        x_samples = r_nodes_m(idx) * cos(theta_grid_rad);
        strip_samples = interp1(geometry.x_strip_m(:), T_x(:), x_samples, 'linear', 'extrap');
        sample_matrix(idx, :) = strip_samples;

        switch average_mode
            case 'temperature'
                T_r_uncorrected(idx) = mean(strip_samples);

            case 'enthalpy_frozen_xi'
                enthalpy_samples = cp_reference * strip_samples;
                T_r_uncorrected(idx) = mean(enthalpy_samples) / cp_reference;

            otherwise
                error('Compress_Diameter101_To_Radial51:UnsupportedAverageMode', ...
                    'Unsupported average_mode: %s', average_mode);
        end
    end

    T_r = T_r_uncorrected;
    strip_C = geometry.strip_heat_capacity_J_per_K(:);
    radial_C = build_radial_heat_capacity_vector(geometry.radial_node_count, geometry);
    strip_energy_output_J = sum(strip_C .* T_x(:));
    radial_energy_uncorrected_J = sum(radial_C .* T_r_uncorrected(:));
    energy_conservation_mode = 'absolute_output_energy';
    energy_correction_offset_K = 0.0;
    strip_energy_reference_J = NaN;
    radial_energy_reference_J = NaN;
    strip_delta_energy_J = NaN;
    radial_delta_energy_uncorrected_J = NaN;
    target_radial_energy_output_J = strip_energy_output_J;

    references_complete = numel(T_r_reference) == geometry.radial_node_count && ...
        numel(T_x_reference) == geometry.strip_count && ...
        all(isfinite(T_r_reference(:))) && all(isfinite(T_x_reference(:)));
    if references_complete
        strip_energy_reference_J = sum(strip_C .* T_x_reference(:));
        radial_energy_reference_J = sum(radial_C .* T_r_reference(:));
        strip_delta_energy_J = strip_energy_output_J - strip_energy_reference_J;
        radial_delta_energy_uncorrected_J = radial_energy_uncorrected_J - radial_energy_reference_J;
        target_radial_energy_output_J = radial_energy_reference_J + strip_delta_energy_J;
        energy_conservation_mode = 'delta_energy_from_reference_state';
    end

    compression_projection_error_before_J = radial_energy_uncorrected_J - target_radial_energy_output_J;
    if enforce_energy_conservation && all(isfinite([compression_projection_error_before_J, sum(radial_C)])) && sum(radial_C) > eps
        energy_correction_offset_K = -compression_projection_error_before_J / sum(radial_C);
        T_r = T_r_uncorrected + energy_correction_offset_K;
    end

    radial_energy_output_J = sum(radial_C .* T_r(:));
    if references_complete
        radial_delta_energy_J = radial_energy_output_J - radial_energy_reference_J;
        compression_projection_error_after_J = radial_delta_energy_J - strip_delta_energy_J;
        reference_scale_J = max(abs(strip_delta_energy_J), 1.0e-12);
    else
        radial_delta_energy_J = NaN;
        compression_projection_error_after_J = radial_energy_output_J - strip_energy_output_J;
        reference_scale_J = max(abs(strip_energy_output_J), 1.0e-12);
    end
    compression_projection_error_ratio = abs(compression_projection_error_after_J) / reference_scale_J;
    projection_energy_conservation_ok = isfinite(compression_projection_error_ratio) && ...
        compression_projection_error_ratio <= 1.0e-8;

    compression_report = struct( ...
        'input_contract_kind', input_contract_kind, ...
        'theta_count', theta_count, ...
        'average_mode', average_mode, ...
        'cp_reference', cp_reference, ...
        'theta_grid_rad', theta_grid_rad, ...
        'raw_strip_count', numel(T_x), ...
        'reconciled_node_count', numel(T_r), ...
        'sample_x_min_m', -max(r_nodes_m), ...
        'sample_x_max_m', max(r_nodes_m), ...
        'sample_matrix', sample_matrix, ...
        'positive_axis_profile', positive_axis_T(:), ...
        'max_proxy_smoothing_delta_K', max(abs(T_r - positive_axis_T(:))), ...
        'energy_conservation_enabled', enforce_energy_conservation, ...
        'energy_conservation_mode', energy_conservation_mode, ...
        'energy_correction_offset_K', energy_correction_offset_K, ...
        'energy_correction_max_abs_K', abs(energy_correction_offset_K), ...
        'strip_energy_reference_J', strip_energy_reference_J, ...
        'strip_energy_output_J', strip_energy_output_J, ...
        'strip_delta_energy_J', strip_delta_energy_J, ...
        'radial_energy_reference_J', radial_energy_reference_J, ...
        'radial_energy_uncorrected_J', radial_energy_uncorrected_J, ...
        'radial_energy_output_J', radial_energy_output_J, ...
        'radial_delta_energy_uncorrected_J', radial_delta_energy_uncorrected_J, ...
        'radial_delta_energy_J', radial_delta_energy_J, ...
        'compression_projection_error_before_J', compression_projection_error_before_J, ...
        'compression_projection_error_after_J', compression_projection_error_after_J, ...
        'compression_projection_error_ratio', compression_projection_error_ratio, ...
        'projection_energy_conservation_ok', projection_energy_conservation_ok, ...
        'input_min_T', min(T_x), ...
        'input_max_T', max(T_x), ...
        'output_min_T', min(T_r), ...
        'output_max_T', max(T_r));
end

function radial_C = build_radial_heat_capacity_vector(radial_node_count, geometry)
    total_C = sum(geometry.strip_heat_capacity_J_per_K(:));
    radius_m = max(geometry.r_nodes_m(:));
    if radial_node_count <= 1 || ~(isfinite(total_C) && total_C > 0.0) || ~(isfinite(radius_m) && radius_m > 0.0)
        radial_C = repmat(total_C / max(radial_node_count, 1), radial_node_count, 1);
        return;
    end

    r_nodes = linspace(0.0, radius_m, radial_node_count).';
    dr = r_nodes(2) - r_nodes(1);
    edges = zeros(radial_node_count + 1, 1);
    edges(1) = 0.0;
    edges(end) = radius_m;
    for idx = 2:radial_node_count
        edges(idx) = min(radius_m, r_nodes(idx - 1) + 0.5 * dr);
    end
    annulus_weights = max(edges(2:end) .^ 2 - edges(1:end - 1) .^ 2, 0.0);
    annulus_weights = annulus_weights / max(sum(annulus_weights), eps);
    radial_C = total_C * annulus_weights(:);
end

function value = numeric_vector_or_empty(value)
    if isnumeric(value) && ~isempty(value)
        value = value(:);
    else
        value = [];
    end
end

function value = get_option_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
