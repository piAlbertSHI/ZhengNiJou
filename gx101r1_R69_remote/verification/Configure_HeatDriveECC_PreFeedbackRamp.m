function contract=Configure_HeatDriveECC_PreFeedbackRamp(repo,model,commands)
% Change the derivative branch only, never the pressure value or state paths.
    assert(strcmp(get_param(model,'StopTime'),'0'));
    proof=fullfile(repo,'outputs_storage_audit','pre_feedback_ramp_audit_20260910','pre_feedback_ramp_audit.json');
    assert(strcmp(hash_file(proof),'2B7B49C81DC82F2F4F114E3FDB6086EF25AE3D4EC816FFBB26AF1134327992BF'));
    q=jsondecode(fileread(proof));assert(q.source_value_and_slope_pass && ~q.production_recovery_allowed);
    held=fullfile(repo,'outputs_storage_audit','nonlinear_cold_held_10us_audit_20260910','nonlinear_cold_held_audit.json');
    assert(strcmp(hash_file(held),'F7224185C7F683A2D396EC3BDAEC7C3B6B2A992C4AB7B33470FD7D948F947A9E'));
    h=jsondecode(fileread(held));assert(h.local_balance_gate && h.passing_joint_balances==6);
    c=Build_HeatDriveECC_PreFeedbackRamp(commands,.14);
    source=[model '/ColdInitialPressureDerivativeOnly'];converter=[model '/SMAPressurePI_SimulinkPS'];
    p=get_param(converter,'PortHandles');assert(numel(p.Inport)==2);
    assert(strcmp(getfullname(get_param(get_param(p.Inport(2),'Line'),'SrcBlockHandle')),source));
    bias=[model '/ColdObserver_bias_PS'];bp=get_param(bias,'PortHandles');
    assert(numel(bp.Inport)==2 && ...
        strcmp(getfullname(get_param(get_param(bp.Inport(2),'Line'),'SrcBlockHandle')),source));
    % Remove both branches explicitly; do not depend on block auto-connection.
    delete_line(get_param(p.Inport(2),'Line'));
    remaining=get_param(bp.Inport(2),'Line');
    if remaining~=-1,delete_line(remaining);end
    delete_block(source);
    source=[model '/ColdPreFeedbackPressureDerivative'];
    assignin('base','cold_pre_feedback_dp',timeseries(c.derivative_MPa_s,c.time_s));
    add_block('simulink/Sources/From Workspace',source,'VariableName','cold_pre_feedback_dp', ...
        'Interpolate','off','OutputAfterFinalValue','Holding final value');
    s=get_param(source,'PortHandles');add_line(model,s.Outport(1),p.Inport(2));
    add_line(model,s.Outport(1),bp.Inport(2));
    sink=[model '/ColdPreFeedbackDerivativeLog'];
    add_block('simulink/Sinks/To Workspace',sink,'VariableName','cold_pre_feedback_derivative_MPa_s', ...
        'SaveFormat','Timeseries','MaxDataPoints','inf');
    d=get_param(sink,'PortHandles');add_line(model,s.Outport(1),d.Inport(1));
    set_param(model,'StopTime','0.14');contract=Verify_HeatDriveECC_PreFeedbackRamp(model);
    contract.qualification_sha256=hash_file(proof);
end

function hash=hash_file(path)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
