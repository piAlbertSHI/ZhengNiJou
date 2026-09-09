function contract=Configure_HeatDriveECC_ColdPSController(repo,model,initial_bias_only,initial_mdot_probe)
% Cold-only PS representation; no imported OP or production model save.
    if nargin<3,initial_bias_only=false;end
    if nargin<4,initial_mdot_probe=false;end
    assert(islogical(initial_mdot_probe) && isscalar(initial_mdot_probe) && (~initial_mdot_probe || initial_bias_only));
    assert(islogical(initial_bias_only) && isscalar(initial_bias_only));
    assert(strcmp(get_param(model,'StartTime'),'0') && strcmp(get_param(model,'StopTime'),'0') && ...
        strcmp(get_param(model,'LoadInitialState'),'off') && strcmp(get_param(model,'SaveOperatingPoint'),'off'));
    root=fullfile(repo,'outputs_storage_audit');
    qualified=fullfile(root,'ps_controller_pair_audit_20260909','controller_pair_audit.json');
    assert(strcmp(file_hash(qualified),'B0B7A15859E885325B9317722BA0B4A222226F9805DFA6AC69AF98D7C8A68C4C'));
    reference_path=fullfile(root,'sma_derivative_contract_20260909_v3','sma_derivative_contract.json');
    assert(strcmp(file_hash(reference_path),'EE5C16D580693FCA925D24D0DB2A8E021BAC65E36F0A77A8E12AE795070ACEE2'));
    r=jsondecode(fileread(reference_path));
    if initial_bias_only
        assert(all(r.commands(3).values(1:2)==0) && all(r.commands(4).values(1:2)==1) && ...
            r.commands(1).values(1)==r.commands(1).values(2),'Bypass only within the held-reset constant-bias initial interval.');
    end
    for k=1:numel(r.blocks)
        b=r.blocks(k);keys=fieldnames(b.settings);
        for j=1:numel(keys),assert(isequal(get_param(b.path,keys{j}),b.settings.(keys{j})));end
        keys=fieldnames(b.resolved);
        for j=1:numel(keys)
            current=slResolve(b.settings.(keys{j}),b.path);expected=b.resolved.(keys{j});
            assert(isequal(current(:),expected(:)),'Controller coefficient changed.');
        end
        p=get_param(b.path,'PortHandles');
        for j=1:numel(b.inputs)
            line=get_param(p.Inport(j),'Line');assert(line>0);
            assert(strcmp(getfullname(get_param(line,'SrcBlockHandle')),b.inputs(j).source_block));
        end
    end
    source=fullfile(repo,'verification','simscape_sma_controller','+ecc_sma_controller','pressure_controller.ssc');
    source_hash=file_hash(source);
    assert(strcmp(source_hash,'EB6AC72398E21E9069674744E1F1ECE1D8133E4729D23E42FDE3AC5C332AEA71'));
    build=fullfile(root,'ps_controller_equivalence_20260909_v2','component_build');
    assert(strcmp(file_hash(fullfile(build,'+ecc_sma_controller','pressure_controller.ssc')),source_hash));
    addpath(build);library=fullfile(build,'ecc_sma_controller_lib.slx');load_system(library);
    lib=find_system('ecc_sma_controller_lib','SearchDepth',1,'Type','Block');assert(isscalar(lib));
    before=physical_connections(model);
    candidate=[model '/ColdSMAPSController'];add_block(lib{1},candidate);
    names={'bias','target','enable','reset'};units={'MPa','kg/s','1','1'};
    for k=1:4
        c=r.commands(k);v=slResolve(c.variable,c.block);
        assert(isequal(v.Time(:),c.time_s(:)) && isequal(v.Data(:),c.values(:)));
        ps=[model '/ColdSMA_' names{k} '_PS'];
        add_block('nesl_utility/Simulink-PS Converter',ps,'Unit',units{k},'UdotUserProvided','1');
        wire(model,c.block,1,ps,1);d=zeros(size(c.values(:)));
        if strcmp(c.interpolate,'on'),d=[diff(c.values(:))./diff(c.time_s(:));0];end
        variable=['cold_sma_ps_' names{k} '_derivative'];assignin('base',variable,timeseries(d,c.time_s(:)));
        db=[ps '_Derivative'];add_block('simulink/Sources/From Workspace',db,'VariableName',variable, ...
            'Interpolate','off','OutputAfterFinalValue','Holding final value');wire(model,db,1,ps,2);
        simscape.addConnection(ps,only_port(ps),candidate,names{k});
    end
    sensor=[model '/FlowSensor_SMA_stage13_loop_PS'];
    snapshot=struct();flow_driver=sensor;
    if initial_mdot_probe
        audit_path=fullfile(root,'initial_flux_pressure_audit_20260909_v2','initial_flux_pressure_audit.json');
        assert(strcmp(file_hash(audit_path),'25BD6933EF469E29F77474659B0D8F74027B890D8E3B80910660559E9CA50B4D'));
        a=jsondecode(fileread(audit_path));
        assert(a.strict_initial_coordinate_match && a.matching_initial_coordinates==204 && ...
            a.compiled_inventory_gate && a.constraints.initial_flux_pressure_consistency_pass);
        trial=fullfile(root,'specific_inventory_projection_initial_flux_20260909');
        evidence=jsondecode(fileread(fullfile(trial,'compiled_states_inspection.json')));
        raw=fullfile(trial,'observations.mat');
        assert(evidence.inspection_pass && strcmp(file_hash(raw),evidence.observations_sha256));
        data=load(raw,'signals');signal=data.signals.mass_flow_sma_stage13_kgps;
        assert(isscalar(signal.time_s) && signal.time_s==0 && isscalar(signal.values) && ...
            isfinite(signal.values) && signal.values==a.measured_flow_signal_initial_kg_s);
        flow_driver=[model '/ColdSMA_InitialMdot_PS'];
        add_block('nesl_utility/Simulink-PS Converter',flow_driver,'Unit','kg/s','UdotUserProvided','1');
        constant=[model '/ColdSMA_InitialMdot'];zero=[constant '_Derivative'];
        add_block('simulink/Sources/Constant',constant,'Value',num2str(signal.values,17));
        add_block('simulink/Sources/Constant',zero,'Value','0');
        wire(model,constant,1,flow_driver,1);wire(model,zero,1,flow_driver,2);
        snapshot=struct('audit_path',audit_path,'audit_sha256',file_hash(audit_path), ...
            'observations_path',raw,'observations_sha256',file_hash(raw), ...
            'signal_name','mass_flow_sma_stage13_kgps','time_s',0,'value_kg_s',signal.values, ...
            'constant_derivative_kg_s2',0,'valid_duration_s',0,'state_imported',false);
    end
    simscape.addConnection(flow_driver,only_port(flow_driver),candidate,'mdot');
    converter=[model '/SMAPressurePI_SimulinkPS'];p=get_param(converter,'PortHandles');
    physical=[p.LConn(:);p.RConn(:)];assert(isscalar(physical));
    connection=get_param(converter,'PortConnectivity');selected=startsWith({connection.Type},{'LConn','RConn'});
    connection=connection(selected);assert(isscalar(connection));destinations=connection.DstPort(:);
    assert(~isempty(destinations) && all(destinations>0));
    destination_paths=arrayfun(@(h) getfullname(get_param(h,'Parent')),destinations,'UniformOutput',false);
    line=get_param(physical,'Line');assert(line>0);delete_line(line);delete_block(converter);
    scratch='ecc_ps_controller_mapping';assert(~bdIsLoaded(scratch));new_system(scratch);
    sc=onCleanup(@() close_system(scratch,0));mapped=Map_HeatDriveECC_PhysicalPortHandles(candidate,scratch);
    pressure=mapped(cellfun(@(x) strcmp(x.name,'pressure'),mapped));assert(isscalar(pressure));
    driver=pressure{1}.handle;driver_path=candidate;
    if initial_bias_only
        driver_path=[model '/ColdSMA_bias_PS'];p=get_param(driver_path,'PortHandles');
        driver=[p.LConn(:);p.RConn(:)];assert(isscalar(driver));
    end
    for k=1:numel(destinations),add_line(model,driver,destinations(k),'autorouting','on');end
    clear sc
    % Preserve the existing pressure logger via its saturation block, not a feedback loop.
    saturation=[model '/SMAPressurePI_Saturation'];p=get_param(saturation,'PortHandles');delete_line(get_param(p.Inport(1),'Line'));
    out=[model '/ColdSMAPressureOutput'];add_block('nesl_utility/PS-Simulink Converter',out,'Unit','MPa');
    simscape.addConnection(candidate,'pressure',out,only_port(out));wire(model,out,1,saturation,1);
    removed={'SMAPressurePI_ErrorSum','SMAPressurePI_ErrorNormalizer','SMAPressurePI_ErrorLag', ...
        'SMAPressurePI_Kp','SMAPressurePI_Ki','SMAPressurePEnableProduct','SMAPressurePI_Integrator','SMAPressurePI_BiasSum'};
    for k=1:numel(removed),delete_block([model '/' removed{k}]);end
    after=physical_connections(model);assert(isequal(before,after),'Thermal/fluid connections changed.');
    set_param(model,'AlgebraicLoopMsg','error');
    contract=struct('schema','heatdrive_ecc_cold_ps_controller_v1','candidate_path',candidate, ...
        'component_sha256',source_hash,'library_sha256',file_hash(library),'library_path',library, ...
        'qualification_sha256',file_hash(qualified),'original_controller_sha256',file_hash(reference_path), ...
        'removed_blocks',{removed},'pressure_destination_paths',{destination_paths}, ...
        'flow_sensor_physical_signal_path',sensor,'physical_connections_unchanged',true, ...
        'physical_connections_before',{before},'physical_connections_after',{after}, ...
        'commands',r.commands,'initial_lag',0,'initial_integral_MPa',0,'stop_time_s',0, ...
        'initial_bias_only',initial_bias_only,'pressure_driver_path',driver_path, ...
        'initial_mdot_probe',initial_mdot_probe,'flow_driver_path',flow_driver,'initial_mdot_snapshot',snapshot, ...
        'c200_state_imported',false,'production_recovery_allowed',false,'controller_representation_changed',true);
