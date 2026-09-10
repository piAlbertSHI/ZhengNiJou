function report=Probe_HeatDriveECC_ResetEventSides(out)
% Observe the discrete source directly, independently of the continuous sum.
    assert(~isfolder(out),'Never overwrite event-side evidence.');
    report=struct('cases',{{}},'matlab_release',version('-release'), ...
        'actual_coupled_model_tested',false,'production_recovery_allowed',false);
    steps=[.00002,.00001];
    for k=1:numel(steps)
        model=['ecc_reset_event_sides_' num2str(k)];
        assert(~bdIsLoaded(model));new_system(model);cleanup=onCleanup(@() close_system(model,0));
        add_block('simulink/Sources/Clock',[model '/Time']);
        add_block('simulink/Math Operations/Gain',[model '/Slope'],'Gain','2');
        add_block('simulink/Sources/Constant',[model '/Offset'],'Value','1');
        add_block('simulink/Discrete/Zero-Order Hold',[model '/SampledTime'],'SampleTime','.001');
        add_block('simulink/Math Operations/Sum',[model '/Flux'],'Inputs','+++');
        add_block('simulink/Continuous/Integrator',[model '/Inventory'],'InitialCondition','1');
        add_block('simulink/Sinks/Out1',[model '/InventoryOut']);
        add_block('simulink/Sinks/Out1',[model '/FluxOut'],'Port','2');
        add_block('simulink/Sinks/Out1',[model '/SampledTimeOut'],'Port','3');
        add_line(model,'Time/1','Slope/1');add_line(model,'Time/1','SampledTime/1');
        add_line(model,'Slope/1','Flux/1');add_line(model,'Offset/1','Flux/2');
        add_line(model,'SampledTime/1','Flux/3');add_line(model,'SampledTime/1','SampledTimeOut/1');
        add_line(model,'Flux/1','Inventory/1');add_line(model,'Inventory/1','InventoryOut/1');
        add_line(model,'Flux/1','FluxOut/1');
        set_param(model,'SolverType','Variable-step','Solver','ode23t','SolverResetMethod','Fast', ...
            'InitialStep','auto','MaxStep',num2str(steps(k),'%.17g'),'RelTol','1e-6','AbsTol','1e-8', ...
            'AutoScaleAbsTol','on','StartTime','0','StopTime','.04','OutputOption','RefineOutputTimes', ...
            'Refine','1','Decimation','1','SaveTime','on','TimeSaveName','tout','SaveOutput','on', ...
            'OutputSaveName','yout','SaveFormat','Dataset','ReturnWorkspaceOutputs','on','SaveFinalState','off');
        result=sim(model);y=result.yout{1}.Values;f=result.yout{2}.Values;h=result.yout{3}.Values;
        report.cases{k}=struct('max_step_s',steps(k),'solver',get_param(model,'Solver'), ...
            'reset_method',get_param(model,'SolverResetMethod'),'sample_time',get_param([model '/SampledTime'],'SampleTime'), ...
            'time_s',y.Time,'inventory',y.Data,'flux_time_s',f.Time,'flux',f.Data, ...
            'held_time_s',h.Time,'held_value',h.Data);
        clear cleanup
    end
    mkdir(out);fid=fopen(fullfile(out,'reset_event_sides.json'),'w','n','UTF-8');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));clear cleanup
    fprintf('%s\n',jsonencode(struct('probe_complete',true,'cases',numel(report.cases), ...
        'production_recovery_allowed',false)));
end
