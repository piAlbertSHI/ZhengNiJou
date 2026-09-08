function audit=Run_HeatDriveECC_OneSecondTransferControl(repo,output_root)
% Run one bounded reference/candidate comparison; never save a recovery OP.
    assert(~isfolder(output_root),'Do not overwrite evidence.');
    [code,commit]=system('git rev-parse HEAD');assert(code==0,'Cannot record source.');
    [code,dirty]=system('git status --porcelain');assert(code==0 && isempty(strtrim(dirty)),'Commit source first.');
    mkdir(output_root);
    audit=struct('schema','heatdrive_ecc_one_second_transfer_execution_v1', ...
        'execution_commit',strtrim(commit),'computation_complete',false, ...
        'production_recovery_allowed',false,'final_checkpoint_saved',false, ...
        'command_horizon_extended',false,'boundary_sample_hold_diagnostic',true, ...
        'start_time_s',2000.001,'stop_time_s',2001.001,'error_message','');
    try
        reference=Run_HeatDriveECC_FullOPRoundtripControl(repo,fullfile(output_root,'reference'),'one_second_reference');
        assert(reference.computation_complete,'Strict reference did not complete.');
        candidate=Run_HeatDriveECC_PublicSnapshotControl(repo,fullfile(output_root,'candidate'), ...
            'advanced_differential_targets','one_second_complete_only');
        assert(candidate.computation_complete,'Candidate did not complete.');
        audit.computation_complete=true;
    catch ME
        audit.error_message=ME.message;audit.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'one_second_execution.json'),'w','n','UTF-8');assert(fid>=0,'Cannot save execution audit.');
    cleanup_file=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(audit));
    assert(audit.computation_complete,'See one_second_execution.json.');
end
