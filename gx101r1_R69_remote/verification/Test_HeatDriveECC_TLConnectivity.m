function Test_HeatDriveECC_TLConnectivity()
% Two fluid channels share a subsystem and a thermal link but not a TL net.
    model = 'ecc_tl_topology_test';
    load_system('fl_lib');
    new_system(model);
    cleanup = onCleanup(@() close_system(model, 0));
    subsystem = [model '/DualChannel'];
    add_block('built-in/Subsystem', subsystem);
    for k = 1:2
        pipe = sprintf('%s/Channel%d', subsystem, k);
        outer = sprintf('%s/Outer%d', model, k);
        add_block('fl_lib/Thermal Liquid/Elements/Pipe (TL)', pipe);
        add_block('fl_lib/Thermal Liquid/Elements/Pipe (TL)', outer);
        for end_index = 1:2
            connector = sprintf('%s/Channel%dEnd%d', subsystem, k, end_index);
            add_block('nesl_utility/Connection Port', connector, ...
                'Port', num2str(2 * (k - 1) + end_index), 'Side', 'Left');
            props = simscape.connectionPortProperties(connector);
            name = 'A'; if end_index == 2, name = 'B'; end
            simscape.addConnection(pipe, name, connector, props.Name);
        end
        ph = get_param(subsystem, 'PortHandles');
        oh = get_param(outer, 'PortHandles');
        add_line(model, oh.RConn(1), ph.LConn(2 * k - 1));
    end
    first = get_param([subsystem '/Channel1'], 'PortHandles');
    second = get_param([subsystem '/Channel2'], 'PortHandles');
    add_line(subsystem, first.LConn(2), second.LConn(2));
    topology = Export_HeatDriveECC_TLConnectivity(model);
    a = cellfun(@(e) e.a, topology.edges);
    b = cellfun(@(e) e.b, topology.edges);
    for k = 1:numel(topology.blocks)
        block = topology.blocks{k};
        if strcmp(block.mask_type, 'Pipe (TL)')
            assert(numel(block.vertex_indices) == 2);
            a(end + 1) = block.vertex_indices(1); %#ok<AGROW>
            b(end + 1) = block.vertex_indices(2); %#ok<AGROW>
        end
    end
    g = graph(a, b, [], numel(topology.vertices));
    labels = conncomp(g);
    assert(numel(unique(labels)) == 2, 'Distinct channels were merged or a bridge is missing.');
    bridge_count = nnz(cellfun(@(e) strcmp(e.kind, 'hierarchy_connector'), topology.edges));
    assert(bridge_count == 4, 'Expected exactly four hierarchy bridges.');
    clear cleanup
    fprintf('TL_CONNECTIVITY_TEST_PASS=1 DISTINCT_CHANNELS=2 BRIDGES=4\n');
end
