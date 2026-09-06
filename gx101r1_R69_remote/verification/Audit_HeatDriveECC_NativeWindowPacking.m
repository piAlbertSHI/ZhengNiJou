function Audit_HeatDriveECC_NativeWindowPacking(source_root, output_root)
% Offline real-data packing regression; this function never starts a simulation.
    summary = jsondecode(fileread(fullfile(source_root, 'segmented_inventory_restore.json')));
    assert(summary.collection_pass && summary.segmentation_equivalence_pass && ...
        ~summary.production_recovery_allowed, 'Require completed restricted diagnostic evidence.');
    assert(~isfolder(output_root), 'Do not overwrite a packing audit.');
    settings = struct('source_result_sha256', summary.source_result_sha256, ...
        'source_checkpoint_sha256', summary.source_checkpoint_sha256, ...
        'fixed_step_s', summary.fixed_step_s, 'cycle_period_s', summary.cycle_period_s);
    for k = 1:numel(summary.cases)
        item = summary.cases(k);
        stored = load(fullfile(source_root, sprintf('case_%d_traces.mat', k)), 'reference', 'prefix', 'suffix');
        parts = {'reference', 'prefix', 'suffix'};
        for j = 1:numel(parts)
            part = parts{j};
            settings.start_s = item.start_s; settings.stop_s = item.end_s;
            if strcmp(part, 'prefix'), settings.stop_s = item.split_s; end
            if strcmp(part, 'suffix'), settings.start_s = item.split_s; end
            path = fullfile(output_root, sprintf('case_%d_%s.mat', k, part));
            traces = stored.(part);
            Write_HeatDriveECC_NativeWindow(path, traces.native, traces.observed, settings);
            packet = load(path);
            assert(isequal(fieldnames(packet), {'header_json'; 'native_values'; 'observed_values'; 'time_s'}), ...
                'Only the shared time, header and value matrices belong in the packet.');
        end
    end
    path = fullfile(output_root, 'rejected_packet.mat');
    bad = traces.native; bad{1}.values(end) = NaN;
    expect_failure(@() Write_HeatDriveECC_NativeWindow(path, bad, traces.observed, settings), ...
        'HeatDriveECC:NativeWindowShape');
    bad = traces.native; bad{1}.time_s(end) = bad{1}.time_s(end) + .0001;
    expect_failure(@() Write_HeatDriveECC_NativeWindow(path, bad, traces.observed, settings), ...
        'HeatDriveECC:NativeWindowGrid');
    bad = traces.native; bad{2} = bad{1};
    expect_failure(@() Write_HeatDriveECC_NativeWindow(path, bad, traces.observed, settings), ...
        'HeatDriveECC:NativeWindowInventory');
    expect_failure(@() Write_HeatDriveECC_NativeWindow(path, traces.native(2:end), traces.observed, settings), ...
        'HeatDriveECC:NativeWindowInventory');
    assert(~isfile(path), 'Rejected data must not be saved.');
    fprintf('NATIVE_WINDOW_PACKING_PASS=1 PACKETS=6 REJECTIONS=4 SIMULATION_RUN=0\n');
end

function expect_failure(action, identifier)
    failed = false;
    try
        action();
    catch e
        assert(strcmp(e.identifier, identifier), 'Unexpected rejection: %s', e.identifier);
        failed = true;
    end
    assert(failed, 'Expected invalid native samples to be rejected.');
end
