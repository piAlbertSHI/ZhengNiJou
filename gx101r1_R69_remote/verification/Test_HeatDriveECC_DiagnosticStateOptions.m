function record = Test_HeatDriveECC_DiagnosticStateOptions()
    defaults=Resolve_HeatDriveECC_DiagnosticStateOptions(struct(),20);
    assert(strcmp(defaults.mode,'off') && defaults.command_horizon_cycles==20,'Default policy changed.');
    preflight=Resolve_HeatDriveECC_DiagnosticStateOptions( ...
        struct('mode','restore_preflight','command_horizon_cycles',200),2);
    assert(preflight.command_horizon_cycles==200,'Fixed command horizon lost.');
    bad={struct('mode','capture'),struct('mode','off','command_horizon_cycles',200), ...
        struct('mode','restore_preflight'),struct('unknown',1)};
    counts=[1,20,20,20];
    for k=1:numel(bad)
        rejected=false;
        try,Resolve_HeatDriveECC_DiagnosticStateOptions(bad{k},counts(k));
        catch,rejected=true;end
        assert(rejected,'Invalid diagnostic state policy accepted.');
    end
    record=struct('default_off_pass',true,'fixed_horizon_pass',true,'rejected_invalid_cases',4);
    fprintf('%s\n',jsonencode(record));
end
