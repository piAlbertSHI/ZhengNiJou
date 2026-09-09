function contract=Configure_HeatDriveECC_HybridHeldInterval(repo,model,seconds)
% Extend only the independently qualified hybrid cold assembly to 40 ms.
    assert(seconds==.04 && strcmp(get_param(model,'StopTime'),'0'));
    qualified=fullfile(repo,'outputs_storage_audit','hybrid_cold_actuation_audit_20260910','hybrid_cold_audit.json');
    hash=file_hash(qualified);
    assert(strcmp(hash,'8598BB08D314EA1B052C5B4CCE9A9DD7F0E30BE6842E668A038306F58E298C13'));
    q=jsondecode(fileread(qualified));
    assert(q.cold_initial_actuation_pass && q.compiled_inventory_gate && q.compiled_algebraic_loops==0 && ~q.production_recovery_allowed);
    set_param([model '/ColdInitialPressureDerivativeOnly'],'Name','ColdHeldPressureDerivative');
    set_param(model,'StopTime','0.04');
    contract=Verify_HeatDriveECC_HybridHeldInterval(model);
    contract.qualification_path=qualified;contract.qualification_sha256=hash;
    contract.state_imported=false;
end
function hash=file_hash(file)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
