function traces = Extract_HeatDriveECC_NativeStorageTraces(log, model, final_only, diagnostic_paths)
% Read named native leaves of actual storage blocks; no anonymous-state mapping.
    if nargin < 3, final_only = false; end
    if nargin < 4, diagnostic_paths = {}; end
    assert(isa(log, 'simscape.logging.Node'), 'Missing native Simscape log.');
    types = {'Pipe (TL)', 'Tank (TL)', 'Constant Volume Chamber (TL)', 'Thermal Mass'};
    traces = {};
    component_count = 0;
    for kind = 1:numel(types)
        paths = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
            'Type', 'Block', 'MaskType', types{kind});
        if kind == 3
            assert(isempty(intersect(paths, diagnostic_paths)), 'Duplicate native/diagnostic storage.');
            paths = [paths(:); diagnostic_paths(:)];
        end
        component_count = component_count + numel(paths);
        for k = 1:numel(paths)
            node = simscape.logging.findNode(log, paths{k});
            assert(~isempty(node), 'Missing native storage node: %s', paths{k});
            names = node.childIds;
            for j = 1:numel(names)
                series = node.child(names{j}).series;
                if isempty(series) || series.points == 0, continue; end
                t = double(time(series));
                data = reshape(double(values(series)), numel(t), []);
                if final_only, t = t(end); data = data(end, :); end
                assert(all(isfinite(t)) && all(isfinite(data), 'all'), ...
                    'Nonfinite native trace: %s/%s', paths{k}, names{j});
                traces{end + 1} = struct('block_path', paths{k}, ...
                    'state_name', names{j}, 'unit', series.unit, ...
                    'time_s', t(:), 'values', data, 'channel_count', size(data, 2)); %#ok<AGROW>
            end
        end
    end
    assert(component_count == 119, 'Unexpected actual storage inventory: %d', component_count);
end
