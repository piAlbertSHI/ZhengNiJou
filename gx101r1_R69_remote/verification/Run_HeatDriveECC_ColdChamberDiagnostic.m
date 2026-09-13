function record = Run_HeatDriveECC_ColdChamberDiagnostic(repo, output_root, duration, scale_inventory, buffer_mass_guess, buffer_mass_targets, pipe_energy_targets, conservative_buffers, formulation, network_absolute_pressure_MPa, diagnostic_branch_overrides, nonlinear_inventory, initial_flux_compensation)
% Authorized independent cold diagnostic. Never import or export a recovery OP.
    if nargin<3, duration=10; end
    if nargin<4, scale_inventory=false; end
    if nargin<5, buffer_mass_guess=false; end
    if nargin<6, buffer_mass_targets=false; end
    if nargin<7, pipe_energy_targets=false; end
    if nargin<8, conservative_buffers=false; end
    if nargin<9, formulation='explicit'; end
    if nargin<10, network_absolute_pressure_MPa=0.75; end
    if nargin<11, diagnostic_branch_overrides=struct(); end
    if nargin<12, nonlinear_inventory=false; end
    if nargin<13, initial_flux_compensation=false; end
    assert(any(strcmp(formulation,{'explicit','specific_inventory'})),'Unknown chamber formulation.');
    specific_inventory=strcmp(formulation,'specific_inventory');
    assert(~specific_inventory || (scale_inventory && conservative_buffers), ...
        'Specific inventory trial requires the complete cold inventory contract.');
    assert(islogical(conservative_buffers) && isscalar(conservative_buffers) && ...
        (~conservative_buffers || (pipe_energy_targets && buffer_mass_targets && buffer_mass_guess)), ...
        'Conservative buffers require the complete independent cold inventory contract.');
    assert(islogical(scale_inventory) && isscalar(scale_inventory),'Require a scalar scaling choice.');
    assert(islogical(buffer_mass_guess) && isscalar(buffer_mass_guess),'Require a scalar buffer guess choice.');
    assert(islogical(buffer_mass_targets) && isscalar(buffer_mass_targets) && ...
        (~buffer_mass_targets || buffer_mass_guess),'Buffer targets require the physical cold mass values.');
    assert(islogical(pipe_energy_targets) && isscalar(pipe_energy_targets),'Require a scalar pipe initial-state choice.');
    assert(ismember(duration,[0.01 0.2 1 10]), ...
        'Only topology smoke, onset probe, one-second preflight, or one full cycle is supported.');
    assert(isscalar(network_absolute_pressure_MPa) && isfinite(network_absolute_pressure_MPa) && ...
        ismember(network_absolute_pressure_MPa,[0.75 0.85]), ...
        'Only the independently qualified 0.75 or 0.85 MPa cold diagnostic datum is supported.');
    assert(isstruct(diagnostic_branch_overrides) && isscalar(diagnostic_branch_overrides), ...
        'Diagnostic branch overrides must be a scalar struct.');
    assert(islogical(nonlinear_inventory) && isscalar(nonlinear_inventory) && ...
        (~nonlinear_inventory || specific_inventory), ...
        'Nonlinear inventory coordinates require the qualified specific-inventory branch.');
    assert(islogical(initial_flux_compensation) && isscalar(initial_flux_compensation) && ...
        (~initial_flux_compensation || (specific_inventory && ~nonlinear_inventory)), ...
        'Initial-flux compensation requires the linear specific-inventory diagnostic.');
    allowed_override_fields = {'se_stage2_pressure_pi_kp_MPa_per_kgps', ...
        'se_stage2_pressure_pi_initial_kp_MPa_per_kgps', ...
        'se_stage4_pressure_pi_kp_MPa_per_kgps', ...
        'se_stage4_pressure_pi_initial_kp_MPa_per_kgps'};
    override_fields = fieldnames(diagnostic_branch_overrides);
    assert(all(ismember(override_fields,allowed_override_fields)), ...
        'Only independent cold SE route Kp overrides are supported.');
    for override_idx = 1:numel(override_fields)
        override_value = diagnostic_branch_overrides.(override_fields{override_idx});
        assert(isnumeric(override_value) && isscalar(override_value) && ...
            isfinite(override_value) && override_value < 0.0, ...
            'Cold diagnostic Kp overrides must be finite negative scalars.');
    end
    assert(~isfolder(output_root), 'Do not overwrite diagnostic evidence.');
    [code,commit]=system('git rev-parse HEAD'); assert(code==0,'Cannot record source.');
    % Ignore unrelated untracked user directories; tracked source must remain committed.
    [code,dirty]=system('git status --porcelain --untracked-files=no'); assert(code==0 && isempty(strtrim(dirty)),'Commit tracked source first.');
    mkdir(output_root); diary(fullfile(output_root,'matlab_diary.log'));
    diary_cleanup=onCleanup(@() diary('off'));
    old=pwd; oldpath=path; path_cleanup=onCleanup(@() restore_path(old,oldpath));
    generation=Simulink.fileGenControl('getConfig');
    generation_cleanup=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'cache'), ...
        'CodeGenFolder',fullfile(output_root,'codegen'),'createDir',true);
    record=struct('schema','heatdrive_ecc_independent_cold_chamber_v1', ...
        'execution_commit',strtrim(commit),'user_authorized_independent_cold_start',true, ...
        'c200_state_imported',false,'production_recovery_allowed',false, ...
        'diagnostic_simulation_mode','normal', ...
        'table4_reproduction_claim',false,'periodic_steady_state',false, ...
        'full_device_first_law_verified',false,'checkpoint_saved',false, ...
        'start_time_s',0,'stop_time_s',duration,'collection_pass',false,'cases',{{}},'error_message','', ...
        'new_inventory_initialization','native_cold_t0_mass_energy_high_targets', ...
        'diagnostic_network_absolute_pressure_MPa',NaN, ...
        'diagnostic_network_absolute_pressure_source','', ...
        'diagnostic_branch_overrides',diagnostic_branch_overrides, ...
        'new_inventory_nominal_scaling',scale_inventory,'physical_buffer_mass_guess',buffer_mass_guess, ...
        'physical_buffer_mass_high_targets',buffer_mass_targets,'physical_pipe_energy_high_targets',pipe_energy_targets, ...
        'conservative_buffers',conservative_buffers,'inventory_formulation',formulation, ...
        'nonlinear_inventory_coordinates',nonlinear_inventory, ...
        'initial_flux_compensation',initial_flux_compensation);
    try
        contract=jsondecode(fileread(fullfile(repo,'verification','c200_mainline_freeze_contract.json')));
        raw=fullfile(repo,contract.result_relative_path); op=fullfile(repo,contract.checkpoint_relative_path);
        assert(strcmp(file_hash(raw),contract.result_sha256) && strcmp(file_hash(op),contract.checkpoint_sha256), ...
            'C200 authority hash mismatch.');
        frozen=load(raw,'options'); overrides=frozen.options;
        overrides.model_path=fullfile(repo,[overrides.model_name '.slx']);
        overrides.cycle_count=1; overrides.simulation.stop_time_s=duration;
        overrides.simulation.persist_model_configuration=false;
        overrides.simulation.resume_checkpoint_path='';
        % The independent cold-start arm uses a qualified mid-window datum.
        % The frozen production datum (1 MPa) triggers the native Simscape
        % pressure ceiling at t=0. The explicit argument is restricted to
        % independently probed mid-window values and never changes C200.
        overrides.branch.network_absolute_pressure_MPa=network_absolute_pressure_MPa;
        overrides.branch.network_absolute_pressure_source=[ ...
            'independent cold diagnostic datum; explicit 0.75/0.85 MPa ', ...
            'onset qualification; frozen C200 1 MPa did not pass at t=0'];
        record.diagnostic_network_absolute_pressure_MPa= ...
            overrides.branch.network_absolute_pressure_MPa;
        record.diagnostic_network_absolute_pressure_source= ...
            overrides.branch.network_absolute_pressure_source;
        for override_idx = 1:numel(override_fields)
            field_name = override_fields{override_idx};
            overrides.branch.(field_name) = ...
                diagnostic_branch_overrides.(field_name);
        end
        model_hash=file_hash(overrides.model_path);
        package='ecc_inventory';source_folder='simscape_inventory';
        if specific_inventory
            audit_path=fullfile(repo,'outputs_storage_audit','compiled_specific_inventory_audit_20260909', ...
                'compiled_inventory_state_audit.json');
            compiled_audit=jsondecode(fileread(audit_path));
            assert(compiled_audit.evidence_audit_pass && compiled_audit.specific_inventory_compiled_gate_pass && ...
                ~compiled_audit.production_recovery_allowed,'Require passed compiled inventory coordinate gate.');
            original=fileread(fullfile(repo,'verification','simscape_inventory','+ecc_inventory','conservative_chamber.ssc'));
            expected=strrep(original,'stored_mass == volume * rho_I;','rho_I == stored_mass / volume;');
            expected=strrep(expected,'stored_energy == stored_mass * u_I;','u_I == stored_energy / stored_mass;');
            variant=fullfile(repo,'verification','simscape_inventory_specific','+ecc_inventory_specific','conservative_chamber.ssc');
            compiled_source=fullfile(repo,'outputs_storage_audit','cold_compiled_states_specific_inventory_20260909', ...
                'component_build','+ecc_inventory_specific','conservative_chamber.ssc');
            assert(strcmp(strrep(expected,sprintf('\r\n'),newline),strrep(fileread(variant),sprintf('\r\n'),newline)) && ...
                strcmp(file_hash(variant),file_hash(compiled_source)),'Chamber formulation differs from compiled-gate source.');
            record.compiled_inventory_gate_sha256=file_hash(audit_path);
            package='ecc_inventory_specific';source_folder='simscape_inventory_specific';
        end
        chamber_source=[package '.conservative_chamber'];library_name=[package '_lib'];
        overrides.branch.independent_conservative_chamber_library=library_name;
        build=fullfile(output_root,'component_build'); mkdir(build);
        copyfile(fullfile(repo,'verification',source_folder,['+' package]),fullfile(build,['+' package]));
        cd(build); ssc_build(package); addpath(build); load_system(library_name); cd(repo);
        assert(strcmp(get_param(library_name,'FileName'),fullfile(build,[library_name '.slx'])),'Wrong chamber library loaded.');
        record.chamber_source_file=chamber_source;
        record.chamber_library_sha256=file_hash(fullfile(build,[library_name '.slx']));
        if conservative_buffers
            component_audit=jsondecode(fileread(fullfile(repo,'outputs_storage_audit', ...
                'conservative_buffer_audit_20260909_v2','conservative_buffer_audit.json')));
            assert(component_audit.isolated_component_conservation_pass && ~component_audit.production_recovery_allowed, ...
                'Require independently qualified buffer candidate.');
            original=fileread(fullfile(repo,'verification','simscape_buffer','+ecc_buffer','conservative_buffer.ssc'));
            aligned=fileread(fullfile(repo,'verification','simscape_buffer_coupled','+ecc_buffer_coupled','conservative_buffer.ssc'));
            assert(strcmp(strrep(original,'% H:left','% H:right'),aligned),'Aligned component changed more than the port location.');
            buffer_build=fullfile(output_root,'buffer_component_build');mkdir(buffer_build);
            copyfile(fullfile(repo,'verification','simscape_buffer_coupled','+ecc_buffer_coupled'),fullfile(buffer_build,'+ecc_buffer_coupled'));
            cd(buffer_build);ssc_build('ecc_buffer_coupled');addpath(buffer_build);load_system('ecc_buffer_coupled_lib');cd(repo);
        end
        for kind={'native','conservative'}
            name=kind{1}; arm=fullfile(output_root,name); mkdir(arm);
            overrides.branch.independent_conservative_chamber_diagnostic=strcmp(name,'conservative');
            [model,options]=Build_HeatDriveECC_EighthRound_Simulink_Model(overrides);
            model_cleanup=onCleanup(@() close_system(model,0));
            changed={};buffer_records={};buffer_paths={};
            if strcmp(name,'conservative')
                changed={[model '/SMA_PumpInletConnectingPipeVolume'],[model '/SMA_PumpOutletConnectingPipeVolume']};
                for k=1:2
                    assert(strcmp(get_param(changed{k},'SourceFile'),chamber_source), ...
                        'Wrong diagnostic component.');
                end
                prior=load(fullfile(output_root,'native','observations.mat'),'native');
                initial_targets=cell(1,2);
                for k=1:2
                    rows=prior.native(cellfun(@(r) strcmp(r.block_path,changed{k}),prior.native));
                    rho=initial_value(rows,'rho_I','kg/m^3'); u=initial_value(rows,'u_I','J/kg');
                    mass=options.branch.sma_pump_manifold_volume_m3*rho;
                    set_param(changed{k},'stored_mass_specify','on','stored_mass_priority','High', ...
                        'stored_mass',num2str(mass,'%.17g'),'stored_mass_unit','kg', ...
                        'stored_energy_specify','on','stored_energy_priority','High', ...
                        'stored_energy',num2str(mass*u,'%.17g'),'stored_energy_unit','J');
                    if scale_inventory
                        assert(mass>0 && mass*u>0,'Require positive physical nominal inventory magnitudes.');
                        set_param(changed{k},'stored_mass_nominal_specify','on', ...
                            'stored_mass_nominal_value',num2str(mass,'%.17g'),'stored_mass_nominal_unit','kg', ...
                            'stored_energy_nominal_specify','on','stored_energy_nominal_value',num2str(mass*u,'%.17g'), ...
                            'stored_energy_nominal_unit','J');
                    end
                    initial_targets{k}=struct('block_path',changed{k},'stored_mass_kg',mass, ...
                        'stored_energy_J',mass*u,'source_time_s',0, ...
                        'source_sha256',file_hash(fullfile(output_root,'native','observations.mat')));
                end
                write_json(fullfile(arm,'cold_inventory_targets.json'),initial_targets);
                if buffer_mass_guess
                    tanks={'ColdFluidBuffer','HotFluidBuffer','SHEXFluidBuffer','SMAHotFluidBuffer'};
                    guesses=cell(size(tanks));
                    for k=1:numel(tanks)
                        p=[model '/' tanks{k}];
                        rows=prior.native(cellfun(@(r) strcmp(r.block_path,p),prior.native));
                        mass=initial_value(rows,'mass','kg');
                        assert(strcmp(get_param(p,'mass_specify'),'off') && strcmp(get_param(p,'mass_priority'),'None') && ...
                            strcmp(get_param(p,'level_priority'),'High') && strcmp(get_param(p,'T_I_priority'),'High'), ...
                            'Unexpected original buffer initial-state contract.');
                        guesses{k}=struct('block_path',p,'old_guess',get_param(p,'mass'), ...
                            'old_unit',get_param(p,'mass_unit'),'new_guess_kg',mass, ...
                            'mass_specify','off','mass_priority','None','source_time_s',0, ...
                            'source_sha256',file_hash(fullfile(output_root,'native','observations.mat')));
                        set_param(p,'mass',num2str(mass,'%.17g'),'mass_unit','kg');
                        if buffer_mass_targets
                            set_param(p,'mass_specify','on','mass_priority','High');
                            guesses{k}.mass_specify='on';guesses{k}.mass_priority='High';
                        end
                    end
                    write_json(fullfile(arm,'buffer_mass_guesses.json'),guesses);
                end
                if conservative_buffers
                    set_param(model,'LoadInitialState','off');
                    buffer_records=Apply_HeatDriveECC_ColdConservativeBuffers(model,prior.native);
                    buffer_paths=cellfun(@(b) b.block_path,buffer_records,'UniformOutput',false);
                    write_json(fullfile(arm,'buffer_replacement_contract.json'),struct('buffers',{buffer_records}, ...
                        'source_sha256',file_hash(fullfile(output_root,'native','observations.mat')),'source_time_s',0));
                end
                if pipe_energy_targets
                    [cold_public_targets,targets]=Build_HeatDriveECC_ColdInventoryTargets(model,prior.native, ...
                        options.branch.sma_pump_manifold_volume_m3,buffer_records,chamber_source);
                    write_json(fullfile(arm,'public_inventory_targets.json'),struct('targets',{targets}, ...
                        'source_sha256',file_hash(fullfile(output_root,'native','observations.mat')), ...
                        'has_private_data',hasPrivateData(cold_public_targets),'source_time_s',0));
                    runtime_targets=targets;
                    if nonlinear_inventory
                        [cold_public_targets,runtime_targets,record.nonlinear_inventory_contract]= ...
                            Apply_HeatDriveECC_NonlinearColdInventory(repo,model,targets,output_root);
                        chamber_source='ecc_nonlinear_chamber.conservative_chamber';
                        record.chamber_source_file=chamber_source;
                        record.nonlinear_buffer_source_file='ecc_nonlinear_buffer.conservative_buffer';
                    elseif initial_flux_compensation
                        [cold_public_targets,runtime_targets,record.initial_flux_compensation_contract]= ...
                            Build_HeatDriveECC_ColdInitialFluxCompensation(repo,model,prior.native,targets);
                    end
                    write_json(fullfile(arm,'runtime_inventory_targets.json'),struct('targets',{runtime_targets}, ...
                        'physical_target_count',numel(targets),'translated_target_count', ...
                        12*double(nonlinear_inventory),'compensated_high_target_count', ...
                        125*double(initial_flux_compensation),'source_time_s',0));
                    save(fullfile(arm,'cold_public_targets.mat'),'cold_public_targets','-v7.3');
                end
            end
            names={'L_valve_command','SMA_L_valve_command','SMA_pressure_bias_command', ...
                'SMA_pressure_feedback_enable_command','SMA_pressure_feedback_reset_command'};
            commands=struct();
            for k=1:numel(names)
                v=evalin('base',names{k}); assert(v.Time(1)==0 && v.Time(end)==10,'Require an actual one-cycle schedule.');
                commands.(names{k})=struct('time_s',v.Time,'values',v.Data);
            end
            save(fullfile(arm,'configuration.mat'),'options','commands','-v7.3');
            set_param(model,'LoadInitialState','off','SimscapeUseOperatingPoints','off', ...
                'StartTime','0','StopTime',num2str(duration,'%.17g'), ...
                'Solver',options.simulation.solver,'FixedStep',num2str(options.simulation.fixed_step_s,'%.17g'), ...
                'SimulationMode','normal','ReturnWorkspaceOutputs','on', ...
                'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
                'SaveFinalState','off','SaveOperatingPoint','off','SaveState','off', ...
                'SaveTime','off','SaveOutput','off','SignalLogging','off');
            if strcmp(name,'conservative') && pipe_energy_targets
                assignin('base','cold_public_targets',cold_public_targets);
                set_param(model,'SimscapeUseOperatingPoints','on','SimscapeOperatingPoint','cold_public_targets');
            end
            assert(options.simscape.local_solver_enabled && ...
                strcmp(options.simscape.local_solver_choice,'NE_BACKWARD_EULER_ADVANCER') && ...
                options.simscape.local_solver_sample_time_s==.001,'Require the unchanged local BE solver.');
            set_param(model,'SimulationCommand','update');
            metadata=export_metadata(model,changed,buffer_paths);
            write_json(fullfile(arm,'inventory_metadata.json'),metadata);
            write_json(fullfile(arm,'tl_connectivity.json'),Export_HeatDriveECC_TLConnectivity(model));
            write_json(fullfile(arm,'thermal_connectivity.json'), ...
                Export_HeatDriveECC_TLConnectivity(model,'foundation.thermal.thermal'));
            input=Simulink.SimulationInput(model);
            input=input.setModelParameter('CaptureErrors','on');
            if strcmp(name,'conservative') && pipe_energy_targets
                input=input.setVariable('cold_public_targets',cold_public_targets);
            end
            output=sim(input);
            if ~isempty(output.ErrorMessage)
                failure_message=output.ErrorMessage;
                Export_HeatDriveECC_FailedColdObservations(output,model,metadata, ...
                    fullfile(arm,'failed_public_observations.mat'));
                error('HeatDriveECC:ColdDiagnosticSimulationFailed','%s',failure_message);
            end
            if specific_inventory && strcmp(name,'conservative')
                inventory_variables={'stored_mass','stored_energy','T_I','p_I'};
                if nonlinear_inventory
                    inventory_variables={'mass_coordinate','energy_delta','T_I','p_I'};
                end
                tags=cell(1,24);tag_count=0;
                for k=1:numel(changed)
                    assert(strcmp(get_param(changed{k},'SourceFile'),chamber_source),'Chamber source changed during trajectory.');
                end
                for block=[changed(:);buffer_paths(:)].'
                    block_name=extractAfter(block{1},[model '/']);parent=output.simlog.child(block_name);
                    for variable=inventory_variables
                        node=parent.child(variable{1});
                        tag_count=tag_count+1;
                        tags{tag_count}=struct('block_name',block_name,'variable_name',variable{1}, ...
                            'tag_names',{node.tagNames},'tag_values',{node.tags});
                    end
                end
                assert(tag_count==24,'Incomplete compiled inventory tag coverage.');
                write_json(fullfile(arm,'compiled_inventory_tags.json'),struct('node_metadata',{tags}, ...
                    'chamber_source_file',chamber_source,'post_simulation_source_verified',true));
            end
            native=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model,false,changed,buffer_paths);
            [source_traces,boundary_metadata]=Extract_HeatDriveECC_BoundaryTraces(output.simlog,model);
            signals=struct(); names=output.who;
            for k=1:numel(names)
                v=output.get(names{k});
                if isa(v,'timeseries'), signals.(names{k})=struct('time_s',v.Time,'values',v.Data);
                elseif isstruct(v) && isscalar(v) && isfield(v,'time') && isfield(v,'signals') && ...
                        isscalar(v.signals) && isfield(v.signals,'values')
                    signals.(names{k})=struct('time_s',v.time,'values',v.signals.values);
                end
            end
            save(fullfile(arm,'observations.mat'),'native','source_traces','boundary_metadata','signals','-v7.3');
            record.cases{end+1}=struct('arm',name,'topology_update_pass',true, ...
                'storage_components',numel(metadata.storage_blocks),'native_trace_count',numel(native), ...
                'source_count',boundary_metadata.source_count,'observation_sha256',file_hash(fullfile(arm,'observations.mat')));
            clear model_cleanup output
        end
        assert(strcmp(file_hash(op),contract.checkpoint_sha256) && strcmp(file_hash(raw),contract.result_sha256) && ...
            strcmp(file_hash(overrides.model_path),model_hash),'Frozen authority or canonical model changed.');
        record.c200_result_sha256=contract.result_sha256; record.c200_checkpoint_sha256=contract.checkpoint_sha256;
        record.collection_pass=numel(record.cases)==2;
    catch ME
        record.error_message=ME.message; record.error_identifier=ME.identifier;
        record.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    write_json(fullfile(output_root,'cold_chamber_execution.json'),record);
    fprintf('%s\n',jsonencode(struct('collection_pass',record.collection_pass, ...
        'completed_arms',numel(record.cases),'production_recovery_allowed',false, ...
        'result_file',fullfile(output_root,'cold_chamber_execution.json'))));
    assert(record.collection_pass,'Cold chamber diagnostic failed; inspect execution JSON.');
