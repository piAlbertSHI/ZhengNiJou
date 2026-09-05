function record = Audit_HeatDriveECC_SavedResult(result_path)
% Complete scalar validation after interrupted plotting, without simulation.
    result_path = char(string(result_path));
    result = load(result_path, 'physical', 'options', 'summary', 'provenance');
    assert(all(isfield(result, {'physical','options','summary','provenance'})), ...
        'HeatDriveECC:IncompleteSavedResult', 'Saved result is incomplete.');
    result.output_dir = fileparts(result_path);
    result.output_mat = result_path;
    result.model_name = result.options.model_name;
    result.authority = result.provenance.authority;
    result.used_simulink_sim = result.physical.sim_call_count >= 1;
    result.legacy_surrogate_used_for_results = ...
        result.provenance.legacy_surrogate_used_for_results;
    result.checkpoint_path = fullfile(result.output_dir, 'final_operating_point.mat');
    audit = Validate_HeatDriveECC_EighthRound_Physics(result);
    record = struct('schema', 'heatdrive_ecc_saved_result_audit_v1', ...
        'result_path', result_path, 'simulation_executed', false, ...
        'continuation_state_modified', false, ...
        'mechanism_pass', audit.passed, 'checks', audit.checks, ...
        'diagnostics', audit.diagnostics, ...
        'performance', audit.result.summary.performance, ...
        'recovery_promotion_authorized', false);
    path = fullfile(result.output_dir, 'saved_result_audit.json');
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'HeatDriveECC:SavedAuditWriteFailed', 'Cannot write %s.', path);
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(record, 'PrettyPrint', true));
    fprintf('SAVED_RESULT_AUDIT mechanism=%d simulation_executed=0 path=%s\n', ...
        record.mechanism_pass, path);
end
