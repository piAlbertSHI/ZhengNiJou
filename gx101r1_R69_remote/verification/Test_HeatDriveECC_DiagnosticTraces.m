function Test_HeatDriveECC_DiagnosticTraces()
    row = struct('block_path', 'model/state', 'state_name', 'x', 'unit', 'K', ...
        'time_s', (0:6)' * .001, 'values', [(0:6)' 300 + (0:6)']);
    part = row; part.time_s = row.time_s(1:4); part.values = row.values(1:4, :);
    audit = Compare_HeatDriveECC_DiagnosticTraces({row}, {part});
    assert(audit.pass && audit.bitwise_values_equal && audit.channel_count == 2);
    part.values(end, 1) = part.values(end, 1) + 1e-5;
    audit = Compare_HeatDriveECC_DiagnosticTraces({row}, {part});
    assert(~audit.pass, 'Terminal differences must not be hidden.');
    part.values = row.values(1:4, :); part.time_s(2) = .0011;
    expect_failure(@() Compare_HeatDriveECC_DiagnosticTraces({row}, {part}));
    part.time_s = row.time_s(1:4); part.values(1, 1) = NaN;
    expect_failure(@() Compare_HeatDriveECC_DiagnosticTraces({row}, {part}));
    part.values = row.values(1:4, :); part.state_name = 'other';
    expect_failure(@() Compare_HeatDriveECC_DiagnosticTraces({row}, {part}));
    part.state_name = row.state_name; part.unit = 'Pa';
    expect_failure(@() Compare_HeatDriveECC_DiagnosticTraces({row}, {part}));
    part.unit = 'K'; part.values(1, 1) = -0.0;
    audit = Compare_HeatDriveECC_DiagnosticTraces({row}, {part});
    assert(audit.pass && ~audit.bitwise_values_equal, 'Signed zero differs bitwise, not numerically.');
    fprintf('DIAGNOSTIC_TRACE_COMPARISON_TEST_PASS=1 CASES=7\n');
end

function expect_failure(action)
    failed = false;
    try
        action();
    catch
        failed = true;
    end
    assert(failed, 'Expected invalid trace evidence to be rejected.');
end
