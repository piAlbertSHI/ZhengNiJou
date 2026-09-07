function audit = Test_HeatDriveECC_LagStateSpaceEquivalence(output_root)
% Compare first-order transfer-function and canonical state-space states.
    assert(~isfolder(output_root),'Do not overwrite lag evidence.'); mkdir(output_root);
    [code,commit]=system('git rev-parse HEAD');assert(code==0,'Cannot record source.');
    generation=Simulink.fileGenControl('getConfig');
    cleanup_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'build_cache'), ...
        'CodeGenFolder',fullfile(output_root,'generated_code'),'createDir',true);
    load_system('simulink'); model='ecc_lag_state_space_equivalence';
    assert(~bdIsLoaded(model),'Model already in use.');new_system(model);
    cleanup_model=onCleanup(@() close_system(model,0));
    tau=.002; x0=-3.379561321780173e-6;
    [A,B,C,D]=tf2ss(1,[tau 1]);
    assert(A==-1/tau && B==1 && C==1/tau && D==0,'Unexpected canonical basis.');
    add_block('simulink/Sources/Sine Wave',[model '/Input'],'Amplitude','0.01','Frequency','500');
    add_block('simulink/Continuous/Transfer Fcn',[model '/Transfer'], ...
        'Numerator','1','Denominator',mat2str([tau 1],17));
    add_block('simulink/Continuous/State-Space',[model '/StateSpace'], ...
        'A',mat2str(A,17),'B',mat2str(B,17),'C',mat2str(C,17),'D',mat2str(D,17), ...
        'InitialCondition',mat2str(x0,17));
    for name={'Transfer','StateSpace'}
        add_block('simulink/Sinks/To Workspace',[model '/' name{1} 'Log'], ...
            'VariableName',[lower(name{1}) '_output'],'SaveFormat','Timeseries');
        add_line(model,'Input/1',[name{1} '/1']);
        add_line(model,[name{1} '/1'],[name{1} 'Log/1']);
    end
    set_param(model,'StartTime','2000','StopTime','2000.1','Solver','ode3','FixedStep','0.001', ...
        'SaveState','on','StateSaveName','states','SaveFormat','Dataset', ...
        'SaveOutput','off','SaveTime','off','ReturnWorkspaceOutputs','on');
    ds=Simulink.BlockDiagram.getInitialState(model);
    assert(isa(ds,'Simulink.SimulationData.Dataset') && ds.numElements==2,'Require exact state metadata.');
    for k=1:ds.numElements
        item=ds.getElement(k); series=item.Values;
        series.Data(:)=x0; series.Time=2000; item.Values=series;
        ds=ds.setElement(k,item);
    end
    input=Simulink.SimulationInput(model);input=input.setInitialState(ds);
    out=sim(input);
    time_s=out.transfer_output.Time; transfer=out.transfer_output.Data; state_space=out.statespace_output.Data;
    observed=out.states;
    assert(numel(time_s)==101 && isequal(time_s,out.statespace_output.Time),'Wrong equivalence grid.');
    state1=observed.getElement(1);state2=observed.getElement(2);
    state_difference=max(abs(state1.Values.Data(:)-state2.Values.Data(:)));
    output_difference=max(abs(transfer(:)-state_space(:)));
    audit=struct('schema','heatdrive_ecc_lag_state_space_equivalence_v1','execution_commit',strtrim(commit), ...
        'tau_s',tau,'initial_canonical_state',x0,'A',A,'B',B,'C',C,'D',D,'samples',101, ...
        'start_s',2000,'stop_s',2000.1,'step_s',.001,'solver','ode3', ...
        'state_max_difference',state_difference,'output_max_difference',output_difference, ...
        'equivalence_pass',state_difference<=1e-15 && output_difference<=1e-12, ...
        'production_model_modified',false,'production_recovery_allowed',false);
    save(fullfile(output_root,'equivalence_traces.mat'),'time_s','transfer','state_space','observed','audit','-v7.3');
    fid=fopen(fullfile(output_root,'lag_equivalence.json'),'w','n','UTF-8');assert(fid>=0,'Cannot save audit.');
    cleanup_file=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(audit));assert(audit.equivalence_pass,'Canonical state equivalence failed.');
end
