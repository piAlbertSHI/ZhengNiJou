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
    b=[model '/' names{1}];delay=get_param(b,'UserData');onset=.1;
    if ~isempty(delay)
        assert(isstruct(delay) && strcmp(delay.schema,'cold_pressure_onset_delay_v1'));
        assert(strcmp(get_param(b,'VariableName'),'cold_pressure_onset_delayed'));
        original=slResolve(delay.original_variable,b);old=commands;
        old{1}.time_s=original.Time;old{1}.values=original.Data;
        reference=Build_HeatDriveECC_PreFeedbackRamp(old,.14);
        expected_t=reference.time_s(:);expected_v=reference.bias_MPa(:);
        expected_t(end-1)=.12;
        expected_v(end)=expected_v(end-1)+reference.ramp_slope_MPa_s*(expected_t(end)-.12);
        assert(isequal(commands{1}.time_s(:),expected_t) && isequal(commands{1}.values(:),expected_v));
        onset=.12;
    end
    contract=Build_HeatDriveECC_PreFeedbackRamp(commands,.14,onset);
    if onset==.12
        assert(abs(contract.ramp_slope_MPa_s-reference.ramp_slope_MPa_s)<1e-14);
        contract.pressure_onset_delayed=true;
        contract.original_ramp_start_s=reference.ramp_start_s;
        contract.original_bias_variable=delay.original_variable;
    end
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
