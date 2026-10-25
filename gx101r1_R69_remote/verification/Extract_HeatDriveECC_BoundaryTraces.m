function [traces, metadata] = Extract_HeatDriveECC_BoundaryTraces(log, model, tl, thermal)
% Observe existing source leaves without inserting sensors or editing the model.
    assert(isa(log,'simscape.logging.Node'), 'Missing native Simscape log.');
    if nargin<3,tl = Export_HeatDriveECC_TLConnectivity(model);end
    if nargin<4,thermal = Export_HeatDriveECC_TLConnectivity(model,'foundation.thermal.thermal');end
    sources = {'foundation.thermal_liquid.sources.pressure_source', ...
        'foundation.thermal.sources.temperature','foundation.thermal.sources.controlled_heat_flow'};
    blocks = [tl.blocks(:); thermal.blocks(:)];
    traces = {}; rows = {}; seen = {};
    for k = 1:numel(blocks)
        block = blocks{k};
        if ~ismember(block.source_file,sources) || ismember(block.block_path,seen), continue; end
        seen{end+1} = block.block_path; %#ok<AGROW>
        node = simscape.logging.findNode(log,block.block_path);
        assert(~isempty(node),'Missing source log: %s',block.block_path);
        row = struct('block_path',block.block_path,'source_file',block.source_file, ...
            'parameters',struct(),'trace_names',{{}});
        dialog = fieldnames(get_param(block.block_path,'DialogParameters'));
        for j = 1:numel(dialog)
            value = get_param(block.block_path,dialog{j});
            if ischar(value), row.parameters.(dialog{j})=value; end
        end
        names = node.childIds;
        for j = 1:numel(names)
            [t,data,unit]=Read_HeatDriveECC_NativeSeries(node.child(names{j}));
            if isempty(t),continue;end
            assert(all(isfinite(t)) && all(isfinite(data),'all'),'Nonfinite boundary trace.');
            traces{end+1} = struct('block_path',block.block_path,'state_name',names{j}, ...
                'unit',unit,'time_s',t(:),'values',data,'channel_count',size(data,2)); %#ok<AGROW>
            row.trace_names{end+1}=names{j};
        end
        assert(~isempty(row.trace_names),'Source has no recorded leaves.');
        rows{end+1}=row; %#ok<AGROW>
    end
    assert(numel(rows)==49,'Expected 43 controlled heat sources, 3 temperature sources and 3 pressure sources.');
    metadata = struct('schema','heatdrive_ecc_native_boundary_discovery_v1', ...
        'source_count',numel(rows),'blocks',{rows},'physical_model_modified',false, ...
        'trace_count',numel(traces),'source_selection',{sources}, ...
        'complete_cycle_verified',false,'full_device_first_law_verified',false, ...
        'production_recovery_allowed',false);
end
