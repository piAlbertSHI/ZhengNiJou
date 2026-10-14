function record = Test_HeatDriveECC_NativeLoggingWindow(workspace, producer)
    assert(Resolve_HeatDriveECC_NativeInventoryWindow(struct(),20,true,'native',true)==2);
    state=struct('mode','diagnostic_resume','command_horizon_cycles',200, ...
        'restore_source_root','source','restore_verification_root','proof', ...
        'storage_state_audit_path','state','storage_complete_cycle_audit_path','cycle', ...
        'native_inventory_window_cycles',10);
    resolved=Resolve_HeatDriveECC_DiagnosticStateOptions(state,20);
    assert(Resolve_HeatDriveECC_NativeInventoryWindow(resolved,20,true,'native',true)==10);
    guard=Require_HeatDriveECC_LoggingOnlyRunnerSource(workspace,producer);
    assert(guard.exact_logging_only_source_delta_pass);
    file=fullfile(workspace,'gx101r1_R69_remote','verification','Run_HeatDriveECC_ColdChamberDiagnostic.m');
    current=fileread(file);baseline=Normalize_HeatDriveECC_LoggingRunnerSource(current);
    changed=strrep(current,'''FixedStep''','''ChangedStep''');
    assert(~strcmp(Normalize_HeatDriveECC_LoggingRunnerSource(changed),baseline));
    changed=strrep(current,'arm,changed,buffer_paths);','arm,changed,wrong_paths);');
    assert(~strcmp(Normalize_HeatDriveECC_LoggingRunnerSource(changed),baseline));
    bad={@() Resolve_HeatDriveECC_NativeInventoryWindow(state,20,false,'native',true), ...
        @() Resolve_HeatDriveECC_NativeInventoryWindow(state,20,true,'conservative',true), ...
        @() Resolve_HeatDriveECC_NativeInventoryWindow(state,2,true,'native',true), ...
        @() Resolve_HeatDriveECC_DiagnosticStateOptions(struct('mode','capture','native_inventory_window_cycles',10),20), ...
        @() Resolve_HeatDriveECC_DiagnosticStateOptions(setfield(state,'native_inventory_window_cycles',9),20)};
    for k=1:numel(bad)
        rejected=false;try,bad{k}();catch,rejected=true;end
        assert(rejected,'Unsupported native recording policy accepted.');
    end
    record=struct('default_two_cycles_unchanged',true,'typed_ten_cycle_option_pass',true, ...
        'exact_logging_only_source_delta_pass',true,'physical_source_mutations_rejected',2, ...
        'invalid_window_policies_rejected',numel(bad),'pass',true);
    fprintf('%s\n',jsonencode(record));
end
