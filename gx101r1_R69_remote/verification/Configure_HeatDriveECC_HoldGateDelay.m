function contract=Configure_HeatDriveECC_HoldGateDelay(model,event_time)
% Delay one initial event only for causal diagnosis; no production eligibility.
    if nargin<2,event_time=.12;end
    assert(isscalar(event_time) && any(event_time==[.12 .13]));
    assert(strcmp(get_param(model,'StopTime'),'0.14'));
    source=[model '/SMA/HoldThermalGateCommandFromWorkspace'];
    assert(strcmp(get_param(source,'Interpolate'),'off') && isempty(get_param(source,'UserData')));
    variable=get_param(source,'VariableName');original=slResolve(variable,source);
    t=original.Time(:);v=original.Data(:);idx=find(v~=v(1),1);
    assert(v(1)==1e-6 && v(idx)==1e6 && abs(t(idx)-.1)<1e-15 && t(idx+1)>.12);
    shifted=t;shifted(idx)=event_time;assert(all(diff(shifted)>0));
    name='cold_hold_gate_delayed_diagnostic';assignin('base',name,timeseries(v,shifted));
    set_param(source,'VariableName',name,'UserData',struct('original_variable',variable,'index',idx,'event_time',event_time));
    contract=Verify_HeatDriveECC_HoldGateDelay(model);
end
