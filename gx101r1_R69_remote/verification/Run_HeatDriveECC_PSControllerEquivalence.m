function record=Run_HeatDriveECC_PSControllerEquivalence(repo,output_root,gate_reference_reset,external_lag)
% Isolated paired controller test, not a coupled-device or recovery test.
    if nargin<3,gate_reference_reset=false;end
    if nargin<4,external_lag=false;end
    assert(islogical(external_lag) && isscalar(external_lag) && (~external_lag || ~gate_reference_reset), ...
        'External-lag representation must be compared to the unchanged reference.');
    assert(islogical(gate_reference_reset) && isscalar(gate_reference_reset));
    assert(~isfolder(output_root),'Do not overwrite paired evidence.');
    [code,dirty]=system(sprintf('git -C "%s" status --porcelain -- .',repo));assert(code==0 && isempty(strtrim(dirty)),'Commit source first.');
    [code,commit]=system('git rev-parse HEAD');assert(code==0);
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));dc=onCleanup(@() diary('off'));
    old=pwd;oldpath=path;pc=onCleanup(@() restore(old,oldpath));
    generation=Simulink.fileGenControl('getConfig');gc=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'cache'),'CodeGenFolder',fullfile(output_root,'codegen'),'createDir',true);
    record=struct('schema','heatdrive_ecc_ps_controller_equivalence_v1','execution_commit',strtrim(commit), ...
        'collection_pass',false,'equivalence_pass',false,'coupled_model_tested',false, ...
        'production_recovery_allowed',false,'error_message','');
    record.reference_input_gated_during_reset=gate_reference_reset;
    record.external_lag_requested=external_lag;
    try
        source=fullfile(repo,'outputs_storage_audit','sma_derivative_contract_20260909_v3','sma_derivative_contract.json');
        record.controller_contract_sha256=file_hash(source);
        assert(strcmp(record.controller_contract_sha256,'EE5C16D580693FCA925D24D0DB2A8E021BAC65E36F0A77A8E12AE795070ACEE2'));
        r=jsondecode(fileread(source));
        package='ecc_sma_controller';folder='simscape_sma_controller';
        if external_lag,package='ecc_sma_hybrid';folder='simscape_sma_hybrid';end
        component=fullfile(repo,'verification',folder,['+' package],'pressure_controller.ssc');
        record.component_sha256=file_hash(component);
        build=fullfile(output_root,'component_build');mkdir(build);copyfile(fileparts(component),fullfile(build,['+' package]));
        cd(build);ssc_build(package);addpath(build);load_system([package '_lib']);cd(repo);
        lib=find_system([package '_lib'],'SearchDepth',1,'Type','Block');assert(isscalar(lib));
        model='ecc_sma_controller_equivalence';assert(~bdIsLoaded(model));new_system(model);mc=onCleanup(@() close_system(model,0));
        set_param(model,'Solver','ode15s','SolverType','Variable-step','MaxStep','.001','RelTol','1e-9','AbsTol','1e-11', ...
            'StopTime','10','ReturnWorkspaceOutputs','on','AlgebraicLoopMsg','error','SaveTime','off','SaveOutput','off');
        candidate=[model '/Candidate'];add_block(lib{1},candidate);
        solver=[model '/Solver'];add_block('nesl_utility/Solver Configuration',solver,'UseLocalSolver','off');
        names={'mdot','target','bias','enable','reset'};units={'kg/s','kg/s','MPa','1','1'};
        mapping=[0,2,1,3,4];commands=cell2struct(cell(1,numel(names)),names,2);
        for k=1:numel(names)
            if k==1
                t=[0,.15,.8,1,2,3,4,4.8,5,5.15,6,7,8,9,10].';
                v=[0,0,-.0508,-.3,-.3,.3,.3,0,0,0,-.3,-.3,.3,.3,0].';mode='on';
            else
                c=r.commands(mapping(k));t=c.time_s(:);v=c.values(:);mode=c.interpolate;
            end
            commands.(names{k})=struct('time_s',t,'values',v,'interpolate',mode);
            variable=['controller_test_' names{k}];assignin('base',variable,timeseries(v,t));
            b=[model '/' names{k}];add_block('simulink/Sources/From Workspace',b,'VariableName',variable, ...
                'Interpolate',mode,'OutputAfterFinalValue','Holding final value');
            if external_lag && any(strcmp(names{k},{'mdot','target'})),continue;end
            ps=[model '/' names{k} '_PS'];add_block('nesl_utility/Simulink-PS Converter',ps,'Unit',units{k},'UdotUserProvided','1');
            wire(model,b,1,ps,1);d=zeros(size(v));if strcmp(mode,'on'),d=[diff(v)./diff(t);0];end
            derivative_variable=[variable '_derivative'];assignin('base',derivative_variable,timeseries(d,t));db=[b '_derivative'];
            add_block('simulink/Sources/From Workspace',db,'VariableName',derivative_variable, ...
                'Interpolate','off','OutputAfterFinalValue','Holding final value');wire(model,db,1,ps,2);
            simscape.addConnection(ps,only_port(ps),candidate,names{k});
        end
        solver_port='mdot';if external_lag,solver_port='lag_input';end
        simscape.addConnection(candidate,solver_port,solver,only_port(solver));
        add_block('simulink/Math Operations/Sum',[model '/Error'],'Inputs','++');
        wire(model,[model '/target'],1,[model '/Error'],1);wire(model,[model '/mdot'],1,[model '/Error'],2);
        add_block('simulink/Continuous/Transfer Fcn',[model '/Lag'],'Numerator','1','Denominator','[.002 1]');
        wire(model,[model '/Error'],1,[model '/Lag'],1);
        if external_lag
            % A separate state avoids making the equivalence test share reference memory.
            lag=[model '/CandidateLag'];ps=[model '/CandidateLagPS'];
            add_block('simulink/Continuous/Transfer Fcn',lag,'Numerator','1','Denominator','[.002 1]');
            wire(model,[model '/Error'],1,lag,1);
            add_block('nesl_utility/Simulink-PS Converter',ps,'Unit','1', ...
                'FilteringAndDerivatives','provide','UdotUserProvided','0');
            wire(model,lag,1,ps,1);simscape.addConnection(ps,only_port(ps),candidate,'lag_input');
            record.external_lag_contract=struct('candidate_path',lag,'reference_path',[model '/Lag'], ...
                'numerator',get_param(lag,'Numerator'),'denominator',get_param(lag,'Denominator'), ...
                'same_reference_state_used',false,'additional_lag_state_added',false, ...
                'converter_filtering',get_param(ps,'FilteringAndDerivatives'), ...
                'provided_derivatives',get_param(ps,'UdotUserProvided'));
        end
        add_block('simulink/Math Operations/Gain',[model '/Kp'],'Gain','-.6');wire(model,[model '/Lag'],1,[model '/Kp'],1);
        add_block('simulink/Math Operations/Gain',[model '/Ki'],'Gain','-10');wire(model,[model '/Lag'],1,[model '/Ki'],1);
        add_block('simulink/Math Operations/Product',[model '/EnabledP'],'Inputs','**');
        wire(model,[model '/Kp'],1,[model '/EnabledP'],1);wire(model,[model '/enable'],1,[model '/EnabledP'],2);
        add_block('simulink/Continuous/Integrator',[model '/Integral'],'ExternalReset','level','InitialCondition','0', ...
            'LimitOutput','on','LowerSaturationLimit','-.14733718599999998','UpperSaturationLimit','.1');
        if gate_reference_reset
            assert(isequal(commands.enable.time_s,commands.reset.time_s) && ...
                all(commands.enable.values+commands.reset.values==1),'Enable must be the exact reset complement.');
            add_block('simulink/Math Operations/Product',[model '/IntegralInputGate'],'Inputs','**');
            wire(model,[model '/Ki'],1,[model '/IntegralInputGate'],1);wire(model,[model '/enable'],1,[model '/IntegralInputGate'],2);
            wire(model,[model '/IntegralInputGate'],1,[model '/Integral'],1);
        else
            wire(model,[model '/Ki'],1,[model '/Integral'],1);
        end
        wire(model,[model '/reset'],1,[model '/Integral'],2);
        add_block('simulink/Math Operations/Sum',[model '/RawPressure'],'Inputs','+++');
        wire(model,[model '/EnabledP'],1,[model '/RawPressure'],1);wire(model,[model '/Integral'],1,[model '/RawPressure'],2);
        wire(model,[model '/bias'],1,[model '/RawPressure'],3);
        add_block('simulink/Discontinuities/Saturation',[model '/Pressure'],'LowerLimit','-.35','UpperLimit','.02');
        wire(model,[model '/RawPressure'],1,[model '/Pressure'],1);
        outputs={'pressure','lag','integral'};output_units={'MPa','1','MPa'};reference={'Pressure','Lag','Integral'};
        add_block('simulink/Signal Routing/Mux',[model '/Observations'],'Inputs','6');
        for k=1:3
            converter=[model '/' outputs{k} '_output'];add_block('nesl_utility/PS-Simulink Converter',converter,'Unit',output_units{k});
            simscape.addConnection(candidate,outputs{k},converter,only_port(converter));
            wire(model,[model '/' reference{k}],1,[model '/Observations'],k);
            wire(model,converter,1,[model '/Observations'],k+3);
        end
        add_block('simulink/Sinks/To Workspace',[model '/SaveObservations'],'VariableName','observations','SaveFormat','Timeseries','MaxDataPoints','inf');
        wire(model,[model '/Observations'],1,[model '/SaveObservations'],1);
        save_system(model,fullfile(output_root,[model '.slx']));
        input=Simulink.SimulationInput(model);input=input.setModelParameter('CaptureErrors','on');started=tic;output=sim(input);
        record.simulation_wall_seconds=toc(started);
        record.simulation_error=output.ErrorMessage;assert(isempty(output.ErrorMessage),output.ErrorMessage);
        observations=output.get('observations');assert(observations.Time(1)==0 && observations.Time(end)==10);
        record.sample_count=numel(observations.Time);
        data=observations.Data;assert(size(data,2)==6 && all(isfinite(data),'all'));
        differences=abs(data(:,1:3)-data(:,4:6));record.maximum_absolute_errors=max(differences,[],1);
        record.comparison_limits=[1e-7,1e-7,1e-7];record.equivalence_pass=all(record.maximum_absolute_errors<=record.comparison_limits);
        save(fullfile(output_root,'paired_observations.mat'),'observations','commands','-v7.3');
        record.observations_sha256=file_hash(fullfile(output_root,'paired_observations.mat'));
        if external_lag
            time_s=observations.Time;values=observations.Data;source_sha256=record.observations_sha256; %#ok<NASGU>
            save(fullfile(output_root,'paired_public_traces.mat'),'time_s','values','source_sha256','-v7.3');
            record.public_traces_sha256=file_hash(fullfile(output_root,'paired_public_traces.mat'));
        end
        record.collection_pass=true;clear mc
    catch ME
        record.error_message=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'controller_equivalence.json'),'w','n','UTF-8');assert(fid>=0);fc=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(record));
    assert(record.collection_pass && record.equivalence_pass,'Isolated controller qualification failed.');
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
function restore(folder,oldpath)
    cd(folder);path(oldpath);
end
