function result = Run_HeatDriveECC_StageClosure(overrides)
% Run one sequential four-stage closure and return the per-stage audit table.

    if nargin < 1
        overrides = struct();
    end
    overrides.cycle_count = 1;
    cycle_result = Run_HeatDriveECC_SeventhRound_Cycles(overrides);
    result = struct();
    result.schema_version = 'heatdrive_ecc_stage_closure_v1';
    result.output_dir = cycle_result.output_dir;
    result.stage_summaries = cycle_result.stage_summaries;
    result.checks = cycle_result.checks;
    result.passed = cycle_result.passed;
    result.source_cycle_result_mat = fullfile(cycle_result.output_dir, ...
        'seventh_round_cycle_result.mat');
    save(fullfile(cycle_result.output_dir, 'seventh_round_stage_closure_result.mat'), ...
        'result', '-v7.3');
end
