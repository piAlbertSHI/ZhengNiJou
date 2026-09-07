function audit=Replay_HeatDriveECC_ConverterHistory(input_path,output_root)
% Generate public converter snapshots from measured inputs, never packed states.
    assert(~isfolder(output_root),'Do not overwrite evidence.');
    [code,commit]=system('git rev-parse HEAD');assert(code==0,'Cannot record source.');
    [code,dirty]=system('git status --porcelain');assert(code==0 && isempty(strtrim(dirty)),'Commit source first.');
    data=jsondecode(fileread(input_path));
    assert(strcmp(data.schema,'heatdrive_ecc_converter_history_input_v1') && ...
        strcmp(data.source_sha256,'0BEE740B0B1298B939F5644FD6BEE44296AE1D7BA121A5C5E7C55573FEAB97DD') && ...
        ~data.production_recovery_allowed && numel(data.rows)==42 && ...
        isequal(data.time_s(:),[1999.997;1999.998;1999.999;2000]),'Wrong replay contract.');
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));cleanup_diary=onCleanup(@() diary('off'));
    generation=Simulink.fileGenControl('getConfig');
    cleanup_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'build_cache'), ...
        'CodeGenFolder',fullfile(output_root,'generated_code'),'createDir',true);
    audit=struct('schema','heatdrive_ecc_converter_history_replay_v1','execution_commit',strtrim(commit), ...
        'computation_complete',false,'production_recovery_allowed',false,'source_sha256',data.source_sha256, ...
        'production_checkpoint_loaded',false,'error_message','','snapshots',{{}});
    try
        load_system('simulink');model='ecc_converter_history_replay';
        assert(~bdIsLoaded(model),'Model name in use.');new_system(model);
        cleanup_model=onCleanup(@() close_system(model,0));
        mass=[model '/Mass'];solver=[model '/Solver'];reference=[model '/Reference'];
        add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass',mass,'mass','1','mass_unit','kg', ...
            'sp_heat','1000','sp_heat_unit','J/(K*kg)','T','340','T_unit','K','T_priority','High');
        add_block('nesl_utility/Solver Configuration',solver);
        add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference',reference);
        simscape.addConnection(mass,only_port(mass),solver,only_port(solver));
        add_block('simulink/Sources/From Workspace',[model '/Input'],'VariableName','heat_command', ...
            'Interpolate','off','OutputAfterFinalValue','Holding final value');
        add_block('simulink/User-Defined Functions/Interpreted MATLAB Function',[model '/DiscreteDriver'], ...
            'MATLABFcn','HeatDriveECC_ConverterIdentity','OutputDimensions','42','SampleTime','0.001');
        add_block('simulink/Signal Routing/Demux',[model '/Demux'],'Outputs','42');
        add_line(model,'Input/1','DiscreteDriver/1');add_line(model,'DiscreteDriver/1','Demux/1');
        command=zeros(4,42);
        for k=1:42
            converter=[model sprintf('/Converter_%02d',k)];source=[model sprintf('/Heat_%02d',k)];
            add_block('nesl_utility/Simulink-PS Converter',converter,'Unit','W','FilteringAndDerivatives','provide', ...
                'UdotUserProvided','0','SimscapeFilterOrder','1','InputFilterTimeConstant','0.001','AffineConversion','off');
            add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source',source);
            simscape.addConnection(source,'A',mass,only_port(mass));
            simscape.addConnection(source,'B',reference,only_port(reference));
            add_line(model,sprintf('Demux/%d',k),sprintf('Converter_%02d/1',k));
            p=get_param(converter,'PortHandles');q=get_param(source,'PortHandles');
            add_line(model,p.RConn(1),q.RConn(1));command(:,k)=data.rows(k).values_W(:);
        end
        set_param(solver,'UseLocalSolver','on','LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER','LocalSolverSampleTime','0.001');
        set_param(model,'StartTime','1999.997','StopTime','2000','Solver','ode3','FixedStep','0.001', ...
            'SimulationMode','accelerator','SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
            'SaveState','on','StateSaveName','states','SaveFormat','Dataset','SaveFinalState','on', ...
            'FinalStateName','xFinal','SaveOperatingPoint','on','SaveTime','off','SaveOutput','off','ReturnWorkspaceOutputs','on');
        input=Simulink.SimulationInput(model);input=input.setVariable('heat_command',timeseries(command,data.time_s));
        input=input.setModelParameter('CaptureErrors','on');out=sim(input);
        assert(isempty(out.ErrorMessage),'HeatDriveECC:ConverterReplayFailed','%s',out.ErrorMessage);
        assert(out.xFinal.snapshotTime==2000,'Wrong replay endpoint.');
        states=out.xFinal.loggedStates;observed=out.states;snapshots={};delivery={};
        for k=1:42
            converter=[model sprintf('/Converter_%02d',k)];source=[model sprintf('/Heat_%02d',k)];
            state=select(states,converter);log=select(observed,converter);
            heat=simscape.logging.findNode(out.simlog,source);
            t=double(time(heat.Q.series));q=value(simscape.Value(double(values(heat.Q.series)),heat.Q.series.unit),'W');
            delivery{end+1}=struct('block_path',data.rows(k).block_path, ...
                'time_s',t(:).','expected_time_s',data.time_s(:).', ...
                'heat_W',q(:).','expected_heat_W',command(:,k).', ...
                'exact_time',isequal(t(:),data.time_s(:)),'exact_heat',isequal(q(:),command(:,k))); %#ok<AGROW>
            assert(isa(state.Values,'timeseries') && numel(state.Values.Data)==2 && state.Values.Time==2000, ...
                'Unexpected public converter snapshot.');
            snapshots{end+1}=struct('block_path',data.rows(k).block_path,'snapshot',state.Values, ...
                'observed',log.Values,'time_s',t,'heat_W',q);
            audit.snapshots{end+1}=struct('block_path',data.rows(k).block_path, ...
                'snapshot_values',state.Values.Data(:).','final_observed_values',log.Values.Data(end,:)); %#ok<AGROW>
        end
        m=simscape.logging.findNode(out.simlog,mass);
        mass_temperature_K=value(simscape.Value(double(values(m.T.series)),m.T.series.unit),'K');
        mass_heat_W=value(simscape.Value(double(values(m.Q.series)),m.Q.series.unit),'W');
        save(fullfile(output_root,'converter_history_snapshots.mat'),'snapshots','data','command', ...
            'mass_temperature_K','mass_heat_W','-v7.3');
        audit.delivery=delivery;
        audit.collection_complete=numel(snapshots)==42;
        audit.exact_input_delivery=all(cellfun(@(r) r.exact_time && r.exact_heat,delivery));
        assert(audit.exact_input_delivery,'Replay input or time grid not delivered exactly; see delivery rows.');
        audit.computation_complete=audit.collection_complete;
    catch ME
        audit.error_message=ME.message;audit.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'converter_history_replay.json'),'w','n','UTF-8');assert(fid>=0,'Cannot write audit.');
    cleanup_file=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('CONVERTER_HISTORY_REPLAY_COMPLETE=%d EVIDENCE=%s\n',audit.computation_complete,output_root);
    assert(audit.computation_complete,'HeatDriveECC:ConverterReplayFailed','See converter_history_replay.json.');
end

function item=select(states,block)
    matches=0;
    for j=1:states.numElements
        candidate=states.getElement(j);
        if strcmp(char(candidate.BlockPath.getBlock(1)),block),item=candidate;matches=matches+1;end
    end
    assert(matches==1,'Missing unique converter state.');
end

function name=only_port(block)
    p=simscape.connectionPortProperties(block);assert(isscalar(p),'Require one port.');name=p.Name;
end
