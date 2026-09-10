function record=Probe_HeatDriveECC_PreFeedbackBridge(repo,out,remove_reference_reset,derivative_consumer)
% Replay qualified controller with a separate unfiltered pressure bridge.
    if nargin<3,remove_reference_reset=false;end
    if nargin<4,derivative_consumer=false;end
    assert(~derivative_consumer || remove_reference_reset);
    assert(~isfolder(out));mkdir(out);
    source=fullfile(repo,'outputs_storage_audit','hybrid_controller_equivalence_20260910');
    oldpath=path;pc=onCleanup(@() path(oldpath));addpath(fullfile(source,'component_build'));
    old=pwd;wc=onCleanup(@() cd(old));build=fullfile(out,'component_build');mkdir(build);
    copyfile(fullfile(repo,'verification','simscape_bridge_probe','+ecc_bridge_probe'), ...
        fullfile(build,'+ecc_bridge_probe'));
    cd(build);ssc_build('ecc_bridge_probe');addpath(build);cd(repo);
    load_system('ecc_bridge_probe_lib');
    blocks=find_system('ecc_bridge_probe_lib','SearchDepth',1,'Type','Block');
    component='ecc_bridge_probe.pressure_integral';
    if derivative_consumer,component='ecc_bridge_probe.pressure_derivative';end
    blocks=blocks(cellfun(@(b) strcmp(get_param(b,'SourceFile'),component),blocks));assert(isscalar(blocks));
    d=load(fullfile(source,'paired_observations.mat'),'commands');names=fieldnames(d.commands);
    for k=1:numel(names)
        c=d.commands.(names{k});variable=['controller_test_' names{k}];
        assignin('base',variable,timeseries(c.values,c.time_s));
        slope=zeros(size(c.values));
        if strcmp(c.interpolate,'on'),slope=[diff(c.values)./diff(c.time_s);0];end
        assignin('base',[variable '_derivative'],timeseries(slope,c.time_s));
    end
    model='ecc_sma_controller_equivalence';assert(~bdIsLoaded(model));
    load_system(fullfile(source,[model '.slx']));mc=onCleanup(@() close_system(model,0));
    if remove_reference_reset
        reset=d.commands.reset;enable=d.commands.enable;
        assert(all(reset.values(reset.time_s<=.14)==1) && ...
            all(enable.values(enable.time_s<=.14)==0));
        assert(reset.time_s(find(reset.values~=1,1))>.14);
        block=[model '/Integral'];p=get_param(block,'PortHandles');
        line=get_param(p.Outport(1),'Line');destinations=get_param(line,'DstPortHandle');
        position=get_param(block,'Position');delete_block(block);
        add_block('simulink/Sources/Constant',block,'Value','0','Position',position);
        p=get_param(block,'PortHandles');
        for k=1:numel(destinations)
            oldline=get_param(destinations(k),'Line');
            if oldline~=-1,delete_line(oldline);end
        end
        for k=1:numel(destinations),add_line(model,p.Outport(1),destinations(k));end
    end
    set_param(model,'Solver','ode23t','MaxStep','0.00001','RelTol','1e-6','AbsTol','1e-8', ...
        'StopTime','0.14','MinStepSizeMsg','error','MaxConsecutiveMinStep','1');
    bridge=[model '/PressureBridge'];
    add_block('nesl_utility/Simulink-PS Converter',bridge,'Unit','MPa', ...
        'FilteringAndDerivatives','provide','UdotUserProvided','1');
    add_line(model,'pressure_output/1','PressureBridge/1');
    add_line(model,'bias_derivative/1','PressureBridge/2');
    consumer=[model '/IntegralConsumer'];add_block(blocks{1},consumer);
    output_unit='MPa*s';output_port='q';
    if derivative_consumer,output_unit='MPa/s';output_port='dp';end
    sink=[model '/BridgeOutput'];add_block('nesl_utility/PS-Simulink Converter',sink,'Unit',output_unit);
    solver=[model '/BridgeSolver'];add_block([model '/Solver'],solver);
    simscape.addConnection(bridge,port(bridge),consumer,'p');
    simscape.addConnection(consumer,output_port,sink,port(sink));
    simscape.addConnection(bridge,port(bridge),solver,port(solver));
    add_block('simulink/Sinks/To Workspace',[model '/BridgeLog'], ...
        'VariableName','bridge_pressure','SaveFormat','Timeseries','MaxDataPoints','inf');
    add_line(model,'BridgeOutput/1','BridgeLog/1');
    input=Simulink.SimulationInput(model);input=input.setModelParameter('CaptureErrors','on');
    output=sim(input);record=struct('simulation_error',output.ErrorMessage, ...
        'full_fluid_network_tested',false,'production_recovery_allowed',false,'bridge_pass',false);
    record.reference_level_reset_removed=remove_reference_reset;
    record.derivative_consumer=derivative_consumer;
    if isempty(output.ErrorMessage)
        observations=output.get('observations');bridge_pressure=output.get('bridge_pressure');
        c=d.commands.bias;slope=diff(c.values)./diff(c.time_s);first=find(slope~=0,1);
        t=bridge_pressure.Time;expected=c.values(1)*t+.5*slope(first)*max(t-c.time_s(first),0).^2;
        record.last_time_s=bridge_pressure.Time(end);record.samples=numel(bridge_pressure.Time);
        record.max_integral_error_MPa_s=max(abs(bridge_pressure.Data(:)-expected(:)));
        record.max_controller_pair_error_MPa=max(abs(observations.Data(:,1)-observations.Data(:,4)));
        record.bridge_pass=record.last_time_s==.14 && all(isfinite(bridge_pressure.Data),'all') && ...
            record.max_integral_error_MPa_s<=1e-7 && record.max_controller_pair_error_MPa<=1e-7;
        record.diagnostic_integrator_added_only_to_fixture=true;
        record.pressure_derivative_consumption_verified=false;
        if derivative_consumer
            record=rmfield(record,'max_integral_error_MPa_s');
            expected_dp=zeros(size(t));expected_dp(t>c.time_s(first))=slope(first);
            away=abs(t-c.time_s(first))>1e-12;
            record.excluded_event_samples=sum(~away);
            record.max_derivative_error_MPa_s=max(abs(bridge_pressure.Data(away)-expected_dp(away)));
            record.bridge_pass=record.last_time_s==.14 && ...
                all(isfinite(bridge_pressure.Data),'all') && record.max_derivative_error_MPa_s<=1e-10 && ...
                record.max_controller_pair_error_MPa<=1e-7;
            record.diagnostic_integrator_added_only_to_fixture=false;
            record.pressure_derivative_consumption_verified=record.bridge_pass;
            record.exact_event_side_verified=false;
        end
        save(fullfile(out,'bridge_observations.mat'),'observations','bridge_pressure','-v7.3');
    end
    fid=fopen(fullfile(out,'bridge_probe.json'),'w','n','UTF-8');assert(fid>=0);
    fc=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(record,PrettyPrint=true));clear fc
    disp(jsonencode(record));assert(record.bridge_pass,'Isolated bridge failed.');
end

function name=port(block)
    p=simscape.connectionPortProperties(block);assert(isscalar(p));name=p.Name;
end
