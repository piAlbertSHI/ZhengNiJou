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
