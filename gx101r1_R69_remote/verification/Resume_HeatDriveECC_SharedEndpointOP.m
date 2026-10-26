function record=Resume_HeatDriveECC_SharedEndpointOP(repo,source,folder)
% New-process strict load of a persisted isolated model and its untouched full OP.
    assert(~isfolder(folder));mkdir(folder);old=pwd;oldpath=path;
    cleanup_path=onCleanup(@() restore_path(old,oldpath));addpath(repo,fullfile(repo,'verification'));
    record=struct('schema','heatdrive_ecc_shared_endpoint_new_process_OP_v1', ...
        'execution_complete',false,'production_recovery_allowed',false,'source_OP_edited',false);
    try
        prior=jsondecode(fileread(fullfile(source,'state_interface_roundtrip.json')));
        assert(prior.execution_complete && ~prior.production_recovery_allowed && prior.fixed_command_horizon_s==1000);
        verify(prior.saved_runtime_model_path,prior.saved_runtime_model_sha256);
        verify(prior.base_workspace.path,prior.base_workspace.sha256);
        verify(prior.operating_point_path,prior.operating_point_sha256);
        verify(prior.interface_contract_path,prior.interface_contract_sha256);
        for k=1:numel(prior.loaded_project_sources)
            p=prior.loaded_project_sources(k);verify(p.path,p.sha256);
        end
        build=fullfile(source,'endpoint_component_build');addpath(build);
        construction=jsondecode(fileread(fullfile(source,'endpoint_inventory_construction.json')));
        for k=1:numel(construction.source_components)
            c=construction.source_components(k);verify(c.path,c.sha256);verify(c.library_path,c.library_sha256);
            load_system(c.library_path);
        end
        library_cleanup=onCleanup(@() close_libraries());
        saved=load(prior.base_workspace.path);names=fieldnames(saved);
        for k=1:numel(names),assignin('base',names{k},saved.(names{k}));end;clear saved
        [~,model]=fileparts(prior.saved_runtime_model_path);assert(~bdIsLoaded(model));
        load_system(prior.saved_runtime_model_path);model_cleanup=onCleanup(@() close_system(model,0));
        assert(strcmp(get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error') && ...
            strcmp(get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error'));
        config=load(prior.interface_contract_path,'contract','options');
        point=load(prior.operating_point_path,'diagnostic_operating_point','production_recovery_allowed');
        assert(~point.production_recovery_allowed && point.diagnostic_operating_point.snapshotTime==prior.snapshot_s);
        original=point.diagnostic_operating_point.loggedStates;
        generation=Simulink.fileGenControl('getConfig');
        cleanup_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
        Simulink.fileGenControl('set','CacheFolder',fullfile(folder,'cache'), ...
            'CodeGenFolder',fullfile(folder,'codegen'),'createDir',true);
        cd(fileparts(prior.saved_runtime_model_path));
        HeatDriveECC_ObserverContext('register',model,fullfile(folder,'solver_time.json'));
        input=Simulink.SimulationInput(model);
        output=sim(input.setModelParameter('CaptureErrors','on','StopTime',num2str(prior.reference_stop_s,17)) ...
            .setInitialState(point.diagnostic_operating_point));
        assert(isempty(output.ErrorMessage),'Strict new-process restore failed: %s',output.ErrorMessage);
        file=fullfile(folder,'new_process_restored_observations.mat');
        record.observation=Capture_HeatDriveECC_StateInterfaceTrace(output,model,config.contract,file);
        record.observation_path=file;record.observation_sha256=file_hash(file);
        assert(isequaln(original,point.diagnostic_operating_point.loggedStates));
        verify(prior.operating_point_path,prior.operating_point_sha256);
        verify(prior.saved_runtime_model_path,prior.saved_runtime_model_sha256);
        record.source_root=source;record.source_OP_sha256=prior.operating_point_sha256;
        record.actual_tout_first_s=double(output.tout(1));record.actual_tout_last_s=double(output.tout(end));
        record.checksum_policy='error/error';record.execution_complete=true;
        record.complete_cycle_numerical_equivalence_evaluated=false;record.state_projection_or_reset_used=false;
        record.reader_source_sha256=file_hash([mfilename('fullpath') '.m']);
        HeatDriveECC_ObserverContext('clear',model);
    catch e
        record.error_identifier=e.identifier;record.error_report=getReport(e,'extended','hyperlinks','off');
        write_json(fullfile(folder,'FAILED_DO_NOT_RESUME.json'),record);rethrow(e);
    end
    write_json(fullfile(folder,'new_process_restore.json'),record);
    disp(jsonencode(struct('execution_complete',true,'production_recovery_allowed',false,'folder',folder)));
end

function verify(p,h)
    assert(strcmp(file_hash(p),h),'Source dependency changed: %s',p);
end
function h=file_hash(p)
    f=fopen(p,'rb');assert(f>=0);c=onCleanup(@() fclose(f));d=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(f),d.update(fread(f,1048576,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
function write_json(p,r)
    assert(~isfile(p));f=fopen(p,'w','n','UTF-8');assert(f>=0);c=onCleanup(@() fclose(f));fprintf(f,'%s',jsonencode(r,'PrettyPrint',true));
end
function restore_path(old,oldpath)
    cd(old);path(oldpath);
end
function close_libraries()
    for name={'ecc_inventory_endpoint_lib','ecc_buffer_coupled_offset_lib'}
        if bdIsLoaded(name{1}),close_system(name{1},0);end
    end
end
