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
        end
        source = '';
        if strcmp(get_param(path, 'BlockType'), 'SimscapeBlock')
            source = get_param(path, 'SourceFile');
        end
        blocks{end + 1} = struct('block_path', path, ...
            'block_type', get_param(path, 'BlockType'), ...
            'mask_type', get_param(path, 'MaskType'), ...
            'source_file', source, 'vertex_indices', indices); %#ok<AGROW>
    end
    edges = {};
    vertex_handles = cellfun(@(v) v.handle, vertices);
    connections = {};
    wire_pairs = zeros(0, 2);
    % Physical DstPort values are handles, not zero-based signal-port indices.
    for k = 1:numel(vertices)
        vertex = vertices{k};
        connectivity = get_param(vertex.block_path, 'PortConnectivity');
        type = [vertex.side num2str(vertex.index)];
        port = connectivity(strcmp({connectivity.Type}, type));
        assert(isscalar(port), 'Missing unique physical PortConnectivity entry.');
        destinations = port.DstPort(:)';
        indices = zeros(size(destinations));
        for j = 1:numel(destinations)
            match = find(vertex_handles == destinations(j));
            assert(isscalar(match), 'Unresolved typed physical destination at %s.', vertex.key);
            indices(j) = match;
            assert(match ~= k, 'Unexpected self-connected physical port.');
            wire_pairs(end + 1, :) = sort([k match]); %#ok<AGROW>
        end
        connections{end + 1} = struct('vertex_index', k, 'type', type, ...
            'destination_handles', destinations, 'destination_indices', indices); %#ok<AGROW>
    end
    wire_pairs = unique(wire_pairs, 'rows');
    for k = 1:size(wire_pairs, 1)
        edges{end + 1} = struct('a', wire_pairs(k, 1), 'b', wire_pairs(k, 2), ...
            'kind', 'physical_wire_net'); %#ok<AGROW>
    end
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
    topology = struct('schema', 'heatdrive_ecc_tl_connectivity_v2', ...
        'domain', domain, 'vertices', {vertices}, 'blocks', {blocks}, ...
        'edges', {edges}, 'port_connectivity', {connections}, ...
        'primitive_internal_connections_inferred', false, ...
        'hydraulic_domains_verified', false, 'source_model_modified', false);
    clear cleanup
end
