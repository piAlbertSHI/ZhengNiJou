function contract = Require_HeatDriveECC_LoggingOnlyRunnerSource(workspace, producer)
    assert(~isempty(regexp(producer,'^[0-9a-f]{40}$','once')),'Require exact source producer.');
    relative='gx101r1_R69_remote/verification/Run_HeatDriveECC_ColdChamberDiagnostic.m';
    [status,original]=system(sprintf('git -C "%s" show %s:%s',workspace,producer,relative));
    assert(status==0,'Missing original physical runner.');
    current=fileread(fullfile(workspace,relative));
    assert(strcmp(Normalize_HeatDriveECC_LoggingRunnerSource(original), ...
        Normalize_HeatDriveECC_LoggingRunnerSource(current)), ...
        'A physical/drive/state/initialization runner edit cannot be disguised as logging.');
    contract=struct('exact_logging_only_source_delta_pass',true,'producer',producer, ...
        'physical_control_and_initialization_source_unchanged',true,'production_recovery_allowed',false);
end
