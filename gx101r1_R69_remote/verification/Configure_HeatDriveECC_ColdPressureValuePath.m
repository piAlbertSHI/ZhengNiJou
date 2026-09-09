function contract=Configure_HeatDriveECC_ColdPressureValuePath(repo,model,derivative_contract)
% Isolate one pressure value edge while retaining the original controller.
    assert(strcmp(get_param(model,'StartTime'),'0') && strcmp(get_param(model,'StopTime'),'0') && ...
        strcmp(get_param(model,'LoadInitialState'),'off') && strcmp(get_param(model,'SaveOperatingPoint'),'off'));
    assert(derivative_contract.initialization_only && derivative_contract.allowed_stop_time_s==0 && ...
        derivative_contract.first_derivative_MPa_per_s==0 && ...
        all(derivative_contract.command_samples{2}.values==0) && all(derivative_contract.command_samples{3}.values==1));
    reference_path=fullfile(repo,'outputs_storage_audit','sma_derivative_contract_20260909_v3','sma_derivative_contract.json');
    reference_hash=file_hash(reference_path);
    assert(strcmp(reference_hash,'EE5C16D580693FCA925D24D0DB2A8E021BAC65E36F0A77A8E12AE795070ACEE2'));
    r=jsondecode(fileread(reference_path));converter=[model '/SMAPressurePI_SimulinkPS'];
    for k=1:numel(r.blocks)
        b=r.blocks(k);keys=fieldnames(b.settings);
        for j=1:numel(keys)
            expected=b.settings.(keys{j});
            if strcmp(b.path,converter) && strcmp(keys{j},'UdotUserProvided'),expected='1';end
            assert(isequal(get_param(b.path,keys{j}),expected),'Original controller setting changed.');
        end
        keys=fieldnames(b.resolved);
        for j=1:numel(keys)
            v=slResolve(b.settings.(keys{j}),b.path);expected=b.resolved.(keys{j});
            assert(isequal(v(:),expected(:)),'Controller coefficient changed.');
        end
        for j=1:numel(b.inputs),assert(strcmp(input_source(b.path,j),b.inputs(j).source_block));end
    end
    bias=derivative_contract.command_samples{1};
    sat=[model '/SMAPressurePI_Saturation'];
    lo=slResolve(get_param(sat,'LowerLimit'),sat);hi=slResolve(get_param(sat,'UpperLimit'),sat);
    assert(bias.values(1)>lo && bias.values(1)<hi,'Initial bias must be strictly inside the original saturation.');
    before=capture_inputs(r.blocks);blocks_before=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block');
    p=get_param(converter,'PortHandles');physical=[p.LConn(:);p.RConn(:)];assert(isscalar(physical));
    physical_line=get_param(physical,'Line');assert(physical_line>0);
    assert(strcmp(input_source(converter,1),sat) && ...
        strcmp(input_source(converter,2),derivative_contract.derivative_source));
    delete_line(get_param(p.Inport(1),'Line'));
    source=get_param(bias.block,'PortHandles');add_line(model,source.Outport(1),p.Inport(1));
    after=capture_inputs(r.blocks);expected=before;
    idx=find(strcmp({r.blocks.path},converter));assert(isscalar(idx));expected{idx}.sources{1}=bias.block;
    assert(isequal(expected,after) && get_param(physical,'Line')==physical_line && ...
        isequal(blocks_before,find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block')), ...
        'Only the declared Simulink value input edge may change.');
    contract=struct('schema','heatdrive_ecc_cold_pressure_value_path_v1', ...
        'reference_path',reference_path,'reference_sha256',reference_hash, ...
        'converter',converter,'value_source_before',sat,'value_source_after',bias.block, ...
        'derivative_source',derivative_contract.derivative_source,'initial_bias_MPa',bias.values(1), ...
        'saturation_limits_MPa',[lo hi],'inputs_before',{before},'inputs_after',{after}, ...
        'original_controller_block_count',numel(r.blocks),'model_block_set_unchanged',true, ...
        'converter_physical_line_unchanged',true,'original_controller_retained',true, ...
        'allowed_stop_time_s',0,'c200_state_imported',false,'production_recovery_allowed',false);
end

function rows=capture_inputs(blocks)
    rows=cell(1,numel(blocks));
    for k=1:numel(blocks)
        p=get_param(blocks(k).path,'PortHandles');sources=cell(1,numel(p.Inport));
        for j=1:numel(p.Inport),sources{j}=input_source(blocks(k).path,j);end
        rows{k}=struct('path',blocks(k).path,'sources',{sources});
    end
end
function source=input_source(block,index)
    p=get_param(block,'PortHandles');line=get_param(p.Inport(index),'Line');assert(line>0);
    source=getfullname(get_param(line,'SrcBlockHandle'));
end
function hash=file_hash(file)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
