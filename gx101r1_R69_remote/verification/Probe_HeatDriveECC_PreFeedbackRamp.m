function report=Probe_HeatDriveECC_PreFeedbackRamp(repo,out)
% Test actual From Workspace interpolation modes before using them in physics.
    assert(~isfolder(out),'Never overwrite ramp evidence.');
    path=fullfile(repo,'outputs_storage_audit','nonlinear_inventory_cold_held_10us_20260910','compiled_states_inspection.json');
    assert(strcmp(hash_file(path),'2D1A1BFBA84027D1CA88ECE5DADFA46D37E9609F287C05D3985F09FF00514CA3'));
    source=jsondecode(fileread(path));contract=Build_HeatDriveECC_PreFeedbackRamp(source.actual_command_schedule,.14);
    model='ecc_pre_feedback_ramp_probe';assert(~bdIsLoaded(model));new_system(model);
    cleanup=onCleanup(@() close_system(model,0));
    assignin('base','probe_bias_ramp',timeseries(contract.bias_MPa,contract.time_s));
    assignin('base','probe_bias_derivative',timeseries(contract.derivative_MPa_s,contract.time_s));
    add_block('simulink/Sources/From Workspace',[model '/Bias'],'VariableName','probe_bias_ramp','Interpolate','on');
    add_block('simulink/Sources/From Workspace',[model '/Slope'],'VariableName','probe_bias_derivative','Interpolate','off');
    add_block('simulink/Sinks/Out1',[model '/BiasOut']);
    add_block('simulink/Sinks/Out1',[model '/SlopeOut'],'Port','2');
    add_block('simulink/Continuous/Integrator',[model '/IntegratedSlope'],'InitialCondition','-1e-6');
    add_block('simulink/Sinks/Out1',[model '/IntegralOut'],'Port','3');
    add_line(model,'Bias/1','BiasOut/1');add_line(model,'Slope/1','SlopeOut/1');
    add_line(model,'Slope/1','IntegratedSlope/1');add_line(model,'IntegratedSlope/1','IntegralOut/1');
    set_param(model,'Solver','ode23t','SolverType','Variable-step','RelTol','1e-6','AbsTol','1e-8', ...
        'MaxStep','.00002','StartTime','0','StopTime','.14','OutputOption','RefineOutputTimes','Refine','1', ...
        'SaveOutput','on','OutputSaveName','yout','SaveFormat','Dataset','ReturnWorkspaceOutputs','on');
    output=sim(model);b=output.yout{1}.Values;d=output.yout{2}.Values;i=output.yout{3}.Values;
    [status,commit]=system('git rev-parse HEAD');assert(status==0);
    report=struct('contract',contract,'time_s',b.Time,'bias_MPa',b.Data,'slope_time_s',d.Time, ...
        'slope_MPa_s',d.Data,'integral_time_s',i.Time,'integral_MPa',i.Data, ...
        'producer',strtrim(commit),'command_source_sha256',hash_file(path), ...
        'coupled_model_tested',false,'production_recovery_allowed',false);
    mkdir(out);fid=fopen(fullfile(out,'pre_feedback_ramp_probe.json'),'w','n','UTF-8');assert(fid>=0);
    fc=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));clear fc
    fprintf('%s\n',jsonencode(struct('ramp_probe_complete',true,'samples',numel(b.Time),'coupled_model_tested',false)));
end

function hash=hash_file(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
