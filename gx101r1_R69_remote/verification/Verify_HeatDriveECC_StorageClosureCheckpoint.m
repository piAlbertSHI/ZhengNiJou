function result = Verify_HeatDriveECC_StorageClosureCheckpoint(source_root,audit_path)
    contract=Require_HeatDriveECC_StorageClosureCheckpoint(source_root,audit_path);
    assert(contract.snapshot_time_s==20 && ~contract.complete_cycle_restore_verified);
    original=jsondecode(fileread(audit_path));
    changes={ ...
        @(a) setfield(a,'full_mechanism_pass',false), ...
        @(a) setfield(a,'local_inventory_pass',false), ...
        @(a) setfield(a,'production_recovery_allowed',true), ...
        @(a) setfield(a,'complete_cycle_restore_verified',true), ...
        @(a) setfield(a,'input_sha256','observations_mat',repmat('0',1,64)), ...
        @(a) setfield(a,'source_operating_point_sha256',repmat('0',1,64))};
    for k=1:numel(changes)
        path=[tempname '.json'];cleanup=onCleanup(@() delete(path));
        fid=fopen(path,'w','n','UTF-8');assert(fid>=0);
        fprintf(fid,'%s\n',jsonencode(changes{k}(original)));fclose(fid);
        rejected=false;
        try,Require_HeatDriveECC_StorageClosureCheckpoint(source_root,path);catch,rejected=true;end
        assert(rejected,'Failed or changed new-model C2 authority was accepted.');clear cleanup
    end
    result=struct('positive_cases',1,'negative_cases',numel(changes),'pass',true);
    fprintf('%s\n',jsonencode(result));
end
