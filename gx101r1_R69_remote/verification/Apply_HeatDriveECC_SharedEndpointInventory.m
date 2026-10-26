function [point,contract,record,libraries]=Apply_HeatDriveECC_SharedEndpointInventory(repo,model,options,reference_root,folder)
% New cold physical variant, never a restore or a numerical-equivalence claim.
    assert(strcmp(get_param(model,'LoadInitialState'),'off') && ...
        strcmp(get_param(model,'SimulationStatus'),'stopped'));
    contract=Build_HeatDriveECC_CoupledCVInventory(model,'shared',options);
    baseline=contract;
    execution_path=fullfile(reference_root,'coupled_CV_execution.json');
    execution=jsondecode(fileread(execution_path));
    assert(execution.collection_complete && ~execution.checkpoint_loaded_or_saved && execution.stop_time_s==20);
    cases=execution.completed_arms;case_record=cases(strcmp({cases.arm},'shared'));assert(isscalar(case_record));
    raw=fullfile(reference_root,'shared','native_CV_observations.mat');
    assert(strcmp(file_hash(raw),case_record.CV_packet.native_sha256),'Reference cold coordinates changed.');
    reference_contract_path=fullfile(reference_root,'shared','CV_contract.json');
    assert(strcmp(file_hash(reference_contract_path),case_record.CV_packet.contract_file_sha256.contract));
    reference_contract=jsondecode(fileread(reference_contract_path));
    assert(isequal(sort(string(reference_contract.storage_paths(:))),sort(string(contract.storage_paths(:)))), ...
        'Reference and constructed storage path sets differ.');
    assert(isequal(reference_contract.settings_tables,jsondecode(jsonencode(baseline.settings_tables))), ...
        'Endpoint comparison cannot silently change fluid property domains.');
    saved=load(raw,'packet');packet=saved.packet;
    assert(strcmp(packet.schema,'heatdrive_ecc_shared_clock_trace_columns_v1') && ...
        ~packet.time_interpolation_performed && ~packet.state_values_modified && packet.not_an_OP_or_restart_state);
    native=cell(size(packet.rows));
    for k=1:numel(packet.rows)
        row=packet.rows{k};grid=packet.time_grids{row.grid_index};
        assert(grid.time_s(1)==0 && size(row.values,1)==numel(grid.time_s) && row.channel_count==1);
        row.time_s=0;row.values=row.values(1,:);native{k}=row;
    end
    clear packet saved
    build=fullfile(folder,'endpoint_component_build');mkdir(build);
    packages={'ecc_inventory_endpoint','ecc_buffer_coupled_offset'};
    source_folders={'simscape_inventory_endpoint','simscape_buffer_coupled_offset'};
    components={'conservative_chamber.ssc','conservative_buffer.ssc'};libraries=cell(1,2);sources=cell(1,2);
    old=pwd;restore=onCleanup(@() cd(old));cd(build);addpath(build);
    for k=1:2
        source=fullfile(repo,'verification',source_folders{k},['+' packages{k}],components{k});
        target=fullfile(build,['+' packages{k}]);mkdir(target);copyfile(source,fullfile(target,components{k}));
        libraries{k}=[packages{k} '_lib'];assert(~bdIsLoaded(libraries{k}),'Library already in use.');
        ssc_build(packages{k});
        library=fullfile(build,[libraries{k} '.slx']);load_system(library);
        sources{k}=struct('path',source,'sha256',file_hash(source),'library_path',library, ...
            'library_sha256',file_hash(library),'compiled_in_experiment',true);
    end
    chambers={[model '/SMA_PumpInletConnectingPipeVolume'],[model '/SMA_PumpOutletConnectingPipeVolume']};
    leaf=find_system(libraries{1},'SearchDepth',1,'Type','Block');leaf=setdiff(leaf,libraries(1));assert(isscalar(leaf));
    scratch='ecc_endpoint_chamber_port_map';assert(~bdIsLoaded(scratch));new_system(scratch);
    clean_scratch=onCleanup(@() close_system(scratch,0));
    for k=1:2
        path=chambers{k};before=Map_HeatDriveECC_PhysicalPortHandles(path,scratch);
        assert(numel(before)==3 && all(cellfun(@(r)strcmp(r.interface_type,'Domain'),before)));
        for j=1:3,before{j}.connected=get_param(before{j}.handle,'Line')>=0;end
        position=get_param(path,'Position');
        hit=replace_block(model,'Name',get_param(path,'Name'),leaf{1},'noprompt');
        assert(isscalar(hit) && strcmp(hit{1},path));
        set_param(path,'Position',position,'volume','sma_pump_manifold_volume_m3','volume_unit','m^3', ...
            'area','sma_connecting_pipe_flow_area_m2','area_unit','m^2', ...
            'p_I_specify','on','p_I_priority','Low','T_I_specify','on','T_I_priority','Low');
        after=Map_HeatDriveECC_PhysicalPortHandles(path,scratch);
        assert(numel(after)==3);
        for j=1:3
            a=before{j};b=after(cellfun(@(r)strcmp(r.name,a.name),after));assert(isscalar(b));b=b{1};
            assert(strcmp(a.domain,b.domain) && strcmp(a.side,b.side) && a.index==b.index && ...
                a.connected==(get_param(b.handle,'Line')>=0),'Chamber physical port identity/connectivity changed.');
        end
    end
    clear clean_scratch
    buffers=Apply_HeatDriveECC_ColdConservativeBuffers(model,native,libraries{2},'zero_based_offset');
    [point,targets]=Build_HeatDriveECC_ColdInventoryTargets(model,native, ...
        options.branch.sma_pump_manifold_volume_m3,buffers,'ecc_inventory_endpoint.conservative_chamber',baseline);
    contract.schema='heatdrive_ecc_endpoint_CV_inventory_v1';
    contract.storage_formulation='endpoint_inventory';contract.endpoint_chamber_paths=chambers;
    contract.endpoint_buffer_paths=cellfun(@(r)r.block_path,buffers,'UniformOutput',false);
    for k=1:numel(contract.storage_blocks)
        row=contract.storage_blocks{k};path=row.block_path;
        if ~ismember(path,[chambers,contract.endpoint_buffer_paths]),continue;end
        row.original_native_mask_type=row.mask_type;
        row.actual_mask_type=get_param(path,'MaskType');row.source_file=get_param(path,'SourceFile');
        row.reference_block=get_param(path,'ReferenceBlock');row.model_modes=struct();row.mask_parameters=struct();
        row.mask_type='Endpoint Chamber';names={'volume','area'};
        if ismember(path,contract.endpoint_buffer_paths)
            row.mask_type='Endpoint Buffer';
            names={'tank_area','port_area','p_environment','gravity','reference_temperature','auxiliary_depth','initial_stored_mass'};
        end
        for j=1:numel(names)
            name=names{j};expr=get_param(path,name);
            row.mask_parameters.(name)=struct('expression',expr,'value',slResolve(expr,path),'unit',get_param(path,[name '_unit']));
        end
        contract.storage_blocks{k}=row;
    end
    record=struct('schema','heatdrive_ecc_shared_endpoint_inventory_construction_v1', ...
        'reference_root',reference_root,'reference_execution_sha256',file_hash(execution_path), ...
        'reference_cold_native_sha256',file_hash(raw),'reference_contract_sha256',file_hash(reference_contract_path), ...
        'source_components',{sources},'buffers',{buffers},'public_targets',{targets}, ...
        'physical_target_count',numel(targets),'high_target_count',sum(cellfun(@(r)strcmp(r.priority,'High'),targets)), ...
        'public_targets_have_private_data',hasPrivateData(point), ...
        'initial_flux_compensation_applied',false,'old_topology_empirical_calibration_reused',false, ...
        'source_time_s',0,'private_state_or_checkpoint_loaded',false,'new_physical_variant_not_native_equivalence',true, ...
        'production_recovery_allowed',false);
    assert(record.physical_target_count==162 && record.high_target_count==104 && ~record.public_targets_have_private_data);
end

function h=file_hash(path)
    f=fopen(path,'rb');assert(f>=0);c=onCleanup(@() fclose(f));d=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(f),d.update(fread(f,1048576,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
