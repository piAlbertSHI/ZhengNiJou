function record=Apply_HeatDriveECC_SharedSMAFluidDiagnostic(model, isolated_model_path, tl, th)
% Structural cold diagnostic only. Do not apply to a loaded production model.
    actual=char(java.io.File(get_param(model,'FileName')).getCanonicalPath());
    isolated=char(java.io.File(isolated_model_path).getCanonicalPath());
    assert(strcmpi(actual,isolated),'Require the explicitly isolated model file.');
    assert(strcmp(get_param(model,'SimulationStatus'),'stopped'));
    assert(strcmp(get_param(model,'LoadInitialState'),'off'), ...
        'New topology cannot load an old complete-state checkpoint.');
    parent=[model '/SMA'];
    [tk,labels]=wire_labels(tl);[hk,hlabels]=wire_labels(th);
    hold=find_system(parent,'SearchDepth',1,'RegExp','on','Name','^HoldPipe_[0-9]{3}$');
    cool=find_system(parent,'SearchDepth',1,'RegExp','on','Name','^CooldownPipe_[0-9]{3}$');
    assert(numel(hold)==21 && numel(cool)==21,'Require the explicit dual 21-cell baseline.');
    keep=cell(1,21);drop=cell(1,21);pipes=cell(1,21);removed={};
    for i=1:21
        keep{i}=sprintf('%s/HoldPipe_%03d',parent,i);
        drop{i}=sprintf('%s/CooldownPipe_%03d',parent,i);
        pipes{i}=pipe_parameters(keep{i});other=pipe_parameters(drop{i});
        assert(pipes{i}.area_m2==other.area_m2 && pipes{i}.length_m==other.length_m, ...
            'Do not silently merge unlike route inventories.');
        for route={'Hold','Cooldown'}
            r=route{1};pipe=sprintf('%s/%sPipe_%03d',parent,r,i);
            gate=sprintf('%s/%sThermalGate_%03d',parent,r,i);
            sensor=sprintf('%s/SMA%sNode%02dHeatFlowSensor',parent,r,i);
            solid=sprintf('%s/Subsystem2/NodeMass_%02d',parent,i);
            require_same(hk,hlabels,[pipe ':H'],[gate ':A']);
            require_same(hk,hlabels,[gate ':B'],[sensor ':A']);
            require_same(hk,hlabels,[sensor ':B'],[solid ':M']);
        end
        if i<21
            require_same(tk,labels,[keep{i} ':B'],sprintf('%s/HoldPipe_%03d:A',parent,i+1));
            require_same(tk,labels,[drop{i} ':A'],sprintf('%s/CooldownPipe_%03d:B',parent,i+1));
        end
    end
    require_same(tk,labels,[keep{1} ':A'],[parent '/Conn2:port']);
    require_same(tk,labels,[keep{21} ':B'],[parent '/Conn1:port']);
    require_same(tk,labels,[drop{1} ':B'],[parent '/Conn3:port']);
    require_same(tk,labels,[drop{21} ':A'],[parent '/Conn4:port']);
    % Remove only complete cooling-chain liquid wire nets. Their sensor and
    % connector branches are explicitly reattached below, never left dangling.
    line_handles=[];
    for i=1:21
        for port={'A','B'}
            h=typed_handle(tl,[drop{i} ':' port{1}]);
            line_handles(end+1)=root_line(get_param(h,'Line')); %#ok<AGROW>
        end
    end
    assert(all(line_handles>0));
    for line=unique(line_handles),delete_line(line);end
    for i=1:21
        names={drop{i},sprintf('%s/CooldownThermalGate_%03d',parent,i), ...
            sprintf('%s/SMACooldownNode%02dHeatFlowSensor',parent,i), ...
            sprintf('%s/SMACooldownNode%02dHeatFlowPS',parent,i), ...
            sprintf('%s/ToWorkspace_sma_cooldown_node%02d_heatflow_W',parent,i)};
        for j=1:numel(names)
            assert(getSimulinkBlockHandle(names{j})>0,'Missing explicitly retired route block.');
            delete_block(names{j});removed{end+1}=names{j}; %#ok<AGROW>
        end
    end
    delete_block([parent '/CooldownThermalGateCommandPS']);
    removed{end+1}=[parent '/CooldownThermalGateCommandPS'];
    % Preserve the existing counter-direction valve/port contract. Conn3 now
    % shares node-1 end; Conn4 shares node-21 end. External valves are unchanged.
    add_line(parent,typed_handle(tl,[keep{1} ':A']),typed_handle(tl,[parent '/Conn3:port']),'autorouting','on');
    add_line(parent,typed_handle(tl,[keep{21} ':B']),typed_handle(tl,[parent '/Conn4:port']),'autorouting','on');
    alias=cell(1,3);
    for j=1:3
        i=[1 11 21];i=i(j);p='B';if i==1,p='A';end
        sensor=sprintf('%s/SMACooldownPipeNode%02dFluidTempSensor',parent,i);
        add_line(parent,typed_handle(tl,[keep{i} ':' p]),typed_handle(tl,[sensor ':A']),'autorouting','on');
        alias{j}=struct('historical_sensor',sensor,'shared_port',[keep{i} ':' p], ...
            'independent_cooling_inventory_measurement',false);
    end
    from1=[parent '/HoldThermalGateCommandFromWorkspace'];
    from2=[parent '/CooldownThermalGateCommandFromWorkspace'];
    converter=[parent '/HoldThermalGateCommandPS'];
    assert(strcmp(get_param(from1,'Interpolate'),'off') && strcmp(get_param(from2,'Interpolate'),'off'));
    maxblock=[parent '/SharedSMAActiveThermalGate'];
    assert(getSimulinkBlockHandle(maxblock)<0,'Never reapply a topology intervention.');
    add_block('simulink/Math Operations/MinMax',maxblock,'Function','max','Inputs','2');
    ports=get_param(converter,'PortHandles');delete_line(get_param(ports.Inport(1),'Line'));
    add_line(parent,'HoldThermalGateCommandFromWorkspace/1','SharedSMAActiveThermalGate/1');
    add_line(parent,'CooldownThermalGateCommandFromWorkspace/1','SharedSMAActiveThermalGate/2');
    add_line(parent,'SharedSMAActiveThermalGate/1','HoldThermalGateCommandPS/1');
    for i=1:21,assert(isequal(pipes{i},pipe_parameters(keep{i})),'Retained pipe geometry or IC expression changed.');end
    assert(isempty(find_system(parent,'SearchDepth',1,'RegExp','on','Name','^CooldownPipe_[0-9]{3}$')));
    record=struct('schema','heatdrive_ecc_shared_SMA_fluid_diagnostic_v1', ...
        'mode','isolated_constructor_only','retained_pipe_parameters',{pipes}, ...
        'removed_blocks',{removed},'historical_temperature_aliases',{alias}, ...
        'single_bed_volume_m3',sum(cellfun(@(p)p.area_m2*p.length_m,pipes)), ...
        'external_valves_modified',false,'solid_capacity_modified',false, ...
        'retained_initial_state_expressions_modified',false,'complete_state_loaded',false, ...
        'gate_command','max(original_hold_G, original_cooldown_G), original ZOH commands and PS converter', ...
        'cooling_heatflow_outputs_removed_not_fabricated',true, ...
        'compiled_or_simulated',false,'switch_continuity_proven',false, ...
        'production_recovery_allowed',false,'scientific_mechanism_qualified',false);
