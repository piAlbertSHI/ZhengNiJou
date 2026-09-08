function audit=Run_HeatDriveECC_PublicSnapshotControl(repo,output_root)
% Same physical graph control: import complete public groups, never state indices.
    assert(~isfolder(output_root),'Do not overwrite control evidence.');
    [code,commit]=system('git rev-parse HEAD');assert(code==0,'Cannot record source.');
    [code,dirty]=system('git status --porcelain');assert(code==0 && isempty(strtrim(dirty)),'Commit source first.');
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));cleanup_diary=onCleanup(@() diary('off'));
    old=pwd;old_path=path;cleanup_path=onCleanup(@() restore_path(old,old_path));
    generation=Simulink.fileGenControl('getConfig');
    cleanup_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'build_cache'), ...
        'CodeGenFolder',fullfile(output_root,'generated_code'),'createDir',true);
    audit=struct('schema','heatdrive_ecc_public_snapshot_control_v1','execution_commit',strtrim(commit), ...
        'computation_complete',false,'production_recovery_allowed',false,'source_physical_model_changed',false, ...
        'controller_representation_changed',true,'source_op_edited',false,'final_checkpoint_saved',false, ...
        'anonymous_indices_edited',false,'start_time_s',2000.001,'stop_time_s',2000.002,'cases',{{}},'error_message','');
    try
        origin=fullfile(repo,'outputs_storage_audit','c200_source_compatibility_20260907');
        template_path=fullfile(origin,'archived_source_probe_v4','DO_NOT_RESUME_FOR_PRODUCTION.mat');
        expected='8ACBED525F7F45170EF308B5F6BCB8E008AAEB87A4A90900982052786273E321';
        assert(strcmp(file_sha256(template_path),expected),'Verified snapshot changed.');
        load_system('simulink');saved=load(template_path,'diagnostic_op','production_recovery_allowed');
        assert(~saved.production_recovery_allowed && saved.diagnostic_op.snapshotTime==2000.001,'Wrong diagnostic snapshot.');
        original=saved.diagnostic_op.loggedStates;
        assert(isa(original,'Simulink.SimulationData.Dataset') && original.numElements==73,'Missing public snapshot groups.');
        authority=jsondecode(fileread(fullfile(repo,'verification','c200_mainline_freeze_contract.json')));
        result_path=fullfile(repo,authority.result_relative_path);
        assert(strcmp(file_sha256(result_path),authority.result_sha256) && ...
            strcmp(file_sha256(fullfile(repo,authority.checkpoint_relative_path)),authority.checkpoint_sha256), ...
            'C200 authority changed.');
        frozen=load(result_path,'options');options=frozen.options;
        source=fullfile(origin,'source','gx101r1_R69_remote');
        options.model_path=fullfile(source,[options.model_name '.slx']);options.simulation.persist_model_configuration=false;
        assert(strcmp(file_sha256(options.model_path),'F1D07FDE12F442AFB2F735D5A9A833269CF433437896E2096F23AE984575EA5E'), ...
            'Archived physical model changed.');
        addpath(repo,'-end');addpath(source,'-begin');cd(source);
        assert(strcmp(which('Build_HeatDriveECC_EighthRound_Simulink_Model'), ...
            fullfile(source,'Build_HeatDriveECC_EighthRound_Simulink_Model.m')),'Wrong builder.');
        [model,built]=Build_HeatDriveECC_EighthRound_Simulink_Model(options);
        cleanup_model=onCleanup(@() close_system(model,0));
        fields={'geometry','material','system','branch','constitutive','fluid','schedule'};
        for k=1:numel(fields),assert(isequaln(built.(fields{k}),frozen.options.(fields{k})),'Physical options changed.');end
        memory={};
        for k=1:original.numElements
            item=original.getElement(k);block=char(item.BlockPath.getBlock(1));
            assert(item.Values.Time==2000.001 && isa(item.Values.Data,'double'),'Wrong public snapshot time/type.');
            if endsWith(block,'/Solver Configuration'),assert(numel(item.Values.Data)==995,'Wrong solver group.');continue;end
            memory{end+1}=struct('block_path',block,'c200_values',item.Values.Data(:).'); %#ok<AGROW>
        end
        assert(numel(memory)==72,'Incomplete named memory.');mapping=struct('named_nonnetwork_state_groups',vertcat(memory{:}));
        audit.controller_initial_conditions=Apply_HeatDriveECC_ObservedControllerInitialState(model,mapping, ...
            fullfile(repo,'outputs_storage_audit','lag_state_space_equivalence_20260908','lag_equivalence.json'));
        [targets,target_records]=Build_HeatDriveECC_DifferentialStateTargets(repo,model,2);
        commands=struct();names={'L_valve_command','SMA_L_valve_command','SMA_pressure_bias_command', ...
            'SMA_pressure_feedback_enable_command','SMA_pressure_feedback_reset_command'};
        for k=1:numel(names)
            value=evalin('base',names{k});assert(value.Time(end)==2000,'Do not extend or shift control events.');
            commands.(names{k})=struct('time_s',value.Time,'values',value.Data);
        end
        save(fullfile(output_root,'control_inputs.mat'),'built','commands','target_records','-v7.3');
        assignin('base','EIGHTH_ROUND_OPTIONS',built);input=Simulink.SimulationInput(model);
        input=input.setVariable('EIGHTH_ROUND_OPTIONS',built);input=input.setVariable('public_targets',targets);
        input=input.setModelParameter('StartTime','2000.001','StopTime','2000.001', ...
            'SimscapeUseOperatingPoints','on','SimscapeOperatingPoint','public_targets', ...
            'Solver',built.simulation.solver,'FixedStep',num2str(built.simulation.fixed_step_s,'%.17g'), ...
            'SimulationMode',built.simulation.mode,'ReturnWorkspaceOutputs','on','CaptureErrors','on', ...
            'SaveTime','off','SaveOutput','off','SignalLogging','off','SaveState','on','StateSaveName','internal_state_log', ...
            'SaveFinalState','on','FinalStateName','xFinal','SaveOperatingPoint','on', ...
            'OperatingPointContentsChecksumMismatchMsg','error','OperatingPointInterfaceChecksumMismatchMsg','error');
        seed=sim(input);assert(isempty(seed.ErrorMessage),'Seed failed: %s',seed.ErrorMessage);
        seed_native=Extract_HeatDriveECC_NativeStorageTraces(seed.simlog,model);
        save(fullfile(output_root,'seed_native.mat'),'seed_native','-v7.3');
        matches={};
        for k=1:numel(target_records)
            row=target_records{k};idx=find(cellfun(@(r) strcmp([r.block_path '/' r.state_name],[model '/' row.path]),seed_native));
            assert(isscalar(idx),'Missing native seed target.');native=seed_native{idx};
            actual=double(native.values(end));assert(strcmp(native.unit,row.unit),'Wrong seed units.');
            delta=abs(actual-row.value);bound=1e-10+1e-11*max(abs(actual),abs(row.value));
            matches{end+1}=struct('path',row.path,'unit',row.unit,'expected',row.value,'actual',actual, ...
                'difference',delta,'bound',bound,'pass',delta<=bound,'differential',row.differential); %#ok<AGROW>
        end
        audit.seed_matches=matches;audit.seed_target_pass=all(cellfun(@(r) r.pass,matches));
        assert(audit.seed_target_pass,'Seed does not preserve source targets.');
        for arm={'nonnetwork_snapshot','whole_snapshot'}
            candidate=seed.xFinal;ds=candidate.loggedStates;replaced=0;solver_groups=0;
            assert(ds.numElements==73 && candidate.snapshotTime==2000.001,'Wrong seeded public state set.');
            for k=1:ds.numElements
                state=ds.getElement(k);block=char(state.BlockPath.getBlock(1));
                solver=endsWith(block,'/Solver Configuration');
                if solver && strcmp(arm{1},'nonnetwork_snapshot'),continue;end
                found=[];
                for j=1:original.numElements
                    item=original.getElement(j);
                    if strcmp(char(item.BlockPath.getBlock(1)),block) && strcmp(char(item.Name),char(state.Name)),found(end+1)=j;end %#ok<AGROW>
                end
                assert(isscalar(found),'Public group identity changed.');item=original.getElement(found);
                assert(isequal(size(item.Values.Data),size(state.Values.Data)) && item.Values.Time==candidate.snapshotTime, ...
                    'Public group shape or time changed.');
                if solver,assert(numel(item.Values.Data)==995,'Wrong whole solver group.');solver_groups=solver_groups+1;end
                ds=ds.setElement(k,item);replaced=replaced+1;
            end
            candidate.loggedStates=ds;
            assert(replaced==72+solver_groups && solver_groups<=1,'Wrong copied group count.');
            run=input.setModelParameter('StopTime','2000.002');run=run.setInitialState(candidate);
            output=sim(run);assert(isempty(output.ErrorMessage),'Snapshot control failed: %s',output.ErrorMessage);
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
                'Incomplete snapshot-control observation.');
            observation_path=fullfile(output_root,[arm{1} '_observations.mat']);
            save(observation_path,'signals','native','observation','-v7.3');
            audit.cases{end+1}=struct('arm',arm{1},'copied_public_groups',replaced,'whole_solver_groups',solver_groups, ...
                'observation_sha256',file_sha256(observation_path)); %#ok<AGROW>
            clear output
        end
        assert(isequaln(original,saved.diagnostic_op.loggedStates),'Source OP was changed.');
        audit.source_snapshot_sha256=expected;audit.computation_complete=numel(audit.cases)==2;
    catch ME
        audit.error_message=ME.message;audit.error_identifier=ME.identifier;audit.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'public_snapshot_control.json'),'w','n','UTF-8');assert(fid>=0,'Cannot save audit.');
    cleanup_file=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('PUBLIC_SNAPSHOT_CONTROL_COMPLETE=%d EVIDENCE=%s\n',audit.computation_complete,output_root);
    assert(audit.computation_complete,'See public_snapshot_control.json.');
end

function result=file_sha256(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');
    assert(fid>=0,'Cannot read evidence.');cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

function restore_path(folder,old_path)
    cd(folder);path(old_path);
end
