function record=Inspect_HeatDriveECC_ColdCompiledStates(repo,output_root,prefer_inventory,component_priorities,formulation,consistency_tolerance,residual_tolerance,capture_runtime,tighten_global,scale_buffers,normal_mode,momentum_buffers)
% Read actual rebuilt cold state metadata; never import a production ModelOP.
    if nargin<3,prefer_inventory=false;end
    if nargin<4,component_priorities=false;end
    if nargin<5,formulation='explicit';end
    if nargin<6,consistency_tolerance=[];end
    if nargin<7,residual_tolerance=[];end
    if nargin<8,capture_runtime=false;end
    if nargin<9,tighten_global=false;end
    if nargin<10,scale_buffers=false;end
    if nargin<11,normal_mode=false;end
    if nargin<12,momentum_buffers=false;end
    assert(islogical(capture_runtime) && isscalar(capture_runtime),'Require explicit callback capture choice.');
    assert(any(strcmp(formulation,{'explicit','specific_inventory'})),'Unknown inventory formulation.');
    specific_inventory=strcmp(formulation,'specific_inventory');
    assert(islogical(momentum_buffers) && isscalar(momentum_buffers) && (~momentum_buffers || ...
        (specific_inventory && capture_runtime && ~normal_mode && ~scale_buffers && ~tighten_global && ...
        isempty(consistency_tolerance) && isempty(residual_tolerance))), ...
        'Momentum-only trial must retain the baseline solver, targets and scaling.');
    assert(islogical(normal_mode) && isscalar(normal_mode) && (~normal_mode || ...
        (specific_inventory && capture_runtime && ~scale_buffers && ~tighten_global && ...
        isempty(consistency_tolerance) && isempty(residual_tolerance))), ...
        'Normal-mode trial must retain the baseline physical solver and scaling.');
    assert(islogical(scale_buffers) && isscalar(scale_buffers) && (~scale_buffers || ...
        (specific_inventory && capture_runtime && ~tighten_global && isempty(consistency_tolerance) && isempty(residual_tolerance))), ...
        'Buffer nominal trial must not change any tolerance.');
    assert(islogical(tighten_global) && isscalar(tighten_global) && (~tighten_global || ...
        (specific_inventory && capture_runtime && isempty(consistency_tolerance) && isempty(residual_tolerance))), ...
        'Global-only trial requires callback evidence and unchanged local settings.');
    assert(isempty(consistency_tolerance) || (specific_inventory && isscalar(consistency_tolerance) && ...
        isfinite(consistency_tolerance) && consistency_tolerance==1e-9), ...
        'Only the declared 1e-9 consistency trial is supported.');
    assert(isempty(residual_tolerance) || (specific_inventory && isempty(consistency_tolerance) && ...
        isscalar(residual_tolerance) && isfinite(residual_tolerance) && residual_tolerance==1e-9), ...
        'Residual-only trial must not also change state-based consistency parameters.');
    assert(~specific_inventory || (~prefer_inventory && ~component_priorities), ...
        'Specific inventory trial must not also change declaration priorities.');
    assert(islogical(prefer_inventory) && isscalar(prefer_inventory),'Require explicit inventory priority choice.');
    assert(islogical(component_priorities) && isscalar(component_priorities) && ...
        (~component_priorities || prefer_inventory),'Component priority trial requires matching block priorities.');
    assert(~isfolder(output_root),'Never overwrite state inspection evidence.');
    [code,dirty]=system('git status --porcelain');assert(code==0 && isempty(strtrim(dirty)),'Commit inspector first.');
    [code,commit]=system('git rev-parse HEAD');assert(code==0,'Cannot record inspector.');
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));dc=onCleanup(@() diary('off'));
    generation=Simulink.fileGenControl('getConfig');
    gc=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'cache'), ...
        'CodeGenFolder',fullfile(output_root,'codegen'),'createDir',true);
    oldpath=path;pc=onCleanup(@() path(oldpath));
    source=fullfile(repo,'outputs_storage_audit','conservative_buffer_coupled_cycle_20260909');
    execution=jsondecode(fileread(fullfile(source,'cold_chamber_execution.json')));
    assert(execution.collection_pass && ~execution.production_recovery_allowed && ...
        strcmp(execution.execution_commit,'6148ebd49c3679821684a0e6206b8661e54fa7fa'),'Wrong cold reference.');
    original=fullfile(source,'native','observations.mat');
    assert(strcmp(file_hash(original),execution.cases(1).observation_sha256),'Native cold source changed.');
    frozen=jsondecode(fileread(fullfile(repo,'verification','c200_mainline_freeze_contract.json')));
    raw=fullfile(repo,frozen.result_relative_path);op=fullfile(repo,frozen.checkpoint_relative_path);
    assert(strcmp(file_hash(raw),frozen.result_sha256) && strcmp(file_hash(op),frozen.checkpoint_sha256),'C200 changed.');
    addpath(fullfile(source,'buffer_component_build'));
    if ~component_priorities && ~specific_inventory,addpath(fullfile(source,'component_build'));end
    assert(strcmp(file_hash(fullfile(source,'component_build','+ecc_inventory','conservative_chamber.ssc')), ...
        file_hash(fullfile(repo,'verification','simscape_inventory','+ecc_inventory','conservative_chamber.ssc'))),'Chamber source changed.');
    if component_priorities || specific_inventory
        if component_priorities
        variant=fullfile(repo,'verification','simscape_inventory_priorities','+ecc_inventory_priority','conservative_chamber.ssc');
        package='ecc_inventory_priority';
        original_text=fileread(fullfile(repo,'verification','simscape_inventory','+ecc_inventory','conservative_chamber.ssc'));
        expected_text=strrep(original_text,'priority = priority.high','priority = priority.low');
        expected_text=strrep(expected_text,"stored_mass = {0.0016, 'kg'};", ...
            "stored_mass = {value = {0.0016, 'kg'}, priority = priority.high};");
        expected_text=strrep(expected_text,"stored_energy = {160, 'J'};", ...
            "stored_energy = {value = {160, 'J'}, priority = priority.high};");
        else
            package='ecc_inventory_specific';
            variant=fullfile(repo,'verification','simscape_inventory_specific',['+' package],'conservative_chamber.ssc');
            original_text=fileread(fullfile(repo,'verification','simscape_inventory','+ecc_inventory','conservative_chamber.ssc'));
            expected_text=strrep(original_text,'stored_mass == volume * rho_I;', 'rho_I == stored_mass / volume;');
            expected_text=strrep(expected_text,'stored_energy == stored_mass * u_I;', 'u_I == stored_energy / stored_mass;');
        end
        assert(strcmp(strrep(expected_text,sprintf('\r\n'),newline), ...
            strrep(fileread(variant),sprintf('\r\n'),newline)),'Variant differs from the declared minimal transformation.');
        build=fullfile(output_root,'component_build');mkdir(build);
        copyfile(fileparts(variant),fullfile(build,['+' package]));
        old=pwd;cc=onCleanup(@() cd(old));cd(build);ssc_build(package);cd(old);clear cc
        addpath(build);
    end
    if component_priorities || specific_inventory
        library_name=[package '_lib'];chamber_source=[package '.conservative_chamber'];
        selected_library=fullfile(build,[library_name '.slx']);
    else
        library_name='ecc_inventory_lib';chamber_source='ecc_inventory.conservative_chamber';
        selected_library=fullfile(source,'component_build','ecc_inventory_lib.slx');
    end
    buffer_library='ecc_buffer_coupled_lib';momentum_contract=struct();
    if momentum_buffers
        audit_path=fullfile(repo,'outputs_storage_audit','conservative_buffer_momentum_audit_20260909','conservative_buffer_audit.json');
        qualified=jsondecode(fileread(audit_path));
        assert(qualified.isolated_component_conservation_pass && qualified.momentum_boundary_trial && ...
            ~qualified.production_recovery_allowed && numel(qualified.cases)==16,'Require isolated momentum qualification.');
        buffer_library='ecc_buffer_momentum_lib';
        buffer_build=fullfile(repo,'outputs_storage_audit','conservative_buffer_momentum_trial_20260909','component_build');
        buffer_component=fullfile(repo,'verification','simscape_buffer_momentum','+ecc_buffer_momentum','conservative_buffer.ssc');
        buffer_source=fullfile(buffer_build,'+ecc_buffer_momentum','conservative_buffer.ssc');
        assert(strcmp(file_hash(buffer_component),file_hash(buffer_source)),'Qualified buffer source changed.');
        addpath(buffer_build);load_system(fullfile(buffer_build,[buffer_library '.slx']));
        assert(strcmp(get_param(buffer_library,'FileName'),fullfile(buffer_build,[buffer_library '.slx'])),'Wrong buffer library loaded.');
        momentum_contract=struct('audit_path',audit_path,'audit_sha256',file_hash(audit_path), ...
            'component_path',buffer_component,'component_sha256',file_hash(buffer_component), ...
            'library_path',fullfile(buffer_build,[buffer_library '.slx']), ...
            'library_sha256',file_hash(fullfile(buffer_build,[buffer_library '.slx'])));
    end
    load_system(selected_library);load_system(buffer_library);
    assert(strcmp(get_param(library_name,'FileName'),selected_library),'A different component library is loaded.');
    config=load(fullfile(source,'conservative','configuration.mat'),'options');
    config.options.simulation.persist_model_configuration=false;
    config.options.branch.independent_conservative_chamber_library=library_name;
    canonical=config.options.model_path;canonical_hash=file_hash(canonical);
    record=struct('schema','heatdrive_ecc_cold_compiled_states_v1','inspector_commit',strtrim(commit), ...
        'inspection_pass',false,'simulation_run',false,'initialization_only',true,'source_time_s',0,'failed_terminal_state_imported',false, ...
        'c200_state_imported',false,'production_recovery_allowed',false,'checkpoint_saved',false, ...
        'source_native_sha256',file_hash(original),'states',{{}},'stage','build','error_message','');
    record.block_temperature_pressure_priority_low=prefer_inventory;
    record.component_inventory_priority_high=component_priorities;
    record.inventory_formulation=formulation;
    record.consistency_tolerance_override=consistency_tolerance;
    record.residual_tolerance_override=residual_tolerance;
    record.runtime_callback_capture_requested=capture_runtime;
    record.global_tolerance_override=tighten_global;
    record.buffer_nominal_scaling_requested=scale_buffers;
    record.normal_mode_requested=normal_mode;
    record.momentum_buffers_requested=momentum_buffers;
    record.momentum_contract=momentum_contract;
    record.loaded_chamber_library=selected_library;record.loaded_library_sha256=file_hash(selected_library);
    record.chamber_package_resolution=evalc('which(chamber_source,''-all'')');
    record.chamber_source_file=chamber_source;
    try
        [model,options]=Build_HeatDriveECC_EighthRound_Simulink_Model(config.options);
        mc=onCleanup(@() close_system(model,0));
        solvers=find_system(model,'LookUnderMasks','all','FollowLinks','on','MaskType','Solver Configuration');
        assert(isscalar(solvers),'Require the single coupled physical solver.');
        names={'ConsistencyTolSource','ConsistencyAbsTol','ConsistencyRelTol','ConsistencyTolFactor', ...
            'ResidualTolerance','UseLocalSolver','LocalSolverChoice','LocalSolverSampleTime'};
        before=struct();for k=1:numel(names),before.(names{k})=get_param(solvers{1},names{k});end
        record.consistency_settings_before=before;
        record.global_tolerances=struct('RelTol',get_param(model,'RelTol'),'AbsTol',get_param(model,'AbsTol'));
        if tighten_global
            assert(strcmp(record.global_tolerances.RelTol,'1e-2') && strcmp(record.global_tolerances.AbsTol,'1e-3'), ...
                'Unexpected global baseline tolerances.');
            set_param(model,'RelTol','1e-10','AbsTol','1e-12');
        end
        record.global_tolerances_after=struct('RelTol',get_param(model,'RelTol'),'AbsTol',get_param(model,'AbsTol'));
        if ~isempty(consistency_tolerance)
            assert(strcmp(before.ConsistencyTolSource,'GLOBAL') && strcmp(before.ConsistencyTolFactor,'0.001'), ...
                'Unexpected baseline consistency settings.');
            set_param(solvers{1},'ConsistencyTolSource','LOCAL','ConsistencyAbsTol','1e-9','ConsistencyRelTol','1e-9');
        end
        if ~isempty(residual_tolerance)
            assert(strcmp(before.ResidualTolerance,'0.001'),'Unexpected baseline residual tolerance.');
            set_param(solvers{1},'ResidualTolerance','1e-9');
        end
        after=struct();for k=1:numel(names),after.(names{k})=get_param(solvers{1},names{k});end
        record.consistency_settings_after=after;
        prior=load(original,'native');
        targets=jsondecode(fileread(fullfile(source,'conservative','cold_inventory_targets.json')));
        for k=1:numel(targets)
            t=targets(k);assert(t.source_time_s==0 && strcmp(t.source_sha256,record.source_native_sha256),'Invalid target source.');
            assert(strcmp(get_param(t.block_path,'SourceFile'),chamber_source),'Actual chamber source mismatch.');
            set_param(t.block_path,'stored_mass_specify','on','stored_mass_priority','High', ...
                'stored_mass',num2str(t.stored_mass_kg,'%.17g'),'stored_mass_unit','kg', ...
                'stored_energy_specify','on','stored_energy_priority','High', ...
                'stored_energy',num2str(t.stored_energy_J,'%.17g'),'stored_energy_unit','J', ...
                'stored_mass_nominal_specify','on','stored_mass_nominal_value',num2str(t.stored_mass_kg,'%.17g'), ...
                'stored_mass_nominal_unit','kg','stored_energy_nominal_specify','on', ...
                'stored_energy_nominal_value',num2str(t.stored_energy_J,'%.17g'),'stored_energy_nominal_unit','J');
            if prefer_inventory,set_param(t.block_path,'T_I_priority','Low','p_I_priority','Low');end
        end
        guesses=jsondecode(fileread(fullfile(source,'conservative','buffer_mass_guesses.json')));
        for k=1:numel(guesses)
            t=guesses(k);set_param(t.block_path,'mass',num2str(t.new_guess_kg,'%.17g'),'mass_unit','kg', ...
                'mass_specify','on','mass_priority','High');
        end
        set_param(model,'LoadInitialState','off');
        buffers=Apply_HeatDriveECC_ColdConservativeBuffers(model,prior.native,buffer_library);
        if momentum_buffers,record.buffer_replacement_contracts=buffers;end
        record.normalize_using_nominal_values=get_param(model,'SimscapeNormalizeSystem');
        record.model_nominal_value_table=get_param(model,'SimscapeNominalValues');
        record.buffer_nominal_changes={};
        if scale_buffers
            assert(strcmp(record.normalize_using_nominal_values,'on'),'Nominal normalization must already be active.');
            for k=1:numel(buffers)
                b=buffers{k};
                for choice={'stored_mass','stored_energy'}
                    name=choice{1};unit='kg';magnitude=b.initial_mass_kg;
                    if strcmp(name,'stored_energy'),unit='J';magnitude=b.initial_extended_energy_J;end
                    assert(isfinite(magnitude) && magnitude>0,'Need positive measured nominal magnitude.');
                    before=struct('specify',get_param(b.block_path,[name '_nominal_specify']), ...
                        'value',get_param(b.block_path,[name '_nominal_value']),'unit',get_param(b.block_path,[name '_nominal_unit']));
                    assert(strcmp(before.specify,'off'),'Unexpected pre-existing buffer scale.');
                    set_param(b.block_path,[name '_nominal_specify'],'on',[name '_nominal_value'], ...
                        num2str(magnitude,'%.17g'),[name '_nominal_unit'],unit);
                    record.buffer_nominal_changes{end+1}=struct('block_path',b.block_path,'state_name',name, ...
                        'before',before,'nominal_value',magnitude,'unit',unit,'source_time_s',0);
                end
            end
            assert(numel(record.buffer_nominal_changes)==8,'Incomplete buffer scaling coverage.');
        end
        [cold_public_targets,public_targets]=Build_HeatDriveECC_ColdInventoryTargets(model,prior.native, ...
            options.branch.sma_pump_manifold_volume_m3,buffers,chamber_source);
        expected=jsondecode(fileread(fullfile(source,'conservative','public_inventory_targets.json')));
        assert(~hasPrivateData(cold_public_targets) && numel(public_targets)==numel(expected.targets),'Public cold target coverage differs.');
        for k=1:numel(public_targets)
            t=public_targets{k};idx=find(strcmp({expected.targets.path},t.path));assert(isscalar(idx),'Wrong target path.');
            e=expected.targets(idx);assert(isequal(t,e),'Public cold target changed.');
        end
        assignin('base','cold_public_targets',cold_public_targets);
        simulation_mode=options.simulation.mode;
        if normal_mode
            assert(strcmp(simulation_mode,'accelerator'),'Unexpected baseline execution mode.');
            simulation_mode='normal';
        end
        record.execution_mode=simulation_mode;
        set_param(model,'LoadInitialState','off','SimscapeUseOperatingPoints','on','SimscapeOperatingPoint','cold_public_targets', ...
            'StartTime','0','StopTime','0','SimulationMode',simulation_mode, ...
            'Solver',options.simulation.solver,'FixedStep',num2str(options.simulation.fixed_step_s,'%.17g'), ...
            'SaveState','on','StateSaveName','states','SaveFormat','Dataset','SaveFinalState','off','SaveOperatingPoint','off', ...
            'ReturnWorkspaceOutputs','on','SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off');
        record.stage='initialization_state_logging';record.simulation_run=true;
        if capture_runtime
            assignin('base','cold_initialization_context',{});
            assignin('base','cold_public_target_records',public_targets);
            for callback={'InitFcn','StartFcn','StopFcn'}
                assert(isempty(strtrim(get_param(model,callback{1}))),'Do not replace an existing model callback.');
                set_param(model,callback{1},sprintf('Capture_HeatDriveECC_ColdInitializationContext(''%s'',''%s'');',model,callback{1}));
            end
        end
        input=Simulink.SimulationInput(model);input=input.setVariable('cold_public_targets',cold_public_targets);
        input=input.setModelParameter('CaptureErrors','on');output=sim(input);
        if capture_runtime,record.runtime_callbacks=evalin('base','cold_initialization_context');end
        assert(isempty(output.ErrorMessage),output.ErrorMessage);
        for k=1:numel(targets)
            assert(strcmp(get_param(targets(k).block_path,'SourceFile'),chamber_source), ...
                'Actual chamber source changed during initialization.');
        end
        record.post_initialization_source_file_verified=true;
        states=output.get('states');
        save(fullfile(output_root,'compiled_initial_state_dataset.mat'),'states','-v7.3');
        assert(isa(states,'Simulink.SimulationData.Dataset'),'Unexpected state representation.');
        record.dataset_elements=states.numElements;
        for k=1:states.numElements
            s=states.getElement(k);v=s.Values;
            entry=struct('index',k,'name',s.Name,'class',class(s),'block_path',{s.BlockPath.convertToCell}, ...
                'values_class',class(v),'properties',{properties(s)});
            if isa(v,'timeseries')
                entry.value_size=size(v.Data);entry.time_s=v.Time;entry.data_info=evalc('disp(v.DataInfo)');
            end
            record.states{end+1}=entry;
        end
        record.stage='read_node_metadata';log=output.get('simlog');record.node_metadata={};
        if momentum_buffers
            record.buffer_momentum_initial={};
            variables={'mdot_A','rho_port','dynamic_pressure','p_A','rho_I','level'};
            units={'kg/s','kg/m^3','Pa','Pa','kg/m^3','m'};
            for k=1:numel(buffers)
                b=buffers{k};node=simscape.logging.findNode(log,b.block_path);
                assert(strcmp(get_param(b.block_path,'SourceFile'),'ecc_buffer_momentum.conservative_buffer'), ...
                    'Actual momentum buffer source changed.');
                row=struct('block_path',b.block_path,'source_time_s',0);
                for j=1:numel(variables)
                    series=node.child(variables{j}).series;t=double(time(series));v=double(values(series));
                    assert(isscalar(t) && t==0 && isscalar(v) && isfinite(v),'Require finite t=0 momentum coordinates.');
                    row.(variables{j})=value(simscape.Value(v,series.unit),units{j});
                end
                record.buffer_momentum_initial{end+1}=row;
            end
        end
        record.initial_coordinates=cell(size(public_targets));
        for k=1:numel(public_targets)
            t=public_targets{k};node=simscape.logging.findNode(log,t.block_path);
            variable_node=node.child(t.state_name);series=variable_node.series;
            times=double(time(series));observed=double(values(series));
            assert(isscalar(times) && times==0 && isscalar(observed) && isfinite(observed), ...
                'Require exactly one finite actual t=0 sample per public target.');
            actual=value(simscape.Value(observed,series.unit),t.unit);
            record.initial_coordinates{k}=struct('path',t.path,'priority',t.priority,'unit',t.unit, ...
                'expected',t.value,'actual',actual,'source_time_s',times,'native_value',observed,'native_unit',series.unit, ...
                'tag_names',{variable_node.tagNames},'tag_values',{variable_node.tags});
        end
        for block={'SMA_PumpInletConnectingPipeVolume','SMA_PumpOutletConnectingPipeVolume', ...
                'ColdFluidBuffer','HotFluidBuffer','SHEXFluidBuffer','SMAHotFluidBuffer'}
            parent=log.child(block{1});
            for name={'stored_mass','stored_energy','T_I','p_I'}
                node=parent.child(name{1});
                record.node_metadata{end+1}=struct('block_name',block{1},'variable_name',name{1}, ...
                    'tags_text',evalc('disp(node.tags)'), 'tag_names',{node.tagNames},'tag_values',{node.tags});
            end
        end
        plugin=get_param(model,'SimscapePlugin');
        record.plugin_class=class(plugin);record.plugin_display=evalc('disp(plugin)');
        if isobject(plugin),record.plugin_methods=methods(plugin);record.plugin_properties=properties(plugin);end
        if capture_runtime
            record.stage='cached_public_initialization_phases';record.cached_phase_targets={};
            count_before=numel(evalin('base','cold_initialization_context'));
            % R2025b calls the target phase Prestart; Target is its R2026a name.
            for phase={'Prestart','Start'}
                cached=simscape.op.create(model,phase{1},true);
                values_only=cell(size(public_targets));
                for k=1:numel(public_targets)
                    t=public_targets{k};target=get(cached,t.path);
                    assert(isa(target,'simscape.op.Target'),'Missing cached public target.');
                    values_only{k}=struct('path',t.path,'unit',t.unit,'value',value(target.Value,t.unit), ...
                        'priority',char(string(target.Priority)));
                end
                record.cached_phase_targets{end+1}=struct('phase',phase{1},'cache_requested',true, ...
                    'public_targets',{values_only},'private_payload_exported',false);
                clear cached
            end
            assert(numel(evalin('base','cold_initialization_context'))==count_before, ...
                'Cached phase extraction must not initialize or simulate again.');
            record.cached_extraction_added_callbacks=false;
        end
        record.stage='verify_frozen_authority';
        if momentum_buffers
            assert(strcmp(file_hash(momentum_contract.component_path),momentum_contract.component_sha256) && ...
                strcmp(file_hash(momentum_contract.library_path),momentum_contract.library_sha256) && ...
                strcmp(file_hash(momentum_contract.audit_path),momentum_contract.audit_sha256), ...
                'Momentum prerequisite changed during initialization.');
        end
        assert(strcmp(file_hash(canonical),canonical_hash) && strcmp(file_hash(raw),frozen.result_sha256) && ...
            strcmp(file_hash(op),frozen.checkpoint_sha256),'Frozen model or authority changed.');
        record.inspection_pass=true;record.stage='complete';
        clear mc
    catch ME
        record.error_message=ME.message;record.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'compiled_states_inspection.json'),'w','n','UTF-8');assert(fid>=0);fc=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));clear fc
    fprintf('%s\n',jsonencode(struct('inspection_pass',record.inspection_pass,'stage',record.stage, ...
        'output_root',output_root,'production_recovery_allowed',false)));assert(record.inspection_pass,'Compiled-state inspection failed.');
end

function hash=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0,'Missing evidence.');
    c=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
