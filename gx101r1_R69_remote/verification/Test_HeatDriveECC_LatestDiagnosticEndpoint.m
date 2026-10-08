function record = Test_HeatDriveECC_LatestDiagnosticEndpoint(source, verified, output_root)
% Read-only actual OP loading plus compact authority-rejection counterexamples.
    assert(~isfolder(output_root),'Never overwrite endpoint guard evidence.');mkdir(output_root);
    options=struct('mode','diagnostic_resume','command_horizon_cycles',200, ...
        'restore_source_root',source,'restore_verification_root',verified);
    [op,contract]=Load_HeatDriveECC_DiagnosticResumeSource(options);
    execution=jsondecode(fileread(fullfile(source,'cold_chamber_execution.json')));
    assert(op.snapshotTime==execution.stop_time_s && contract.snapshot_time_s==execution.stop_time_s && ...
        contract.source_physical_gates_evaluated && ~contract.production_recovery_allowed && ...
        ~contract.latest_endpoint_complete_cycle_reference_compared,'Require the actual C22 diagnostic endpoint.');
    original=jsondecode(fileread(fullfile(verified,'diagnostic_resume_qualification.json')));
    mutations={'production','edited','missing_role','changed_hash','wrong_clock','wrong_root'};
    rejected=false(size(mutations));
    for idx=1:numel(mutations)
        receipt=original;folder=fullfile(output_root,mutations{idx});mkdir(folder);
        switch mutations{idx}
            case 'production',receipt.production_recovery_allowed=true;
            case 'edited',receipt.source_state_edited=true;
            case 'missing_role',receipt.files(end)=[];
            case 'changed_hash',receipt.files(1).sha256=repmat('0',1,64);
            case 'wrong_clock',receipt.snapshot_time_s=20;
            case 'wrong_root',receipt.source_root=folder;
        end
        write_json(fullfile(folder,'diagnostic_resume_qualification.json'),receipt);
        bad=options;bad.restore_verification_root=folder;
        try
            Load_HeatDriveECC_DiagnosticResumeSource(bad);
        catch
            rejected(idx)=true;
        end
    end
    assert(all(rejected),'A forbidden endpoint authority was accepted.');
    record=struct('schema','heatdrive_ecc_actual_latest_endpoint_guard_v1', ...
        'snapshot_time_s',op.snapshotTime,'vendor_op_class',class(op), ...
        'qualification_sha256',contract.qualification_sha256,'valid_actual_endpoint_loaded',true, ...
        'negative_cases',{mutations},'negative_cases_rejected',rejected, ...
        'simulation_executed',false,'source_state_edited',false,'production_recovery_allowed',false);
    write_json(fullfile(output_root,'actual_endpoint_guard.json'),record);
    fprintf('%s\n',jsonencode(record,'PrettyPrint',true));
end

function write_json(path,record)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0,'Cannot persist endpoint guard evidence.');
    cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
end
