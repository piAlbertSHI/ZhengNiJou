function validation = Validate_HeatDriveECC_FifthRound_3Cycle(options)
% Strict fifth-round 3-cycle validation; errors on failed hard checks.

    if nargin < 1
        options = struct();
    end
    options.cycle_count = 3;
    options = Build_HeatDriveECC_FifthRound_Defaults(options);
    structure = Validate_HeatDriveECC_FifthRound_Structure();
    options.force_rebuild_model = false;
    result = Run_HeatDriveECC_FifthRound_Cycles(options);
    s = result.stage_energy_table;
    c = result.cycle_energy_table;
    checks = {
        'copied_mature_structure', structure.ok;
        'exact_three_cycles', height(c)==3;
        'eq6_strict', max(s.max_eq6_scaled)<options.validation.max_eq6_scaled;
        'eq7_strict', max(s.max_eq7_scaled)<options.validation.max_eq7_scaled;
        'stage_energy_closure', max([s.sma_relative_residual;s.se_relative_residual])<options.validation.max_stage_energy_residual_fraction;
        'cycle3_energy_closure', c.relative_residual(end)<options.validation.max_cycle_energy_residual_fraction;
        'dynamic_probe_temperatures', max(abs(s.Ta_end_K-s.Ta_start_K))+max(abs(s.Tr_end_K-s.Tr_start_K))>options.validation.minimum_probe_delta_K;
        'dynamic_Qr_not_article_copy', abs(c.Qr_dynamic_W(end)-options.system.article_Qr_W)>1e-9};
    validation=struct('passed',all(cell2mat(checks(:,2))),'checks',{checks}, ...
        'structure',structure,'result',result);
    save(fullfile(options.outputs_dir,'fifth_round_validation.mat'),'validation','-v7.3');
    if ~validation.passed
        failed=checks(~cell2mat(checks(:,2)),1);
        error('Validate_HeatDriveECC_FifthRound_3Cycle:Failed', ...
            'Fifth-round hard checks failed: %s',strjoin(failed,', '));
    end
end
