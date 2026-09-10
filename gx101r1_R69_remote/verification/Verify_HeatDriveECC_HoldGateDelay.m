function contract=Verify_HeatDriveECC_HoldGateDelay(model)
    assert(strcmp(get_param(model,'StartTime'),'0') && strcmp(get_param(model,'StopTime'),'0.14'));
    assert(strcmp(get_param(model,'LoadInitialState'),'off') && strcmp(get_param(model,'SaveOperatingPoint'),'off'));
    source=[model '/SMA/HoldThermalGateCommandFromWorkspace'];marker=get_param(source,'UserData');
    assert(isstruct(marker) && strcmp(get_param(source,'VariableName'),'cold_hold_gate_delayed_diagnostic'));
    original=slResolve(marker.original_variable,source);actual=slResolve(get_param(source,'VariableName'),source);
    t=original.Time(:);v=original.Data(:);idx=marker.index;
    assert(strcmp(get_param(source,'Interpolate'),'off') && v(1)==1e-6 && v(idx)==1e6);
    expected=t;expected(idx)=.12;
    assert(isequal(actual.Time(:),expected) && isequal(actual.Data(:),v) && abs(t(idx)-.1)<1e-15);
    contract=struct('original_event_s',t(idx),'delayed_event_s',.12,'inactive',v(1),'active',v(idx), ...
        'only_one_command_time_changed',true,'production_recovery_allowed',false,'source',source);
end
