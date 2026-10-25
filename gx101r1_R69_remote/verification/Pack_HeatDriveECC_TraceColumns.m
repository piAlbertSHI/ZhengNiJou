function packet=Pack_HeatDriveECC_TraceColumns(traces)
% Lossless shared clocks; do not repeat the same full time vector per leaf.
    grids={};rows=cell(size(traces));
    for k=1:numel(traces)
        row=traces{k};t=row.time_s(:);assert(isa(t,'double') && all(isfinite(t)) && all(diff(t)>=0));
        assert(size(row.values,1)==numel(t),'Time/data shape mismatch.');
        hit=[];
        for j=1:numel(grids)
            if isequal(typecast(grids{j}.time_s,'uint64'),typecast(t,'uint64')),hit=j;break;end
        end
        if isempty(hit),hit=numel(grids)+1;grids{hit}=struct('grid_index',hit,'time_s',t);end %#ok<AGROW>
        row=rmfield(row,'time_s');row.grid_index=hit;rows{k}=row;
    end
    packet=struct('schema','heatdrive_ecc_shared_clock_trace_columns_v1', ...
        'time_grids',{grids},'rows',{rows},'time_interpolation_performed',false, ...
        'state_values_modified',false,'not_an_OP_or_restart_state',true);
end
