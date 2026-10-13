function result = Verify_HeatDriveECC_StorageClosureWarmupSource(source_root,state_path,cycle_path)
    contract=Require_HeatDriveECC_StorageClosureWarmupSource(source_root,state_path,cycle_path);
    assert(contract.snapshot_time_s==20 && contract.complete_cycle_restore_verified && ...
        contract.diagnostic_warmup_continuation_allowed && ~contract.production_recovery_allowed);
    options=struct('mode','diagnostic_resume','command_horizon_cycles',200, ...
        'restore_source_root',source_root,'restore_verification_root',contract.verification_root, ...
        'storage_state_audit_path',state_path,'storage_complete_cycle_audit_path',cycle_path);
    options=Resolve_HeatDriveECC_DiagnosticStateOptions(options,20);
    [op,resume]=Load_HeatDriveECC_DiagnosticResumeSource(options);
    assert(op.snapshotTime==20 && resume.full_cycle_state_restore_verified && ...
        resume.source_physical_gates_evaluated && ~resume.source_state_edited);
    original=jsondecode(fileread(cycle_path));
    changes={@(a) setfield(a,'diagnostic_warmup_continuation_allowed',false), ...
        @(a) setfield(a,'local_inventory_pass',false), ...
        @(a) setfield(a,'production_recovery_allowed',true), ...
        @(a) setfield(a,'samples_per_comparison',1), ...
        @(a) setfield(a,'C2_audit_sha256',repmat('0',1,64)), ...
        @(a) setfield(a,'input_sha256','native_rebuilt_cycle_restore_json',repmat('0',1,64))};
    for k=1:numel(changes)
        path=[tempname '.json'];cleanup=onCleanup(@() delete(path));
        fid=fopen(path,'w','n','UTF-8');assert(fid>=0);
        fprintf(fid,'%s\n',jsonencode(changes{k}(original)));fclose(fid);
        rejected=false;
        try,Require_HeatDriveECC_StorageClosureWarmupSource(source_root,state_path,path);catch,rejected=true;end
        assert(rejected,'Incomplete or changed warmup authority accepted.');clear cleanup
    end
    config=jsondecode(fileread(fullfile(fileparts(source_root),'candidate_config.json')));
    inventory=config.diagnostic_inventory_options;
    inventory.rebuilt_state_audit_path=state_path;inventory.warmup_restore_audit_path=cycle_path;
    Resolve_HeatDriveECC_ManifoldInventoryDiagnostic(inventory,'diagnostic_resume',20,200,'native',true);
    reference=config.diagnostic_se_reference_options;
    reference.rebuilt_state_audit_path=state_path;reference.warmup_restore_audit_path=cycle_path;
    Resolve_HeatDriveECC_SEReferenceDiagnostic(reference,'diagnostic_resume',20,200,'native',true);
    result=struct('positive_cases',4,'negative_cases',numel(changes),'pass',true, ...
        'source_snapshot_time_s',20,'source_operating_point_sha256',contract.operating_point_sha256, ...
        'storage_density_approximation_only',true,'production_recovery_allowed',false);
    fprintf('%s\n',jsonencode(result));
end
