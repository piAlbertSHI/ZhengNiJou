function record=Test_HeatDriveECC_ObservationPreflight(pointer,python)
    state=struct('mode','diagnostic_resume');
    empty=Resolve_HeatDriveECC_ObservationPreflight(struct(),struct(),1,10,'both',false,struct());
    assert(isempty(fieldnames(empty)));
    request=struct('mode','split_preflight','python_executable',python,'source_contract_path',pointer);
    actual=Resolve_HeatDriveECC_ObservationPreflight(request,state,20,200,'native',true,struct());
    assert(isequal(actual,request));
    invalid={request,request,request,request,request,request};
    invalid{1}.mode='anything';invalid{2}.arbitrary_state_reset=true;
    invalid{3}.python_executable='missing-executable';
    states={state,state,state,struct('mode','off'),state,state};
    factors={struct(),struct(),struct(),struct(),struct('geometry','sma_pipe_matched'),struct()};
    states{6}.native_inventory_window_cycles=10;
    rejected=0;
    for k=1:numel(invalid)
        try,Resolve_HeatDriveECC_ObservationPreflight(invalid{k},states{k},20,200,'native',true,factors{k});
        catch,rejected=rejected+1;end
    end
    assert(rejected==6);
    record=struct('default_no_op',true,'explicit_mode_resolved',true,'unsafe_options_rejected',rejected, ...
        'simulation_executed',false,'operating_point_loaded',false);
end
