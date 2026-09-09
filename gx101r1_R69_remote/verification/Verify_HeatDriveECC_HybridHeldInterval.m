function contract=Verify_HeatDriveECC_HybridHeldInterval(model)
% Prove the constant-pressure derivative only before the first command boundary.
    stop=str2double(get_param(model,'StopTime'));
    assert(stop==.04 && strcmp(get_param(model,'StartTime'),'0') && ...
        strcmp(get_param(model,'LoadInitialState'),'off') && strcmp(get_param(model,'SaveOperatingPoint'),'off'));
    names={'SMAPressureBiasFromWorkspace','SMAPressureFeedbackEnableFromWorkspace','SMAPressureFeedbackResetFromWorkspace'};
    expected=[-1e-6,0,1];rows=cell(1,3);until=Inf;
    for k=1:3
        b=[model '/' names{k}];v=slResolve(get_param(b,'VariableName'),b);
        assert(isa(v,'timeseries') && numel(v.Time)>=2 && v.Time(1)==0 && ...
            v.Time(2)>stop && all(v.Data(1:2)==expected(k)), 'Held interval crosses a command change.');
        until=min(until,v.Time(2));
        rows{k}=struct('block',b,'time_s',v.Time(1:2),'values',v.Data(1:2),'interpolate',get_param(b,'Interpolate'));
    end
    assert(until==.05 && strcmp(rows{1}.interpolate,'on') && ...
        strcmp(rows{2}.interpolate,'off') && strcmp(rows{3}.interpolate,'off'));
    source=[model '/ColdHeldPressureDerivative'];converter=[model '/SMAPressurePI_SimulinkPS'];
    assert(strcmp(get_param(source,'Value'),'0') && strcmp(get_param(source,'SampleTime'),'inf'));
    p=get_param(converter,'PortHandles');assert(numel(p.Inport)==2);
    assert(strcmp(getfullname(get_param(get_param(p.Inport(2),'Line'),'SrcBlockHandle')),source));
    assert(strcmp(getfullname(get_param(get_param(p.Inport(1),'Line'),'SrcBlockHandle')),[model '/ColdObserver_pressure_Output']));
    observer=[model '/ColdSMAPassiveObserver'];
    assert(strcmp(get_param(observer,'SourceFile'),'ecc_sma_hybrid.pressure_controller') && ...
        strcmp(get_param(observer,'initial_integral'),'0'));
    contract=struct('schema','heatdrive_ecc_hybrid_held_interval_v1','allowed_stop_time_s',stop, ...
        'constant_interval_end_exclusive_s',until,'commands',{rows},'derivative_source',source, ...
        'first_derivative_MPa_s',0,'feedback_enable',0,'reset_held',1, ...
        'full_cycle_derivative_verified',false,'production_recovery_allowed',false);
end
