function record = Verify_HeatDriveECC_DiagnosticStateCapture(output_root)
% Actual vendor roundtrip and bounded history; never load the coupled plant.
    assert(~isfolder(output_root),'Never overwrite verification evidence.');
    [status,commit]=system('git rev-parse HEAD');assert(status==0,'Missing source provenance.');
    mkdir(output_root);
    old_config=Simulink.fileGenControl('getConfig');
    cleanup_config=onCleanup(@() Simulink.fileGenControl('setConfig','config',old_config));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'cache'), ...
        'CodeGenFolder',fullfile(output_root,'codegen'),'createDir',true);
    load_system('simulink');model='ecc_diagnostic_state_capture_isolation';
    assert(~bdIsLoaded(model),'Isolated model name in use.');new_system(model);
    cleanup_model=onCleanup(@() close_system(model,0));
    mass=[model '/Mass'];solver=[model '/Solver'];
    add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass',mass, ...
        'mass','1','mass_unit','kg','sp_heat','1000','sp_heat_unit','J/(K*kg)', ...
        'T','300','T_unit','K','T_specify','on','T_priority','High');
    add_block('nesl_utility/Solver Configuration',solver);
    mp=simscape.connectionPortProperties(mass);sp=simscape.connectionPortProperties(solver);
    assert(isscalar(mp) && isscalar(sp),'Unexpected isolated ports.');
    simscape.addConnection(mass,mp.Name,solver,sp.Name);
    set_param(solver,'UseLocalSolver','on','LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER', ...
        'LocalSolverSampleTime','0.001');
    for pair={ {'Stage2Memory','7.25','0.003'}, {'Stage4Memory','-3','0.004'} }
        row=pair{1};name=row{1};
        add_block('simulink/Sources/Constant',[model '/' name '_Derivative'],'Value',row{3});
        add_block('simulink/Continuous/Integrator',[model '/' name],'InitialCondition',row{2});
        add_block('simulink/Sinks/To Workspace',[model '/' name '_Log'], ...
            'VariableName',[name '_log'],'SaveFormat','Timeseries','MaxDataPoints','inf');
        add_line(model,[name '_Derivative/1'],[name '/1']);
        add_line(model,[name '/1'],[name '_Log/1']);
    end
    set_param(model,'Solver','ode3','FixedStep','0.001','StartTime','0','StopTime','30', ...
        'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
        'SaveTime','off','SaveOutput','off','ReturnWorkspaceOutputs','on');
    settings=Configure_HeatDriveECC_DiagnosticStateCapture(model,2);
    input=Simulink.SimulationInput(model);
    input=input.setModelParameter('CaptureErrors','on');
    first=sim(input);
    capture=Save_HeatDriveECC_DiagnosticStateCapture(first,output_root,settings,30);
    saved=load(capture.operating_point_file,'diagnostic_operating_point');
    assert(isequaln(saved.diagnostic_operating_point.loggedStates,first.diagnostic_final_op.loggedStates), ...
        'Disk roundtrip changed named numerical state.');
    reference=sim(input.setModelParameter('StopTime','30.01'));
    restored=sim(input.setModelParameter('StopTime','30.01').setInitialState(saved.diagnostic_operating_point));
    assert(isempty(reference.ErrorMessage) && isempty(restored.ErrorMessage), ...
        'Strict continuation or continuous reference failed.');
    restored_states=Extract_HeatDriveECC_ObservedStates(restored.diagnostic_state_log,10,1);
    reference_states=Extract_HeatDriveECC_ObservedStates(reference.diagnostic_state_log,10,1);
    comparisons={};
    assert(numel(restored_states.states)==numel(reference_states.states),'Logged state groups changed.');
    for k=1:numel(restored_states.states)
        a=restored_states.states{k};b=reference_states.states{k};
        assert(strcmp(a.block_path,b.block_path) && strcmp(a.state_name,b.state_name), ...
            'Named state correspondence changed.');
        expected=30+(0:10)'*.001;
        assert(numel(a.time_s)==11 && all(abs(a.time_s-expected)<=1e-9),'Wrong restored clock.');
        selected=b.time_s>=30-1e-9;
        assert(isequaln(a.values,b.values(selected,:)), ...
            'Restored versus continuous state differs: %s',a.block_path);
        comparisons{end+1}=struct('block_path',a.block_path,'state_name',a.state_name, ...
            'channels',a.channel_count,'samples',11,'values_exact',true); %#ok<AGROW>
    end
    record=struct('schema','heatdrive_ecc_diagnostic_state_capture_isolation_v1', ...
        'execution_commit',strtrim(commit),'capture',capture,'state_comparisons',{comparisons}, ...
        'disk_roundtrip_exact',true,'continuous_vs_restored_exact',true, ...
        'bounded_history_verified',true,'production_model_loaded',false, ...
        'current_coupled_model_restore_verified',false,'production_recovery_allowed',false);
    fid=fopen(fullfile(output_root,'diagnostic_state_capture_isolation.json'),'w','n','UTF-8');
    assert(fid>=0,'Cannot save verification.');cleanup_file=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));fprintf('%s\n',jsonencode(record));
end
