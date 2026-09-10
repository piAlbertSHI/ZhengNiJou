function report=Probe_HeatDriveECC_ODE23tReset(out,solver,max_step)
% An exactly integrable ODE tests reset startup behavior, not physical validity.
    assert(~isfolder(out),'Never overwrite probe evidence.');
    if nargin<2,solver='ode23t';end
    if nargin<3,max_step=.00025;end
    assert(any(strcmp(solver,{'ode23t','ode23tb'})),'Only declared implicit-method probes are allowed.');
    assert(ismember(max_step,[.00025,.00002]) && (max_step==.00025 || strcmp(solver,'ode23t')), ...
        'Only the declared reset-error step probe is allowed.');
    cases={{'continuous','Fast','auto'},{'sampled','Fast','auto'}, ...
        {'sampled','Robust','auto'},{'sampled','Fast','1e-6'}};
    if strcmp(solver,'ode23tb'),cases=cases(1:2);end
    if max_step==.00002,cases=cases(2);end
    report=struct('matlab_release',version('-release'),'case_results',{{}}, ...
        'solver',solver,'max_step_s',max_step,'actual_coupled_model_tested',false,'production_recovery_allowed',false);
    for k=1:numel(cases)
        c=cases{k};model=['ecc_ode23t_reset_probe_' num2str(k)];
        assert(~bdIsLoaded(model));new_system(model);cleanup=onCleanup(@() close_system(model,0));
        add_block('simulink/Sources/Clock',[model '/Time']);
        add_block('simulink/Math Operations/Gain',[model '/Slope'],'Gain','2');
        add_block('simulink/Sources/Constant',[model '/Offset'],'Value','1');
        add_block('simulink/Math Operations/Sum',[model '/Flux'],'Inputs','+++');
        add_block('simulink/Continuous/Integrator',[model '/Inventory'],'InitialCondition','1');
        add_block('simulink/Sinks/Out1',[model '/y']);
        add_block('simulink/Sinks/Out1',[model '/f'],'Port','2');
        add_line(model,'Time/1','Slope/1');add_line(model,'Slope/1','Flux/1');
        add_line(model,'Offset/1','Flux/2');
        if strcmp(c{1},'sampled')
            add_block('simulink/Discrete/Zero-Order Hold',[model '/SampledTime'],'SampleTime','.001');
            add_line(model,'Time/1','SampledTime/1');add_line(model,'SampledTime/1','Flux/3');
        else
            add_block('simulink/Sources/Constant',[model '/NoSampledFlux'],'Value','0');
            add_line(model,'NoSampledFlux/1','Flux/3');
        end
        add_line(model,'Flux/1','Inventory/1');add_line(model,'Inventory/1','y/1');add_line(model,'Flux/1','f/1');
        set_param(model,'SolverType','Variable-step','Solver',solver,'SolverResetMethod',c{2}, ...
            'InitialStep',c{3},'MaxStep',num2str(max_step,'%.17g'),'RelTol','1e-6','AbsTol','1e-8', ...
            'AutoScaleAbsTol','on','StartTime','0','StopTime','.04', ...
            'OutputOption','RefineOutputTimes','Refine','1','Decimation','1', ...
            'SaveTime','on','TimeSaveName','tout','SaveOutput','on','OutputSaveName','yout', ...
            'SaveFormat','Dataset','ReturnWorkspaceOutputs','on','SaveFinalState','off');
        result=sim(model);t=result.tout;y=result.yout{1}.Values.Data;flux=result.yout{2}.Values.Data;
        exact=1+t+t.^2;
        if strcmp(c{1},'sampled')
            n=floor(t/.001+1e-12);
            exact=exact+(.001)^2*n.*(n-1)/2+n*.001.*(t-n*.001);
        end
        resets=(0:.001:.039)';first_steps=zeros(size(resets));first_step_errors=zeros(size(resets));
        for q=1:numel(resets)
            index=find(abs(t-resets(q))<1e-14,1,'last');
            if isempty(index) || index==numel(t),first_steps(q)=NaN;first_step_errors(q)=NaN;
            else
                first_steps(q)=t(index+1)-t(index);
                first_step_errors(q)=(y(index+1)-y(index))-(exact(index+1)-exact(index));
            end
        end
        report.case_results{k}=struct('forcing',c{1},'reset_method',c{2},'initial_step_setting',c{3}, ...
            'time_s',t,'inventory',y,'logged_flux',flux,'analytic_inventory',exact, ...
            'max_abs_analytic_error',max(abs(y-exact)), ...
            'candidate_reset_times_s',resets,'steps_after_candidate_reset_s',first_steps, ...
            'analytic_increment_errors_after_candidate_reset',first_step_errors);
        clear cleanup
    end
    report.probe_source_sha256=hash_file([mfilename('fullpath') '.m']);
    mkdir(out);fid=fopen(fullfile(out,'ode23t_reset_probe.json'),'w','n','UTF-8');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));clear cleanup
    for k=1:numel(report.case_results)
        c=report.case_results{k};fprintf('%s\n',jsonencode(struct('forcing',c.forcing,'reset_method',c.reset_method, ...
            'initial_step',c.initial_step_setting,'samples',numel(c.time_s),'max_abs_analytic_error',c.max_abs_analytic_error, ...
            'first_step_s',c.steps_after_candidate_reset_s(1),'step_after_1ms_s',c.steps_after_candidate_reset_s(2))));
    end
end

function hash=hash_file(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(path,'rb');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,1048576,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
