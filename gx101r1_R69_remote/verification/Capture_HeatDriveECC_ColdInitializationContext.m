function Capture_HeatDriveECC_ColdInitializationContext(model,stage)
% Read callback-visible configuration and public targets; never set model data.
    assert(any(strcmp(stage,{'InitFcn','StartFcn','StopFcn'})),'Unknown capture stage.');
    assert(strcmp(get_param(model,'SimscapeOperatingPoint'),'cold_public_targets'),'Unexpected public target variable.');
    blocks=find_system(model,'LookUnderMasks','all','FollowLinks','on','MaskType','Solver Configuration');
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
    record.global_fixed_step=get_param(model,'FixedStep');
    converter=[model '/SMAPressurePI_SimulinkPS'];
    record.pressure_converter=struct('Unit',get_param(converter,'Unit'), ...
        'FilteringAndDerivatives',get_param(converter,'FilteringAndDerivatives'), ...
        'UdotUserProvided',get_param(converter,'UdotUserProvided'),'StopTime',get_param(model,'StopTime'));
    if strcmp(record.pressure_converter.UdotUserProvided,'1')
        p=get_param(converter,'PortHandles');line=get_param(p.Inport(2),'Line');
        source=getfullname(get_param(line,'SrcBlockHandle'));
        if strcmp(source,[model '/ColdInitialPressureDerivativeOnly'])
            assert(strcmp(get_param(model,'StopTime'),'0') && strcmp(get_param(source,'Value'),'0'), ...
                'Initial derivative must not enter a trajectory.');
        else
            assert(strcmp(source,[model '/ColdPressureDerivative']) && ...
                ismember(str2double(get_param(model,'StopTime')),[0,.2]),'Unknown derivative diagnostic.');
            chart=find(sfroot,'-isa','Stateflow.EMChart','Path',source);assert(isscalar(chart));
            record.pressure_converter.chart_script=chart.Script;
        end
        record.pressure_converter.derivative_source=source;
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
        for name={'stored_mass','stored_energy'}
            idx=idx+1;
            record.buffer_nominals{idx}=struct('block_path',p,'state_name',name{1}, ...
                'specify',get_param(p,[name{1} '_nominal_specify']), ...
                'value',get_param(p,[name{1} '_nominal_value']),'unit',get_param(p,[name{1} '_nominal_unit']));
        end
    end
    history=evalin('base','cold_initialization_context');history{end+1}=record;
    assignin('base','cold_initialization_context',history);
end
