function record=Probe_HeatDriveECC_ProfilerFailureLifecycle(output_root,stop_before_event)
% Isolate profiler persistence on an intentional simulation assertion failure.
    if nargin<2,stop_before_event=false;end
    assert(~isfolder(output_root),'Never overwrite diagnostic evidence.');
    mkdir(output_root);
    model='ecc_profiler_lifecycle_fixture';
    assert(~bdIsLoaded(model),'Fixture is already loaded.');
    new_system(model);cleanup=onCleanup(@() close_system(model,0));
    add_block('simulink/Sources/Clock',[model '/Clock']);
    add_block('simulink/Logic and Bit Operations/Compare To Constant',[model '/BeforeFailure'], ...
        'const','0.1','relop','<');
    add_block('simulink/Model Verification/Assertion',[model '/IntentionalFailure']);
    add_block('simulink/Continuous/Integrator',[model '/State']);
    add_line(model,'Clock/1','BeforeFailure/1');
    add_line(model,'BeforeFailure/1','IntentionalFailure/1');
    add_line(model,'Clock/1','State/1');
    set_param(model,'Solver','ode23t','StopTime','0.14','MaxStep','0.001');
    if stop_before_event,set_param(model,'StopTime','0.09');end
    destination=fullfile(output_root,'solver_profile.mat');
    record=struct('api_returned',false,'error_identifier','','error_report','', ...
        'fixture_only',true,'physical_model_executed',false,'science_gate_pass',false, ...
        'stop_before_event',stop_before_event,'configured_stop_time',get_param(model,'StopTime'));
    try
        result=solverprofiler.profileModel(model,'SaveStates','on','SaveSimscapeStates','on', ...
            'SaveJacobian','on','SaveZCSignals','off','OpenSP','off','BufferSize',50000, ...
            'DataFullFile',destination);
        record.api_returned=true;record.api_result=result;
    catch ME
        record.error_identifier=ME.identifier;
        record.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    record.data_file_exists=isfile(destination);
    if record.data_file_exists
        loaded=load(destination,'sessionData');
        wrapper=loaded.sessionData.getActualDataFromSolverProfilerSessionData();
        data=wrapper.data;
        record.saved_model=data.Model;
        record.jacobian_times_s=data.getJacobianUpdateTime();
        record.solver_times_s=data.getTout();
        record.jacobian_public_properties=properties(data.SortedPD.JacobianInfo);
        record.raw_matrices_verified=false;
    end
    fid=fopen(fullfile(output_root,'lifecycle.json'),'w');assert(fid>=0);
    file_cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,PrettyPrint=true));
    clear file_cleanup
    disp(jsonencode(record));
end
