function record=Verify_HeatDriveECC_SplitObservation(input,source_op,options,folder,chambers,buffers,settings,request,producer)
% Compare a real two-cycle run with a qualified disk split, keeping all model settings.
    root=fullfile(folder,'split_observation');assert(~isfolder(root),'Never overwrite split evidence.');mkdir(root);
    model=input.ModelName;start=source_op.snapshotTime;middle=start+10;stop=start+20;
    contract=jsondecode(fileread(request.source_contract_path));
    source=fullfile(contract.execution_repo,contract.source_root_relative);
    source_file=fullfile(source,contract.operating_point_relative);
    history_file=fullfile(source,contract.history_relative);
    assert(start==contract.snapshot_time_s && start==620 && ...
        strcmp(file_hash(source_file),contract.operating_point_sha256) && ...
        strcmp(file_hash(history_file),contract.history_sha256),'Require intact current C62.');
    native_history=get_param(model,'SimscapeLogDataHistory');
    state_history=get_param(model,'MaxDataPoints');
    write_json(fullfile(root,'actual_observation_settings.json'),struct( ...
        'native_history_raw',native_history,'native_history_class',class(native_history), ...
        'state_history_raw',state_history,'state_history_class',class(state_history), ...
        'native_history_points',Resolve_HeatDriveECC_ObservationCount(native_history), ...
        'state_history_points',Resolve_HeatDriveECC_ObservationCount(state_history), ...
        'settings_changed',false));
    assert(strcmp(get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'SimscapeLogLimitData'),'on') && ...
        Resolve_HeatDriveECC_ObservationCount(native_history)==20002 && ...
        Resolve_HeatDriveECC_ObservationCount(state_history)==110002 && settings.history_cycles==11 && ...
        strcmp(get_param(model,'SaveOperatingPoint'),'on'),'Do not alter checkpoint-bound observation settings.');
    record=struct('schema','heatdrive_ecc_split_observation_preflight_v1','producer',producer, ...
        'source_root',source,'source_operating_point_sha256',contract.operating_point_sha256, ...
        'source_history_sha256',contract.history_sha256,'full_window_s',[start stop], ...
        'split_time_s',middle,'history_cap_cycles',2,'state_history_cap_cycles',11, ...
        'checksum_policy','error/error','pass',false,'completed_packets',{{}}, ...
        'source_state_edited',false,'partial_state_restore_used',false, ...
        'physical_parameters_changed',false,'production_recovery_allowed',false, ...
        'outer_solve_eligible',false,'error_message','');
    write_json(fullfile(root,'progress.json'),record);
    try
        reference=packet('reference',source_op,start,stop);
        record.completed_packets{end+1}='reference';write_json(fullfile(root,'progress.json'),record);
        prefix=packet('prefix',source_op,start,middle);
        record.completed_packets{end+1}='prefix';write_json(fullfile(root,'progress.json'),record);
        compare_packet(reference,prefix,fullfile(root,'prefix_comparison.json'));
        prefix_manifest=jsondecode(fileread(fullfile(prefix,'packet_manifest.json')));
        assert(strcmp(file_hash(fullfile(prefix,'comparison_only_complete_op.mat')),prefix_manifest.complete_OP_sha256));
        restored=load(fullfile(root,'prefix','comparison_only_complete_op.mat'), ...
            'diagnostic_operating_point','production_recovery_allowed');
        assert(~restored.production_recovery_allowed && restored.diagnostic_operating_point.snapshotTime==middle);
        suffix=packet('suffix',restored.diagnostic_operating_point,middle,stop);
        record.completed_packets{end+1}='suffix';write_json(fullfile(root,'progress.json'),record);
        compare_packet(reference,suffix,fullfile(root,'suffix_comparison.json'));
        record.pass=true;
        record.complete_two_cycle_split_comparison_pass=true;
        record.final_reference_OP_is_comparison_only=true;
    catch ME
        record.error_message=ME.message;record.error_identifier=ME.identifier;
        record.error_report=getReport(ME,'extended','hyperlinks','off');
        write_json(fullfile(root,'REJECTED_DO_NOT_RESUME.json'),struct( ...
            'reason',ME.message,'failed_comparison_state_may_propagate',false,'production_recovery_allowed',false));
    end
    assert(strcmp(file_hash(source_file),contract.operating_point_sha256) && ...
        strcmp(file_hash(history_file),contract.history_sha256),'Original C62 evidence changed.');
    write_json(fullfile(root,'split_observation_preflight.json'),record);
    fprintf('SPLIT_PREFLIGHT_JSON=%s\n',jsonencode(record));
    assert(record.pass,'HeatDriveECC:SplitObservationFailed', ...
        'Preserve split evidence and diagnose: %s',record.error_message);

    function result=packet(name,initial,a,b)
        destination=fullfile(root,name);mkdir(destination);arm=fullfile(destination,'native');mkdir(arm);
        write_json(fullfile(destination,'simulation_start.json'),struct('window_s',[a b], ...
            'parent_snapshot_s',initial.snapshotTime,'simulation_returned_without_error',false));
        output=sim(input.setModelParameter('StopTime',num2str(b,'%.17g')).setInitialState(initial));
        assert(isempty(output.ErrorMessage),'Actual restored simulation failed: %s',output.ErrorMessage);
        diagnostic_operating_point=output.diagnostic_final_op;production_recovery_allowed=false;
        assert(diagnostic_operating_point.snapshotTime==b && ...
            (isa(diagnostic_operating_point,'Simulink.op.ModelOperatingPoint') || ...
             isa(diagnostic_operating_point,'Simulink.SimulationOperatingPoint')));
        save(fullfile(destination,'comparison_only_complete_op.mat'), ...
            'diagnostic_operating_point','production_recovery_allowed','-v7.3');
        observation=Extract_HeatDriveECC_ObservedStates(output.diagnostic_state_log,10,(b-a)/10);
        save(fullfile(destination,'observed_states.mat'),'observation','-v7.3');
        signals=public_signals(output,a,b);
        [native,~]=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model,false,chambers,buffers);
        [source_traces,boundary_metadata]=Extract_HeatDriveECC_BoundaryTraces(output.simlog,model);
        assert(numel(observation.states)==74 && numel(fieldnames(signals))==201 && ...
            numel(native)==1262 && numel(source_traces)==162,'Incomplete actual packet.');
        save(fullfile(arm,'observations.mat'),'native','source_traces','boundary_metadata','signals','-v7.3');
        for item={'configuration.mat','inventory_metadata.json','tl_connectivity.json', ...
                'thermal_connectivity.json','buffer_replacement_contract.json'}
            copyfile(fullfile(folder,item{1}),fullfile(arm,item{1}));
        end
        physical=Extract_HeatDriveECC_PhysicalLogs(output,options,model,false);
        physical.authority='physical_simscape_to_workspace_logs';physical.legacy_surrogate_used_for_results=false;
        physical.sim_call_count=1;physical.walltime_s=NaN;
        provenance=struct('checkpoint_restart_used',true,'checkpoint_chain_verified',true,'sim_call_count',1);
        view=Make_HeatDriveECC_MechanismWindow(physical,options,provenance,destination);
        mechanism=Validate_HeatDriveECC_EighthRound_Physics(view);
        write_json(fullfile(destination,'mechanism.json'),mechanism);
        manifest=struct('schema','heatdrive_ecc_split_observation_packet_v1','producer',producer, ...
            'window_s',[a b],'source_snapshot_s',initial.snapshotTime,'history_cap_cycles',2, ...
            'state_history_cap_cycles',11,'simulation_returned_without_error',true, ...
            'strict_vendor_restore',true,'source_state_edited',false,'production_recovery_allowed',false, ...
            'complete_OP_sha256',file_hash(fullfile(destination,'comparison_only_complete_op.mat')));
        paths={'native/observations.mat','native/configuration.mat','native/inventory_metadata.json', ...
            'native/tl_connectivity.json','native/thermal_connectivity.json', ...
            'native/buffer_replacement_contract.json','mechanism.json','observed_states.mat'};
        % JSON struct keys cannot contain slashes. Persist path/hash rows, then normalize in Python.
        entries=cell(size(paths));
        for k=1:numel(paths),entries{k}=struct('path',paths{k},'sha256',file_hash(fullfile(destination,paths{k})));end
        manifest.input_files=entries;
        write_json(fullfile(destination,'packet_manifest.json'),manifest);
        clear output physical native source_traces signals observation diagnostic_operating_point
        validator=fullfile(fileparts(mfilename('fullpath')),'Verify_HeatDriveECC_ObservationPacket.py');
        [status,message]=system(sprintf('"%s" "%s" --packet-root "%s"',request.python_executable,validator,destination));
        fid=fopen(fullfile(destination,'packet_gate_stdout.log'),'w','n','UTF-8');assert(fid>=0);
        fprintf(fid,'%s',message);fclose(fid);
        gate_file=fullfile(destination,'packet_gate.json');
        assert(status==0 && isfile(gate_file),'Packet gate failed; inspect %s',destination);
        gate=jsondecode(fileread(gate_file));assert(gate.gate_pass,'A failed packet cannot propagate.');
        result=destination;
    end
