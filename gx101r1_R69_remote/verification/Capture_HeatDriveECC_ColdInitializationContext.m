function Capture_HeatDriveECC_ColdInitializationContext(model,stage)
% Read callback-visible configuration and public targets; never set model data.
    assert(any(strcmp(stage,{'InitFcn','StartFcn','StopFcn'})),'Unknown capture stage.');
    assert(strcmp(get_param(model,'SimscapeOperatingPoint'),'cold_public_targets'),'Unexpected public target variable.');
    blocks=find_system(model,'LookUnderMasks','all','FollowLinks','on','MaskType','Solver Configuration');
    isolated=[model '/ColdObserver_Solver'];observer_solver=struct();
    if any(strcmp(blocks,isolated))
        assert(numel(blocks)==2 && getSimulinkBlockHandle([model '/ColdSMAPassiveObserver'])>0);
        blocks=blocks(~strcmp(blocks,isolated));keys=fieldnames(get_param(isolated,'DialogParameters'));settings=struct();
        for k=1:numel(keys)
            settings.(keys{k})=get_param(isolated,keys{k});
            assert(isequal(settings.(keys{k}),get_param(blocks{1},keys{k})),'Observer solver configuration changed.');
        end
        observer_solver=struct('path',isolated,'settings',settings,'copied_settings_identical',true);
    end
    assert(isscalar(blocks),'Expected one coupled solver.');
    names={'ConsistencyTolSource','ConsistencyAbsTol','ConsistencyRelTol','ConsistencyTolFactor', ...
        'ResidualTolerance','UseLocalSolver','LocalSolverChoice','LocalSolverSampleTime'};
    settings=struct();for k=1:numel(names),settings.(names{k})=get_param(blocks{1},names{k});end
    point=slResolve('cold_public_targets',model);
    assert(isa(point,'simscape.op.OperatingPoint') && ~hasPrivateData(point),'Only public cold targets are allowed.');
    expected=evalin('base','cold_public_target_records');
    targets=cell(size(expected));
    for k=1:numel(expected)
        t=expected{k};target=get(point,t.path);
        assert(isa(target,'simscape.op.Target'),'Missing public runtime target.');
        targets{k}=struct('path',t.path,'unit',t.unit,'value',value(target.Value,t.unit), ...
            'priority',char(string(target.Priority)));
    end
    record=struct('stage',stage,'simulation_status',get_param(model,'SimulationStatus'), ...
        'model_file',get_param(model,'FileName'),'mode',get_param(model,'SimulationMode'), ...
        'solver_settings',settings,'RelTol',get_param(model,'RelTol'),'AbsTol',get_param(model,'AbsTol'), ...
        'SimscapeUseOperatingPoints',get_param(model,'SimscapeUseOperatingPoints'), ...
        'LoadInitialState',get_param(model,'LoadInitialState'),'targets',{targets},'has_private_data',false);
    record.normalize_using_nominal_values=get_param(model,'SimscapeNormalizeSystem');
    record.AutoScaleAbsTol=get_param(model,'AutoScaleAbsTol');
    record.passive_observer_solver=observer_solver;
    observer_flow=[model '/ColdObserver_mdot_PS'];
    if getSimulinkBlockHandle(observer_flow)>0
        p=get_param(observer_flow,'PortHandles');line=get_param(p.Inport(1),'Line');assert(line>0);
        record.passive_observer_flow_input=struct('path',observer_flow,'Unit',get_param(observer_flow,'Unit'), ...
            'FilteringAndDerivatives',get_param(observer_flow,'FilteringAndDerivatives'), ...
            'UdotUserProvided',get_param(observer_flow,'UdotUserProvided'),'input_count',numel(p.Inport), ...
            'value_source',getfullname(get_param(line,'SrcBlockHandle')));
    end
    record.global_fixed_step=get_param(model,'FixedStep');
    record.solver_iteration_options=struct('SolverResetMethod',get_param(model,'SolverResetMethod'), ...
        'MaxOrder',get_param(model,'MaxOrder'));
    record.constitutive_discrete_blocks={};
    for name={'ECC_Constitutive21_SMA_TempDelay','ECC_Constitutive21_SE_TempDelay','ECC_Constitutive21_StateDelay'}
        path=[model '/' name{1}];
        if getSimulinkBlockHandle(path)>0
            sample=get_param(path,'SampleTime');
            record.constitutive_discrete_blocks{end+1}=struct('path',path,'block_type',get_param(path,'BlockType'), ...
                'sample_time_expression',sample,'sample_time_s',slResolve(sample,path), ...
                'initial_condition_expression',get_param(path,'InitialCondition'));
        end
    end
    record.solver_failure_policy=struct('MinStepSizeMsg',get_param(model,'MinStepSizeMsg'), ...
        'MaxConsecutiveMinStep',get_param(model,'MaxConsecutiveMinStep'),'MinStep',get_param(model,'MinStep'));
    record.output_sampling_settings=struct();
    for key={'OutputOption','OutputTimes','Refine','Decimation','SimscapeLogDecimation','SimscapeLogLimitData'}
        record.output_sampling_settings.(key{1})=get_param(model,key{1});
    end
    record.algebraic_loop_options=struct('solver',get_param(model,'AlgebraicLoopSolver'), ...
        'diagnostic',get_param(model,'AlgebraicLoopMsg'));
    record.original_control_state_blocks_present=struct( ...
        'lag',getSimulinkBlockHandle([model '/SMAPressurePI_ErrorLag'])>0, ...
        'integral',getSimulinkBlockHandle([model '/SMAPressurePI_Integrator'])>0);
    external_lag=[model '/ColdObserver_ErrorLag'];
    if getSimulinkBlockHandle(external_lag)>0
        p=get_param(external_lag,'PortHandles');line=get_param(p.Inport(1),'Line');
        record.external_controller_lag=struct('path',external_lag,'block_type',get_param(external_lag,'BlockType'), ...
            'numerator',get_param(external_lag,'Numerator'),'denominator',get_param(external_lag,'Denominator'), ...
            'input_source',getfullname(get_param(line,'SrcBlockHandle')));
    end
    converter=[model '/SMAPressurePI_SimulinkPS'];
    candidate=[model '/ColdSMAPSController'];
    if getSimulinkBlockHandle(candidate)>0
        assert(getSimulinkBlockHandle(converter)<0 && strcmp(get_param(model,'StopTime'),'0'));
        record.pressure_converter=struct('representation','physical_signal_controller', ...
            'source_file',get_param(candidate,'SourceFile'),'StopTime',get_param(model,'StopTime'));
        record.ps_input_converters={};
        names={'ColdSMA_bias_PS','ColdSMA_target_PS','ColdSMA_enable_PS','ColdSMA_reset_PS','ColdSMA_InitialMdot_PS'};
        for k=1:numel(names)
            block=[model '/' names{k}];if getSimulinkBlockHandle(block)<0,continue;end
            p=get_param(block,'PortHandles');inputs={};
            for j=1:numel(p.Inport)
                line=get_param(p.Inport(j),'Line');assert(line>0);
                source=getfullname(get_param(line,'SrcBlockHandle'));kind=get_param(source,'BlockType');
                item=struct('path',source,'type',kind,'sample_time',get_param(source,'SampleTime'));
                if strcmp(kind,'Constant')
                    item.value=get_param(source,'Value');
                elseif strcmp(kind,'FromWorkspace')
                    item.variable=get_param(source,'VariableName');item.interpolate=get_param(source,'Interpolate');
                    signal=slResolve(item.variable,source);item.time_s=signal.Time;item.values=signal.Data;
                else
                    error('Unexpected cold PS converter input.');
                end
                inputs{end+1}=item; %#ok<AGROW>
            end
            record.ps_input_converters{end+1}=struct('path',block,'Unit',get_param(block,'Unit'), ...
                'FilteringAndDerivatives',get_param(block,'FilteringAndDerivatives'), ...
                'UdotUserProvided',get_param(block,'UdotUserProvided'),'inputs',{inputs});
        end
        record.ps_controller_parameters=struct();
        keys={'normalization','tau','kp','ki','initial_lag','initial_integral', ...
            'integral_min','integral_max','pressure_min','pressure_max'};
        for j=1:numel(keys)
            record.ps_controller_parameters.(keys{j})=get_param(candidate,keys{j});
            record.ps_controller_parameters.([keys{j} '_unit'])=get_param(candidate,[keys{j} '_unit']);
        end
    else
    record.pressure_converter=struct('Unit',get_param(converter,'Unit'), ...
        'FilteringAndDerivatives',get_param(converter,'FilteringAndDerivatives'), ...
        'UdotUserProvided',get_param(converter,'UdotUserProvided'),'StopTime',get_param(model,'StopTime'));
    p=get_param(converter,'PortHandles');line=get_param(p.Inport(1),'Line');assert(line>0);
    record.pressure_converter.value_source=getfullname(get_param(line,'SrcBlockHandle'));
    if strcmp(record.pressure_converter.UdotUserProvided,'1')
        p=get_param(converter,'PortHandles');line=get_param(p.Inport(2),'Line');
        source=getfullname(get_param(line,'SrcBlockHandle'));
        if strcmp(source,[model '/ColdInitialPressureDerivativeOnly'])
            assert(strcmp(get_param(model,'StopTime'),'0') && strcmp(get_param(source,'Value'),'0'), ...
                'Initial derivative must not enter a trajectory.');
        elseif strcmp(source,[model '/ColdHeldPressureDerivative'])
            record.held_interval_contract=Verify_HeatDriveECC_HybridHeldInterval(model);
        else
            assert(strcmp(source,[model '/ColdPressureDerivative']) && ...
                ismember(str2double(get_param(model,'StopTime')),[0,.2]),'Unknown derivative diagnostic.');
            chart=find(sfroot,'-isa','Stateflow.EMChart','Path',source);assert(isscalar(chart));
            record.pressure_converter.chart_script=chart.Script;
        end
        record.pressure_converter.derivative_source=source;
    end
    end
    record.global_solver_configuration=struct('Solver',get_param(model,'Solver'), ...
        'SolverType',get_param(model,'SolverType'),'MaxStep',get_param(model,'MaxStep'), ...
        'InitialStep',get_param(model,'InitialStep'));
    runtime_names={'ResolveIndetEquations','DoFixedCost','ComputeImpulses','ImpulseIterations','IndexReductionMethod','DoDC'};
    record.runtime_solver_options=struct();
    for k=1:numel(runtime_names)
        record.runtime_solver_options.(runtime_names{k})=get_param(blocks{1},runtime_names{k});
    end
    record.buffer_nominals=cell(1,8);idx=0;
    for block={'ColdFluidBuffer','HotFluidBuffer','SHEXFluidBuffer','SMAHotFluidBuffer'}
        p=[model '/' block{1}];
        inventory_names={'stored_mass','stored_energy'};
        if startsWith(get_param(p,'SourceFile'),'ecc_nonlinear_'),inventory_names={'mass_coordinate','energy_delta'};end
        for name=inventory_names
            idx=idx+1;
            record.buffer_nominals{idx}=struct('block_path',p,'state_name',name{1}, ...
                'specify',get_param(p,[name{1} '_nominal_specify']), ...
                'value',get_param(p,[name{1} '_nominal_value']),'unit',get_param(p,[name{1} '_nominal_unit']));
        end
    end
    record.chamber_nominals={};
    for block={'SMA_PumpInletConnectingPipeVolume','SMA_PumpOutletConnectingPipeVolume'}
        p=[model '/' block{1}];
        inventory_names={'stored_mass','stored_energy'};
        if startsWith(get_param(p,'SourceFile'),'ecc_nonlinear_'),inventory_names={'mass_coordinate','energy_delta'};end
        for key=inventory_names
            name=key{1};record.chamber_nominals{end+1}=struct('block_path',p,'state_name',name, ...
                'specify',get_param(p,[name '_nominal_specify']),'value',get_param(p,[name '_nominal_value']), ...
                'unit',get_param(p,[name '_nominal_unit']));
        end
    end
    history=evalin('base','cold_initialization_context');history{end+1}=record;
    assignin('base','cold_initialization_context',history);
end
