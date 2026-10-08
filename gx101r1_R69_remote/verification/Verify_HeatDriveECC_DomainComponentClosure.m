function record = Verify_HeatDriveECC_DomainComponentClosure(source_root, output_root)
% Actual model preflight for a NEW diagnostic, not a correction of old physics.
    assert(~isfolder(output_root),'Never overwrite domain/component evidence.');
    execution=jsondecode(fileread(fullfile(source_root,'cold_chamber_execution.json')));
    stored=load(fullfile(source_root,'native','configuration.mat'),'options');
    original=stored.options;
    assert(~original.simulation.persist_model_configuration && ...
        original.branch.independent_conservative_chamber_diagnostic && ...
        strcmp(original.branch.independent_conservative_chamber_library,'ecc_inventory_endpoint_lib'));
    old_path=path; cleanup_path=onCleanup(@() path(old_path));
    addpath(fullfile(source_root,'component_build'),fullfile(source_root,'buffer_component_build'));
    library_file=fullfile(source_root,'component_build','ecc_inventory_endpoint_lib.slx');
    assert(strcmp(file_hash(library_file),execution.chamber_library_sha256));
    load_system(library_file); cleanup_library=onCleanup(@() close_system('ecc_inventory_endpoint_lib',0));
    Test_HeatDriveECC_PressureCommandInterval();
    [model,before]=Build_HeatDriveECC_EighthRound_Simulink_Model(original);
    cleanup_model=onCleanup(@() close_system(model,0));
    assert(before.validation.article_component_pipe_UA_audit.SMA_pump_manifolds.ok, ...
        'Exact conservative source/port/geometry contract was not verified.');
    assert(~before.validation.article_component_pipe_UA_audit.pressure.ok, ...
        'The unsafe historical pressure envelope must remain rejected.');
    clear cleanup_model
    requested=original;
    requested.branch.pressure_command_domain_closure_enabled=true;
    requested.branch.pressure_command_domain_margin_MPa=0.01;
    [model,after]=Build_HeatDriveECC_EighthRound_Simulink_Model(requested);
    cleanup_model=onCleanup(@() close_system(model,0));
    allowed={'pressure_command_domain_closure_enabled','pressure_command_domain_margin_MPa', ...
        'pressure_pi_min_MPa','pressure_pi_max_MPa','se_pressure_pi_min_MPa', ...
        'sma_pressure_pi_min_MPa','sma_pressure_integrator_min_MPa', ...
        'se_pressure_integrator_min_MPa','se_stage2_pressure_integrator_min_MPa', ...
        'se_stage4_pressure_integrator_min_MPa'};
    names=fieldnames(before);
    for k=1:numel(names)
        if ismember(names{k},{'branch','validation'}),continue;end
        assert(isequaln(before.(names{k}),after.(names{k})), ...
            'Protected model configuration changed: %s',names{k});
    end
    names=union(fieldnames(before.branch),fieldnames(after.branch));
    for k=1:numel(names)
        if ismember(names{k},allowed),continue;end
        assert(isequaln(before.branch.(names{k}),after.branch.(names{k})), ...
            'An undeclared controller/material/geometry option changed: %s',names{k});
    end
    assert(after.validation.article_component_pipe_UA_audit.ok && ...
        HeatDriveECC_SEPressureLowerBoundContract(after), ...
        'Actual rebuilt component/pressure contract failed.');
    route_before=Audit_HeatDriveECC_RouteMemoryContract(model);
    distributed=Configure_HeatDriveECC_DistributedPressureFeedforward(model,after);
    route_after=Audit_HeatDriveECC_RouteMemoryContract(model);
    assert(route_before.pass && isequaln(route_before,route_after));
    % Obtain actual chamber paths from source identity, not a display-name guess.
    chambers=find_system(model,'LookUnderMasks','all','FollowLinks','on', ...
        'SourceFile','ecc_inventory_endpoint.conservative_chamber');
    assert(numel(chambers)>=2,'Missing conservative chambers.');
    candidate=chambers(cellfun(@(b) strcmp(get_param(b,'volume'), ...
        'sma_pump_manifold_volume_m3'),chambers));
    assert(numel(candidate)==2,'Require both actual SMA manifolds.');
    chamber=candidate{1}; [pass,component]=Audit_HeatDriveECC_ManifoldMask(chamber,after);
    assert(pass);
    set_param(chamber,'area','1');
    assert(~Audit_HeatDriveECC_ManifoldMask(chamber,after),'Wrong geometry was accepted.');
    set_param(chamber,'area','sma_connecting_pipe_flow_area_m2');
    unsupported=after;unsupported.branch.independent_conservative_chamber_library='unknown_lib';
    assert(~Audit_HeatDriveECC_ManifoldMask(chamber,unsupported),'Unknown implementation was accepted.');
    [status,commit]=system('git rev-parse HEAD');assert(status==0);
    record=struct('schema','heatdrive_ecc_domain_component_preflight_v1', ...
        'source_root',source_root,'execution_commit',strtrim(commit), ...
        'source_configuration_sha256',file_hash(fullfile(source_root,'native','configuration.mat')), ...
        'source_chamber_library_sha256',execution.chamber_library_sha256, ...
        'historical_pressure_envelope_rejected',true, ...
        'component_contract',component,'pressure_domain',after.validation.pressure_command_domain_contract, ...
        'original_article_audit',before.validation.article_component_pipe_UA_audit, ...
        'bounded_article_audit',after.validation.article_component_pipe_UA_audit, ...
        'protected_configuration_unchanged',true,'negative_component_cases_rejected',true, ...
        'route_memory_contract',route_after,'distributed_formula',distributed.formula, ...
        'simulation_executed',false,'operating_point_loaded',false, ...
        'actual_trajectory_pressure_verified',false,'production_recovery_allowed',false);
    mkdir(output_root);save(fullfile(output_root,'bounded_configuration.mat'),'after','-v7.3');
    fid=fopen(fullfile(output_root,'domain_component_preflight.json'),'w','n','UTF-8');assert(fid>=0);
    cleanup_file=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(struct('static_component_pressure_pass',true, ...
        'se_minimum_command_MPa',after.branch.se_pressure_pi_min_MPa, ...
        'simulation_executed',false,'production_recovery_allowed',false)));
end

function hash=file_hash(file)
    fid=fopen(file,'rb');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    digest=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
