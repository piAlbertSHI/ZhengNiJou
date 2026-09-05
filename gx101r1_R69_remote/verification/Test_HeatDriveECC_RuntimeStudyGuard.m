function Test_HeatDriveECC_RuntimeStudyGuard()
% A same-parameter audit checkpoint must not seed a Table 4 candidate.
    settings = struct('run_candidates', false, 'output_root', tempname, ...
        'authority_settings', struct('contract_path', fullfile( ...
        fileparts(mfilename('fullpath')), 'runtime_c180_recovery_contract.json')));
    rejected = false;
    try
        Run_HeatDriveECC_Table4_OuterSolve(settings);
    catch e
        rejected = strcmp(e.identifier, ...
            'HeatDriveECC:SteadyParameterStudyNotAuthorized');
    end
    assert(rejected, 'C180 must remain excluded from parameter/root studies.');
    assert(~isfolder(settings.output_root), 'Rejected study created an output directory.');
    fprintf('RUNTIME_STUDY_GUARD_PASS=1\n');
end
