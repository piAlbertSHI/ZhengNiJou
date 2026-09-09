function record=Inspect_HeatDriveECC_PumpSubnetworkContract(repo,output_root)
% Export actual local pump/port settings without simulation or state import.
    assert(~isfolder(output_root),'Never overwrite a local equation contract.');
    [code,dirty]=system(sprintf('git -C "%s" status --porcelain -- .',repo));
    assert(code==0 && isempty(strtrim(dirty)),'Commit source first.');
    [code,commit]=system(sprintf('git -C "%s" rev-parse HEAD',repo));assert(code==0);
    root=fullfile(repo,'outputs_storage_audit');
    prior_root=fullfile(root,'conservative_buffer_coupled_cycle_20260909');
    config_path=fullfile(prior_root,'conservative','configuration.mat');
    config=load(config_path,'options');config.options.simulation.persist_model_configuration=false;
    config.options.branch.independent_conservative_chamber_library='ecc_inventory_specific_lib';
    canonical=config.options.model_path;canonical_hash=file_hash(canonical);
    oldpath=path;pc=onCleanup(@() path(oldpath));
    addpath(repo);addpath(fullfile(prior_root,'buffer_component_build'));
    build=fullfile(root,'specific_inventory_ps_controller_initial_20260909','component_build');
    addpath(build);load_system(fullfile(build,'ecc_inventory_specific_lib.slx'));load_system('ecc_buffer_coupled_lib');
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));dc=onCleanup(@() diary('off'));
    record=struct('schema','heatdrive_ecc_pump_subnetwork_contract_v1','execution_commit',strtrim(commit), ...
        'collection_pass',false,'simulation_run',false,'state_imported',false,'production_recovery_allowed',false, ...
        'configuration_sha256',file_hash(config_path),'canonical_sha256',canonical_hash,'blocks',{{}}, ...
        'capture_phase','rebuilt geometry before public cold target/PS adapter application', ...
        'equation_sources',{{}},'error_message','');
    try
        [model,~]=Build_HeatDriveECC_EighthRound_Simulink_Model(config.options);mc=onCleanup(@() close_system(model,0));
        names={'SMA_ThermalLiquidSettings','SMA Pressure Source (TL)','FlowSensor_SMA_stage13_loop', ...
            'SMA_PumpInletConnectingPipeVolume','SMA_PumpOutletConnectingPipeVolume'};
        scratch='ecc_pump_contract_mapping';assert(~bdIsLoaded(scratch));new_system(scratch);sc=onCleanup(@() close_system(scratch,0));
        for k=1:numel(names)
            b=[model '/' names{k}];keys=fieldnames(get_param(b,'DialogParameters'));parameters=struct();
            for j=1:numel(keys),parameters.(keys{j})=get_param(b,keys{j});end
            resolved=struct();
            for key={'area','volume'}
                name=key{1};if ~isfield(parameters,name),continue;end
                v=slResolve(parameters.(name),b);assert(isnumeric(v) && isscalar(v) && isfinite(v) && v>0);
                resolved.(name)=struct('value',v,'unit',parameters.([name '_unit']));
            end
            source='';if strcmp(get_param(b,'BlockType'),'SimscapeBlock'),source=get_param(b,'SourceFile');end
            ports=Map_HeatDriveECC_PhysicalPortHandles(b,scratch);connections=get_param(b,'PortConnectivity');
            for j=1:numel(ports)
                port=ports{j};c=connections(strcmp({connections.Type},[port.side num2str(port.index)]));assert(isscalar(c));
                ports{j}.connected_block_paths=arrayfun(@(h) getfullname(h),c.DstBlock(:),'UniformOutput',false);
                ports{j}.connected_port_handles=c.DstPort(:);
            end
            record.blocks{end+1}=struct('path',b,'source_file',source,'parameters',parameters,'resolved_geometry',resolved,'ports',{ports});
        end
        clear sc
        folder=fullfile(matlabroot,'toolbox','physmod','simscape','library','m','+foundation','+thermal_liquid');
        sources={fullfile(folder,'+sources','pressure_source.ssc'),fullfile(folder,'+sensors','flow_sensor.ssc'), ...
            fullfile(folder,'port_convection.ssc'),fullfile(folder,'+utilities','thermal_liquid_settings.ssc'), ...
            fullfile(repo,'verification','simscape_inventory_specific','+ecc_inventory_specific','conservative_chamber.ssc')};
        for k=1:numel(sources)
            record.equation_sources{end+1}=struct('path',sources{k},'sha256',file_hash(sources{k}));
        end
        assert(strcmp(file_hash(canonical),canonical_hash),'Canonical model changed.');
        record.collection_pass=true;clear mc
    catch ME
        record.error_message=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'pump_subnetwork_contract.json'),'w','n','UTF-8');assert(fid>=0);fc=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(struct('collection_pass',record.collection_pass,'simulation_run',false,'error_message',record.error_message)));
    assert(record.collection_pass,'Local equation contract collection failed.');
end
function hash=file_hash(file)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
