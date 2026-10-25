function [traces, profiling] = Extract_HeatDriveECC_NativeStorageTraces(log, model, final_only, diagnostic_paths, buffer_paths, inventory_contract)
% Read named native leaves of actual storage blocks; no anonymous-state mapping.
    if nargin < 3, final_only = false; end
    if nargin < 4, diagnostic_paths = {}; end
    if nargin < 5, buffer_paths = {}; end
    if nargin < 6, inventory_contract = []; end
    assert(isa(log, 'simscape.logging.Node'), 'Missing native Simscape log.');
    types = {'Pipe (TL)', 'Tank (TL)', 'Constant Volume Chamber (TL)', 'Thermal Mass'};
    traces = {};
    timings={};
    component_count = 0;
    observed_paths={};observed_counts=zeros(1,4);
    for kind = 1:numel(types)
        paths = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', ...
            'Type', 'Block', 'MaskType', types{kind});
        if kind == 3
            assert(isempty(intersect(paths, diagnostic_paths)), 'Duplicate native/diagnostic storage.');
            paths = [paths(:); diagnostic_paths(:)];
        end
        if kind == 2
            assert(isempty(intersect(paths, buffer_paths)), 'Duplicate native/candidate buffer.');
            paths = [paths(:); buffer_paths(:)];
        end
        component_count = component_count + numel(paths);
        observed_counts(kind)=numel(paths);observed_paths=[observed_paths;paths(:)]; %#ok<AGROW>
        for k = 1:numel(paths)
            node = simscape.logging.findNode(log, paths{k});
            assert(~isempty(node), 'Missing native storage node: %s', paths{k});
            names = node.childIds;
            for j = 1:numel(names)
                [t,data,unit,timing]=Read_HeatDriveECC_NativeSeries(node.child(names{j}));
                timing.block_path=paths{k}; timing.state_name=names{j};
                timings{end+1}=timing; %#ok<AGROW>
                if isempty(t),continue;end
                if final_only, t = t(end); data = data(end, :); end
                assert(all(isfinite(t)) && all(isfinite(data), 'all'), ...
                    'Nonfinite native trace: %s/%s', paths{k}, names{j});
                traces{end + 1} = struct('block_path', paths{k}, ...
                    'state_name', names{j}, 'unit', unit, ...
                    'time_s', t(:), 'values', data, 'channel_count', size(data, 2)); %#ok<AGROW>
            end
        end
    end
    if isempty(inventory_contract)
        assert(component_count == 119, 'Unexpected actual storage inventory: %d', component_count);
    else
        assert(strcmp(inventory_contract.schema,'heatdrive_ecc_coupled_CV_inventory_v1') && ...
            isequal(types,inventory_contract.type_names) && ...
            isequal(observed_counts,inventory_contract.type_counts) && ...
            numel(unique(observed_paths))==component_count && ...
            isequal(sort(observed_paths(:)),sort(inventory_contract.storage_paths(:))), ...
            'Declared coupled topology requires exact storage paths AND type counts.');
    end
    rows=[timings{:}]; fields={'series_access_s','points_access_s','time_access_s', ...
        'values_access_s','unit_access_s','reshape_s','total_s'};
    totals=struct();
    for idx=1:numel(fields),totals.(fields{idx})=sum([rows.(fields{idx})]);end
    [~,order]=sort([rows.total_s],'descend');
    profiling=struct('schema','heatdrive_ecc_native_leaf_api_profile_v1', ...
        'leaf_count',numel(rows),'totals_s',totals, ...
        'slowest_leaves',rows(order(1:min(numel(order),20))), ...
        'physical_or_observation_values_modified',false);
end
