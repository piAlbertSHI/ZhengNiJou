function audit=Audit_HeatDriveECC_OperatingPointAPISemantics(output_root)
% Isolated interface test. Never load, reset, or modify production state.
    assert(~isfolder(output_root),'Do not overwrite evidence.');
    [code,commit]=system('git rev-parse HEAD');assert(code==0,'Cannot record source.');
    [code,dirty]=system('git status --porcelain');assert(code==0 && isempty(strtrim(dirty)),'Commit source first.');
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));
    cleanup_diary=onCleanup(@() diary('off'));
    generation=Simulink.fileGenControl('getConfig');
    cleanup_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'build_cache'), ...
        'CodeGenFolder',fullfile(output_root,'generated_code'),'createDir',true);
    load_system('simulink');model='ecc_operating_point_api_isolation';
    assert(~bdIsLoaded(model),'Model name in use.');new_system(model);
    cleanup_model=onCleanup(@() close_system(model,0));
    audit=struct('schema','heatdrive_ecc_op_api_isolation_v1','execution_commit',strtrim(commit), ...
        'matlab_release',version('-release'),'production_model_loaded',false, ...
        'production_checkpoint_loaded',false,'production_recovery_allowed',false, ...
        'collection_complete',false,'cases',{{}},'error_message','');
    try
        mass=[model '/Mass'];solver=[model '/Solver'];memory=[model '/Memory'];
        add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass',mass,'mass','1','mass_unit','kg', ...
            'sp_heat','1000','sp_heat_unit','J/(K*kg)','T','300','T_unit','K','T_specify','on','T_priority','High');
        add_block('nesl_utility/Solver Configuration',solver);
        mp=simscape.connectionPortProperties(mass);sp=simscape.connectionPortProperties(solver);
        assert(isscalar(mp) && isscalar(sp),'Unexpected ports.');
        simscape.addConnection(mass,mp.Name,solver,sp.Name);
        add_block('simulink/Sources/Constant',[model '/Zero'],'Value','0');
        add_block('simulink/Continuous/Integrator',memory,'InitialCondition','7.25');
        add_block('simulink/Sinks/To Workspace',[model '/MemoryLog'],'VariableName','memory_log','SaveFormat','Timeseries');
        add_line(model,'Zero/1','Memory/1');add_line(model,'Memory/1','MemoryLog/1');
        set_param(solver,'UseLocalSolver','on','LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER','LocalSolverSampleTime','0.001');
        cold=simscape.op.OperatingPoint;hot=simscape.op.OperatingPoint;
        cold=set(cold,'Mass/T',simscape.op.Target(340,'K','High'));
        hot=set(hot,'Mass/T',simscape.op.Target(400,'K','High'));
        input=Simulink.SimulationInput(model);input=input.setVariable('thermal_targets',cold);
        input=input.setModelParameter('StartTime','2000','StopTime','2000.001', ...
            'Solver','ode3','FixedStep','0.001','SimulationMode','accelerator', ...
            'SimscapeUseOperatingPoints','on','SimscapeOperatingPoint','thermal_targets', ...
            'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
            'SaveState','on','StateSaveName','states','SaveFormat','Dataset', ...
            'SaveFinalState','on','FinalStateName','xFinal','SaveOperatingPoint','on', ...
            'SaveTime','off','SaveOutput','off','ReturnWorkspaceOutputs','on','CaptureErrors','on', ...
            'OperatingPointContentsChecksumMismatchMsg','error','OperatingPointInterfaceChecksumMismatchMsg','error');
        low=sim(input);assert(isempty(low.ErrorMessage),'Low seed failed: %s',low.ErrorMessage);
        high=sim(input.setVariable('thermal_targets',hot));assert(isempty(high.ErrorMessage),'High seed failed: %s',high.ErrorMessage);
        audit.low_seed=observe(low,mass);audit.high_seed=observe(high,mass);
        assert(all(audit.low_seed.temperature_K==340) && all(audit.high_seed.temperature_K==400),'Conflicting target seeds not established.');
        original=low.xFinal.loggedStates;
        for name={'baseline','conflicting_simscape_target','builtin_memory_edit','whole_solver_group_copy'}
            row=struct('name',name{1},'computation_complete',false,'error_message','', ...
                'public_assignment_completed',false,'state_before',[],'state_after',[], ...
                'target_temperature_K',340,'requested_memory',7.25);
            try
                candidate=low.xFinal;ds=candidate.loggedStates;
                run=input.setModelParameter('StopTime','2000.002');
                if strcmp(name{1},'conflicting_simscape_target')
                    run=run.setVariable('thermal_targets',hot);row.target_temperature_K=400;
                end
                if strcmp(name{1},'builtin_memory_edit') || strcmp(name{1},'whole_solver_group_copy')
                    selected=memory;if strcmp(name{1},'whole_solver_group_copy'),selected=solver;end
                    count=0;
                    for k=1:ds.numElements
                        item=ds.getElement(k);
                        if ~strcmp(char(item.BlockPath.getBlock(1)),selected),continue;end
                        row.state_before=item.Values.Data(:).';
                        if strcmp(name{1},'builtin_memory_edit')
                            values=item.Values;values.Data(:)=8.25;item.Values=values;row.requested_memory=8.25;
                        else
                            hot_states=high.xFinal.loggedStates;found=0;
                            for j=1:hot_states.numElements
                                hot_item=hot_states.getElement(j);
                                if strcmp(char(hot_item.BlockPath.getBlock(1)),solver)
                                    assert(isequal(size(item.Values.Data),size(hot_item.Values.Data)),'Whole-group shape changed.');
                                    item=hot_item;found=found+1;
                                end
                            end
                            assert(found==1,'Expected one whole solver group.');
                        end
                        row.state_after=item.Values.Data(:).';ds=ds.setElement(k,item);count=count+1;
                    end
                    assert(count==1,'Expected one selected public group.');candidate.loggedStates=ds;
                    assert(isequaln(candidate.loggedStates,ds),'Public readback changed.');
                    row.public_assignment_completed=true;
                end
                output=sim(run.setInitialState(candidate));
                assert(isempty(output.ErrorMessage),'Restart rejected: %s',output.ErrorMessage);
                row.observed=observe(output,mass);row.computation_complete=true;
            catch ME
                row.error_message=ME.message;row.error_identifier=ME.identifier;
            end
            audit.cases{end+1}=row; %#ok<AGROW>
        end
        assert(isequaln(original,low.xFinal.loggedStates),'Original isolated OP changed.');
        audit.collection_complete=numel(audit.cases)==4;
    catch ME
        audit.error_message=ME.message;audit.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'operating_point_api_isolation.json'),'w','n','UTF-8');assert(fid>=0,'Cannot write audit.');
    cleanup_file=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(audit));
    assert(audit.collection_complete,'See operating_point_api_isolation.json.');
end

function row=observe(output,mass)
    node=simscape.logging.findNode(output.simlog,mass);series=node.T.series;
    row=struct('time_s',double(time(series)).','temperature_K', ...
        value(simscape.Value(double(values(series)),series.unit),'K').', ...
        'memory_time_s',output.memory_log.Time(:).','memory',output.memory_log.Data(:).');
end
