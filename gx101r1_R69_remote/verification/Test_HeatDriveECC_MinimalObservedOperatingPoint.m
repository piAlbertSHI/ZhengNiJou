function result=Test_HeatDriveECC_MinimalObservedOperatingPoint(folder)
% Complete untouched OP plus bounded scalar evidence; no production model/state.
    assert(~isfolder(folder),'Never overwrite fixture evidence.');mkdir(folder);
    model='ecc_minimal_observed_op_fixture';assert(~bdIsLoaded(model));new_system(model);
    cleanup=onCleanup(@() close_fixture(model));
    generation=Simulink.fileGenControl('getConfig');
    restore_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(folder,'cache'), ...
        'CodeGenFolder',fullfile(folder,'codegen'),'createDir',true);
    result=struct('pass',false,'production_model_loaded',false, ...
        'production_checkpoint_loaded',false,'coupled_model_restore_verified',false, ...
        'production_recovery_allowed',false,'error_message','');
    try
        add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source',[model '/Heat']);
        add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass',[model '/Mass'], ...
            'mass','1','sp_heat','1000','T','300','T_specify','on','T_priority','High');
        add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference',[model '/Reference']);
        add_block('nesl_utility/Solver Configuration',[model '/Solver']);
        add_block('nesl_utility/Simulink-PS Converter',[model '/HeatPS'],'Unit','W');
        add_block('simulink/Sources/Constant',[model '/HeatInput'],'Value','10');
        add_line(model,'HeatInput/1','HeatPS/1');
        p=get_param([model '/HeatPS'],'PortHandles');q=get_param([model '/Heat'],'PortHandles');
        add_line(model,p.RConn(1),q.RConn(1));
        simscape.addConnection([model '/Heat'],'A',[model '/Mass'],only_port([model '/Mass']));
        simscape.addConnection([model '/Heat'],'B',[model '/Reference'],only_port([model '/Reference']));
        simscape.addConnection([model '/Heat'],'A',[model '/Solver'],only_port([model '/Solver']));
        add_block('simulink/Sources/Constant',[model '/One'],'Value','1');
        add_block('simulink/Continuous/Integrator',[model '/Memory'],'InitialCondition','0');
        add_block('simulink/Sinks/To Workspace',[model '/MemoryLog'], ...
            'VariableName','memory_log','SaveFormat','Timeseries');
        add_line(model,'One/1','Memory/1');add_line(model,'Memory/1','MemoryLog/1');
        add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function', ...
            [model '/Observer'],'FunctionName','HeatDriveECC_ProcessLocalTimeObserver','Parameters','');
        set_param([model '/Solver'],'UseLocalSolver','on', ...
            'LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER','LocalSolverSampleTime','.001');
        set_param(model,'Solver','ode3','FixedStep','.001','StartTime','0','StopTime','6', ...
            'SimulationMode','normal','ReturnWorkspaceOutputs','on','SaveTime','off','SaveOutput','off', ...
            'SaveState','off','SaveFinalState','on','FinalStateName','xFinal','SaveOperatingPoint','on', ...
            'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
            'SimscapeLogToSDI','off','OperatingPointContentsChecksumMismatchMsg','error', ...
            'OperatingPointInterfaceChecksumMismatchMsg','error');
        HeatDriveECC_ObserverContext('register',model,fullfile(folder,'reference.json'));
        input=Simulink.SimulationInput(model);reference=sim(input);
        assert(isa(reference.xFinal,'Simulink.op.ModelOperatingPoint'));
        HeatDriveECC_ObserverContext('register',model,fullfile(folder,'segment_a.json'));
        first=sim(input.setModelParameter('StopTime','3'));
        final_op=first.xFinal;
        file=fullfile(folder,'segment_a_complete_op.mat');save(file,'final_op','-v7.3');
        before=Simulink.BlockDiagram.getChecksum(model);
        HeatDriveECC_ObserverContext('register',model,fullfile(folder,'segment_b.json'));
        after=Simulink.BlockDiagram.getChecksum(model);
        assert(isequaln(before,after),'Changing only output routing changed the model checksum.');
        saved=load(file,'final_op');original=saved.final_op.loggedStates;
        % Model start stays zero; the untouched OP supplies snapshot time 3 s.
        second=sim(input.setModelParameter('StopTime','6').setInitialState(saved.final_op));
        assert(isequaln(original,saved.final_op.loggedStates),'Fixture OP was mutated.');
        ra=simscape.logging.findNode(reference.simlog,[model '/Mass']);
        rb=simscape.logging.findNode(second.simlog,[model '/Mass']);
        ta=double(time(ra.T.series));tb=double(time(rb.T.series));
        va=double(values(ra.T.series));vb=double(values(rb.T.series));
        [common,ia,ib]=intersect(ta,tb);
        assert(numel(common)==numel(tb) && tb(1)==3 && tb(end)==6);
        thermal_error=max(abs(va(ia)-vb(ib)));
        rt=double(reference.memory_log.Time(:));st=double(second.memory_log.Time(:));
        indices=round(st/.001)+1;
        assert(numel(st)==3001 && all(diff(indices)==1) && ...
            indices(1)==3001 && indices(end)==6001 && ...
            all(indices>=1 & indices<=numel(rt)), 'Missing or duplicated 1 ms clock slots.');
        clock_offset=max(abs(rt(indices)-st));
        assert(clock_offset<=16*eps(6),'Warm and reference clock slots differ.');
        memory_error=max(abs(reference.memory_log.Data(indices)-second.memory_log.Data));
        result.thermal_cold_K=va(1);result.thermal_reference_snapshot_K=va(ia(1));
        result.thermal_restored_snapshot_K=vb(1);
        result.integrator_reference_snapshot=reference.memory_log.Data(indices(1));
        result.integrator_restored_snapshot=second.memory_log.Data(1);
        result.thermal_max_error_K=thermal_error;result.integrator_max_error=memory_error;
        result.integrator_clock_max_offset_s=clock_offset;
        assert(thermal_error<=1e-12 && memory_error<=1e-12,'Untouched full-OP trajectory differs.');
        assert(second.memory_log.Data(1)>2.9 && abs(va(ia(1))-va(1))>.02 && ...
            abs(vb(1)-va(ia(1)))<=1e-12,'A physical or integrator state was reset.');
        progress=jsondecode(fileread(fullfile(folder,'segment_b.json')));
        assert(progress.simulation_time_s==6 && ~progress.simulation_completed);
        assert(strcmp(get_param(model,'SaveState'),'off') && ...
            ~ismember('xout',second.who),'Unexpected per-step state history.');
        missing_rejected=false;HeatDriveECC_ObserverContext('clear',model);
        try,HeatDriveECC_ObserverContext('get',model);catch,missing_rejected=true;end
        assert(missing_rejected);
        result.pass=true;result.full_unmodified_op_restore_pass=true;
        result.only_destination_changed_checksum_equal=true;result.per_step_state_history_saved=false;
        result.complete_op_bytes=dir(file).bytes;result.thermal_max_error_K=thermal_error;
        result.integrator_clock_max_offset_s=clock_offset;
        result.integrator_max_error=memory_error;result.missing_context_rejected=missing_rejected;
    catch exception
        result.error_message=getReport(exception,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(folder,'fixture_result.json'),'w','n','UTF-8');assert(fid>=0);
    c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(result,'PrettyPrint',true));clear c
    fprintf('FINAL_JSON=%s\n',jsonencode(result));
    assert(result.pass,'HeatDriveECC:MinimalObservedOPFixtureFailed','%s',result.error_message);
end

function name=only_port(block)
    p=simscape.connectionPortProperties(block);assert(isscalar(p));name=p.Name;
end

function close_fixture(model)
    HeatDriveECC_ObserverContext('clear',model);
    if bdIsLoaded(model),close_system(model,0);end
end
