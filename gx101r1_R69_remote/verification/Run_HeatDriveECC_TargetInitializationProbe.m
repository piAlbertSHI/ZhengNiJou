function audit = Run_HeatDriveECC_TargetInitializationProbe(repo, output_root)
% Diagnostic joint initialization, not a production operating-point restore.
    assert(~isfolder(output_root),'Do not overwrite initialization evidence.');
    [code,commit]=system('git rev-parse HEAD'); assert(code==0,'Cannot record source.');
    [code,dirty]=system('git status --porcelain');
    assert(code==0 && isempty(strtrim(dirty)),'Commit source before the probe.');
    mkdir(output_root);
    diary(fullfile(output_root,'matlab_diary.log')); cleanup_diary=onCleanup(@() diary('off'));
    old_folder=pwd; old_path=path;
    cleanup_path=onCleanup(@() restore_path(old_folder,old_path));
    generation=Simulink.fileGenControl('getConfig');
    cleanup_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'build_cache'), ...
        'CodeGenFolder',fullfile(output_root,'generated_code'),'createDir',true);
    audit=struct('schema','heatdrive_ecc_target_initialization_probe_v1', ...
        'execution_commit',strtrim(commit),'computation_complete',false, ...
        'joint_initialization_attempted',false,'production_recovery_allowed',false, ...
        'strict_model_operating_point_restore',false,'source_operating_point_edited',false, ...
        'packed_solver_state_imported',false,'source_physical_model_changed',false, ...
        'state_preservation_verified',false,'final_checkpoint_saved',false, ...
        'start_time_s',2000,'stop_time_s',2000.001,'error_identifier','','error_message','');
    try
        origin=fullfile(repo,'outputs_storage_audit','c200_source_compatibility_20260907');
        probe=fullfile(origin,'archived_source_probe_v4');
        base=fullfile(repo,'outputs_storage_audit','state_target_catalog_20260908');
        mapping_path=fullfile(base,'c200_target_mapping.json');
        mapping=jsondecode(fileread(mapping_path));
        candidate_path=fullfile(base,'candidate','DO_NOT_RESUME_TARGET_CANDIDATE.mat');
        serial=jsondecode(fileread(fullfile(base,'candidate','target_candidate_audit.json')));
        assert(serial.serialization_pass && ~serial.state_preservation_verified && ...
            ~serial.production_recovery_allowed && strcmp(file_sha256(mapping_path),serial.mapping_sha256) && ...
            strcmp(file_sha256(candidate_path),serial.candidate_sha256),'Unverified target candidate.');
        loaded=load(candidate_path,'candidate','production_recovery_allowed');
        assert(~loaded.production_recovery_allowed && ~hasPrivateData(loaded.candidate),'Invalid diagnostic scope.');
        candidate=loaded.candidate;
        for k=1:numel(mapping.initialization_candidates)
            row=mapping.initialization_candidates(k); item=get(candidate,row.path);
            assert(isequal(value(item.Value,row.unit),row.c200_value) && ...
                strcmp(char(item.Priority),row.priority),'Candidate changed.');
        end
        capture=jsondecode(fileread(fullfile(origin,'c200_state_capture_v1.json')));
        observed_path=fullfile(probe,'registered_states.mat');
        template_path=fullfile(probe,'DO_NOT_RESUME_FOR_PRODUCTION.mat');
        template_sha='8ACBED525F7F45170EF308B5F6BCB8E008AAEB87A4A90900982052786273E321';
        assert(strcmp(file_sha256(template_path),template_sha) && ...
            strcmp(file_sha256(observed_path),capture.input_sha256.registered), 'State source changed.');
        template=load(template_path,'diagnostic_op');
        observed=load(observed_path,'observation');
        assert(template.diagnostic_op.snapshotTime==2000.001,'Wrong typed template endpoint.');
        states=template.diagnostic_op.loggedStates;
        assert(isa(states,'Simulink.SimulationData.Dataset') && states.numElements==73,'Missing typed states.');
        initial=Simulink.SimulationData.Dataset;
        imported={}; omitted={};
        for k=1:states.numElements
            state=states.getElement(k);
            block=char(state.BlockPath.getBlock(1)); name=char(state.Name);
            indices=find(cellfun(@(r) strcmp(r.block_path,block) && strcmp(r.state_name,name),observed.observation.states));
            assert(isscalar(indices),'Missing or duplicate observed state identity.');
            row=observed.observation.states{indices}; series=state.Values;
            assert(isa(series,'timeseries') && isa(series.Data,'double') && ...
                isscalar(series.Time) && series.Time==2000.001 && series.IsTimeFirst && ...
                isequal(row.time_s(:),[2000;2000.001]) && ...
                isequal(series.Data(:),reshape(row.values(end,:),[],1)), 'Typed state differs from observation.');
            if endsWith(block,'/Solver Configuration')
                assert(row.channel_count==995,'Unexpected opaque state size.');
                omitted{end+1}=struct('block_path',block,'state_name',name,'channels',995); %#ok<AGROW>
                continue;
            end
            % Copy the public state metadata, replacing only the sample by its
            % measured C200 value. Never edit the source ModelOperatingPoint.
            series=copy(series);
            series.Data=reshape(row.values(1,:),size(series.Data));
            series.Time=2000;
            state.Values=series;
            initial=addElement(initial,state);
            imported{end+1}=struct('block_path',block,'state_name',name, ...
                'channels',row.channel_count,'data_class',class(series.Data), ...
                'data_size',size(series.Data),'label',char(state.Label)); %#ok<AGROW>
        end
        assert(initial.numElements==72 && isscalar(omitted) && ...
            sum(cellfun(@(r) r.channels,imported))==381,'Incomplete named-state import.');
        assert(isequaln(template.diagnostic_op.loggedStates,states),'Typed source was changed.');
        save(fullfile(output_root,'initial_named_states.mat'),'initial','imported','omitted','-v7.3');
        clear template states loaded
        authority=jsondecode(fileread(fullfile(repo,'verification','c200_mainline_freeze_contract.json')));
        result_path=fullfile(repo,authority.result_relative_path);
        assert(strcmp(file_sha256(result_path),authority.result_sha256) && ...
            strcmp(file_sha256(fullfile(repo,authority.checkpoint_relative_path)),authority.checkpoint_sha256), ...
            'Frozen C200 changed.');
        frozen=load(result_path,'options');
        options=frozen.options;
        source=fullfile(origin,'source','gx101r1_R69_remote');
        restored=jsondecode(fileread(fullfile(probe,'source_restore_audit.json')));
        options.model_path=fullfile(source,[options.model_name '.slx']);
        options.simulation.persist_model_configuration=false;
        assert(strcmp(file_sha256(options.model_path),restored.archived_model_sha256),'Archived SLX changed.');
        addpath(repo,'-end'); addpath(source,'-begin'); cd(source);
        assert(strcmp(which('Build_HeatDriveECC_EighthRound_Simulink_Model'), ...
            fullfile(source,'Build_HeatDriveECC_EighthRound_Simulink_Model.m')),'Wrong builder.');
        [model,built]=Build_HeatDriveECC_EighthRound_Simulink_Model(options);
        cleanup_model=onCleanup(@() close_system(model,0));
        fields={'geometry','material','system','branch','constitutive','fluid','schedule'};
        for k=1:numel(fields)
            assert(isequaln(built.(fields{k}),frozen.options.(fields{k})),'Physical options changed: %s',fields{k});
        end
        commands=struct();
        names={'L_valve_command','SMA_L_valve_command','SMA_pressure_bias_command', ...
            'SMA_pressure_feedback_enable_command','SMA_pressure_feedback_reset_command'};
        for k=1:numel(names)
            series=evalin('base',names{k});
            commands.(names{k})=struct('time_s',series.Time,'values',series.Data);
            assert(series.Time(end)==2000,'Do not extend or retime the command horizon.');
        end
        save(fullfile(output_root,'options_and_commands.mat'),'built','commands','-v7.3');
        assignin('base','EIGHTH_ROUND_OPTIONS',built);
        input=Simulink.SimulationInput(model);
        input=input.setVariable('EIGHTH_ROUND_OPTIONS',built);
        input=input.setVariable('c200_public_targets',candidate);
        input=input.setInitialState(initial);
        input=input.setModelParameter('StartTime','2000','StopTime','2000.001', ...
            'SimscapeUseOperatingPoints','on','SimscapeOperatingPoint','c200_public_targets', ...
            'Solver',built.simulation.solver,'FixedStep',num2str(built.simulation.fixed_step_s,'%.17g'), ...
            'SimulationMode',built.simulation.mode,'ReturnWorkspaceOutputs','on','CaptureErrors','on', ...
            'SaveTime','off','SaveOutput','off','SignalLogging','off', ...
            'SaveState','on','StateSaveName','internal_state_log', ...
            'SaveFinalState','on','FinalStateName','xFinal','SaveOperatingPoint','on', ...
            'OperatingPointContentsChecksumMismatchMsg','error','OperatingPointInterfaceChecksumMismatchMsg','error');
        audit.input_parameters=input.ModelParameters;
        audit.source_result_sha256=authority.result_sha256;
        audit.source_checkpoint_sha256=authority.checkpoint_sha256;
        audit.mapping_sha256=serial.mapping_sha256;
        audit.candidate_sha256=serial.candidate_sha256;
        audit.typed_template_sha256=template_sha;
        audit.imported_states=imported; audit.omitted_states=omitted;
        audit.joint_initialization_attempted=true;
        write_json(fullfile(output_root,'initialization_probe_audit.json'),audit);
        started=tic;
        output=sim(input);
        audit.wall_time_s=toc(started);
        audit.error_message=char(string(output.ErrorMessage));
        assert(isempty(audit.error_message),'HeatDriveECC:JointInitializationSimulationFailed','%s',audit.error_message);
        signals=struct(); names=output.who;
        for k=1:numel(names)
            item=output.get(names{k});
            if isa(item,'timeseries')
                signals.(names{k})=struct('time_s',item.Time,'values',item.Data);
            elseif isstruct(item) && isscalar(item) && isfield(item,'time') && ...
                    isfield(item,'signals') && isscalar(item.signals) && isfield(item.signals,'values')
                signals.(names{k})=struct('time_s',item.time,'values',item.signals.values);
            end
        end
        native=Extract_HeatDriveECC_NativeStorageTraces(output.get('simlog'),model);
        observation=Extract_HeatDriveECC_ObservedStates(output.internal_state_log,built.schedule.tau_cycle_s,1);
        save(fullfile(output_root,'joint_initialization_observations.mat'),'signals','native','observation','-v7.3');
        audit.signal_count=numel(fieldnames(signals)); audit.native_count=numel(native);
        audit.registered_state_group_count=observation.logged_state_group_count;
        audit.observation_sha256=file_sha256(fullfile(output_root,'joint_initialization_observations.mat'));
        assert(audit.signal_count==161 && audit.native_count==1240 && ...
            audit.registered_state_group_count==73,'Incomplete output observation.');
        audit.computation_complete=true;
        clear output cleanup_model
    catch ME
        audit.error_identifier=ME.identifier;
        audit.error_message=ME.message;
        audit.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    write_json(fullfile(output_root,'initialization_probe_audit.json'),audit);
    clear cleanup_generation cleanup_path
    fprintf('JOINT_INITIALIZATION_COMPUTATION_COMPLETE=%d\n%s\n',audit.computation_complete,jsonencode(audit));
    assert(audit.computation_complete,'HeatDriveECC:JointInitializationProbeFailed','%s',audit.error_message);
end

function write_json(path,data)
    fid=fopen(path,'w','n','UTF-8'); assert(fid>=0,'Cannot write evidence.');
    cleanup=onCleanup(@() fclose(fid)); fprintf(fid,'%s\n',jsonencode(data,'PrettyPrint',true));
end

function result=file_sha256(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(path,'rb'); assert(fid>=0,'Cannot read source.');
    cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

function restore_path(folder,old_path)
    cd(folder);path(old_path);
end
