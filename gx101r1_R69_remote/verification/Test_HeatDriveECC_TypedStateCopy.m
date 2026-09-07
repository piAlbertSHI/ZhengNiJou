function Test_HeatDriveECC_TypedStateCopy(repo)
% Verify public typed-state edits are detached from the diagnostic template.
    root=fullfile(repo,'outputs_storage_audit','c200_source_compatibility_20260907','archived_source_probe_v4');
    load_system('simulink');
    template=load(fullfile(root,'DO_NOT_RESUME_FOR_PRODUCTION.mat'),'diagnostic_op');
    observations=load(fullfile(root,'registered_states.mat'),'observation');
    states=template.diagnostic_op.loggedStates;
    assert(isa(states,'Simulink.SimulationData.Dataset') && states.numElements==73,'Typed-state load failed.');
    for k=1:states.numElements
        state=states.getElement(k); original=state.Values;
        block=char(state.BlockPath.getBlock(1)); name=char(state.Name);
        idx=find(cellfun(@(r) strcmp(r.block_path,block) && strcmp(r.state_name,name),observations.observation.states));
        assert(isscalar(idx),'Unique observed state required.');
        row=observations.observation.states{idx};
        series=state.Values;
        assert(~isa(series,'handle'),'Expected value-class timeseries.');
        series.Data=reshape(row.values(1,:),size(series.Data));
        series.Time=2000;
        state.Values=series;
        unchanged=states.getElement(k);
        assert(isequal(unchanged.Values.Data,original.Data) && ...
            isequal(unchanged.Values.Time,original.Time),'Source state changed through an alias.');
        assert(isequaln(series.DataInfo,original.DataInfo) && ...
            isequal(size(series.Data),size(original.Data)) && ...
            strcmp(class(series.Data),class(original.Data)) && ...
            isequal(series.Data(:),row.values(1,:).'),'Typed metadata or imported values changed.');
    end
    assert(isequaln(states,template.diagnostic_op.loggedStates),'Source template changed.');
    fprintf('TYPED_STATE_VALUE_COPY_PASS=1 GROUPS=%d\n',states.numElements);
end
