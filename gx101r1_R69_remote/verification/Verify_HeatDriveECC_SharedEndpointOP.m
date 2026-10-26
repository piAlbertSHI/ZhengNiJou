function record=Verify_HeatDriveECC_SharedEndpointOP(repo,input,options,contract,folder)
% Untouched complete OP roundtrip on the actual shared endpoint model.
    model=input.ModelName;snapshot=.2;stop=10.202;
    assert(options.cycle_count==100 && options.schedule.total_time_s==1000 && ...
        strcmp(contract.schema,'heatdrive_ecc_endpoint_CV_inventory_v1'));
    assert(options.simscape.local_solver_enabled && options.simscape.local_solver_sample_time_s==.001);
    record=struct('schema','heatdrive_ecc_shared_endpoint_OP_execution_v1', ...
        'snapshot_s',snapshot,'reference_stop_s',stop,'fixed_command_horizon_s',1000, ...
        'execution_complete',false,'production_recovery_allowed',false,'source_OP_edited',false, ...
        'partial_state_or_private_coordinate_reconstruction',false,'cases',{{}});
    model_file=get_param(model,'FileName');
    root=char(java.io.File(folder).getCanonicalPath());actual=char(java.io.File(model_file).getCanonicalPath());
    assert(startsWith(lower(actual),[lower(root) filesep]),'Only persist this isolated experiment model.');
    set_param(model,'SaveState','on','StateSaveName','interface_state_history','SaveFormat','Dataset', ...
        'LimitDataPoints','on','MaxDataPoints','12002','Decimation','1', ...
        'SaveFinalState','on','FinalStateName','interface_final_op','SaveOperatingPoint','on', ...
        'OperatingPointContentsChecksumMismatchMsg','error','OperatingPointInterfaceChecksumMismatchMsg','error');
    save_system(model,model_file);
    record.saved_runtime_model_path=model_file;record.saved_runtime_model_sha256=file_hash(model_file);
    names=evalin('base','who');base_state=struct();descriptors=cell(size(names));
    for k=1:numel(names)
        v=evalin('base',names{k});
        assert(~isa(v,'Simulink.op.ModelOperatingPoint') && ~isa(v,'Simulink.SimulationOutput'), ...
            'Do not archive another state or large simulation output from the base workspace.');
        base_state.(names{k})=v;
        descriptors{k}=struct('name',names{k},'class',class(v),'size',size(v));
    end
    base_file=fullfile(folder,'fixed_runtime_base_workspace.mat');assert(~isfile(base_file));
    save(base_file,'-struct','base_state','-v7.3');clear base_state
    record.base_workspace=struct('path',base_file,'sha256',file_hash(base_file),'variables',{descriptors});
    cv_file=fullfile(folder,'state_interface_contract.mat');save(cv_file,'contract','options','-v7');
    record.interface_contract_path=cv_file;record.interface_contract_sha256=file_hash(cv_file);
    input=input.setModelParameter('CaptureErrors','on');
    reference=sim(input.setModelParameter('StopTime',num2str(stop,17)));
    assert(isempty(reference.ErrorMessage),'Continuous reference failed: %s',reference.ErrorMessage);
    reference_file=fullfile(folder,'continuous_reference_observations.mat');
    record.cases{end+1}=Capture_HeatDriveECC_StateInterfaceTrace(reference,model,contract,reference_file);
    record.reference_file=reference_file;record.reference_sha256=file_hash(reference_file);clear reference
    HeatDriveECC_ObserverContext('register',model,fullfile(folder,'prefix_solver_time.json'));
    prefix=sim(input.setModelParameter('StopTime',num2str(snapshot,17)));
    assert(isempty(prefix.ErrorMessage),'Prefix failed: %s',prefix.ErrorMessage);
    diagnostic_operating_point=prefix.interface_final_op;
    assert(isa(diagnostic_operating_point,'Simulink.op.ModelOperatingPoint') && diagnostic_operating_point.snapshotTime==snapshot);
    record.source_public_state_groups=diagnostic_operating_point.loggedStates.numElements;
    production_recovery_allowed=false; %#ok<NASGU>
    op_file=fullfile(folder,'diagnostic_complete_operating_point.mat');assert(~isfile(op_file));
    save(op_file,'diagnostic_operating_point','production_recovery_allowed','-v7.3');
    record.operating_point_path=op_file;record.operating_point_sha256=file_hash(op_file);clear prefix diagnostic_operating_point
    loaded=load(op_file,'diagnostic_operating_point','production_recovery_allowed');
    assert(~loaded.production_recovery_allowed && loaded.diagnostic_operating_point.snapshotTime==snapshot);
    before=loaded.diagnostic_operating_point.loggedStates;
    HeatDriveECC_ObserverContext('register',model,fullfile(folder,'restored_solver_time.json'));
    restored=sim(input.setModelParameter('StopTime',num2str(stop,17)).setInitialState(loaded.diagnostic_operating_point));
    assert(isempty(restored.ErrorMessage),'Strict roundtrip restore failed: %s',restored.ErrorMessage);
    restored_file=fullfile(folder,'same_model_restored_observations.mat');
    record.cases{end+1}=Capture_HeatDriveECC_StateInterfaceTrace(restored,model,contract,restored_file);
    record.restored_file=restored_file;record.restored_sha256=file_hash(restored_file);clear restored
    assert(isequaln(before,loaded.diagnostic_operating_point.loggedStates) && strcmp(file_hash(op_file),record.operating_point_sha256));
    record.strict_checksum_policy='error/error';record.execution_complete=true;
    record.same_model_numerical_equivalence_evaluated=false;record.new_process_restore_verified=false;
    files=inmem('-completenames');root=char(java.io.File(repo).getCanonicalPath());record.loaded_project_sources={};
    for k=1:numel(files)
        p=files{k};
        if startsWith(lower(p),[lower(root) filesep]) && endsWith(p,'.m') && isfile(p)
            record.loaded_project_sources{end+1}=struct('path',p,'sha256',file_hash(p)); %#ok<AGROW>
        end
    end
    write_json(fullfile(folder,'state_interface_roundtrip.json'),record);
end

function h=file_hash(p)
    f=fopen(p,'rb');assert(f>=0);c=onCleanup(@() fclose(f));d=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(f),d.update(fread(f,1048576,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end

function write_json(p,r)
    assert(~isfile(p));f=fopen(p,'w','n','UTF-8');assert(f>=0);c=onCleanup(@() fclose(f));fprintf(f,'%s',jsonencode(r,'PrettyPrint',true));
end
