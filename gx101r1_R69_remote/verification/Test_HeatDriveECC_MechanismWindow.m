function Test_HeatDriveECC_MechanismWindow(tail_path, output_root)
% Exercise the unmodified mechanism gates with a bounded, historical C180 view.
    assert(~isfolder(output_root), 'Do not overwrite mechanism-window evidence.');
    stored = load(tail_path, 'physical', 'slice_metadata');
    source = load(stored.slice_metadata.source_result_path, 'options', 'provenance');
    before = stored.physical;
    mkdir(output_root);
    result = Make_HeatDriveECC_MechanismWindow(before, source.options, source.provenance, output_root);
    audit = Validate_HeatDriveECC_EighthRound_Physics(result);
    assert(audit.passed, 'HeatDriveECC:MechanismWindowRegression', 'Historical tail must pass its mechanism gates.');
    assert(isequaln(before, stored.physical), 'Input physical data were changed.');
    assert(result.options.cycle_count == 1 && result.analysis_window.global_last_cycle == 180);
    assert(~audit.result.summary.quantitative_literature_reproduction_pass);
    invalid = before; invalid.time_s(end) = [];
    expect_failure(@() Make_HeatDriveECC_MechanismWindow(invalid, source.options, source.provenance, output_root));
    invalid = before; invalid.time_s = invalid.time_s + .1;
    expect_failure(@() Make_HeatDriveECC_MechanismWindow(invalid, source.options, source.provenance, output_root));
    record = struct('schema', 'heatdrive_ecc_mechanism_window_test_v1', ...
        'mechanism_pass', audit.passed, 'checks', audit.checks, 'diagnostics', audit.diagnostics, ...
        'analysis_window', result.analysis_window, 'simulation_executed', false, ...
        'source_result_sha256', stored.slice_metadata.source_result_sha256);
    fid = fopen(fullfile(output_root, 'mechanism_window_test.json'), 'w', 'n', 'UTF-8');
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('MECHANISM_WINDOW_TEST_PASS=1 SIMULATION_EXECUTED=0\n');
end

function expect_failure(action)
    failed = false;
    try
        action();
    catch e
        assert(strcmp(e.identifier, 'HeatDriveECC:IncompleteMechanismWindow'));
        failed = true;
    end
    assert(failed, 'An incomplete mechanism window must be rejected.');
end
