function record=Run_HeatDriveECC_ControllerIsolation(repo,output_root,side)
% Delete one controller from the frozen paired bench to localize solver cost.
    assert(any(strcmp(side,{'reference','candidate'})));
    assert(~isfolder(output_root),'Never overwrite diagnostic evidence.');
    [code,dirty]=system(sprintf('git -C "%s" status --porcelain -- .',repo));
    assert(code==0 && isempty(strtrim(dirty)),'Commit source first.');
    [code,commit]=system(sprintf('git -C "%s" rev-parse HEAD',repo));assert(code==0);
    root=fullfile(repo,'outputs_storage_audit','ps_controller_equivalence_20260909_v2');
    baseline=jsondecode(fileread(fullfile(root,'controller_equivalence.json')));
    assert(baseline.collection_pass && baseline.equivalence_pass && ~baseline.production_recovery_allowed);
    assert(strcmp(baseline.execution_commit,'35ab1dc15bfdc3266ef12e7c56ec1b77f601bc01'));
    source=fullfile(root,'paired_observations.mat');source_hash=file_hash(source);
    assert(strcmp(source_hash,baseline.observations_sha256));
    s=load(source,'commands');names=fieldnames(s.commands);
    oldpath=path;pc=onCleanup(@() path(oldpath));
    addpath(fullfile(root,'component_build'));load_system('ecc_sma_controller_lib');
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));dc=onCleanup(@() diary('off'));
    generation=Simulink.fileGenControl('getConfig');gc=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'cache'),'CodeGenFolder',fullfile(output_root,'codegen'),'createDir',true);
    record=struct('schema','heatdrive_ecc_controller_isolation_v1','side',side, ...
        'execution_commit',strtrim(commit),'collection_pass',false,'coupled_model_tested',false, ...
        'production_recovery_allowed',false,'error_message','','baseline_observations_sha256',source_hash);
    try
        model='ecc_sma_controller_equivalence';assert(~bdIsLoaded(model));
        model_source=fullfile(root,[model '.slx']);record.baseline_model_sha256=file_hash(model_source);
        load_system(model_source);mc=onCleanup(@() close_system(model,0));
        for k=1:numel(names)
            c=s.commands.(names{k});t=c.time_s;v=c.values;variable=['controller_test_' names{k}];
            assignin('base',variable,timeseries(v,t));d=zeros(size(v));
            if strcmp(c.interpolate,'on'),d=[diff(v)./diff(t);0];end
            assignin('base',[variable '_derivative'],timeseries(d,t));
        end
        parameters={'Solver','SolverType','MaxStep','RelTol','AbsTol','StopTime','AlgebraicLoopMsg'};
        expected={'ode15s','Variable-step','.001','1e-9','1e-11','10','error'};
        for k=1:numel(parameters),assert(strcmp(get_param(model,parameters{k}),expected{k}));end
        record.solver_parameters=cell2struct(expected,parameters,2);
        delete_block([model '/Observations']);
        add_block('simulink/Signal Routing/Mux',[model '/Observations'],'Inputs','3');
        if strcmp(side,'candidate')
            removed={'Error','Lag','Kp','Ki','EnabledP','Integral','RawPressure','Pressure'};
            observed={'pressure_output','lag_output','integral_output'};
        else
            removed={'Candidate','Solver','pressure_output','lag_output','integral_output'};
            for k=1:numel(names)
                removed=[removed,{[names{k} '_PS'],[names{k} '_derivative']}]; %#ok<AGROW>
            end
            observed={'Pressure','Lag','Integral'};
        end
        for k=1:numel(removed),delete_block([model '/' removed{k}]);end
        record.removed_blocks=removed;
        for k=1:3,wire(model,[model '/' observed{k}],1,[model '/Observations'],k);end
        wire(model,[model '/Observations'],1,[model '/SaveObservations'],1);
        save_system(model,fullfile(output_root,[model '.slx']));
        input=Simulink.SimulationInput(model);input=input.setModelParameter('CaptureErrors','on');started=tic;output=sim(input);
        record.simulation_wall_seconds=toc(started);record.simulation_error=output.ErrorMessage;
        assert(isempty(output.ErrorMessage),output.ErrorMessage);
        observations=output.get('observations');time_s=observations.Time;values=observations.Data;
        assert(time_s(1)==0 && time_s(end)==10 && all(diff(time_s)>0));
        assert(size(values,2)==3 && all(isfinite(values),'all'));
        dt=diff(time_s);record.sample_count=numel(time_s);record.minimum_step_s=min(dt);
        record.steps_below_1e_6_s=sum(dt<1e-6);record.sample_counts_by_second=histcounts(time_s,0:10);
        commands=s.commands;save(fullfile(output_root,'isolated_public_traces.mat'),'time_s','values','commands','-v7.3');
        record.observations_sha256=file_hash(fullfile(output_root,'isolated_public_traces.mat'));
        record.collection_pass=true;clear mc
    catch ME
        record.error_message=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'controller_isolation.json'),'w','n','UTF-8');assert(fid>=0);fc=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));fprintf('%s\n',jsonencode(record));
    assert(record.collection_pass,'Controller isolation collection failed.');
end

function wire(model,source,si,destination,di)
    s=get_param(source,'PortHandles');d=get_param(destination,'PortHandles');add_line(model,s.Outport(si),d.Inport(di));
end
function hash=file_hash(file)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
