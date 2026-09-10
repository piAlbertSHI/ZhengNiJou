function record=Audit_HeatDriveECC_BridgeIntegral(repo,out)
% Read archived trajectories only; preserve the failed diagnostic gate.
    assert(~isfolder(out));
    source=fullfile(repo,'outputs_storage_audit','pre_feedback_bridge_consumer_20260910','bridge_observations.mat');
    d=load(source);c=load(fullfile(repo,'outputs_storage_audit','hybrid_controller_equivalence_20260910', ...
        'paired_observations.mat'),'commands');c=c.commands.bias;
    t=d.bridge_pressure.Time(:);q=d.bridge_pressure.Data(:);
    tt=d.observations.Time(:);p=d.observations.Data(:,4);
    assert(isequal(t,tt),'Do not interpolate different observation grids silently.');
    slope=diff(c.values)./diff(c.time_s);first=find(slope~=0,1);onset=c.time_s(first);
    expected=c.values(1)*t+.5*slope(first)*max(t-onset,0).^2;
    pressure=interp1(c.time_s,c.values,t,'linear');
    integrated=cumtrapz(t,p);error=q-expected;
    right=[0;cumsum(diff(t).*p(2:end))];
    boundaries=[0,.099,.1,.101,.105,.11,.12,.13,.14];rows=cell(1,numel(boundaries)-1);
    for k=1:numel(rows)
        ix=find(t>=boundaries(k) & t<=boundaries(k+1));assert(~isempty(ix));
        rows{k}=struct('start_s',boundaries(k),'end_s',boundaries(k+1),'samples',numel(ix), ...
            'first_error_MPa_s',error(ix(1)),'last_error_MPa_s',error(ix(end)), ...
            'max_absolute_error_MPa_s',max(abs(error(ix))));
    end
    record=struct('simulation_run',false,'production_recovery_allowed',false,'ramp_onset_s',onset, ...
        'maximum_pressure_error_MPa',max(abs(p-pressure)), ...
        'maximum_trapezoid_error_MPa_s',max(abs(integrated-expected)), ...
        'maximum_consumer_vs_trapezoid_MPa_s',max(abs(q-integrated)), ...
        'maximum_integral_error_MPa_s',max(abs(error)),'gate_limit_MPa_s',1e-7, ...
        'maximum_consumer_vs_right_rectangle_MPa_s',max(abs(q-right)), ...
        'right_rectangle_endpoint_error_MPa_s',right(end)-expected(end), ...
        'reset_mechanism_proven',false, ...
        'original_integral_gate_pass',max(abs(error))<=1e-7,'windows',{rows}, ...
        'source_sha256',file_hash(source));
    mkdir(out);fid=fopen(fullfile(out,'integral_error_audit.json'),'w','n','UTF-8');assert(fid>=0);
    fc=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(record,PrettyPrint=true));clear fc
    disp(jsonencode(record));
end

function hash=file_hash(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(path,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,1048576,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
