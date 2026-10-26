function record=Capture_HeatDriveECC_StateInterfaceTrace(output,model,contract,destination)
% One compact, disjoint packet per case; not a replacement for a full OP.
    assert(isempty(output.ErrorMessage),'State-interface simulation failed: %s',output.ErrorMessage);
    [native,~]=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model,false, ...
        contract.endpoint_chamber_paths,contract.endpoint_buffer_paths,contract);
    native_packet=Pack_HeatDriveECC_TraceColumns(native); %#ok<NASGU>
    [boundary,~]=Extract_HeatDriveECC_BoundaryTraces(output.simlog,model,contract.tl_topology,contract.thermal_topology);
    source_packet=Pack_HeatDriveECC_TraceColumns(boundary); %#ok<NASGU>
    observations={};available=output.who;
    assert(isempty(setdiff(contract.required_workspace_variables,available)));
    for k=1:numel(contract.workspace_variables)
        name=contract.workspace_variables{k};if ~ismember(name,available),continue;end
        v=output.get(name);
        if isstruct(v) && isfield(v,'time') && isfield(v,'signals')
            t=double(v.time(:));data=squeeze(double(v.signals.values));
        elseif isa(v,'timeseries'),t=double(v.Time(:));data=squeeze(double(v.Data));
        else,continue;end
        if isvector(data),data=data(:);
        elseif size(data,1)~=numel(t) && size(data,2)==numel(t),data=data.';end
        assert(size(data,1)==numel(t) && all(isfinite(data),'all'));
        observations{end+1}=struct('block_path',model,'state_name',name,'time_s',t, ...
            'values',data,'channel_count',size(data,2),'unit','model-signal'); %#ok<AGROW>
    end
    workspace_packet=Pack_HeatDriveECC_TraceColumns(observations); %#ok<NASGU>
    state_observation=Extract_HeatDriveECC_ObservedStates(output.interface_state_history,10,2);
    state_packet=Pack_HeatDriveECC_TraceColumns(state_observation.states); %#ok<NASGU>
    record=struct('native_trace_count',numel(native),'workspace_trace_count',numel(observations), ...
        'source_trace_count',numel(boundary),'logged_public_state_groups',state_observation.logged_state_group_count, ...
        'all_vendor_private_state_fields_exposed',false,'observations_are_not_a_restart_state',true);
    assert(~isfile(destination));save(destination,'native_packet','source_packet','workspace_packet','state_packet','record','-v7');
end
