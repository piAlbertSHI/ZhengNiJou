function record=Verify_HeatDriveECC_RuntimeHorizon(input,options,folder,chambers,buffers,request,producer)
% Compare future input coverage, always restarting from the original complete OP.
    root=fullfile(folder,'horizon_preflight');progress=fullfile(folder,'horizon_preflight_progress.json');
    assert(~isfolder(root) && ~isfile(progress));
    q=jsondecode(fileread(request.candidate_qualification_path));
    Test_HeatDriveECC_RuntimeTcSource(request.candidate_qualification_path);
    for k=1:numel(q.files),assert(strcmp(file_hash(q.files(k).path),q.files(k).sha256));end
    [source_op,source_manifest]=Load_HeatDriveECC_GatedObservationPacket(q.source_packet_root,true);
    assert(strcmp(source_manifest.complete_OP_sha256,q.operating_point_sha256));
    source=source_op.snapshotTime;model=input.ModelName;
    immutable_options=evalin('base','EIGHTH_ROUND_OPTIONS');
    record=struct('schema','heatdrive_ecc_command_horizon_preflight_v1','producer',producer, ...
        'source_qualification_sha256',file_hash(request.candidate_qualification_path), ...
        'source_OP_sha256',q.operating_point_sha256,'source_snapshot_s',source, ...
        'full_window_s',[source source+20],'short_window_s',[source source+.001], ...
        'stage','preparing','process_pid',feature('getpid'),'pass',false,'old_horizon_cycles',200,'future_horizon_cycles',1000, ...
        'source_state_edited',false,'physical_parameters_changed',false,'checksum_policy','error/error', ...
        'past_old_horizon_crossing_physically_executed',false,'comparison_states_may_propagate',false, ...
        'production_recovery_allowed',false,'error_message','');
    write_json(progress,record);
    try
        recipe=Compare_HeatDriveECC_RuntimeBoundaryRecipe(fullfile(q.source_packet_root,'native','configuration.mat'), ...
            fullfile(folder,'configuration.mat'),fullfile(folder,'horizon_recipe_comparison.json'),'plant_build_options');
        assert(recipe.only_declared_change && recipe.numeric_validation_thresholds_equal);
        [reference,extended,proof]=Build_HeatDriveECC_CommandHorizonPayload(model,options,source,root);
        future_options=immutable_options;future_options.cycle_count=1000;
        future_options.schedule.total_time_s=10000;future_options.simulation.stop_time_s=10000;
        checked=future_options;checked.cycle_count=immutable_options.cycle_count;
        checked.schedule.total_time_s=immutable_options.schedule.total_time_s;
        checked.simulation.stop_time_s=immutable_options.simulation.stop_time_s;assert(isequaln(checked,immutable_options));
        restore=onCleanup(@() Install_HeatDriveECC_HorizonCommands(model,reference,proof,'reference',immutable_options));
        base=input.setVariable('cold_sink_T_init',q.temperature_K);
        assert(~any(ismember({base.Variables.Name},fieldnames(reference))), ...
            'SimulationInput must not shadow the measured command-workspace bindings.');
        names={'reference','extended'};commands={reference,extended};runtime_options={immutable_options,future_options};
        for k=1:2
            record.stage=['short_' names{k}];write_json(progress,record);
            Install_HeatDriveECC_HorizonCommands(model,commands{k},proof,names{k},runtime_options{k});
            result=sim(base.setModelParameter('StopTime',num2str(source+.001,'%.17g')).setInitialState(source_op));
            assert(isempty(result.ErrorMessage),'Strict restored short step failed: %s',result.ErrorMessage);
            destination=fullfile(root,['short_' names{k}]);save_short(result,destination,model,chambers,buffers,source,source+.001);
            clear result
            readback=Check_HeatDriveECC_HorizonBindings(commands{k},proof,names{k},runtime_options{k});
            write_json(fullfile(destination,'resolved_commands.json'),readback);
            Verify_HeatDriveECC_ObservationBoundary(q.source_packet_root,destination);
            assert(isequaln(runtime_options{k},evalin('base','EIGHTH_ROUND_OPTIONS')));
        end
        short=Compare_HeatDriveECC_ObservationPackets(fullfile(root,'short_reference'),fullfile(root,'short_extended'), ...
            fullfile(root,'short_comparison.json'));
        assert(short.pass);record.short_step_comparison_pass=true;write_json(progress,record);
        analysis_options=options;analysis_options.system.Tchex_K=q.temperature_K;
        analysis_options.validation.cold_boundary_audit.prescribed_Tchex_K=q.temperature_K;
        for k=1:2
            record.stage=['full_' names{k}];write_json(progress,record);
            Install_HeatDriveECC_HorizonCommands(model,commands{k},proof,names{k},runtime_options{k});
            case_options=analysis_options;case_options.cycle_count=runtime_options{k}.cycle_count;
            case_options.schedule.total_time_s=runtime_options{k}.schedule.total_time_s;
            case_options.simulation.stop_time_s=runtime_options{k}.simulation.stop_time_s;
            c=struct('schema','heatdrive_ecc_command_horizon_comparison_v1','case',names{k}, ...
                'source_snapshot_s',source,'source_Tc_K',q.temperature_K,'source_horizon_cycles',200, ...
                'future_horizon_cycles',1000,'actual_horizon_cycles',200+800*(k==2), ...
                'runtime_metadata_horizon_cycles',runtime_options{k}.cycle_count, ...
                'source_OP_sha256',q.operating_point_sha256, ...
                'source_qualification_sha256',file_hash(request.candidate_qualification_path), ...
                'prefix_proof_sha256',file_hash(fullfile(root,'command_prefix.json')), ...
                'payload_sha256',proof.payload_sha256,'comparison_only',true,'source_state_edited',false);
            destination=fullfile(root,names{k});
            Collect_HeatDriveECC_ObservationPacket(base,source_op,source,source+20,destination,case_options, ...
                folder,chambers,buffers,producer,request.python_executable,'runtime_horizon_comparison',q.operating_point_sha256,c);
            readback=Check_HeatDriveECC_HorizonBindings(commands{k},proof,names{k},runtime_options{k});
            write_json(fullfile(destination,'resolved_commands.json'),readback);
            Verify_HeatDriveECC_ObservationBoundary(q.source_packet_root,destination);
            assert(isequaln(runtime_options{k},evalin('base','EIGHTH_ROUND_OPTIONS')));
        end
        compared=Compare_HeatDriveECC_ObservationPackets(fullfile(root,'reference'),fullfile(root,'extended'), ...
            fullfile(root,'full_comparison.json'));
        assert(compared.pass && strcmp(file_hash(q.operating_point_path),q.operating_point_sha256));
        record.pass=true;record.stage='completed';record.complete_two_cycle_comparison_pass=true;
        record.prefix_proof_sha256=file_hash(fullfile(root,'command_prefix.json'));
        record.payload_sha256=proof.payload_sha256;
        clear restore
    catch ME
        record.error_message=ME.message;record.error_identifier=ME.identifier;
        record.error_report=getReport(ME,'extended','hyperlinks','off');
        if isfolder(root),write_json(fullfile(root,'REJECTED_DO_NOT_RESUME.json'),struct('reason',ME.message,'states_may_propagate',false));end
    end
    write_json(progress,record);write_json(fullfile(folder,'command_horizon_preflight.json'),record);
    fprintf('COMMAND_HORIZON_PREFLIGHT_JSON=%s\n',jsonencode(record));
    assert(record.pass,'HeatDriveECC:CommandHorizonPreflightFailed','Diagnose preserved command-horizon evidence.');
