function [overrides,contract]=Apply_HeatDriveECC_RuntimeSensitivity(overrides,request)
% This changes a new cold constructor, never an existing complete Operating Point.
    row=Build_HeatDriveECC_L8Case(request.case_index);baseline=overrides;
    [model,branch,fields]=Build_HeatDriveECC_SensitivityOverrides(row,baseline,baseline.branch,1);
    overrides.branch=branch;
    overrides.simulation.checkpoint_transition_fields=fields;
    for group={'system','validation'}
        name=group{1};keys=fieldnames(model.(name));
        for k=1:numel(keys),overrides.(name).(keys{k})=model.(name).(keys{k});end
    end
    for name={'SMA','SE'}
        keys=fieldnames(model.material.(name{1}));
        for k=1:numel(keys),overrides.material.(name{1}).(keys{k})=model.material.(name{1}).(keys{k});end
    end
    rows=cell(size(fields));
    for k=1:numel(fields)
        parts=strsplit(fields{k},'.');a=baseline;b=overrides;
        for j=1:numel(parts),a=a.(parts{j});b=b.(parts{j});end
        rows{k}=struct('field',fields{k},'before',a,'after',b);
    end
    contract=struct('schema','heatdrive_ecc_runtime_sensitivity_cold_case_v1','design',row, ...
        'parameters',{rows},'fixed_Tc_K',276.95,'source_state_imported',false, ...
        'source_qualification_path',request.candidate_qualification_path, ...
        'source_role','stored constructor parameters only, never its OP', ...
        'C200_gap_attribution_authorized',false,'orthogonal_effects_evaluated',false, ...
        'production_recovery_allowed',false,'original_scientific_thresholds_changed',false);
    contract.factor_scope=struct( ...
        'UA','Joint forced, natural and boundary conductances in the declared 15-field mapping', ...
        'flow_utilization','SE nominal flow field and two active SE route targets; SMA route targets fixed; not a direct ideal heat-recovery efficiency', ...
        'latent_heat','Paired Delta_h and Delta_s0 at fixed reference temperature, calibrated transformation surfaces and kinetics; reduced-model sensitivity only', ...
        'inactive_eta_hr_metadata_varied',false,'active_SE_mass_and_geometry_changed',false);
end
