function record=Test_HeatDriveECC_PressureCommandInterval()
    safe=HeatDriveECC_PressureCommandInterval(.85,.45,5,.01,[-.5,.02]);
    assert(max(abs(safe-[-.39,.02]))<1e-12);
    assert(isequal(HeatDriveECC_PressureCommandInterval(1,.45,5,.01,[-.5,.02]),[-.5,.02]));
    assert(isequal(HeatDriveECC_PressureCommandInterval(.85,.45,5,.01,[-.35,.02]),[-.35,.02]));
    upper=HeatDriveECC_PressureCommandInterval(4.9,.45,5,.01,[-.5,.2]);
    assert(abs(upper(2)-.09)<1e-12);
    bad={{.46,.45,5,.01,[-.5,.02]}, {.85,.45,5,0,[-.5,.02]}, ...
        {.85,5,.45,.01,[-.5,.02]}, {.85,.45,5,.01,[.02,-.5]}, ...
        {NaN,.45,5,.01,[-.5,.02]}};
    for k=1:numel(bad)
        rejected=false;
        try,HeatDriveECC_PressureCommandInterval(bad{k}{:});catch,rejected=true;end
        assert(rejected,'Invalid domain admitted.');
    end
    record=struct('domain_interval_pass',true,'unchanged_safe_limit_pass',true, ...
        'upper_domain_bound_pass',true,'invalid_cases_rejected',numel(bad), ...
        'simulation_executed',false,'production_recovery_allowed',false);
    fprintf('%s\n',jsonencode(record));
end
