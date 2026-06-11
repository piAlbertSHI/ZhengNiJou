function result = Validate_HeatDriveECC_SeventhRound_3Cycle(overrides)
% Full seventh-round validation sequence through 3-cycle.

    if nargin < 1
        overrides = struct();
    end
    options = Build_HeatDriveECC_SeventhRound_Defaults(overrides);
    output_dir = fullfile(options.outputs_dir, 'validation_sequence');
    if ~isfolder(output_dir)
        mkdir(output_dir);
    end

    constitutive = Validate_HeatDriveECC_Constitutive_LoadUnload(overrides);
    branch = Run_HeatDriveECC_BranchUnit_Preflight(overrides);
    one_cycle = Run_HeatDriveECC_SeventhRound_Cycles(merge_structs(overrides, ...
        struct('cycle_count', 1)));
    three_cycle = Run_HeatDriveECC_SeventhRound_Cycles(merge_structs(overrides, ...
        struct('cycle_count', 3)));

    result = struct();
    result.schema_version = 'heatdrive_ecc_seventh_round_validation_sequence_v1';
    result.output_dir = output_dir;
    result.constitutive_passed = constitutive.passed;
    result.branch_preflight_passed = branch.passed;
    result.one_cycle_passed = one_cycle.passed;
    result.three_cycle_passed = three_cycle.passed;
    result.passed = result.constitutive_passed && result.branch_preflight_passed && ...
        result.one_cycle_passed && result.three_cycle_passed;
    result.constitutive_summary_json = constitutive.summary_json;
    result.branch_preflight_csv = branch.csv_path;
    result.one_cycle_summary_json = fullfile(one_cycle.output_dir, ...
        'seventh_round_cycle_summary.json');
    result.three_cycle_summary_json = fullfile(three_cycle.output_dir, ...
        'seventh_round_cycle_summary.json');
    result.three_cycle_output_dir = three_cycle.output_dir;
    result.three_cycle_checks = three_cycle.checks;
    result.three_cycle_cycle_summaries = three_cycle.cycle_summaries;

    write_json(fullfile(output_dir, 'seventh_round_validation_sequence_summary.json'), result);
    save(fullfile(output_dir, 'seventh_round_validation_sequence_result.mat'), ...
        'result', '-v7.3');
end

function out = merge_structs(out, overrides)
    names = fieldnames(overrides);
    for idx = 1:numel(names)
        key = names{idx};
        if isfield(out, key) && isstruct(out.(key)) && isstruct(overrides.(key))
            out.(key) = merge_structs(out.(key), overrides.(key));
        else
            out.(key) = overrides.(key);
        end
    end
end

function write_json(path_value, s)
    try
        text = jsonencode(s, 'PrettyPrint', true);
    catch
        text = jsonencode(s);
    end
    fid = fopen(path_value, 'w');
    cleanup = onCleanup(@() fclose(fid));
    fwrite(fid, text, 'char');
end
