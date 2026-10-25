function proof=Verify_HeatDriveECC_SavedSpecificManifold(source_root,output_root)
% Rebuild without sim/OP; bind the specific-inventory mask to its actual source.
    assert(~isfolder(output_root),'Never overwrite component evidence.');
    execution=jsondecode(fileread(fullfile(source_root,'cold_chamber_execution.json')));
    completion=jsondecode(fileread(fullfile(source_root,'conservative','arm_completion.json')));
    Resolve_HeatDriveECC_ColdAnalysisScope(execution,completion,'conservative',2);
    producer=execution.execution_commit;
    assert(~isempty(regexp(producer,'^[0-9a-f]{40}$','once')));
    repo=fileparts(fileparts(mfilename('fullpath')));workspace=fileparts(repo);
    protected={'Build_HeatDriveECC_EighthRound_Simulink_Model.m', ...
        'Integrate_HeatDriveECC_Constitutive21_Interface.m','Build_HeatDriveECC_EighthRound_Defaults.m', ...
        'verification/Configure_HeatDriveECC_DistributedPressureFeedforward.m'};
    for k=1:numel(protected)
        if strcmp(protected{k},'Build_HeatDriveECC_EighthRound_Simulink_Model.m')
            [status,historical]=system(sprintf('git -C "%s" show %s:gx101r1_R69_remote/%s', ...
                workspace,producer,protected{k}));assert(status==0);
            historical=strrep(historical,sprintf('\r\n'),sprintf('\n'));
            current=strrep(fileread(fullfile(repo,protected{k})),sprintf('\r\n'),sprintf('\n'));
            expected=strrep(historical,'    load_system(model_name);', ...
                '    Load_HeatDriveECC_ModelByPath(model_path,model_name);');
            assert(~strcmp(expected,historical) && strcmp(current,expected), ...
                'Only the exact absolute-path loader substitution is authorized.');
        else
            [status,~]=system(sprintf('git -C "%s" diff --quiet %s -- "gx101r1_R69_remote/%s"', ...
                workspace,producer,protected{k}));
            assert(status==0,'Physical/controller construction changed since producer.');
        end
    end
    folder=fullfile(source_root,'conservative');
    configuration_path=fullfile(folder,'configuration.mat');
    observation_path=fullfile(folder,'observations.mat');
    saved=load(configuration_path,'options');original=saved.options;
    assert(~original.simulation.persist_model_configuration && isempty(original.simulation.resume_checkpoint_path) && ...
        original.branch.independent_conservative_chamber_diagnostic && ...
        strcmp(original.branch.independent_conservative_chamber_library,'ecc_inventory_specific_lib'));
    model_workspace=fileparts(fileparts(original.model_path));
    [status,~]=system(sprintf('git -C "%s" diff --quiet %s -- "gx101r1_R69_remote/heatdrive_ecc_coupled_se21.slx"', ...
        model_workspace,producer));
    assert(status==0,'The actual source model path is not the frozen producer model.');
    metadata=jsondecode(fileread(fullfile(folder,'inventory_metadata.json')));
    topology=jsondecode(fileread(fullfile(folder,'tl_connectivity.json')));
    library=fullfile(source_root,'component_build','ecc_inventory_specific_lib.slx');
    assert(strcmp(file_hash(library),execution.chamber_library_sha256));
    mkdir(output_root);
    generated=Simulink.fileGenControl('getConfig');
    restore_generated=onCleanup(@() Simulink.fileGenControl('setConfig','config',generated));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'cache'), ...
        'CodeGenFolder',fullfile(output_root,'codegen'),'createDir',true);
    oldpath=path;restore_path=onCleanup(@() path(oldpath));
    addpath(fullfile(source_root,'component_build'));
    load_system(library);close_library=onCleanup(@() close_system('ecc_inventory_specific_lib',0));
    [model,refreshed]=Build_HeatDriveECC_EighthRound_Simulink_Model(original);
    close_model=onCleanup(@() close_system(model,0));
    loaded_model=get_param(model,'FileName');
    assert(same_path(loaded_model,original.model_path), ...
        'Actual loaded model differs from the frozen producer path.');
    assert(same_path(which('Audit_HeatDriveECC_ManifoldMask'), ...
        fullfile(repo,'Audit_HeatDriveECC_ManifoldMask.m')), ...
        'A same-name worktree auditor shadows the reviewed auditor.');
    for field={'geometry','material','equilibrium','branch','system','constitutive','schedule','simscape'}
        assert(isequaln(original.(field{1}),refreshed.(field{1})), ...
            'Protected physical/numerical configuration changed: %s',field{1});
    end
    old=original.validation.article_component_pipe_UA_audit;
    corrected=refreshed.validation.article_component_pipe_UA_audit;
    assert(~old.SMA_pump_manifolds.mask_expressions_ok && ...
        ~old.SMA_pump_manifolds.ok && ~old.pressure.ok && ~old.ok, ...
        'This certificate applies only to the historical specific-source mask omission.');
    expected=old;expected.SMA_pump_manifolds.mask_expressions_ok=true;
    expected.SMA_pump_manifolds.ok=true;expected.pressure.ok=true;expected.ok=true;
    assert(isequaln(expected,corrected), ...
        'UA, pressure, valve or other component audit changed beyond the four derived flags.');
    old_validation=original.validation;new_validation=refreshed.validation;
    for field={'article_component_pipe_UA_audit','article_component_pipe_UA_implemented'}
        old_validation=rmfield(old_validation,field{1});new_validation=rmfield(new_validation,field{1});
    end
    names=union(fieldnames(old_validation),fieldnames(new_validation));delta={};
    for k=1:numel(names)
        name=names{k};
        if ~isfield(old_validation,name) || ~isfield(new_validation,name) || ...
                ~isequaln(old_validation.(name),new_validation.(name))
            row=struct('field',name,'before_present',isfield(old_validation,name), ...
                'after_present',isfield(new_validation,name));
            if row.before_present,row.before=old_validation.(name);end
            if row.after_present,row.after=new_validation.(name);end
            delta{end+1}=row; %#ok<AGROW>
        end
    end
    save(fullfile(output_root,'rebuild_metadata.mat'),'original','refreshed','-v7.3');
    fid=fopen(fullfile(output_root,'validation_rebuild_delta.json'),'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(struct('differences',{delta}, ...
        'simulation_executed',false,'production_recovery_allowed',false),'PrettyPrint',true));fclose(fid);
    [validation_equivalent,rebuild_equivalence]=Compare_HeatDriveECC_RebuiltValidation( ...
        old_validation,new_validation,original.branch);
    assert(validation_equivalent,'A scientific predicate or threshold changed.');
    contracts=cell(2,1);
    names={'SMA_PumpInletConnectingPipeVolume','SMA_PumpOutletConnectingPipeVolume'};
    for k=1:2
        block=[model '/' names{k}];
        [pass,contracts{k}]=Audit_HeatDriveECC_ManifoldMask(block,refreshed);assert(pass);
        actual=metadata.storage_blocks(strcmp({metadata.storage_blocks.block_path},block));
        declared=topology.blocks(strcmp({topology.blocks.block_path},block));
        assert(isscalar(actual) && isscalar(declared) && ...
            strcmp(declared.source_file,'ecc_inventory_specific.conservative_chamber'));
        for field={'volume','area'}
            p=actual.mask_parameters.(field{1});
            assert(strcmp(get_param(block,field{1}),p.expression) && ...
                strcmp(get_param(block,[field{1} '_unit']),p.unit) && ...
                isequaln(slResolve(get_param(block,field{1}),block),p.value), ...
                'Observed geometry differs from the rebuilt mask.');
        end
    end
    block=[model '/' names{1}];
    set_param(block,'area','1');assert(~Audit_HeatDriveECC_ManifoldMask(block,refreshed));
    set_param(block,'area','sma_connecting_pipe_flow_area_m2');
    bad=refreshed;bad.branch.independent_conservative_chamber_library='unknown_lib';
    assert(~Audit_HeatDriveECC_ManifoldMask(block,bad));
    bad=refreshed;bad.branch.independent_conservative_chamber_library='ecc_inventory_endpoint_lib';
    assert(~Audit_HeatDriveECC_ManifoldMask(block,bad));
    proof=struct('schema','heatdrive_ecc_saved_specific_inventory_mask_v1', ...
        'source_root',source_root,'source_producer',producer, ...
        'source_configuration_sha256',file_hash(configuration_path), ...
        'source_observation_sha256',file_hash(observation_path), ...
        'source_metadata_sha256',file_hash(fullfile(folder,'inventory_metadata.json')), ...
        'source_topology_sha256',file_hash(fullfile(folder,'tl_connectivity.json')), ...
        'source_library_sha256',file_hash(library), ...
        'source_model_sha256',file_hash(original.model_path), ...
        'loaded_model_path',loaded_model,'loaded_model_matches_requested',true, ...
        'absolute_model_loader_sha256',file_hash(which('Load_HeatDriveECC_ModelByPath')), ...
        'builder_sha256',file_hash(which('Build_HeatDriveECC_EighthRound_Simulink_Model')), ...
        'validation_rebuild_equivalence',rebuild_equivalence, ...
        'verifier_sha256',file_hash(which(mfilename)), ...
        'manifold_auditor_sha256',file_hash(which('Audit_HeatDriveECC_ManifoldMask')), ...
        'component_contracts',{contracts},'original_article_audit',old, ...
        'corrected_article_audit',corrected,'exact_specific_source_and_geometry_pass',true, ...
        'only_component_audit_metadata_changed',true,'negative_component_cases_rejected',3, ...
        'runtime_initial_targets_not_loaded_by_this_proof',true, ...
        'simulation_executed',false,'operating_point_loaded',false, ...
        'production_recovery_allowed',false);
    fid=fopen(fullfile(output_root,'specific_inventory_mask_proof.json'),'w','n','UTF-8');
    assert(fid>=0);c=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(proof,'PrettyPrint',true));clear c
    fprintf('COMPONENT_PROOF_JSON=%s\n',jsonencode(struct( ...
        'specific_source_bound',true,'negative_cases_rejected',3,'simulation_executed',false)));
end

function yes=same_path(a,b)
    yes=strcmpi(char(java.io.File(a).getCanonicalPath()), ...
        char(java.io.File(b).getCanonicalPath()));
end

function hash=file_hash(path)
    md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);
    c=onCleanup(@() fclose(fid));while ~feof(fid),md.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
