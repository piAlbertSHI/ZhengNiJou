function result=Test_HeatDriveECC_RuntimeSensitivityMapping(qualification,python,parent)
% Pure parameter/design/request tests; no model load, simulation or OP import.
    q=jsondecode(fileread(qualification));saved=load(fullfile(q.source_packet_root,'native','configuration.mat'),'plant_build_options');
    baseline=saved.plant_build_options;matrix=zeros(8,6);
    for index=0:8
        request=struct('case_index',index,'candidate_qualification_path',qualification);
        [actual,contract]=Apply_HeatDriveECC_RuntimeSensitivity(baseline,request);
        row=Build_HeatDriveECC_L8Case(index);if index>0,matrix(index,:)=row.levels;end
        restored=actual;assert(numel(contract.parameters)==27);
        for k=1:numel(contract.parameters)
            r=contract.parameters{k};parts=strsplit(r.field,'.');
            if numel(parts)==2,restored.(parts{1}).(parts{2})=r.before;
            else,restored.(parts{1}).(parts{2}).(parts{3})=r.before;end
            assert(isfinite(r.after) && r.after>=0);
        end
        restored.validation=baseline.validation;restored.simulation=baseline.simulation;assert(isequaln(restored,baseline));
        built=Build_HeatDriveECC_EighthRound_Defaults(actual);
        for name={'SMA','SE'}
            material=built.material.(name{1});
            assert(abs(material.Delta_h_J_per_kg/material.Delta_s0_J_per_kgK-material.transformation_reference_T_K)<1e-10);
            assert(material.C_A_Pa_per_K==baseline.material.(name{1}).C_A_Pa_per_K && ...
                material.C_M_Pa_per_K==baseline.material.(name{1}).C_M_Pa_per_K);
        end
        assert(~contract.factor_scope.inactive_eta_hr_metadata_varied && ...
            ~contract.factor_scope.active_SE_mass_and_geometry_changed);
        assert(built.branch.m_dot_sma_shex_kg_per_s==baseline.branch.m_dot_sma_shex_kg_per_s && ...
            built.branch.m_dot_sma_the_kg_per_s==baseline.branch.m_dot_sma_the_kg_per_s);
        assert(isequal(sort(string(built.simulation.checkpoint_transition_fields)), ...
            sort(string(built.validation.sensitivity_declared_transition_fields))));
        for k=1:numel(contract.parameters)
            r=contract.parameters{k};parts=strsplit(r.field,'.');v=built;
            for j=1:numel(parts),v=v.(parts{j});end
            assert(isequaln(v,r.after));
        end
        keys=fieldnames(baseline.validation);
        for k=1:numel(keys)
            name=keys{k};v=baseline.validation.(name);
            if isnumeric(v),assert(isequaln(v,actual.validation.(name)));end
        end
        assert(isequaln(actual.fluid,baseline.fluid) && isequaln(actual.geometry,baseline.geometry) && ...
            actual.constitutive.diagnostic_substeps==baseline.constitutive.diagnostic_substeps && ...
            actual.branch.se_stage2_pressure_pi_kp_MPa_per_kgps==baseline.branch.se_stage2_pressure_pi_kp_MPa_per_kgps && ...
            actual.branch.se_stage4_pressure_pi_kp_MPa_per_kgps==baseline.branch.se_stage4_pressure_pi_kp_MPa_per_kgps);
        [legacy,control,fields]=Build_HeatDriveECC_SensitivityOverrides(row,baseline,struct('test_controller',-255),201);
        assert(control.test_controller==-255 && legacy.validation.mechanism_gate_start_cycle==201 && numel(fields)==27);
    end
    assert(isequal(matrix'*matrix,8*eye(6)) && all(sum(matrix)==0));
    state=struct('mode','capture','command_horizon_cycles',200);
    request=struct('mode','runtime_sensitivity_cold','python_executable',python,'source_contract_path',parent, ...
        'candidate_qualification_path',qualification,'case_index',1,'probe_only',true);
    assert(isequaln(Resolve_HeatDriveECC_ObservationPreflight(request,state,20,200,'native',true,struct()),request));
    rejected=0;
    for value={-1,9,1.5,'1'}
        bad=request;bad.case_index=value{1};
        try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    end
    bad=request;bad.resume_checkpoint_path='old.mat';
    try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    bad=request;bad.probe_only=1;
    try,Resolve_HeatDriveECC_ObservationPreflight(bad,state,20,200,'native',true,struct());catch,rejected=rejected+1;end
    assert(rejected==6);
    result=struct('cases_checked',9,'declared_fields_per_case',27,'rejected_requests',rejected, ...
        'design_orthogonal',true,'all_original_numeric_validation_values_unchanged',true, ...
        'model_loaded',false,'simulation_executed',false,'OP_loaded',false);
    fprintf('SENSITIVITY_MAPPING_TEST_JSON=%s\n',jsonencode(result));
end
