function rows = Map_HeatDriveECC_PhysicalPortHandles(block_path, scratch_model, domain_filter)
% Identify names by a public named connection on a disposable block copy.
% connectionPortProperties order is not the LConn/RConn handle order.
    properties = simscape.connectionPortProperties(block_path);
    if nargin < 3, domain_filter = ''; end
    if ~isempty(domain_filter)
        selected = arrayfun(@(p) strcmp(p.Type.Name, domain_filter), properties);
        properties = properties(selected);
    end
    rows = {};
    if isempty(properties), return; end
    original = get_param(block_path, 'PortHandles');
    copied_path = [scratch_model '/CopiedBlock'];
    probe_path = [scratch_model '/Probe'];
    add_block(block_path, copied_path);
    cleanup = onCleanup(@() delete_block(copied_path));
    copied = get_param(copied_path, 'PortHandles');
    assert(numel(original.LConn) == numel(copied.LConn) && ...
        numel(original.RConn) == numel(copied.RConn), 'Copy changed port layout.');
    for k = 1:numel(properties)
        copied = get_param(copied_path, 'PortHandles');
        isolated = [copied.LConn(:); copied.RConn(:)];
        assert(all(arrayfun(@(h) get_param(h, 'Line') < 0, isolated)), ...
            'A disposable copy must have no external wires before mapping.');
        add_block('nesl_utility/Connection Port', probe_path);
        probe_cleanup = onCleanup(@() delete_block(probe_path));
        probe_properties = simscape.connectionPortProperties(probe_path);
        assert(isscalar(probe_properties), 'Expected one untyped probe port.');
        simscape.addConnection(copied_path, properties(k).Name, ...
            probe_path, probe_properties.Name);
        probe_handles = get_param(probe_path, 'PortHandles');
        probe_handle = [probe_handles.LConn(:); probe_handles.RConn(:)];
        assert(isscalar(probe_handle), 'Expected one probe handle.');
        line = get_param(probe_handle, 'Line');
        line_cleanup = onCleanup(@() delete_line(line));
        % On an isolated copy, the named wire identifies exactly one port.
        copied = get_param(copied_path, 'PortHandles');
        candidates = [copied.LConn(:); copied.RConn(:)];
        matched = candidates(arrayfun(@(h) get_param(h, 'Line') > 0, candidates));
        assert(isscalar(matched), 'Named connection has no unique target handle.');
        left = find(copied.LConn == matched);
        right = find(copied.RConn == matched);
        if ~isempty(left)
            side = 'LConn'; index = left;
        else
            side = 'RConn'; index = right;
        end
        domain = properties(k).Type.Name;
        if ismissing(domain), domain = ""; end
        rows{end + 1} = struct('name', char(properties(k).Name), ...
            'interface_type', char(string(properties(k).Type.InterfaceType)), ...
            'domain', char(domain), 'side', side, 'index', index, ...
            'handle', original.(side)(index)); %#ok<AGROW>
        clear line_cleanup probe_cleanup
    end
    assert(numel(unique(cellfun(@(r) r.handle, rows))) == numel(rows), ...
        'Port-name mapping is not bijective.');
    clear cleanup
end
