function source=Capture_HeatDriveECC_FreshSensitivityNative(overrides,root)
% Measure this case's native t=0 coordinates/fluxes before replacing storage components.
    assert(~isfolder(root));mkdir(root);mkdir(fullfile(root,'native'));
    overrides.branch.independent_conservative_chamber_diagnostic=false;
    [model,options]=Build_HeatDriveECC_EighthRound_Simulink_Model(overrides);
    cleanup=onCleanup(@() close_system(model,0));
    ff=Configure_HeatDriveECC_DistributedPressureFeedforward(model,options);
    Configure_HeatDriveECC_SEReferenceClosure(model,options,ff,0,.001);
    set_param(model,'LoadInitialState','off','SimscapeUseOperatingPoints','off','StartTime','0', ...
        'StopTime','.001','ReturnWorkspaceOutputs','on','SaveFinalState','off','SaveOperatingPoint','off', ...
        'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
        'SimscapeLogToSDI','off','SimulationMode','normal','Solver',options.simulation.solver, ...
        'FixedStep',num2str(options.simulation.fixed_step_s,'%.17g'));
    input=Simulink.SimulationInput(model);output=sim(input.setModelParameter('CaptureErrors','on'));
    assert(isempty(output.ErrorMessage),'HeatDriveECC:FreshNativeSourceFailed','%s',output.ErrorMessage);
    native=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model,false);
    assert(all(cellfun(@(r) r.time_s(1)==0,native)));
    save(fullfile(root,'native','observations.mat'),'native','-v7.3');
    source=struct('schema','heatdrive_ecc_fresh_sensitivity_native_source_v1', ...
        'window_s',[0 .001],'old_state_loaded',false,'complete_OP_saved',false, ...
        'full_cycle_gates_evaluated',false,'source_role','same-case t0 coordinates and fluxes only', ...
        'raw_path',fullfile(root,'native','observations.mat'),'production_recovery_allowed',false);
    write_json(fullfile(root,'fresh_native_source.json'),source);
end
function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
