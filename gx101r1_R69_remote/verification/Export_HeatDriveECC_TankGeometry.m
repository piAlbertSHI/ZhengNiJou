function record = Export_HeatDriveECC_TankGeometry(output_root, physical_path)
% Build-only geometry evidence; no operating point is loaded or saved.
    target = fullfile(output_root, 'tank_geometry.json');
    assert(~isfile(target), 'Do not overwrite tank geometry evidence.');
    if ~isfolder(output_root), mkdir(output_root); end
    saved = load(physical_path, 'options');
    [model, ~] = Build_HeatDriveECC_EighthRound_Simulink_Model(saved.options);
    cleanup = onCleanup(@() close_system(model, 0));
    paths = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
        'Type', 'Block', 'MaskType', 'Tank (TL)');
    assert(numel(paths) == 4, 'Expected four source tanks.');
    rows = cell(size(paths));
    for k = 1:numel(paths)
        names = fieldnames(get_param(paths{k}, 'DialogParameters'));
        parameters = struct();
        for j = 1:numel(names)
            value = get_param(paths{k}, names{j});
            if ischar(value), parameters.(names{j}) = value; end
        end
        ports = get_param(paths{k}, 'PortHandles');
        resolved = struct();
        for name = {'tank_area', 'tank_pressure', 'level', 'T_I'}
            resolved.(name{1}) = slResolve(parameters.(name{1}), paths{k});
        end
        rows{k} = struct('block_path', paths{k}, 'parameters', parameters, 'resolved', resolved, ...
            'LConn_count', numel(ports.LConn), 'RConn_count', numel(ports.RConn));
    end
    record = struct('schema', 'heatdrive_ecc_tank_geometry_v1', ...
        'physical_path', physical_path, 'tanks', {rows}, 'simulation_run', false, ...
        'checkpoint_loaded', false, 'checkpoint_saved', false, ...
        'production_recovery_allowed', false);
    fid = fopen(target, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'Cannot write tank geometry evidence.');
    file_cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('TANK_GEOMETRY_PASS=1 TANKS=4 SIMULATION_RUN=0\n');
end
