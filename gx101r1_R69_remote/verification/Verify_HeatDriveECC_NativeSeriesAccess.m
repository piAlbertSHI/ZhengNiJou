function record = Verify_HeatDriveECC_NativeSeriesAccess(output_root)
% Compare actual vendor series APIs in an isolated model, never the plant.
    assert(~isfolder(output_root),'Never overwrite verification evidence.');
    [status,commit]=system('git rev-parse HEAD');assert(status==0,'Missing provenance.');
    mkdir(output_root);
    old_config=Simulink.fileGenControl('getConfig');
    cleanup_config=onCleanup(@() Simulink.fileGenControl('setConfig','config',old_config));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'cache'), ...
        'CodeGenFolder',fullfile(output_root,'codegen'),'createDir',true);
    diagnostics=checkcode(which('Read_HeatDriveECC_NativeSeries'),'-id');
    assert(~any(strcmp({diagnostics.id},'SYNER')),'Native reader syntax error.');
    load_system('simulink');
    model='ecc_native_series_access_isolation';
    assert(~bdIsLoaded(model),'Isolated model name in use.');new_system(model);
    cleanup_model=onCleanup(@() close_system(model,0));
    mass=[model '/Mass'];solver=[model '/Solver'];
    add_block('fl_lib/Thermal/Thermal Elements/Thermal Mass',mass, ...
        'mass','1','mass_unit','kg','sp_heat','1000','sp_heat_unit','J/(K*kg)', ...
        'T','300','T_unit','K','T_specify','on','T_priority','High');
    add_block('nesl_utility/Solver Configuration',solver);
    mp=simscape.connectionPortProperties(mass);sp=simscape.connectionPortProperties(solver);
    assert(isscalar(mp) && isscalar(sp),'Unexpected isolated physical ports.');
    simscape.addConnection(mass,mp.Name,solver,sp.Name);
    set_param(solver,'UseLocalSolver','on','LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER', ...
        'LocalSolverSampleTime','0.001');
    set_param(model,'Solver','ode3','FixedStep','0.001','StopTime','20', ...
        'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
        'SaveTime','off','SaveOutput','off','ReturnWorkspaceOutputs','on');
    output=sim(model);
    node=simscape.logging.findNode(output.simlog,mass);
    cases={};names=node.childIds;
    for k=1:numel(names)
        leaf=node.child(names{k});series=leaf.series;
        if isempty(series),continue;end
        started=tic;points=series.points;classic_points_s=toc(started);
        classic_time=[];classic_data=[];classic_unit='';
        if points>0
            classic_time=double(time(series));classic_values=double(values(series));
            classic_data=reshape(classic_values,numel(classic_time),[]);classic_unit=series.unit;
        end
        [t,data,unit,timing]=Read_HeatDriveECC_NativeSeries(leaf);
        cases{end+1}=struct('state',names{k},'points',points, ...
            'point_count_equal',points==numel(t), ...
            'time_equal',isequaln(t,classic_time),'data_equal',isequaln(data,classic_data), ...
            'unit_equal',strcmp(unit,classic_unit),'classic_unit',classic_unit,'new_unit',unit, ...
            'classic_points_access_s',classic_points_s,'new_timing',timing); %#ok<AGROW>
        write_json(fullfile(output_root,'comparison_progress.json'),struct('cases',{cases}));
        assert(points==numel(t) && isequaln(t,classic_time) && ...
            isequaln(data,classic_data) && strcmp(unit,classic_unit), ...
            'Native time/data/unit/count mismatch: %s; see comparison_progress.json',names{k});
    end
    [empty_time,empty_data,empty_unit,empty_timing]=Read_HeatDriveECC_NativeSeries(node);
    assert(isempty(empty_time) && isempty(empty_data) && isempty(empty_unit) && ...
        empty_timing.points==0,'Branch node empty-series behavior changed.');
    assert(~isempty(cases),'No actual native leaf series tested.');
    record=struct('schema','heatdrive_ecc_native_series_access_isolation_v1', ...
        'execution_commit',strtrim(commit),'matlab_release',version('-release'), ...
        'production_model_loaded',false,'checkpoint_loaded',false, ...
        'cases',{cases},'empty_series_pass',true,'data_equivalence_pass',true, ...
        'full_plant_speedup_measured',false,'production_recovery_allowed',false);
    file=fullfile(output_root,'native_series_access.json');
    fid=fopen(file,'w','n','UTF-8');assert(fid>=0,'Cannot save verification.');
    cleanup_file=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(record));
end

function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0,'Cannot save comparison evidence.');
    cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
