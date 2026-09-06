function topology = Export_HeatDriveECC_TLConnectivity(model)
% Export typed wire nets and hierarchy bridges, without merging fluid channels.
    scratch = 'ecc_tl_connectivity_scratch';
    assert(~bdIsLoaded(scratch), 'Scratch model is already in use.');
    new_system(scratch);
    cleanup = onCleanup(@() close_system(scratch, 0));
    domain = 'foundation.thermal_liquid.thermal_liquid';
    paths = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Type', 'Block');
    vertices = {};
    blocks = {};
    roots = [];
    for k = 1:numel(paths)
        path = paths{k};
        handles = get_param(path, 'PortHandles');
        if isempty(handles.LConn) && isempty(handles.RConn), continue; end
        properties = simscape.connectionPortProperties(path);
        if ~any(arrayfun(@(p) strcmp(p.Type.Name, domain), properties)), continue; end
        rows = Map_HeatDriveECC_PhysicalPortHandles(path, scratch, domain);
        indices = [];
        for j = 1:numel(rows)
            row = rows{j};
            row.block_path = path;
            row.key = [path ':' row.name];
            vertices{end + 1} = row; %#ok<AGROW>
            indices(end + 1) = numel(vertices); %#ok<AGROW>
            line = get_param(row.handle, 'Line');
            if line > 0
                parent = get_param(line, 'LineParent');
                while parent > 0
                    line = parent;
                    parent = get_param(line, 'LineParent');
                end
            end
            roots(end + 1) = line; %#ok<AGROW>
        end
        source = '';
        parameters = get_param(path, 'ObjectParameters');
        if isfield(parameters, 'SourceFile'), source = get_param(path, 'SourceFile'); end
        blocks{end + 1} = struct('block_path', path, ...
            'block_type', get_param(path, 'BlockType'), ...
            'mask_type', get_param(path, 'MaskType'), ...
            'source_file', source, 'vertex_indices', indices); %#ok<AGROW>
    end
    edges = {};
    for root = unique(roots(roots > 0))
        indices = find(roots == root);
        for j = 2:numel(indices)
            edges{end + 1} = struct('a', indices(1), 'b', indices(j), ...
                'kind', 'physical_wire_net'); %#ok<AGROW>
        end
    end
    vertex_handles = cellfun(@(v) v.handle, vertices);
    for k = 1:numel(blocks)
        block = blocks{k};
        if ~strcmp(block.block_type, 'PMIOPort'), continue; end
        path = block.block_path;
        parent = get_param(path, 'Parent');
        assert(~strcmp(parent, model), 'Unexpected root-level TL connection port.');
        siblings = find_system(parent, 'SearchDepth', 1, 'LookUnderMasks', 'all', ...
            'FollowLinks', 'on', 'BlockType', 'PMIOPort');
        side = get_param(path, 'Side');
        side_siblings = siblings(cellfun(@(p) strcmp(get_param(p, 'Side'), side), siblings));
        numbers = cellfun(@(p) str2double(get_param(p, 'Port')), side_siblings);
        number = str2double(get_param(path, 'Port'));
        assert(numel(unique(numbers)) == numel(numbers) && all(isfinite(numbers)), ...
            'Ambiguous hierarchy port numbering.');
        index = nnz(numbers <= number);
        field = 'LConn';
        if strcmp(side, 'Right'), field = 'RConn'; else, assert(strcmp(side, 'Left')); end
        parent_handles = get_param(parent, 'PortHandles');
        assert(index >= 1 && index <= numel(parent_handles.(field)), ...
            'Hierarchy connector index is outside parent ports.');
        external = find(vertex_handles == parent_handles.(field)(index));
        assert(isscalar(external) && isscalar(block.vertex_indices), ...
            'Missing typed parent/child TL connector mapping.');
        edges{end + 1} = struct('a', block.vertex_indices, 'b', external, ...
            'kind', 'hierarchy_connector'); %#ok<AGROW>
    end
    topology = struct('schema', 'heatdrive_ecc_tl_connectivity_v1', ...
        'domain', domain, 'vertices', {vertices}, 'blocks', {blocks}, ...
        'edges', {edges}, 'primitive_internal_connections_inferred', false, ...
        'hydraulic_domains_verified', false, 'source_model_modified', false);
    clear cleanup
end
