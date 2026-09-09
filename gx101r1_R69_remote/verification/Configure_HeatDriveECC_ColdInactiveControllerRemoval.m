function contract=Configure_HeatDriveECC_ColdInactiveControllerRemoval(model,value_contract)
% Remove the inactive controller only after the qualified t=0 value bypass.
    assert(strcmp(get_param(model,'StartTime'),'0') && strcmp(get_param(model,'StopTime'),'0') && ...
        strcmp(get_param(model,'LoadInitialState'),'off') && strcmp(get_param(model,'SaveOperatingPoint'),'off'));
    assert(value_contract.original_controller_retained && value_contract.allowed_stop_time_s==0 && ...
        ~value_contract.production_recovery_allowed && value_contract.converter_physical_line_unchanged);
    converter=value_contract.converter;bias=value_contract.value_source_after;sat=[model '/SMAPressurePI_Saturation'];
    removed={'SMAPressurePI_ErrorSum','SMAPressurePI_ErrorNormalizer','SMAPressurePI_ErrorLag', ...
        'SMAPressurePI_Kp','SMAPressurePI_Ki','SMAPressurePEnableProduct','SMAPressurePI_Integrator','SMAPressurePI_BiasSum'};
    removed_paths=cellfun(@(x) [model '/' x],removed,'UniformOutput',false);
    before=value_contract.inputs_after;
    for k=1:numel(before)
        b=before{k};p=get_param(b.path,'PortHandles');assert(numel(p.Inport)==numel(b.sources));
        for j=1:numel(b.sources),assert(strcmp(input_source(b.path,j),b.sources{j}));end
    end
    % Deleting control blocks must not discard an unexpected external logger or actuator.
    for k=1:numel(removed_paths)
        p=get_param(removed_paths{k},'PortHandles');
        for j=1:numel(p.Outport)
            line=get_param(p.Outport(j),'Line');if line<0,continue;end
            destinations=get_param(line,'DstBlockHandle');
            for n=1:numel(destinations)
                assert(any(strcmp(getfullname(destinations(n)),[removed_paths {sat}])), ...
                    'Unexpected destination from an inactive controller block.');
            end
        end
    end
    blocks_before=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block');
    p=get_param(converter,'PortHandles');physical=[p.LConn(:);p.RConn(:)];assert(isscalar(physical));
    physical_line=get_param(physical,'Line');assert(physical_line>0);
    assert(strcmp(input_source(converter,1),bias) && strcmp(input_source(converter,2),value_contract.derivative_source));
    p=get_param(sat,'PortHandles');delete_line(get_param(p.Inport(1),'Line'));
    source=get_param(bias,'PortHandles');add_line(model,source.Outport(1),p.Inport(1));
    for k=1:numel(removed_paths),delete_block(removed_paths{k});end
    blocks_after=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block');
    assert(isequal(sort(setdiff(blocks_before,removed_paths)),sort(blocks_after)) && ...
        get_param(physical,'Line')==physical_line,'Unexpected model or physical input change.');
    retained={};
    for k=1:numel(before)
        b=before{k};if any(strcmp(b.path,removed_paths)),continue;end
        if strcmp(b.path,sat),b.sources={bias};end
        for j=1:numel(b.sources),assert(strcmp(input_source(b.path,j),b.sources{j}));end
        retained{end+1}=b; %#ok<AGROW>
    end
    assert(numel(retained)==7);
    contract=struct('schema','heatdrive_ecc_cold_inactive_controller_removal_v1', ...
        'removed_paths',{removed_paths},'inputs_before',{before},'retained_inputs_after',{retained}, ...
        'pressure_converter',converter,'pressure_value_source',bias,'pressure_derivative_source',value_contract.derivative_source, ...
        'logger_saturation',sat,'logger_value_source_after',bias,'converter_physical_line_unchanged',true, ...
        'only_expected_blocks_removed',true,'candidate_ps_added',false,'allowed_stop_time_s',0, ...
        'c200_state_imported',false,'production_recovery_allowed',false);
end
function source=input_source(block,index)
    p=get_param(block,'PortHandles');line=get_param(p.Inport(index),'Line');assert(line>0);
    source=getfullname(get_param(line,'SrcBlockHandle'));
end
