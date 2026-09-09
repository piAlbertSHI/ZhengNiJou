function contract=Configure_HeatDriveECC_ColdPSInitialActuation(repo,model,observer)
% Close the pressure value path only at the verified held-reset initial point.
    assert(strcmp(get_param(model,'StartTime'),'0') && strcmp(get_param(model,'StopTime'),'0') && ...
        strcmp(get_param(model,'LoadInitialState'),'off') && strcmp(get_param(model,'SaveOperatingPoint'),'off'));
    assert(observer.separate_solver_added && strcmp(observer.flow_input_mode,'live_simulink_bridge') && ~observer.observer_drives_pump);
    qualified=fullfile(repo,'outputs_storage_audit','passive_ps_live_flow_audit_20260909','passive_ps_network_audit.json');
    assert(strcmp(file_hash(qualified),'3C47AB592F9CC5BBAC3C4005BEA53B9EE58CE36D0F0FA36B42A62B0FE8598330'));
    commands=observer.commands;
    assert(all(commands(3).values(1:2)==0) && all(commands(4).values(1:2)==1) && ...
        commands(1).values(1)==commands(1).values(2),'Only the initial constant, feedback-disabled interval is admissible.');
    converter=observer.pressure_converter;driver=[model '/ColdObserver_pressure_Output'];sat=[model '/SMAPressurePI_Saturation'];
    assert(strcmp(get_param(driver,'Unit'),'MPa') && strcmp(get_param(converter,'UdotUserProvided'),'1') && ...
        strcmp(get_param(converter,'FilteringAndDerivatives'),'provide') && ...
        strcmp(input_source(converter,2),observer.pressure_derivative_source));
    assert(strcmp(get_param(observer.pressure_derivative_source,'Value'),'0') && ...
        strcmp(get_param(observer.pressure_derivative_source,'SampleTime'),'inf'));
    p=get_param(driver,'PortHandles');changes={};
    for block={converter,sat}
        destination=block{1};assert(strcmp(input_source(destination,1),observer.pressure_value_source));
        d=get_param(destination,'PortHandles');delete_line(get_param(d.Inport(1),'Line'));add_line(model,p.Outport(1),d.Inport(1));
        assert(strcmp(input_source(destination,1),driver));
        changes{end+1}=struct('destination',destination,'input',1,'before',observer.pressure_value_source,'after',driver); %#ok<AGROW>
    end
    assert(strcmp(input_source(converter,2),observer.pressure_derivative_source));
    contract=struct('schema','heatdrive_ecc_cold_ps_initial_actuation_v1','qualification_path',qualified, ...
        'qualification_sha256',file_hash(qualified),'changed_inputs',{changes},'pressure_driver',driver, ...
        'pressure_converter',converter,'pressure_derivative_source',observer.pressure_derivative_source, ...
        'observer_drives_pump',true,'initial_feedback_enable',0,'initial_reset',1, ...
        'first_derivative_MPa_s',0,'allowed_stop_time_s',0,'full_cycle_derivative_verified',false, ...
        'c200_state_imported',false,'production_recovery_allowed',false);
end
function source=input_source(block,index)
    p=get_param(block,'PortHandles');line=get_param(p.Inport(index),'Line');assert(line>0);source=getfullname(get_param(line,'SrcBlockHandle'));
end
function hash=file_hash(file)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