end

function metadata=export_metadata(model,changed,buffer_paths)
    metadata=struct('schema','heatdrive_ecc_cold_chamber_inventory_v1','storage_blocks',{{}},'settings_tables',{{}});
    types={'Pipe (TL)','Tank (TL)','Constant Volume Chamber (TL)','Thermal Mass','Conservative Buffer (TL)'};
    modes={'dynamic_compressibility','inertia','mass_type','p_nominal','p_nominal_unit','T_nominal','T_nominal_unit','num_ports','num_inlet','volume_spec'};
    params={'area','length','volume','mass','sp_heat','tank_area','g','inlet_height_A', ...
        'port_area','p_environment','gravity','reference_temperature','auxiliary_depth'};
    for kind=1:5
        blocks=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block','MaskType',types{kind});
        if kind==3, blocks=[blocks(:);changed(:)]; end
        if kind==5, blocks=[blocks(:);buffer_paths(:)]; end
        for k=1:numel(blocks)
            p=blocks{k}; dialog=get_param(p,'DialogParameters');
            row=struct('block_path',p,'mask_type',types{kind},'model_modes',struct(),'mask_parameters',struct(), ...
                'initialization_parameters',struct(), ...
                'conservative_diagnostic',ismember(p,[changed(:);buffer_paths(:)]));
            names=fieldnames(dialog);
            for j=1:numel(names)
                n=names{j};
                if ~isempty(regexp(n,'^(p_I|T_I|u_I|mass|stored_mass|stored_energy|level)(_|$)','once'))
                    row.initialization_parameters.(n)=get_param(p,n);
                end
            end
            for j=1:numel(modes)
                n=modes{j}; if isfield(dialog,n),row.model_modes.(n)=get_param(p,n);end
            end
            for j=1:numel(params)
                n=params{j};
                if isfield(dialog,n)
                    expression=get_param(p,n); row.mask_parameters.(n)=struct('expression',expression, ...
                        'value',slResolve(expression,p),'unit',get_param(p,[n '_unit']));
                end
            end
            metadata.storage_blocks{end+1}=row;
        end
    end
    topology=Export_HeatDriveECC_TLConnectivity(model);
    names={'table_dimensions','T_TLU','T_TLU_unit','T_min_1D','T_max_1D','p_min_1D','p_max_1D', ...
        'p_min_1D_unit','p_max_1D_unit','rho_parameterization_1D','rho_TLU_4','rho_TLU_4_unit', ...
        'beta_const_4','beta_const_4_unit','p_ref_4','p_ref_4_unit','u_parameterization_1D', ...
        'u_TLU_4','u_TLU_4_unit','cp_TLU_5','cp_TLU_5_unit'};
    for k=1:numel(topology.blocks)
        block=topology.blocks{k};
        if strcmp(block.source_file,'foundation.thermal_liquid.utilities.thermal_liquid_settings')
            row=struct('block_path',block.block_path,'parameters',struct());
            for j=1:numel(names),row.parameters.(names{j})=get_param(block.block_path,names{j});end
            metadata.settings_tables{end+1}=row;
        end
    end
    assert(numel(metadata.storage_blocks)==119 && numel(metadata.settings_tables)==2,'Incomplete storage inventory.');
end

function v=initial_value(rows,name,unit)
    selected=rows(cellfun(@(r) strcmp(r.state_name,name),rows));
    assert(isscalar(selected) && selected{1}.time_s(1)==0,'Require actual native cold initial sample.');
    v=value(simscape.Value(selected{1}.values(1),selected{1}.unit),unit);
    assert(isfinite(v),'Nonfinite cold coordinate.');
end

function write_json(file,value)
    fid=fopen(file,'w','n','UTF-8'); assert(fid>=0,'Cannot save JSON.'); cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
function hash=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256'); fid=fopen(file,'rb'); assert(fid>=0,'Missing file.');
    cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
function restore_path(folder,oldpath)
    cd(folder);path(oldpath);
end
