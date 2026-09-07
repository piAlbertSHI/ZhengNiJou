function audit = Audit_HeatDriveECC_RouteGeometry(output_root, physical_path, include_thermal)
% Export actual geometry and physical connectivity without loading any OP.
    if nargin < 3, include_thermal = false; end
    assert(~isfolder(output_root), 'Do not overwrite geometry evidence.');
    [code, commit] = system('git rev-parse HEAD');
    assert(code == 0, 'Cannot identify source commit.');
    [code, dirty] = system('git status --porcelain');
    assert(code == 0 && isempty(strtrim(dirty)), 'Commit source before model inspection.');
    saved = load(physical_path, 'options');
    [model, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(saved.options);
    cleanup = onCleanup(@() close_system(model, 0));
    set_param(model, 'SimulationCommand', 'update');
    audit = Export_HeatDriveECC_TLConnectivity(model);
    audit.geometry_schema = 'heatdrive_ecc_route_geometry_v1';
    audit.execution_commit = strtrim(commit);
    audit.source_options_path = physical_path;
    audit.simulation_run = false;
    audit.production_checkpoint_loaded = false;
    audit.production_model_saved = false;
    audit.production_recovery_allowed = false;
    audit.branch_options = saved.options.branch;
    if include_thermal
        audit.thermal_connectivity = Export_HeatDriveECC_TLConnectivity( ...
            model, 'foundation.thermal.thermal');
        audit.system_options = saved.options.system;
        audit.material_options = saved.options.material;
        audit.geometry_options = saved.options.geometry;
    end
    audit.geometry = {};
    selected = {'length', 'length_add', 'Dh', 'area', 'area_A', 'area_B', 'volume', ...
        'mass', 'sp_heat', 'specific_heat', 'roughness', 'Re_lam', 'Re_tur', 'shape_factor', ...
        'dynamic_compressibility', 'inertia', 'num_ports'};
    blocks = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Type', 'Block');
    for k = 1:numel(blocks)
        path = blocks{k};
        mask = strrep(get_param(path, 'MaskType'), newline, ' ');
        if ~ismember(mask, {'Pipe (TL)', 'Constant Volume Chamber (TL)', 'Thermal Mass'})
            continue;
        end
        dialog = get_param(path, 'DialogParameters');
        row = struct('block_path', path, 'mask_type', mask, 'parameters', struct(), ...
            'resolved', struct(), 'resolution_errors', struct());
        for j = 1:numel(selected)
            key = selected{j};
            if ~isfield(dialog, key), continue; end
            expression = get_param(path, key);
            row.parameters.(key) = expression;
            unit_key = [key '_unit'];
            unit = '1';
            if isfield(dialog, unit_key)
                unit = get_param(path, unit_key);
                row.parameters.(unit_key) = unit;
            end
            if ismember(key, {'dynamic_compressibility', 'inertia', 'num_ports'}), continue; end
            try
                number = evalin('base', expression);
                assert(isnumeric(number) && isscalar(number) && isreal(number) && isfinite(number), ...
                    'Require finite scalar geometry.');
                row.resolved.(key) = struct('value', number, 'unit', unit);
            catch exception
                row.resolution_errors.(key) = exception.message;
            end
        end
        audit.geometry{end+1} = row;
    end
    mkdir(output_root);
    fid = fopen(fullfile(output_root, 'route_geometry.json'), 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot write route geometry.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(audit, 'PrettyPrint', true));
    clear file_cleanup cleanup
    fprintf('ROUTE_GEOMETRY_EXPORTED=1 COMPONENTS=%d\n', numel(audit.geometry));
end