end

function line=root_line(line)
    assert(line>0,'Expected a connected cooling-chain liquid port.');
    parent=get_param(line,'LineParent');
    while parent>0,line=parent;parent=get_param(line,'LineParent');end
end

function p=pipe_parameters(block)
    assert(strcmp(get_param(block,'SourceFile'),'foundation.thermal_liquid.elements.pipe'));
    assert(strcmp(get_param(block,'area_unit'),'m^2') && strcmp(get_param(block,'length_unit'),'m'));
    fields={'area','length','Dh','Nu_lam','T0','p0'};expressions=struct();
    for i=1:numel(fields),expressions.(fields{i})=get_param(block,fields{i});end
    a=slResolve(expressions.area,block);l=slResolve(expressions.length,block);
    assert(isscalar(a) && isfinite(a) && a>0 && isscalar(l) && isfinite(l) && l>0);
    p=struct('block',block,'area_m2',a,'length_m',l,'retained_mask_expressions',expressions);
end

function h=typed_handle(t,key)
    rows=t.vertices;idx=find(cellfun(@(r)strcmp(r.key,key),rows));
    assert(isscalar(idx),'Expected a uniquely named typed physical port.');h=rows{idx}.handle;
end

function [keys,labels]=wire_labels(t)
    keys=cellfun(@(r)r.key,t.vertices,'UniformOutput',false);
    edges=t.edges;allowed=cellfun(@(e)ismember(e.kind,{'physical_wire_net','hierarchy_connector'}),edges);
    a=cellfun(@(e)e.a,edges(allowed));b=cellfun(@(e)e.b,edges(allowed));
    labels=conncomp(graph(a,b,[],numel(keys)));
end

function require_same(keys,labels,a,b)
    i=find(strcmp(keys,a));j=find(strcmp(keys,b));assert(isscalar(i) && isscalar(j));
    assert(labels(i)==labels(j),'Baseline typed wire/solid mapping is not the diagnosed topology.');
end
