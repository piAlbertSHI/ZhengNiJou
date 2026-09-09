function record=Inspect_HeatDriveECC_SMADerivativeContract(repo,output_root)
% Export the rebuilt controller contract without simulation or state import.
    assert(~isfolder(output_root),'Never overwrite controller evidence.');
    [code,dirty]=system('git status --porcelain');assert(code==0 && isempty(strtrim(dirty)),'Commit inspector first.');
    [code,commit]=system('git rev-parse HEAD');assert(code==0,'Cannot record producer.');
    source=fullfile(repo,'outputs_storage_audit','conservative_buffer_coupled_cycle_20260909');
    config_path=fullfile(source,'conservative','configuration.mat');
    prior=load(config_path,'options');prior.options.simulation.persist_model_configuration=false;
    canonical=prior.options.model_path;canonical_hash=file_hash(canonical);
    frozen=jsondecode(fileread(fullfile(repo,'verification','c200_mainline_freeze_contract.json')));
    for name={'result','checkpoint'}
        assert(strcmp(file_hash(fullfile(repo,frozen.([name{1} '_relative_path']))), ...
            frozen.([name{1} '_sha256'])),'C200 changed.');
    end
    oldpath=path;pc=onCleanup(@() path(oldpath));
    addpath(repo);addpath(fullfile(source,'component_build'));addpath(fullfile(source,'buffer_component_build'));
    load_system('ecc_inventory_lib');load_system('ecc_buffer_coupled_lib');
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));dc=onCleanup(@() diary('off'));
    record=struct('schema','heatdrive_ecc_sma_derivative_contract_v1','producer_commit',strtrim(commit), ...
        'collection_pass',false,'simulation_run',false,'state_imported',false,'model_saved',false, ...
        'production_recovery_allowed',false,'configuration_sha256',file_hash(config_path), ...
        'canonical_sha256',canonical_hash,'commands',{{}},'blocks',{{}},'error_message','');
    try
        [model,options]=Build_HeatDriveECC_EighthRound_Simulink_Model(prior.options);
        mc=onCleanup(@() close_system(model,0));
        assert(options.cycle_count==1 && options.simulation.stop_time_s==10,'Require actual single-cycle schedule.');
        variables={'SMA_pressure_bias_command','SMA_mdot_target_command', ...
            'SMA_pressure_feedback_enable_command','SMA_pressure_feedback_reset_command'};
        command_blocks={'SMAPressureBiasFromWorkspace','SMAFlowTargetFromWorkspace', ...
            'SMAPressureFeedbackEnableFromWorkspace','SMAPressureFeedbackResetFromWorkspace'};
        for k=1:numel(variables)
            b=[model '/' command_blocks{k}];v=slResolve(variables{k},b);
            assert(strcmp(get_param(b,'VariableName'),variables{k}) && isa(v,'timeseries') && ...
                isvector(v.Data) && v.Time(1)==0 && v.Time(end)==10 && all(diff(v.Time)>0),'Invalid command schedule.');
            record.commands{k}=struct('block',b,'variable',variables{k},'time_s',v.Time,'values',v.Data, ...
                'interpolate',get_param(b,'Interpolate'),'sample_time',get_param(b,'SampleTime'));
        end
        names=[command_blocks,{'SMAPressurePI_ErrorSum','SMAPressurePI_Kp','SMAPressurePI_Ki', ...
            'SMAPressurePEnableProduct','SMAPressurePI_Integrator','SMAPressurePI_BiasSum', ...
            'SMAPressurePI_Saturation','SMAPressurePI_SimulinkPS'}];
        resolve_keys={'Gain','InitialCondition','UpperSaturationLimit','LowerSaturationLimit','UpperLimit','LowerLimit'};
        for k=1:numel(names)
            b=[model '/' names{k}];params=fieldnames(get_param(b,'DialogParameters'));settings=struct();resolved=struct();
            for j=1:numel(params)
                key=params{j};settings.(key)=get_param(b,key);
                if ismember(key,resolve_keys)
                    val=slResolve(settings.(key),b);
                    assert(isnumeric(val) && isscalar(val) && isfinite(val),'Require finite actual controller constants.');
                    resolved.(key)=val;
                end
            end
            p=get_param(b,'PortHandles');inputs=cell(1,numel(p.Inport));
            for j=1:numel(p.Inport)
                line=get_param(p.Inport(j),'Line');assert(line~=-1,'Unconnected PI input.');
                src=get_param(line,'SrcPortHandle');
                inputs{j}=struct('index',j,'source_block',getfullname(get_param(line,'SrcBlockHandle')), ...
                    'source_port',get_param(src,'PortNumber'));
            end
            record.blocks{k}=struct('path',b,'type',get_param(b,'BlockType'), ...
                'settings',settings,'resolved',resolved,'inputs',{inputs});
        end
        assert(strcmp(file_hash(canonical),canonical_hash),'Canonical model changed.');
        record.collection_pass=true;clear mc
    catch ME
        record.error_message=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'sma_derivative_contract.json'),'w','n','UTF-8');assert(fid>=0);fc=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));clear fc
    fprintf('%s\n',jsonencode(struct('collection_pass',record.collection_pass,'simulation_run',false, ...
        'output_root',output_root,'error_message',record.error_message)));
    assert(record.collection_pass,'Controller contract collection failed.');
end

function hash=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0,'Missing evidence.');
    c=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