end

function compare_packet(reference,candidate,path)
    a=load(fullfile(reference,'observed_states.mat'),'observation');
    b=load(fullfile(candidate,'observed_states.mat'),'observation');
    states=Compare_HeatDriveECC_DiagnosticTraces(a.observation.states,b.observation.states);clear a b
    a=load(fullfile(reference,'native','observations.mat'),'native','source_traces','signals');
    b=load(fullfile(candidate,'native','observations.mat'),'native','source_traces','signals');
    native=Compare_HeatDriveECC_DiagnosticTraces(a.native,b.native);
    sources=Compare_HeatDriveECC_DiagnosticTraces(a.source_traces,b.source_traces);
    public=Compare_HeatDriveECC_DiagnosticTraces(public_traces(a.signals),public_traces(b.signals));
    record=struct('states',states,'native',native,'sources',sources,'public',public, ...
        'pass',states.pass && native.pass && sources.pass && public.pass, ...
        'comparison_scope','same samples; original numerical comparison tolerances, not physical steady tolerances');
    write_json(path,record);assert(record.pass,'HeatDriveECC:SplitTrajectoryMismatch','Actual split trajectory differs.');
end

function traces=public_traces(signals)
    names=fieldnames(signals);traces=cell(size(names));
    for k=1:numel(names)
        row=signals.(names{k});traces{k}=struct('block_path',names{k},'state_name','', ...
            'unit','','time_s',row.time_s,'values',row.values,'channel_count',size(row.values,2));
    end
end

function signals=public_signals(output,start,stop)
    signals=struct();names=output.who;
    for k=1:numel(names)
        value=output.get(names{k});
        if isa(value,'timeseries')
            t=double(value.Time(:));data=value.Data;
            if ~value.IsTimeFirst,data=permute(data,[ndims(data),1:ndims(data)-1]);end
        elseif isstruct(value) && isscalar(value) && isfield(value,'time') && ...
                isfield(value,'signals') && isscalar(value.signals) && isfield(value.signals,'values')
            t=double(value.time(:));data=value.signals.values;
        else
            continue
        end
        data=reshape(double(data),numel(t),[]);selected=t>=start-1e-9 & t<=stop+1e-9;
        time=t(selected);values=data(selected,:);
        assert(numel(time)==round((stop-start)/.001)+1 && all(isfinite(values),'all'));
        signals.(names{k})=struct('time_s',time,'values',values);
    end
end

function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
