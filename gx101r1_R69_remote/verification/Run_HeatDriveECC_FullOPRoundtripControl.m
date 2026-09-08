function audit=Run_HeatDriveECC_FullOPRoundtripControl(repo,output_root,window_mode)
% Compare an untouched full OP with an identity write through its public Dataset.
    if nargin<3,window_mode='one_step_pair';end
    assert(any(strcmp(window_mode,{'one_step_pair','one_second_reference'})),'Unknown window mode.');
    stop_time=2000.002;arms={'untouched','identity_dataset_write'};
    if strcmp(window_mode,'one_second_reference'),stop_time=2001.001;arms={'untouched'};end
    assert(~isfolder(output_root),'Do not overwrite evidence.');
    [code,commit]=system('git rev-parse HEAD');assert(code==0,'Cannot record source.');
    [code,dirty]=system('git status --porcelain');assert(code==0 && isempty(strtrim(dirty)),'Commit source first.');
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));
    cleanup_diary=onCleanup(@() diary('off'));
    old=pwd;old_path=path;cleanup_path=onCleanup(@() restore_path(old,old_path));
    generation=Simulink.fileGenControl('getConfig');
    cleanup_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'build_cache'), ...
        'CodeGenFolder',fullfile(output_root,'generated_code'),'createDir',true);
    audit=struct('schema','heatdrive_ecc_full_op_roundtrip_v1','execution_commit',strtrim(commit), ...
        'computation_complete',false,'production_recovery_allowed',false,'cases',{{}}, ...
        'physical_options_changed',false,'controller_representation_changed',false, ...
        'command_horizon_extended',false,'source_op_edited',false,'final_checkpoint_saved',false, ...
        'anonymous_indices_edited',false,'error_message','');
    audit.window_mode=window_mode;audit.start_time_s=2000.001;audit.stop_time_s=stop_time;
    audit.boundary_sample_hold_diagnostic=true;
    try
        origin=fullfile(repo,'outputs_storage_audit','c200_source_compatibility_20260907');
        op_path=fullfile(origin,'archived_source_probe_v4','DO_NOT_RESUME_FOR_PRODUCTION.mat');
        expected='8ACBED525F7F45170EF308B5F6BCB8E008AAEB87A4A90900982052786273E321';
        assert(strcmp(file_sha256(op_path),expected),'Source diagnostic OP changed.');
        load_system('simulink');saved=load(op_path,'diagnostic_op','production_recovery_allowed');
        assert(~saved.production_recovery_allowed && saved.diagnostic_op.snapshotTime==2000.001,'Wrong source.');
        original=saved.diagnostic_op.loggedStates;
        assert(isa(original,'Simulink.SimulationData.Dataset') && original.numElements==73,'Wrong public state set.');
        authority=jsondecode(fileread(fullfile(repo,'verification','c200_mainline_freeze_contract.json')));
        result_path=fullfile(repo,authority.result_relative_path);
        assert(strcmp(file_sha256(result_path),authority.result_sha256) && ...
            strcmp(file_sha256(fullfile(repo,authority.checkpoint_relative_path)),authority.checkpoint_sha256), ...
            'C200 authority changed.');
        frozen=load(result_path,'options');options=frozen.options;
        source=fullfile(origin,'source','gx101r1_R69_remote');
        options.model_path=fullfile(source,[options.model_name '.slx']);
        options.simulation.persist_model_configuration=false;
        assert(strcmp(file_sha256(options.model_path), ...
            'F1D07FDE12F442AFB2F735D5A9A833269CF433437896E2096F23AE984575EA5E'),'Archived SLX changed.');
        addpath(repo,'-end');addpath(source,'-begin');cd(source);
        assert(strcmp(which('Build_HeatDriveECC_EighthRound_Simulink_Model'), ...
            fullfile(source,'Build_HeatDriveECC_EighthRound_Simulink_Model.m')),'Wrong builder.');
        [model,built]=Build_HeatDriveECC_EighthRound_Simulink_Model(options);
        cleanup_model=onCleanup(@() close_system(model,0));
        fields={'geometry','material','system','branch','constitutive','fluid','schedule'};
        for k=1:numel(fields),assert(isequaln(built.(fields{k}),frozen.options.(fields{k})),'Physical options changed.');end
        commands=struct();names={'L_valve_command','SMA_L_valve_command','SMA_pressure_bias_command', ...
            'SMA_pressure_feedback_enable_command','SMA_pressure_feedback_reset_command'};
        for k=1:numel(names)
            value=evalin('base',names{k});assert(value.Time(end)==2000,'Command horizon changed.');
            commands.(names{k})=struct('time_s',value.Time,'values',value.Data);
        end
        save(fullfile(output_root,'control_inputs.mat'),'built','commands','-v7.3');
        assignin('base','EIGHTH_ROUND_OPTIONS',built);input=Simulink.SimulationInput(model);
        input=input.setVariable('EIGHTH_ROUND_OPTIONS',built);
        input=input.setModelParameter('StartTime','0','StopTime',num2str(stop_time,'%.17g'), ...
            'Solver',built.simulation.solver,'FixedStep',num2str(built.simulation.fixed_step_s,'%.17g'), ...
            'SimulationMode',built.simulation.mode,'ReturnWorkspaceOutputs','on','CaptureErrors','on', ...
            'SaveTime','off','SaveOutput','off','SignalLogging','off','SaveState','on','StateSaveName','internal_state_log', ...
            'SaveFinalState','on','FinalStateName','xFinal','SaveOperatingPoint','on', ...
            'OperatingPointContentsChecksumMismatchMsg','error','OperatingPointInterfaceChecksumMismatchMsg','error');
        for arm=arms
            candidate=saved.diagnostic_op;
            if strcmp(arm{1},'identity_dataset_write'),candidate.loggedStates=original;end
            assert(candidate.snapshotTime==2000.001 && isequaln(candidate.loggedStates,original), ...
                'Identity Dataset readback changed.');
            observation=Extract_HeatDriveECC_ObservedStates(candidate.loggedStates,built.schedule.tau_cycle_s,1);
            input_path=fullfile(output_root,[arm{1} '_input_public_states.mat']);
            save(input_path,'observation','-v7.3');
            run=input.setInitialState(candidate);output=sim(run);
            assert(isempty(output.ErrorMessage),'Full OP control failed: %s',output.ErrorMessage);
            signals=struct();names=output.who;
            for k=1:numel(names)
                item=output.get(names{k});
                if isa(item,'timeseries'),signals.(names{k})=struct('time_s',item.Time,'values',item.Data);
                elseif isstruct(item) && isscalar(item) && isfield(item,'time') && isfield(item,'signals') && ...
                    isscalar(item.signals) && isfield(item.signals,'values')
                    signals.(names{k})=struct('time_s',item.time,'values',item.signals.values);
                end
            end
            native=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model);
            observation=Extract_HeatDriveECC_ObservedStates(output.internal_state_log,built.schedule.tau_cycle_s,1);
            assert(numel(fieldnames(signals))==161 && numel(native)==1240 && observation.logged_state_group_count==73, ...
                'Incomplete observation.');
            observation_path=fullfile(output_root,[arm{1} '_observations.mat']);
            save(observation_path,'signals','native','observation','-v7.3');
            audit.cases{end+1}=struct('arm',arm{1},'public_input_readback_exact',true, ...
                'input_sha256',file_sha256(input_path),'observation_sha256',file_sha256(observation_path)); %#ok<AGROW>
            clear output
        end
        assert(isequaln(original,saved.diagnostic_op.loggedStates) && strcmp(file_sha256(op_path),expected),'Source changed.');
        audit.source_snapshot_sha256=expected;audit.computation_complete=numel(audit.cases)==numel(arms);
    catch ME
        audit.error_message=ME.message;audit.error_identifier=ME.identifier;
        audit.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'full_op_roundtrip.json'),'w','n','UTF-8');assert(fid>=0,'Cannot save audit.');
    cleanup_file=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(struct('computation_complete',audit.computation_complete, ...
        'production_recovery_allowed',false,'output_root',output_root)));
    assert(audit.computation_complete,'See full_op_roundtrip.json.');
end

function result=file_sha256(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');
    assert(fid>=0,'Cannot read evidence.');cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

function restore_path(folder,old_path)
    cd(folder);path(old_path);
end
