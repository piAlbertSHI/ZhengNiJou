function record=Test_HeatDriveECC_ColdL8GeometryPermission(qualification,root)
% File-bound construction tests only; no model, simulation, or Operating Point load.
    assert(~isfolder(root));mkdir(root);q=jsondecode(fileread(qualification));
    cfg=fullfile(q.source_packet_root,'native','configuration.mat');saved=load(cfg,'plant_build_options');baseline=saved.plant_build_options;
    for index=1:8
        [actual,c]=Apply_HeatDriveECC_RuntimeSensitivity(baseline,struct('case_index',index,'candidate_qualification_path',qualification));
        c.source_qualification_sha256=file_hash(qualification);c.parameter_source_configuration_sha256=file_hash(cfg);
        path=fullfile(root,sprintf('case_%02d.json',index));write_json(path,c);
        actual.branch.independent_conservative_chamber_diagnostic=true;
        actual.branch.cold_L8_geometry_contract_path=path;actual.simulation.persist_model_configuration=false;
        actual.simulation.resume_checkpoint_path='';actual=Build_HeatDriveECC_EighthRound_Defaults(actual);
        [allowed,review]=Check_HeatDriveECC_ColdL8ManifoldGeometry(actual);
        assert(allowed && review.checked_declared_fields==27 && Check_HeatDriveECC_DiagnosticManifoldGeometry(actual),'%s',review.reason);
        if index==1,first=actual;contract=c;end
    end
    nominal=baseline.branch.connecting_pipe_flow_area_m2*baseline.branch.connecting_pipe_length_m;
    old=baseline;old.branch.sma_pump_manifold_volume_m3=nominal;
    assert(Check_HeatDriveECC_DiagnosticManifoldGeometry(old));
    old.branch.sma_pump_manifold_volume_m3=.1*nominal;old.branch.cold_manifold_inventory_volume_factor=.1;
    old.branch.independent_conservative_chamber_diagnostic=true;
    old.validation.sensitivity_mode=true;old.validation.sensitivity_declared_transition_fields={'branch.sma_pump_manifold_volume_m3'};
    old.simulation.persist_model_configuration=false;old.simulation.resume_checkpoint_path='';
    assert(Check_HeatDriveECC_DiagnosticManifoldGeometry(old));
    rejected=0;
    for k=1:6
        bad=first;
        if k==1,bad.branch=rmfield(bad.branch,'cold_L8_geometry_contract_path');
        elseif k==2,bad.branch.sma_pump_manifold_volume_m3=.8*nominal;
        elseif k==3,bad.simulation.persist_model_configuration=true;
        elseif k==4,bad.simulation.resume_checkpoint_path='old.mat';
        elseif k==5,bad.branch.independent_conservative_chamber_diagnostic=false;
        else,bad.validation.sensitivity_declared_transition_fields(1)=[];end
        assert(~Check_HeatDriveECC_ColdL8ManifoldGeometry(bad));rejected=rejected+1;
    end
    for k=1:5
        c=contract;
        if k==1,c.source_state_imported=true;
        elseif k==2,c.original_scientific_thresholds_changed=true;
        elseif k==3,c.design.run_index=2;
        elseif k==4,c.parameters{1}.after=c.parameters{1}.after+.001;
        else,c.parameter_source_configuration_sha256=repmat('0',1,64);end
        path=fullfile(root,sprintf('bad_contract_%02d.json',k));write_json(path,c);
        bad=first;bad.branch.cold_L8_geometry_contract_path=path;
        assert(~Check_HeatDriveECC_ColdL8ManifoldGeometry(bad));rejected=rejected+1;
    end
    workspace=fileparts(fileparts(fileparts(mfilename('fullpath'))));
    review=Review_HeatDriveECC_ConstructorSourceDelta(workspace,'cb32149b98ed401aef61ff310e3b6a2bb005f15c',fullfile(root,'legacy_source_delta_review.json'));
    assert(review.numerical_sources_unchanged && review.legacy_accepted_geometry_path_unchanged);
    record=struct('declared_cases_allowed',8,'legacy_cases_allowed',2,'malformed_requests_rejected',rejected, ...
        'model_loaded',false,'simulation_executed',false,'operating_point_loaded',false,'source_review',review);
    write_json(fullfile(root,'permission_test_result.json'),record);
    fprintf('L8_GEOMETRY_TEST_JSON=%s\n',jsonencode(record));
end
function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
function h=file_hash(path)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
