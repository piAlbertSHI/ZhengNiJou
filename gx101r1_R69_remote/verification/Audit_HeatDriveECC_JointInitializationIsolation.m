function audit = Audit_HeatDriveECC_JointInitializationIsolation(output_root)
% Isolate Dataset/Simscape-target interaction without loading production data.
    assert(~isfolder(output_root),'Do not overwrite isolation evidence.');
    [code,commit]=system('git rev-parse HEAD'); assert(code==0,'Cannot record source.');
    [code,dirty]=system('git status --porcelain');
    assert(code==0 && isempty(strtrim(dirty)),'Commit isolation source first.');
    mkdir(output_root); diary(fullfile(output_root,'matlab_diary.log'));
    cleanup_diary=onCleanup(@() diary('off'));
    generation=Simulink.fileGenControl('getConfig');
    cleanup_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'build_cache'), ...
        'CodeGenFolder',fullfile(output_root,'generated_code'),'createDir',true);
    load_system('simulink');
    audit=struct('schema','heatdrive_ecc_joint_initialization_isolation_v1','execution_commit',strtrim(commit), ...
        'production_model_loaded',false,'production_checkpoint_loaded',false, ...
        'production_recovery_allowed',false,'collection_complete',false,'cases',{{}});
    modes={'target_only','target_and_partial_dataset','target_and_block_initial_condition', ...
        'target_and_complete_dataset_from_seed'};
    for k=1:numel(modes)
        row=struct('mode',modes{k},'computation_complete',false,'error_identifier','','error_message','', ...
            'expected_temperature_K',340,'expected_integrator',7.25*(k~=1), ...
            'start_time_s',2000,'stop_time_s',2000.001);
        model=['ecc_joint_init_isolation_' num2str(k)];
        assert(~bdIsLoaded(model),'Isolation name in use.');
        new_system(model); cleanup_model=onCleanup(@() close_system(model,0));
        try
            mass=[model '/Mass']; solver=[model '/Solver'];
            add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass',mass, ...
                'mass','1','mass_unit','kg','sp_heat','1000','sp_heat_unit','J/(K*kg)', ...
                'T','300','T_unit','K','T_specify','on','T_priority','High');
            add_block('nesl_utility/Solver Configuration',solver);
            p=simscape.connectionPortProperties(solver);
            mass_port=simscape.connectionPortProperties(mass);
            assert(isscalar(p) && isscalar(mass_port),'Unexpected thermal or solver port count.');
            row.mass_port=mass_port.Name;
            simscape.addConnection(mass,mass_port.Name,solver,p.Name);
            add_block('simulink/Sources/Constant',[model '/Zero'],'Value','0');
            add_block('simulink/Continuous/Integrator',[model '/Memory'],'InitialCondition','0');
            add_block('simulink/Sinks/To Workspace',[model '/MemoryLog'], ...
                'VariableName','memory_log','SaveFormat','Timeseries');
            add_line(model,'Zero/1','Memory/1'); add_line(model,'Memory/1','MemoryLog/1');
            if k==3,set_param([model '/Memory'],'InitialCondition','7.25');end
            set_param(solver,'UseLocalSolver','on','LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER', ...
                'LocalSolverSampleTime','0.001');
            targets=simscape.op.OperatingPoint;
            targets=set(targets,'Mass/T',simscape.op.Target(340,'K','High'));
            input=Simulink.SimulationInput(model);
            input=input.setVariable('isolation_targets',targets);
            input=input.setModelParameter('StartTime','2000','StopTime','2000.001', ...
                'Solver','ode3','FixedStep','0.001','SimulationMode','accelerator', ...
                'ReturnWorkspaceOutputs','on','CaptureErrors','on', ...
                'SimscapeUseOperatingPoints','on','SimscapeOperatingPoint','isolation_targets', ...
                'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
                'SaveTime','off','SaveOutput','off','SaveState','off');
            if k==2 || k==4
                state=Simulink.SimulationData.State;
                state.Name='CSTATE'; state.BlockPath=Simulink.SimulationData.BlockPath([model '/Memory']);
                state.Values=timeseries(7.25,2000);
                initial=Simulink.SimulationData.Dataset;
                initial=addElement(initial,state);
                if k==4
                    seed_input=input.setModelParameter('StopTime','2000','SaveState','on', ...
                        'SaveFinalState','on','FinalStateName','xFinal','SaveOperatingPoint','on');
                    seed=sim(seed_input);
                    assert(isempty(seed.ErrorMessage),'HeatDriveECC:IsolationSeedFailed','%s',seed.ErrorMessage);
                    ds=seed.xFinal.loggedStates;
                    assert(isa(ds,'Simulink.SimulationData.Dataset'),'Missing initialized network state.');
                    appended=0;
                    for j=1:ds.numElements
                        item=ds.getElement(j);
                        if strcmp(char(item.BlockPath.getBlock(1)),solver)
                            initial=addElement(initial,item); appended=appended+1;
                        end
                    end
                    assert(appended==1 && initial.numElements==ds.numElements,'Incomplete seeded Dataset.');
                    row.seed_time_s=seed.xFinal.snapshotTime;
                    row.seed_network_obtained_from_model=true;
                    row.packed_indices_edited=false;
                end
                input=input.setInitialState(initial);
            end
            out=sim(input);
            row.error_message=char(string(out.ErrorMessage));
            assert(isempty(row.error_message),'HeatDriveECC:IsolationSimFailure','%s',row.error_message);
            node=simscape.logging.findNode(out.simlog,mass);
            series=node.T.series;
            temperature_K=value(simscape.Value(double(values(series)),series.unit),'K');
            time_s=double(time(series)); memory=out.memory_log;
            row.temperature_time_s=time_s(:).'; row.temperature_K=temperature_K(:).';
            row.memory_time_s=memory.Time(:).'; row.memory_values=memory.Data(:).';
            assert(isequal(time_s(:),[2000;2000.001]) && ...
                isequal(memory.Time(:),[2000;2000.001]),'Incomplete isolation grid.');
            row.temperature_target_pass=all(abs(temperature_K(:)-340)<=1e-10);
            row.memory_target_pass=all(abs(memory.Data(:)-row.expected_integrator)<=1e-12);
            row.computation_complete=true;
        catch ME
            row.error_identifier=ME.identifier; row.error_message=ME.message;
        end
        audit.cases{end+1}=row;
        clear cleanup_model
    end
    audit.collection_complete=numel(audit.cases)==4;
    fid=fopen(fullfile(output_root,'joint_initialization_isolation.json'),'w','n','UTF-8');
    assert(fid>=0,'Cannot write isolation evidence.'); cleanup_file=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(audit));
    assert(all(cellfun(@(r) r.computation_complete,audit.cases)), ...
        'HeatDriveECC:IsolationCollectionFailed','See per-case evidence.');
end
