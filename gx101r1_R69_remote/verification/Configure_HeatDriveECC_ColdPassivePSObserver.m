function contract=Configure_HeatDriveECC_ColdPassivePSObserver(repo,model,removal,separate_network,live_flow,external_lag)
% Add a non-driving PS observer to the qualified original pressure input.
    assert(strcmp(get_param(model,'StartTime'),'0') && strcmp(get_param(model,'StopTime'),'0') && ...
        strcmp(get_param(model,'LoadInitialState'),'off') && strcmp(get_param(model,'SaveOperatingPoint'),'off'));
    assert(removal.only_expected_blocks_removed && removal.allowed_stop_time_s==0 && ~removal.candidate_ps_added);
    if nargin<4,separate_network=false;end
    if nargin<5,live_flow=false;end
    if nargin<6,external_lag=false;end
    assert(islogical(external_lag) && isscalar(external_lag) && (~external_lag || live_flow));
    assert(islogical(live_flow) && isscalar(live_flow) && (~live_flow || separate_network));
    assert(islogical(separate_network) && isscalar(separate_network));
    root=fullfile(repo,'outputs_storage_audit');
    qualified=fullfile(root,'ps_controller_pair_audit_20260909','controller_pair_audit.json');
    assert(strcmp(file_hash(qualified),'B0B7A15859E885325B9317722BA0B4A222226F9805DFA6AC69AF98D7C8A68C4C'));
    reference_path=fullfile(root,'sma_derivative_contract_20260909_v3','sma_derivative_contract.json');
    assert(strcmp(file_hash(reference_path),'EE5C16D580693FCA925D24D0DB2A8E021BAC65E36F0A77A8E12AE795070ACEE2'));
    r=jsondecode(fileread(reference_path));
    audit_path=fullfile(root,'initial_flux_pressure_audit_20260909_v2','initial_flux_pressure_audit.json');
    assert(strcmp(file_hash(audit_path),'25BD6933EF469E29F77474659B0D8F74027B890D8E3B80910660559E9CA50B4D'));
    a=jsondecode(fileread(audit_path));assert(a.strict_initial_coordinate_match && a.constraints.initial_flux_pressure_consistency_pass);
    trial=fullfile(root,'specific_inventory_projection_initial_flux_20260909');
    evidence=jsondecode(fileread(fullfile(trial,'compiled_states_inspection.json')));raw=fullfile(trial,'observations.mat');
    assert(evidence.inspection_pass && strcmp(file_hash(raw),evidence.observations_sha256));
    data=load(raw,'signals');signal=data.signals.mass_flow_sma_stage13_kgps;
    assert(isscalar(signal.time_s) && signal.time_s==0 && isscalar(signal.values) && ...
        isfinite(signal.values) && signal.values==a.measured_flow_signal_initial_kg_s);
    source=fullfile(repo,'verification','simscape_sma_controller','+ecc_sma_controller','pressure_controller.ssc');
    source_hash=file_hash(source);assert(strcmp(source_hash,'EB6AC72398E21E9069674744E1F1ECE1D8133E4729D23E42FDE3AC5C332AEA71'));
    build=fullfile(root,'ps_controller_equivalence_20260909_v2','component_build');
    assert(strcmp(file_hash(fullfile(build,'+ecc_sma_controller','pressure_controller.ssc')),source_hash));
    library_name='ecc_sma_controller_lib';hybrid_contract=struct();
    if external_lag
        hp=fullfile(root,'hybrid_controller_equivalence_20260910','hybrid_controller_audit.json');
        assert(strcmp(file_hash(hp),'E2B9A87B4EA88A33C3376D11F3EE716692F5C8B7F558133E7471142CBF6A4CC9'));
        h=jsondecode(fileread(hp));assert(h.isolated_equivalence_pass && ~h.production_recovery_allowed);
        source=fullfile(repo,'verification','simscape_sma_hybrid','+ecc_sma_hybrid','pressure_controller.ssc');
        source_hash=file_hash(source);assert(strcmp(source_hash,'A5A02F73DA1A197922BA42EB693C1D81CE11C329903D7AF112923C8B4FB9FF79'));
        build=fullfile(root,'hybrid_controller_equivalence_20260910','component_build');library_name='ecc_sma_hybrid_lib';
        assert(strcmp(file_hash(fullfile(build,'+ecc_sma_hybrid','pressure_controller.ssc')),source_hash));
        assert(strcmp(file_hash(fullfile(build,[library_name '.slx'])), ...
            '42A1C93C7130EDCE8D85E0FD21740D81B4EEC0C6BE10A6C1B6021DBD856B4743'));
        hybrid_contract=struct('qualification_path',hp,'qualification_sha256',file_hash(hp));
    end
    addpath(build);library=fullfile(build,[library_name '.slx']);load_system(library);
    lib=find_system(library_name,'SearchDepth',1,'Type','Block');assert(isscalar(lib));
    converter=removal.pressure_converter;
    assert(strcmp(input_source(converter,1),removal.pressure_value_source) && ...
        strcmp(input_source(converter,2),removal.pressure_derivative_source));
    before=destinations(converter);observer=[model '/ColdSMAPassiveObserver'];add_block(lib{1},observer);
    names={'target','enable','reset'};units={'kg/s','1','1'};
    for k=1:3
        c=r.commands(k+1);v=slResolve(c.variable,c.block);
        assert(isequal(v.Time(:),c.time_s(:)) && isequal(v.Data(:),c.values(:)));
        if external_lag && k==1,continue;end
        ps=[model '/ColdObserver_' names{k} '_PS'];
        add_block('nesl_utility/Simulink-PS Converter',ps,'Unit',units{k},'UdotUserProvided','1');
        assert(strcmp(get_param(ps,'FilteringAndDerivatives'),'provide'));
        wire(model,c.block,1,ps,1);d=zeros(size(c.values(:)));
        if strcmp(c.interpolate,'on'),d=[diff(c.values(:))./diff(c.time_s(:));0];end
        variable=['cold_observer_' names{k} '_derivative'];assignin('base',variable,timeseries(d,c.time_s(:)));
        db=[ps '_Derivative'];add_block('simulink/Sources/From Workspace',db,'VariableName',variable, ...
            'Interpolate','off','OutputAfterFinalValue','Holding final value');wire(model,db,1,ps,2);
        simscape.addConnection(ps,only_port(ps),observer,names{k});
    end
    mdot=[model '/ColdObserver_mdot_PS'];constant=[mdot '_Value'];zero=[mdot '_Derivative'];
    flow_source=constant;flow_mode='frozen_initial';flow_derivatives='1';
    observer_input='mdot';
    if external_lag
        flow_mode='live_external_lag';flow_derivatives='0';flow_unit='1';observer_input='lag_input';
        sum_block=[model '/ColdObserver_ErrorSum'];norm_block=[model '/ColdObserver_ErrorNormalizer'];
        flow_source=[model '/ColdObserver_ErrorLag'];
        add_block('simulink/Math Operations/Sum',sum_block,'Inputs','++');
        add_block('simulink/Math Operations/Gain',norm_block,'Gain','1');
        add_block('simulink/Continuous/Transfer Fcn',flow_source,'Numerator','1','Denominator','[.002 1]');
        wire(model,r.commands(2).block,1,sum_block,1);
        wire(model,[model '/FlowSensor_SMA_stage13_loop_PS'],1,sum_block,2);
        wire(model,sum_block,1,norm_block,1);wire(model,norm_block,1,flow_source,1);
        add_block('nesl_utility/Simulink-PS Converter',mdot,'Unit',flow_unit,'FilteringAndDerivatives','provide','UdotUserProvided','0');
        wire(model,flow_source,1,mdot,1);
        hybrid_contract.lag_path=flow_source;hybrid_contract.lag_numerator=get_param(flow_source,'Numerator');
        hybrid_contract.lag_denominator=get_param(flow_source,'Denominator');hybrid_contract.normalization=get_param(norm_block,'Gain');
        hybrid_contract.additional_lag_state_added=false;hybrid_contract.original_internal_lag_removed=true;
    elseif live_flow
        flow_source=[model '/FlowSensor_SMA_stage13_loop_PS'];flow_mode='live_simulink_bridge';flow_derivatives='0';
        assert(strcmp(get_param(flow_source,'Unit'),'kg/s'));
        add_block('nesl_utility/Simulink-PS Converter',mdot,'Unit','kg/s','FilteringAndDerivatives','provide','UdotUserProvided','0');
        wire(model,flow_source,1,mdot,1);
    else
        add_block('nesl_utility/Simulink-PS Converter',mdot,'Unit','kg/s','UdotUserProvided','1');
        add_block('simulink/Sources/Constant',constant,'Value',num2str(signal.values,17));
        add_block('simulink/Sources/Constant',zero,'Value','0');
        wire(model,constant,1,mdot,1);wire(model,zero,1,mdot,2);
    end
    simscape.addConnection(mdot,only_port(mdot),observer,observer_input);
    solver_contract=struct();bias_driver=converter;
    if separate_network
        bias_driver=[model '/ColdObserver_bias_PS'];
        add_block('nesl_utility/Simulink-PS Converter',bias_driver,'Unit','MPa','UdotUserProvided','1');
        wire(model,removal.pressure_value_source,1,bias_driver,1);
        wire(model,removal.pressure_derivative_source,1,bias_driver,2);
        solvers=find_system(model,'LookUnderMasks','all','FollowLinks','on','MaskType','Solver Configuration');
        assert(isscalar(solvers));isolated=[model '/ColdObserver_Solver'];add_block(solvers{1},isolated);
        parameters=fieldnames(get_param(solvers{1},'DialogParameters'));settings=struct();
        for k=1:numel(parameters)
            settings.(parameters{k})=get_param(solvers{1},parameters{k});
            assert(isequal(get_param(isolated,parameters{k}),settings.(parameters{k})));
        end
        simscape.addConnection(observer,observer_input,isolated,only_port(isolated));
        solver_contract=struct('original_path',solvers{1},'observer_path',isolated,'settings',settings,'copied_settings_identical',true);
    end
    simscape.addConnection(bias_driver,only_port(bias_driver),observer,'bias');
    outputs={'pressure','lag','integral'};output_units={'MPa','1','MPa'};
    for k=1:3
        out=[model '/ColdObserver_' outputs{k} '_Output'];
        add_block('nesl_utility/PS-Simulink Converter',out,'Unit',output_units{k});
        simscape.addConnection(observer,outputs{k},out,only_port(out));
        logger=[out '_Log'];add_block('simulink/Sinks/To Workspace',logger, ...
            'VariableName',['cold_observer_' outputs{k}],'SaveFormat','Timeseries');wire(model,out,1,logger,1);
    end
    after=destinations(converter);
    expected=before;if ~separate_network,expected=[before;{observer}];end
    assert(isequal(sort(after),sort(expected)) && ...
        strcmp(input_source(converter,1),removal.pressure_value_source) && ...
        strcmp(input_source(converter,2),removal.pressure_derivative_source),'Pressure actuator path changed.');
    contract=struct('schema','heatdrive_ecc_cold_passive_ps_observer_v1','observer_path',observer, ...
        'component_sha256',source_hash,'library_path',library,'library_sha256',file_hash(library), ...
        'qualification_sha256',file_hash(qualified),'reference_sha256',file_hash(reference_path), ...
        'flow_audit_path',audit_path,'flow_audit_sha256',file_hash(audit_path), ...
        'flow_observations_path',raw,'flow_observations_sha256',file_hash(raw),'frozen_mdot_kg_s',signal.values, ...
        'commands',r.commands,'pressure_converter',converter,'pressure_value_source',removal.pressure_value_source, ...
        'pressure_derivative_source',removal.pressure_derivative_source,'pressure_destinations_before',{before}, ...
        'pressure_destinations_after',{after},'observer_drives_pump',false,'separate_solver_added',separate_network, ...
        'observer_bias_driver',bias_driver,'observer_solver_contract',solver_contract, ...
        'flow_input_mode',flow_mode,'flow_value_source',flow_source,'provided_flow_derivatives',flow_derivatives, ...
        'external_lag',external_lag,'hybrid_contract',hybrid_contract, ...
        'allowed_stop_time_s',0,'production_recovery_allowed',false,'c200_state_imported',false);
end
function rows=destinations(block)
    c=get_param(block,'PortConnectivity');c=c(startsWith({c.Type},{'LConn','RConn'}));assert(isscalar(c));
    rows=arrayfun(@(h) getfullname(get_param(h,'Parent')),c.DstPort(:),'UniformOutput',false);
end
function wire(model,source,si,destination,di)
    s=get_param(source,'PortHandles');d=get_param(destination,'PortHandles');add_line(model,s.Outport(si),d.Inport(di));
end
function source=input_source(block,index)
    p=get_param(block,'PortHandles');line=get_param(p.Inport(index),'Line');assert(line>0);source=getfullname(get_param(line,'SrcBlockHandle'));
end
function name=only_port(block)
    p=simscape.connectionPortProperties(block);assert(isscalar(p));name=p.Name;
end
function hash=file_hash(file)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
