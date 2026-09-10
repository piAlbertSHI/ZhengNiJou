function contract=Configure_HeatDriveECC_PressureOnsetDelay(model)
% Preserve the slope while separating pressure onset from the valve event.
    before=Verify_HeatDriveECC_PreFeedbackRamp(model);
    assert(before.direct_bias_diagnostic && abs(before.ramp_start_s-.1)<1e-15);
    b=[model '/SMAPressureBiasFromWorkspace'];
    assert(isempty(get_param(b,'UserData')));
    original=get_param(b,'VariableName');
    t=before.time_s(:);v=before.bias_MPa(:);idx=numel(t)-1;
    assert(t(idx-1)<.12 && t(end)>.14);
    t(idx)=.12;v(end)=v(idx)+before.ramp_slope_MPa_s*(t(end)-t(idx));
    assignin('base','cold_pressure_onset_delayed',timeseries(v,t));
    set_param(b,'VariableName','cold_pressure_onset_delayed', ...
        'UserData',struct('schema','cold_pressure_onset_delay_v1','original_variable',original));
    dp=[diff(v)./diff(t);0];
    assignin('base','cold_pre_feedback_dp',timeseries(dp,t));
    contract=Verify_HeatDriveECC_PreFeedbackRamp(model);
end