end

function rows=physical_connections(model)
    blocks=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block');rows={};
    domains={'foundation.thermal_liquid.thermal_liquid','foundation.thermal.thermal'};
    scratch='ecc_cold_ps_boundary_mapping';assert(~bdIsLoaded(scratch));new_system(scratch);
    cleanup=onCleanup(@() close_system(scratch,0));
    for k=1:numel(blocks)
        b=blocks{k};p=get_param(b,'PortHandles');if isempty([p.LConn,p.RConn]),continue;end
        properties=simscape.connectionPortProperties(b);
        if ~any(arrayfun(@(x) isprop(x.Type,'Name') && any(strcmp(x.Type.Name,domains)),properties)),continue;end
        for d=1:numel(domains)
            mapped=Map_HeatDriveECC_PhysicalPortHandles(b,scratch,domains{d});c=get_param(b,'PortConnectivity');
            for j=1:numel(mapped)
                name=[mapped{j}.side num2str(mapped{j}.index)];selected=c(strcmp({c.Type},name));assert(isscalar(selected));
                rows{end+1}=struct('block',b,'port',mapped{j}.name,'domain',domains{d}, ...
                    'destinations',sort(selected.DstPort(:))); %#ok<AGROW>
            end
        end
    end
end
function wire(model,source,si,destination,di)
    s=get_param(source,'PortHandles');d=get_param(destination,'PortHandles');add_line(model,s.Outport(si),d.Inport(di));
end
function name=only_port(block)
    p=simscape.connectionPortProperties(block);assert(isscalar(p));name=p.Name;
end
function hash=file_hash(file)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
