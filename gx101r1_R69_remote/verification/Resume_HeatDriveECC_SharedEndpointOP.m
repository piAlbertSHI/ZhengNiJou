function record=Resume_HeatDriveECC_SharedEndpointOP(repo,source,folder,mode)
% New-process strict load of a persisted isolated model and its untouched full OP.
    if nargin<4,mode='reference_cycle';end
    assert(ismember(mode,{'reference_cycle','bounded_step_probe','bounded_buffer_state_probe_from_C100','warmup_C40','warmup_C60_from_C40','warmup_C80_from_C60','warmup_C100_from_C80','warmup_C120_from_C100'}));
    assert(~isfolder(folder));mkdir(folder);old=pwd;oldpath=path;
    cleanup_path=onCleanup(@() restore_path(old,oldpath));addpath(repo,fullfile(repo,'verification'));
    record=struct('schema','heatdrive_ecc_shared_endpoint_new_process_OP_v1', ...
        'execution_complete',false,'production_recovery_allowed',false,'source_OP_edited',false);
    try
        is_continuation=~isempty(strfind(mode,'_from_C')); %#ok<STREMP>
        buffer_state_probe=strcmp(mode,'bounded_buffer_state_probe_from_C100');
        assert(~buffer_state_probe || is_continuation,'Buffer state probe must be anchored to a recorded continuation.');
        if is_continuation
            prior=jsondecode(fileread(fullfile(source,'new_process_restore.json')));
            [runtime,runtime_root]=load_runtime_metadata(prior.source_root);
            point_path=prior.terminal_OP_path;point_sha=prior.terminal_OP_sha256;
            point_snapshot=prior.terminal_OP_snapshot_s;
            previous_cycles=prior.completed_total_cycles;
            review_file=fullfile(repo,'outputs_storage_audit',sprintf('shared_endpoint_OP_C%d_20261027',previous_cycles), ...
                'shared_endpoint_warmup_review.json');
            review=jsondecode(fileread(review_file));
            assert(review.completed_total_cycles==previous_cycles && ~review.periodic_steady_state && ...
                strcmp(review.terminal_OP_sha256,point_sha));
            record.prerequisite_warmup_review_sha256=file_hash(review_file);
        else
            prior=jsondecode(fileread(fullfile(source,'state_interface_roundtrip.json')));
            runtime=prior;point_path=prior.operating_point_path;point_sha=prior.operating_point_sha256;
            point_snapshot=prior.snapshot_s;runtime_root=source;
        end
        assert(runtime.execution_complete && ~runtime.production_recovery_allowed && runtime.fixed_command_horizon_s==1000);
        if strcmp(mode,'warmup_C40')
            proof_file=fullfile(repo,'outputs_storage_audit','shared_endpoint_OP_bounded_cycle_20261026_r2', ...
                'shared_endpoint_OP_review.json');
            verify(proof_file,'07DDCBCEF6A399EBB60212F9C14855EDEF8A33BA3B3CED49F7A9CABEE3EBBDCB');
            proof=jsondecode(fileread(proof_file));
            assert(runtime.bounded_observation_from_cold_start && proof.same_model_actual_all_value_bits_exact && ...
                proof.new_process_actual_all_value_bits_exact && proof.new_process_full_cycle_covered);
            assert(strcmp(runtime.operating_point_sha256,'7479D0608D73F40A92637CD0113DE7B676067E8FB507E78233D48B2FE00573DA'));
            record.prerequisite_proof_sha256=file_hash(proof_file);
        end
        verify(runtime.saved_runtime_model_path,runtime.saved_runtime_model_sha256);
        verify(runtime.base_workspace.path,runtime.base_workspace.sha256);
        verify(point_path,point_sha);
        verify(runtime.interface_contract_path,runtime.interface_contract_sha256);
        for k=1:numel(runtime.loaded_project_sources)
            p=runtime.loaded_project_sources(k);verify(p.path,p.sha256);
        end
        build=fullfile(runtime_root,'endpoint_component_build');addpath(build);
        construction=jsondecode(fileread(fullfile(runtime_root,'endpoint_inventory_construction.json')));
        for k=1:numel(construction.source_components)
            c=construction.source_components(k);verify(c.path,c.sha256);verify(c.library_path,c.library_sha256);
            load_system(c.library_path);
        end
        library_cleanup=onCleanup(@() close_libraries());
        saved=load(runtime.base_workspace.path);names=fieldnames(saved);
        for k=1:numel(names),assignin('base',names{k},saved.(names{k}));end;clear saved
        [~,model]=fileparts(runtime.saved_runtime_model_path);assert(~bdIsLoaded(model));
        cd(fileparts(runtime.saved_runtime_model_path));
        load_system(runtime.saved_runtime_model_path);model_cleanup=onCleanup(@() close_system(model,0));
        actual=char(java.io.File(get_param(model,'FileName')).getCanonicalPath());
        expected=char(java.io.File(runtime.saved_runtime_model_path).getCanonicalPath());
        assert(strcmpi(actual,expected),'Loaded the wrong same-named model.');
        record.actual_loaded_model_path=actual;
        assert(strcmp(get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error') && ...
            strcmp(get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error'));
        config=load(runtime.interface_contract_path,'contract','options');
        point=load(point_path,'diagnostic_operating_point','production_recovery_allowed');
        assert(~point.production_recovery_allowed && point.diagnostic_operating_point.snapshotTime==point_snapshot);
        original=point.diagnostic_operating_point.loggedStates;
        generation=Simulink.fileGenControl('getConfig');
        cleanup_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
        Simulink.fileGenControl('set','CacheFolder',fullfile(folder,'cache'), ...
            'CodeGenFolder',fullfile(folder,'codegen'),'createDir',true);
        cd(fileparts(runtime.saved_runtime_model_path));
        HeatDriveECC_ObserverContext('register',model,fullfile(folder,'solver_time.json'));
        input=Simulink.SimulationInput(model);stop=runtime.reference_stop_s;
        record.observation_profile=mode;
        if strcmp(mode,'warmup_C40')
            stop=400;
            assert(strcmp(get_param(model,'SimscapeLogLimitData'),'on') && ...
                numeric_parameter(get_param(model,'SimscapeLogDataHistory'))==20002 && ...
                numeric_parameter(get_param(model,'MaxDataPoints'))==40002);
        end
        if is_continuation && ~buffer_state_probe
            numbers=sscanf(mode,'warmup_C%d_from_C%d');
            assert(numel(numbers)==2 && numbers(2)==previous_cycles && numbers(1)>numbers(2));
            stop=numbers(1)*10;
            assert(strcmp(get_param(model,'SimscapeLogLimitData'),'on') && ...
                numeric_parameter(get_param(model,'SimscapeLogDataHistory'))==20002 && ...
                numeric_parameter(get_param(model,'MaxDataPoints'))==40002);
        end
        if strcmp(mode,'bounded_step_probe')
            stop=runtime.snapshot_s+.002;
            input=input.setModelParameter('SimscapeLogLimitData','on','SimscapeLogDataHistory',20002,'MaxDataPoints','40002');
            sinks=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block','BlockType','ToWorkspace');
            for k=1:numel(sinks),input=input.setBlockParameter(sinks{k},'MaxDataPoints','40002');end
            record.bounded_logging_requested=struct('native_history_points',20002,'public_state_and_sink_points',40002, ...
                'sink_count',numel(sinks),'sample_times_or_equations_modified',false);
        end
        if buffer_state_probe
            stop=point_snapshot+0.002;
            input=input.setModelParameter('SimscapeLogLimitData','on','SimscapeLogDataHistory',20002,'MaxDataPoints','40002');
            sinks=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block','BlockType','ToWorkspace');
            for k=1:numel(sinks),input=input.setBlockParameter(sinks{k},'MaxDataPoints','40002');end
            record.buffer_probe_logging_requested=struct('native_history_points',20002,'workspace_history_points',40002, ...
                'sink_count',numel(sinks),'sample_times_or_equations_modified',false);
        end
        wall=tic;cpu=cputime;
        input=input.setModelParameter('CaptureErrors','on', ...
            'StartTime',num2str(point_snapshot,17),'StopTime',num2str(stop,17));
        record.absolute_time_contract=struct('start_time_s',point_snapshot, ...
            'stop_time_s',stop,'operating_point_snapshot_s',point_snapshot, ...
            'start_time_matches_operating_point',true);
        output=sim(input ...
            .setInitialState(point.diagnostic_operating_point));
        record.simulation_wall_seconds=toc(wall);record.simulation_CPU_seconds=cputime-cpu;
        assert(isempty(output.ErrorMessage),'Strict new-process restore failed: %s',output.ErrorMessage);
        if buffer_state_probe
            selected={};
            node=simscape.logging.findNode(output.simlog,'heatdrive_ecc_coupled_se21/HotFluidBuffer');
            assert(~isempty(node),'HotFluidBuffer log node was not exported by the bounded probe.');
            names=node.childIds;
            for k=1:numel(names)
                if ismember(names{k},{'stored_mass','mass_offset','mdot_A','stored_energy'})
                    [time_values,data,unit]=Read_HeatDriveECC_NativeSeries(node.child(names{k}));
                    values=double(data(:));
                    selected{end+1}=struct('state_name',names{k}, ...
                        'unit',unit,'samples',numel(values), ...
                        'time_first_s',double(time_values(1)),'time_last_s',double(time_values(end)), ...
                        'value_first',values(1),'value_last',values(end), ...
                        'value_min',min(values),'value_max',max(values)); %#ok<AGROW>
                end
            end
            assert(any(cellfun(@(x)strcmp(x.state_name,'stored_mass'),selected)), ...
                'HotFluidBuffer stored_mass was not exported by the bounded probe.');
            record.execution_complete=true;
            record.probe_only=true;
            record.production_recovery_allowed=false;
            record.state_projection_or_reset_used=false;
            record.actual_tout_first_s=double(output.tout(1));
            record.actual_tout_last_s=double(output.tout(end));
            record.buffer_state_probe=selected;
            record.reader_source_sha256=file_hash([mfilename('fullpath') '.m']);
            write_json(fullfile(folder,'bounded_buffer_state_probe.json'),record);
            HeatDriveECC_ObserverContext('clear',model);
            disp(jsonencode(struct('execution_complete',true,'probe_only',true,'folder',folder)));
            return
        end
        if ismember(mode,{'warmup_C40','warmup_C60_from_C40','warmup_C80_from_C60','warmup_C100_from_C80','warmup_C120_from_C100'})
            % Save the untouched final OP before optional evidence serialization.
            diagnostic_operating_point=output.interface_final_op;production_recovery_allowed=false; %#ok<NASGU>
            assert(isa(diagnostic_operating_point,'Simulink.op.ModelOperatingPoint') && ...
                diagnostic_operating_point.snapshotTime==stop);
            terminal=fullfile(folder,'diagnostic_complete_operating_point.mat');assert(~isfile(terminal));
            save(terminal,'diagnostic_operating_point','production_recovery_allowed','-v7.3');
            record.terminal_OP_path=terminal;record.terminal_OP_sha256=file_hash(terminal);
            record.terminal_OP_snapshot_s=stop;record.terminal_OP_requires_scientific_review_before_continuation=true;
            write_json(fullfile(folder,'terminal_OP_saved_pending_observations.json'),record);
            [~,boundary]=Extract_HeatDriveECC_BoundaryTraces(output.simlog,model,config.contract.tl_topology,config.contract.thermal_topology);
            contract=config.contract;options=config.options; %#ok<NASGU>
            context=fullfile(folder,'warmup_context.mat');assert(~isfile(context));
            save(context,'contract','options','boundary','-v7');
            record.context_path=context;record.context_sha256=file_hash(context);
            record.completed_total_cycles=stop/10;record.fixed_command_horizon_s=1000;
            record.all_mechanism_gates_evaluated=false;record.periodic_steady_state=false;
            record.outer_solve_or_Table4_allowed=false;
        end
        file=fullfile(folder,'new_process_restored_observations.mat');
        record.observation=Capture_HeatDriveECC_StateInterfaceTrace(output,model,config.contract,file);
        record.observation_path=file;record.observation_sha256=file_hash(file);
        assert(isequaln(original,point.diagnostic_operating_point.loggedStates));
        verify(point_path,point_sha);
        verify(runtime.saved_runtime_model_path,runtime.saved_runtime_model_sha256);
        record.source_root=source;record.source_OP_sha256=point_sha;
        record.actual_tout_first_s=double(output.tout(1));record.actual_tout_last_s=double(output.tout(end));
        record.checksum_policy='error/error';record.execution_complete=true;
        record.complete_cycle_numerical_equivalence_evaluated=false;record.state_projection_or_reset_used=false;
        record.reader_source_sha256=file_hash([mfilename('fullpath') '.m']);
        HeatDriveECC_ObserverContext('clear',model);
    catch e
        record.error_identifier=e.identifier;record.error_report=getReport(e,'extended','hyperlinks','off');
        write_json(fullfile(folder,'FAILED_DO_NOT_RESUME.json'),record);rethrow(e);
    end
    write_json(fullfile(folder,'new_process_restore.json'),record);
    disp(jsonencode(struct('execution_complete',true,'production_recovery_allowed',false,'folder',folder)));
end

function v=numeric_parameter(v)
    if ischar(v) || isstring(v),v=str2double(v);end
    validateattributes(v,{'numeric'},{'scalar','real','finite'});
end

function [runtime,root]=load_runtime_metadata(root)
    for hop=1:4
        state_file=fullfile(root,'state_interface_roundtrip.json');
        if isfile(state_file)
            runtime=jsondecode(fileread(state_file));return
        end
        parent_file=fullfile(root,'new_process_restore.json');
        assert(isfile(parent_file),'Missing recorded warmup parent at hop %d: %s',hop,root);
        parent=jsondecode(fileread(parent_file));root=parent.source_root;
    end
    error('HeatDriveECC:ParentChainTooDeep','Warmup parent chain exceeded four recorded links.');
end

function verify(p,h)
    assert(strcmp(file_hash(p),h),'Source dependency changed: %s',p);
end
function h=file_hash(p)
    f=fopen(p,'rb');assert(f>=0);c=onCleanup(@() fclose(f));d=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(f),d.update(fread(f,1048576,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
function write_json(p,r)
    assert(~isfile(p));f=fopen(p,'w','n','UTF-8');assert(f>=0);c=onCleanup(@() fclose(f));fprintf(f,'%s',jsonencode(r,'PrettyPrint',true));
end
function restore_path(old,oldpath)
    cd(old);path(oldpath);
end
function close_libraries()
    for name={'ecc_inventory_endpoint_lib','ecc_buffer_coupled_offset_lib'}
        if bdIsLoaded(name{1}),close_system(name{1},0);end
    end
end
