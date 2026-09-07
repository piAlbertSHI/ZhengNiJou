function audit = Audit_HeatDriveECC_ConverterBoundary(output_root)
% Isolate converter observations from delivered heat at a warm restart boundary.
    assert(~isfolder(output_root),'Do not overwrite converter evidence.');
    [code,commit]=system('git rev-parse HEAD');assert(code==0,'Cannot record source.');
    [code,dirty]=system('git status --porcelain');assert(code==0 && isempty(strtrim(dirty)),'Commit source first.');
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));cleanup_diary=onCleanup(@() diary('off'));
    generation=Simulink.fileGenControl('getConfig');
    cleanup_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'build_cache'), ...
        'CodeGenFolder',fullfile(output_root,'generated_code'),'createDir',true);
    load_system('simulink');
    audit=struct('schema','heatdrive_ecc_converter_boundary_trial_v1','execution_commit',strtrim(commit), ...
        'production_model_loaded',false,'production_checkpoint_loaded',false,'production_recovery_allowed',false, ...
        'collection_complete',false,'cases',{{}},'error_identifier','','error_message','');
    try
        for waveform={'zero','signed_steps'}
            model=['ecc_converter_boundary_' waveform{1}];
            assert(~bdIsLoaded(model),'Model name in use.');new_system(model);
            cleanup_model=onCleanup(@() close_system(model,0));
            mass=[model '/Mass'];converter=[model '/Converter'];source=[model '/Heat'];solver=[model '/Solver'];
            add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass',mass,'mass','1','mass_unit','kg', ...
                'sp_heat','1000','sp_heat_unit','J/(K*kg)','T','340','T_unit','K','T_specify','on','T_priority','High');
            add_block('nesl_utility/Solver Configuration',solver);
            add_block('nesl_utility/Simulink-PS Converter',converter,'Unit','W','FilteringAndDerivatives','provide', ...
                'UdotUserProvided','0','SimscapeFilterOrder','1','InputFilterTimeConstant','0.001','AffineConversion','off');
            add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source',source);
            add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference',[model '/Reference']);
            add_block('simulink/Sources/From Workspace',[model '/Input'],'VariableName','heat_command','Interpolate','off');
            simscape.addConnection(mass,only_port(mass),solver,only_port(solver));
            simscape.addConnection(source,'A',mass,only_port(mass));
            simscape.addConnection(source,'B',[model '/Reference'],only_port([model '/Reference']));
            add_line(model,'Input/1','Converter/1');
            ports=get_param(converter,'PortHandles'); heat_ports=get_param(source,'PortHandles');
            add_line(model,ports.RConn(1),heat_ports.RConn(1));
            set_param(solver,'UseLocalSolver','on','LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER','LocalSolverSampleTime','0.001');
            set_param(model,'StartTime','1999.99','StopTime','2000.004','Solver','ode3','FixedStep','0.001', ...
                'SimulationMode','accelerator','SimscapeLogType','all','SimscapeLogName','simlog', ...
                'SimscapeLogLimitData','off','SaveState','on','StateSaveName','states','SaveFormat','Dataset', ...
                'SaveFinalState','on','FinalStateName','xFinal','SaveOperatingPoint','on', ...
                'SaveTime','off','SaveOutput','off','ReturnWorkspaceOutputs','on', ...
                'OperatingPointContentsChecksumMismatchMsg','error','OperatingPointInterfaceChecksumMismatchMsg','error');
            command_time=[1999.99;2000;2000.003;2000.004;2000.006;2000.009;2000.01];
            command_values=[0;0;0;5;-3;7;0];
            if strcmp(waveform{1},'zero'),command_values(:)=0;end
            heat_command=timeseries(command_values,command_time);
            input=Simulink.SimulationInput(model);input=input.setVariable('heat_command',heat_command);
            input=input.setModelParameter('CaptureErrors','on');
            prefix=sim(input);assert(isempty(prefix.ErrorMessage),'HeatDriveECC:ConverterPrefixFailed','%s',prefix.ErrorMessage);
            original_op=prefix.xFinal;
            prefix_row=observe(prefix,mass,source,converter);
            temperature=prefix_row.temperature_K(end);
            strict=input.setModelParameter('StopTime','2000.01');strict=strict.setInitialState(original_op);
            strict_out=sim(strict);assert(isempty(strict_out.ErrorMessage),'HeatDriveECC:ConverterStrictFailed','%s',strict_out.ErrorMessage);
            reference=observe(strict_out,mass,source,converter);
            targets=simscape.op.OperatingPoint;
            targets=set(targets,'Mass/T',simscape.op.Target(temperature,'K','High'));
            seed_input=input.setVariable('boundary_targets',targets);
            seed_input=seed_input.setModelParameter('StartTime','2000.004','StopTime','2000.004', ...
                'SimscapeUseOperatingPoints','on','SimscapeOperatingPoint','boundary_targets');
            seed=sim(seed_input);assert(isempty(seed.ErrorMessage),'HeatDriveECC:ConverterSeedFailed','%s',seed.ErrorMessage);
            seed_row=observe(seed,mass,source,converter);
            assert(abs(seed_row.temperature_K(end)-temperature)<=1e-10,'Warm temperature not preserved.');
            for mode={'seed_op','seed_op_with_converter_logged_state'}
                candidate=seed.xFinal;
                if strcmp(mode{1},'seed_op_with_converter_logged_state')
                    original=original_op.loggedStates; rebuilt=candidate.loggedStates; count=0;
                    for j=1:rebuilt.numElements
                        item=rebuilt.getElement(j);
                        if strcmp(char(item.BlockPath.getBlock(1)),converter)
                            for k=1:original.numElements
                                prior=original.getElement(k);
                                if strcmp(char(prior.BlockPath.getBlock(1)),converter)
                                    rebuilt=rebuilt.setElement(j,prior);count=count+1;
                                end
                            end
                        end
                    end
                    assert(count==1,'Unique converter state required.');candidate.loggedStates=rebuilt;
                end
                run=seed_input.setModelParameter('StopTime','2000.01');run=run.setInitialState(candidate);
                out=sim(run);assert(isempty(out.ErrorMessage),'HeatDriveECC:ConverterRestartFailed','%s',out.ErrorMessage);
                actual=observe(out,mass,source,converter);
                row=struct('waveform',waveform{1},'mode',mode{1},'command_time_s',command_time, ...
                    'command_values_W',command_values,'prefix',prefix_row,'seed',seed_row, ...
                    'reference',reference,'actual',actual,'capacity_J_K',1000, ...
                    'step_s',.001,'start_s',2000.004,'stop_s',2000.01);
                row.exact_delivered_heat=isequal(reference.source_Q_W,actual.source_Q_W) && ...
                    isequal(reference.mass_Q_W,actual.mass_Q_W);
                row.max_temperature_difference_K=max(abs(reference.temperature_K-actual.temperature_K));
                row.exact_converter_observations=isequal(reference.converter_values,actual.converter_values);
                row.converter_parameters=struct();
                names={'Unit','FilteringAndDerivatives','UdotUserProvided','SimscapeFilterOrder','InputFilterTimeConstant','AffineConversion'};
                for j=1:numel(names),row.converter_parameters.(names{j})=get_param(converter,names{j});end
                save(fullfile(output_root,sprintf('case_%d.mat',numel(audit.cases)+1)),'row','-v7.3');
                audit.cases{end+1}=rmfield(row,{'prefix','seed','reference','actual'});
            end
            clear cleanup_model
        end
        audit.collection_complete=numel(audit.cases)==4;
    catch ME
        audit.error_identifier=ME.identifier;audit.error_message=ME.message;
        audit.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'converter_boundary_trial.json'),'w','n','UTF-8');assert(fid>=0,'Cannot write audit.');
    cleanup_file=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(audit));
    assert(audit.collection_complete,'HeatDriveECC:ConverterBoundaryFailed','See converter_boundary_trial.json.');
end

function row=observe(output,mass,source,converter)
    m=simscape.logging.findNode(output.simlog,mass);q=simscape.logging.findNode(output.simlog,source);
    row=struct('time_s',double(time(m.T.series)),'temperature_K',si(m.T.series,'K'), ...
        'mass_Q_W',si(m.Q.series,'W'),'source_Q_W',si(q.Q.series,'W'));
    states=output.states;matches=0;
    for k=1:states.numElements
        item=states.getElement(k);
        if strcmp(char(item.BlockPath.getBlock(1)),converter)
            row.converter_time_s=item.Values.Time;row.converter_values=item.Values.Data;
            row.converter_state_name=char(item.Name);matches=matches+1;
        end
    end
    assert(matches==1,'Missing converter observation.');
end

function data=si(series,units)
    data=value(simscape.Value(double(values(series)),series.unit),units);
end

function name=only_port(block)
    p=simscape.connectionPortProperties(block);assert(isscalar(p),'Require one port.');name=p.Name;
end
