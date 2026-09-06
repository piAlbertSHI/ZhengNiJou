function Test_HeatDriveECC_PhysicalPortHandles()
    model = 'ecc_port_mapping_test';
    scratch = 'ecc_port_mapping_scratch';
    load_system('fl_lib');
    new_system(model); new_system(scratch);
    cleanup = onCleanup(@() close_models(model, scratch));
    pipe = [model '/Pipe'];
    add_block('fl_lib/Thermal Liquid/Elements/Pipe (TL)', pipe);
    for orientation = {'right', 'left', 'up', 'down'}
        set_param(pipe, 'Orientation', orientation{1});
        rows = Map_HeatDriveECC_PhysicalPortHandles(pipe, scratch);
        names = cellfun(@(r) r.name, rows, 'UniformOutput', false);
        handles = get_param(pipe, 'PortHandles');
        assert(rows{strcmp(names, 'A')}.handle == handles.LConn(1));
        assert(rows{strcmp(names, 'H')}.handle == handles.LConn(2));
        assert(rows{strcmp(names, 'B')}.handle == handles.RConn(1));
        assert(strcmp(rows{strcmp(names, 'H')}.domain, 'foundation.thermal.thermal'));
        assert(all(arrayfun(@(h) get_param(h, 'Line') < 0, ...
            [handles.LConn(:); handles.RConn(:)])), 'Original block was modified.');
    end
    clear cleanup
    fprintf('PHYSICAL_PORT_MAPPING_TEST_PASS=1 ORIENTATIONS=4\n');
end

function close_models(model, scratch)
    close_system(scratch, 0); close_system(model, 0);
end
