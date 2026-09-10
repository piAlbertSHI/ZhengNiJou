function contract=Verify_HeatDriveECC_PreFeedbackRamp(model)
    assert(strcmp(get_param(model,'StartTime'),'0') && strcmp(get_param(model,'StopTime'),'0.14'));
    assert(strcmp(get_param(model,'LoadInitialState'),'off') && strcmp(get_param(model,'SaveOperatingPoint'),'off'));
    names={'SMAPressureBiasFromWorkspace','SMAFlowTargetFromWorkspace', ...
        'SMAPressureFeedbackEnableFromWorkspace','SMAPressureFeedbackResetFromWorkspace'};
    commands=cell(1,4);
    for k=1:4
        b=[model '/' names{k}];variable=get_param(b,'VariableName');v=slResolve(variable,b);
        commands{k}=struct('block',b,'time_s',v.Time,'values',v.Data,'interpolate',get_param(b,'Interpolate'));
    end
    contract=Build_HeatDriveECC_PreFeedbackRamp(commands,.14);
    source=[model '/ColdPreFeedbackPressureDerivative'];converter=[model '/SMAPressurePI_SimulinkPS'];
    assert(strcmp(get_param(source,'BlockType'),'FromWorkspace') && strcmp(get_param(source,'Interpolate'),'off') && ...
        strcmp(get_param(source,'OutputAfterFinalValue'),'Holding final value'));
    v=slResolve(get_param(source,'VariableName'),source);
    assert(isequal(v.Time(:),contract.time_s(:)) && isequal(v.Data(:),contract.derivative_MPa_s(:)));
    assert(strcmp(get_param(converter,'Unit'),'MPa') && strcmp(get_param(converter,'FilteringAndDerivatives'),'provide') && ...
        strcmp(get_param(converter,'UdotUserProvided'),'1'));
    ports=get_param(converter,'PortHandles');assert(numel(ports.Inport)==2);
    marker=get_param(converter,'UserData');
    direct=isequal(marker,'cold_pre_feedback_direct_bias_v1');
    assert(isempty(marker) || direct,'Unknown pressure-path marker.');
    value_source=[model '/ColdObserver_pressure_Output'];
    if direct,value_source=[model '/SMAPressureBiasFromWorkspace'];end
    assert(strcmp(getfullname(get_param(get_param(ports.Inport(1),'Line'),'SrcBlockHandle')),value_source));
    assert(strcmp(getfullname(get_param(get_param(ports.Inport(2),'Line'),'SrcBlockHandle')),source));
    bias=[model '/ColdObserver_bias_PS'];bp=get_param(bias,'PortHandles');
    assert(strcmp(get_param(bias,'Unit'),'MPa') && ...
        strcmp(get_param(bias,'FilteringAndDerivatives'),'provide') && ...
        strcmp(get_param(bias,'UdotUserProvided'),'1') && numel(bp.Inport)==2);
    assert(strcmp(getfullname(get_param(get_param(bp.Inport(1),'Line'),'SrcBlockHandle')), ...
        [model '/SMAPressureBiasFromWorkspace']));
    assert(strcmp(getfullname(get_param(get_param(bp.Inport(2),'Line'),'SrcBlockHandle')),source));
    observer=[model '/ColdSMAPassiveObserver'];
    assert(strcmp(get_param(observer,'SourceFile'),'ecc_sma_hybrid.pressure_controller') && ...
        strcmp(get_param(observer,'initial_integral'),'0'));
    contract.derivative_source=source;
    if direct
        contract.direct_bias_diagnostic=true;
        contract.value_source=value_source;
        contract.equivalence_scope='feedback disabled, integral held zero, unsaturated bias, t<=0.14s only';
    end
end