end

function save_short(output,destination,model,chambers,buffers,a,b)
    mkdir(destination);mkdir(fullfile(destination,'native'));
    observation=Extract_HeatDriveECC_ObservedStates(output.diagnostic_state_log,10,1);
    observation.states=slice(observation.states,a,b);save(fullfile(destination,'observed_states.mat'),'observation','-v7.3');
    [native,~]=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model,false,chambers,buffers);
    [source_traces,boundary_metadata]=Extract_HeatDriveECC_BoundaryTraces(output.simlog,model);
    native=slice(native,a,b);source_traces=slice(source_traces,a,b);signals=struct();names=output.who;
    for k=1:numel(names)
        value=output.get(names{k});
        if isa(value,'timeseries')
            t=double(value.Time(:));data=value.Data;if ~value.IsTimeFirst,data=permute(data,[ndims(data),1:ndims(data)-1]);end
        elseif isstruct(value) && isscalar(value) && isfield(value,'time') && isfield(value,'signals') && isscalar(value.signals)
            t=double(value.time(:));data=value.signals.values;
        else,continue;end
        data=reshape(double(data),numel(t),[]);selected=t>=a-1e-9 & t<=b+1e-9;
        signals.(names{k})=struct('time_s',t(selected),'values',data(selected,:));
        assert(numel(signals.(names{k}).time_s)==2);
    end
    assert(numel(observation.states)==74 && numel(native)==1262 && numel(source_traces)==162 && numel(fieldnames(signals))==201);
    save(fullfile(destination,'native','observations.mat'),'native','source_traces','boundary_metadata','signals','-v7.3');
end
function rows=slice(rows,a,b)
    for k=1:numel(rows)
        r=rows{k};selected=r.time_s>=a-1e-9 & r.time_s<=b+1e-9;
        r.time_s=r.time_s(selected);r.values=r.values(selected,:);assert(numel(r.time_s)==2);rows{k}=r;
    end
end
function write_json(file,value)
    fid=fopen(file,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
