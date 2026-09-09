function contract=Configure_HeatDriveECC_ColdPressureDerivative(repo,model)
% Add only an observed derivative branch; leave original PI state/value paths.
    duration=str2double(get_param(model,'StopTime'));
    assert(strcmp(get_param(model,'StartTime'),'0') && ismember(duration,[0,.2]) && ...
        strcmp(get_param(model,'LoadInitialState'),'off') && strcmp(get_param(model,'SaveOperatingPoint'),'off'), ...
        'Only the declared independent cold initial/onset diagnostic is allowed.');
    source=fullfile(repo,'outputs_storage_audit','sma_derivative_contract_20260909_v3','sma_derivative_contract.json');
    kernel=fullfile(repo,'verification','Evaluate_HeatDriveECC_SMADerivative.m');
    tests=fullfile(repo,'outputs_storage_audit','sma_derivative_kernel_20260909','kernel_tests.json');
    assert(strcmp(file_hash(source),'EE5C16D580693FCA925D24D0DB2A8E021BAC65E36F0A77A8E12AE795070ACEE2') && ...
        strcmp(file_hash(kernel),'113A46F15A8B653867A5E1950DF934EA32D166DF6481EA25D519F8E8E33D161C') && ...
        strcmp(file_hash(tests),'CD75BF50CDFAF05B8D5713F90CB27889E07DA816DEAA8EF344D64BF94BE0F6F6'), ...
        'Derivative prerequisite changed.');
    reference=jsondecode(fileread(source));
    for k=1:numel(reference.blocks)
        b=reference.blocks(k);names=fieldnames(b.settings);
        for j=1:numel(names)
            assert(isequal(get_param(b.path,names{j}),b.settings.(names{j})),'Original controller configuration changed.');
        end
        names=fieldnames(b.resolved);
        for j=1:numel(names)
            current=slResolve(b.settings.(names{j}),b.path);expected=b.resolved.(names{j});
            assert(isequal(current(:),expected(:)),'Resolved controller coefficient changed.');
        end
        for j=1:numel(b.inputs)
            assert(strcmp(input_source(b.path,j),b.inputs(j).source_block),'Original controller wiring changed.');
        end
    end
    for k=1:numel(reference.commands)
        c=reference.commands(k);v=slResolve(c.variable,c.block);
        assert(isequal(v.Time(:),c.time_s(:)) && isequal(v.Data(:),c.values(:)), ...
            'Original full-cycle command values changed.');
    end
    c=reference.commands(1);t=c.time_s(:);bias=c.values(:);
    slopes=[diff(bias)./diff(t);0];
    assignin('base','cold_sma_bias_derivative_command',timeseries(slopes,t));
    slope_block=[model '/ColdSMABiasDerivativeFromWorkspace'];
    add_block('simulink/Sources/From Workspace',slope_block,'VariableName','cold_sma_bias_derivative_command', ...
        'Interpolate','off','OutputAfterFinalValue','Holding final value');
    sources={'SMAPressurePI_ErrorNormalizer','SMAPressurePI_ErrorLag','SMAPressurePI_Integrator', ...
        'SMAPressureFeedbackEnableFromWorkspace','SMAPressureFeedbackResetFromWorkspace', ...
        'SMAPressureBiasFromWorkspace','ColdSMABiasDerivativeFromWorkspace'};
    mux=[model '/ColdPressureDerivativeInputs'];add_block('simulink/Signal Routing/Mux',mux,'Inputs','7');
    ports=get_param(mux,'PortHandles');
    for k=1:numel(sources)
        p=get_param([model '/' sources{k}],'PortHandles');add_line(model,p.Outport(1),ports.Inport(k));
    end
    derivative=[model '/ColdPressureDerivative'];
    add_block('simulink/User-Defined Functions/MATLAB Function',derivative);
    chart=find(sfroot,'-isa','Stateflow.EMChart','Path',derivative);assert(isscalar(chart),'Missing derivative chart.');
    parameters=[.002,-.6,-10,-.14733718599999998,.1,-.35,.02];
    script=sprintf(['function [dp,debug]=fcn(u)\n', ...
        'parameters=%s;\n', ...
        '[dp,p,dx,di]=Evaluate_HeatDriveECC_SMADerivative(u(1),u(2),u(3),u(4),u(5),u(6),u(7),parameters);\n', ...
        'debug=[u(:);dp;p;dx;di];\nend\n'],mat2str(parameters,17));
    chart.Script=script;p=get_param(derivative,'PortHandles');add_line(model,ports.Outport(1),p.Inport(1));
    converter=[model '/SMAPressurePI_SimulinkPS'];value_source=input_source(converter,1);
    set_param(converter,'UdotUserProvided','1');ports=get_param(converter,'PortHandles');
    assert(numel(ports.Inport)==2,'Need exactly value and first derivative inputs.');
    add_line(model,p.Outport(1),ports.Inport(2));
    sink=[model '/ColdPressureDerivativeObservations'];
    add_block('simulink/Sinks/To Workspace',sink,'VariableName','cold_pressure_derivative_observations', ...
        'SaveFormat','Timeseries','MaxDataPoints','inf','SampleTime','-1');
    ports=get_param(sink,'PortHandles');add_line(model,p.Outport(2),ports.Inport(1));
    assert(strcmp(input_source(converter,1),value_source) && strcmp(input_source(converter,2),derivative), ...
        'Pressure value path must remain unchanged.');
    contract=struct('schema','heatdrive_ecc_cold_pressure_derivative_adapter_v1', ...
        'stop_time_s',duration,'original_controller_contract_sha256',file_hash(source),'kernel_sha256',file_hash(kernel), ...
        'kernel_tests_sha256',file_hash(tests),'parameters',parameters,'sources',{sources}, ...
        'bias_derivative_time_s',t,'bias_derivative_values_MPa_s',slopes,'chart_script',script, ...
        'value_source',value_source,'derivative_source',derivative,'original_value_path_retained',true, ...
        'new_filter_added',false,'original_controller_state_retained',true, ...
        'production_recovery_allowed',false,'event_handling_verified',false);
end

function source=input_source(block,index)
    p=get_param(block,'PortHandles');line=get_param(p.Inport(index),'Line');assert(line~=-1,'Missing original input.');
    source=getfullname(get_param(line,'SrcBlockHandle'));
end

function hash=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0,'Missing prerequisite.');c=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
