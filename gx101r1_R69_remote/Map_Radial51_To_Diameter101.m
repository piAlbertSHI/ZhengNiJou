function [T_x, map_report] = Map_Radial51_To_Diameter101(T_r, geometry)
% Mirror a 51-point radial temperature field onto a 101-strip diameter field.

    if nargin < 2 || isempty(geometry)
        geometry = Build_Diameter_Strip_Geometry();
    end

    T_r = T_r(:);
    radial_node_count = numel(T_r);
    if radial_node_count ~= geometry.radial_node_count
        error('Map_Radial51_To_Diameter101:NodeCountMismatch', ...
            'Expected %d radial nodes, got %d.', geometry.radial_node_count, radial_node_count);
    end
    if any(~isfinite(T_r))
        error('Map_Radial51_To_Diameter101:InvalidTemperature', ...
            'T_r must contain only finite values.');
    end

    if geometry.strip_count == 2 * radial_node_count - 1
        T_x = [flipud(T_r(2:end)); T_r];
        exact_mirror_used = true;
    else
        x_abs = abs(geometry.x_strip_m(:));
        T_x = interp1(geometry.r_nodes_m(:), T_r(:), x_abs, 'linear', 'extrap');
        exact_mirror_used = false;
    end

    map_report = struct( ...
        'source_node_count', radial_node_count, ...
        'target_node_count', numel(T_x), ...
        'exact_mirror_used', exact_mirror_used, ...
        'source_min_T', min(T_r), ...
        'source_max_T', max(T_r), ...
        'target_min_T', min(T_x), ...
        'target_max_T', max(T_x));
end
