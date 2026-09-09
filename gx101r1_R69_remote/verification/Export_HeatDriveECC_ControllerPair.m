function Export_HeatDriveECC_ControllerPair(root)
% Export public timeseries arrays for independent, non-MATLAB audit.
    record=jsondecode(fileread(fullfile(root,'controller_equivalence.json')));
    assert(record.collection_pass && ~record.production_recovery_allowed && ~record.coupled_model_tested);
    source=fullfile(root,'paired_observations.mat');destination=fullfile(root,'paired_public_traces.mat');
    assert(~isfile(destination),'Never overwrite a public trace export.');
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(source,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    source_sha256=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));clear c
    assert(strcmp(source_sha256,record.observations_sha256),'Source observation hash changed.');
    s=load(source,'observations','commands');time_s=s.observations.Time;values=s.observations.Data;commands=s.commands;
    assert(size(values,1)==numel(time_s) && size(values,2)==6 && time_s(1)==0 && time_s(end)==10);
    save(destination,'time_s','values','commands','source_sha256','-v7.3');
    fprintf('%s\n',jsonencode(struct('public_export_pass',true,'sample_count',numel(time_s),'source_sha256',source_sha256)));
end
