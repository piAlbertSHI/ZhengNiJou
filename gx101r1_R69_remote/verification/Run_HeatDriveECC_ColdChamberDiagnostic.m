function record = Run_HeatDriveECC_ColdChamberDiagnostic(repo, output_root, duration, scale_inventory, buffer_mass_guess, buffer_mass_targets, pipe_energy_targets, conservative_buffers, formulation, network_absolute_pressure_MPa, diagnostic_branch_overrides, nonlinear_inventory, initial_flux_compensation, buffer_mass_formulation, cycle_count, initial_observation_root, simulation_mode, endpoint_chamber_diagnostic, endpoint_all_arms)
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
    if nargin<14, buffer_mass_formulation='direct'; end
    if nargin<15, cycle_count=1; end
    if nargin<16, initial_observation_root=''; end
    if nargin<17, simulation_mode='normal'; end
    if nargin<18, endpoint_chamber_diagnostic=false; end
    if nargin<19, endpoint_all_arms=false; end
    assert(any(strcmp(formulation,{'explicit','specific_inventory'})),'Unknown chamber formulation.');
    specific_inventory=strcmp(formulation,'specific_inventory');
    assert(islogical(endpoint_chamber_diagnostic) && isscalar(endpoint_chamber_diagnostic), ...
        'Require a scalar endpoint chamber diagnostic choice.');
    assert(islogical(endpoint_all_arms) && isscalar(endpoint_all_arms) && ...
        (~endpoint_all_arms || endpoint_chamber_diagnostic), ...
        'Endpoint all-arm mode requires endpoint chamber diagnostics.');
    assert(~endpoint_chamber_diagnostic || (specific_inventory && conservative_buffers && ...
        ~nonlinear_inventory && islogical(initial_flux_compensation)), ...
        'Endpoint chamber diagnostic requires the linear specific-inventory contract.');
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
    assert(isnumeric(cycle_count) && isscalar(cycle_count) && isfinite(cycle_count) && ...
        cycle_count == round(cycle_count) && ismember(cycle_count,[1 2 20]), ...
        'Only the qualified one-cycle, two-cycle preflight, or 20-cycle cold diagnostic is supported.');
    if cycle_count == 1
        assert(ismember(duration,[0.01 0.2 1 10]), ...
            'One-cycle cold diagnostic duration must be 0.01, 0.2, 1, or 10 s.');
    else
        assert(abs(duration - cycle_count*10) <= 1.0e-9, ...
            'A multi-cycle diagnostic must span exactly cycle_count*10 s.');
        initial_observation_root=canonical_path(initial_observation_root);
        initial_observation_path=fullfile(initial_observation_root,'native','observations.mat');
        initial_execution_path=fullfile(initial_observation_root,'cold_chamber_execution.json');
        assert(isfolder(initial_observation_root) && isfile(initial_observation_path) && ...
            isfile(initial_execution_path),'The cold initialization source is incomplete.');
        seed_record=jsondecode(fileread(initial_execution_path));
        assert(seed_record.collection_pass && seed_record.stop_time_s==10 && ...
            seed_record.conservative_buffers && strcmp(seed_record.buffer_mass_formulation,'zero_based_offset') && ...
            seed_record.initial_flux_compensation && ~seed_record.production_recovery_allowed, ...
            'The cold initialization source is not the qualified zero-based seed.');
    end
    endpoint_qualified_source_root='';
    endpoint_qualified_source_observation_sha256='';
    if endpoint_chamber_diagnostic && cycle_count == 1
        initial_observation_root=canonical_path(initial_observation_root);
        initial_observation_path=fullfile(initial_observation_root,'native','observations.mat');
        initial_execution_path=fullfile(initial_observation_root,'cold_chamber_execution.json');
        assert(isfolder(initial_observation_root) && isfile(initial_observation_path) && ...
            isfile(initial_execution_path),'Endpoint chamber diagnostic requires a complete t=0 source.');
        seed_record=jsondecode(fileread(initial_execution_path));
        assert(seed_record.collection_pass && seed_record.stop_time_s==10 && ...
            seed_record.conservative_buffers && strcmp(seed_record.buffer_mass_formulation,'zero_based_offset') && ...
            seed_record.initial_flux_compensation && ~seed_record.production_recovery_allowed, ...
            'Endpoint chamber source is not the qualified zero-based seed.');
        endpoint_qualified_source_root=initial_observation_root;
        endpoint_qualified_source_observation_sha256=file_hash(initial_observation_path);
    end
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
    simulation_mode=lower(strtrim(char(string(simulation_mode))));
    assert(ismember(simulation_mode,{'normal','accelerator'}), ...
        'Only normal or accelerator cold diagnostic simulation modes are supported.');
    buffer_mass_formulation=char(string(buffer_mass_formulation));
    assert(ismember(buffer_mass_formulation,{'direct','zero_based_offset'}), ...
        'Unknown cold buffer mass formulation.');
    assert(~strcmp(buffer_mass_formulation,'zero_based_offset') || conservative_buffers, ...
        'Zero-based offset mass requires conservative buffers.');
    allowed_override_fields = {'se_stage2_pressure_pi_kp_MPa_per_kgps', ...
        'se_stage2_pressure_pi_initial_kp_MPa_per_kgps', ...
        'se_stage2_pressure_pi_transition_start_s', ...
        'se_stage2_pressure_pi_transition_duration_s', ...
        'se_stage4_pressure_pi_kp_MPa_per_kgps', ...
        'se_stage4_pressure_pi_initial_kp_MPa_per_kgps', ...
        'se_stage4_pressure_pi_transition_start_s', ...
        'se_stage4_pressure_pi_transition_duration_s', ...
        'se_stage4_endpoint_viscosity_blend_initial', ...
        'se_stage4_endpoint_viscosity_blend_final', ...
        'se_stage4_endpoint_viscosity_blend_start_s', ...
        'se_stage4_endpoint_viscosity_blend_duration_s', ...
        'se_stage4_endpoint_viscosity_closure_mode'};
    gain_override_fields = {'se_stage2_pressure_pi_kp_MPa_per_kgps', ...
        'se_stage2_pressure_pi_initial_kp_MPa_per_kgps', ...
        'se_stage4_pressure_pi_kp_MPa_per_kgps', ...
        'se_stage4_pressure_pi_initial_kp_MPa_per_kgps'};
    blend_override_fields = {'se_stage4_endpoint_viscosity_blend_initial', ...
        'se_stage4_endpoint_viscosity_blend_final'};
    closure_override_fields = {'se_stage4_endpoint_viscosity_closure_mode'};
    override_fields = fieldnames(diagnostic_branch_overrides);
    assert(all(ismember(override_fields,allowed_override_fields)), ...
        'Only independent cold SE route Kp and bounded transition overrides are supported.');
    for override_idx = 1:numel(override_fields)
        field_name = override_fields{override_idx};
        override_value = diagnostic_branch_overrides.(field_name);
        if ismember(field_name,closure_override_fields)
            assert((ischar(override_value) || isstring(override_value)) && ...
                isscalar(string(override_value)) && ...
                ismember(lower(strtrim(char(string(override_value)))), ...
                {'arithmetic_blend','logarithmic_endpoint'}), ...
                'Unsupported Stage4 viscosity closure mode.');
        else
            assert(isnumeric(override_value) && isscalar(override_value) && isfinite(override_value), ...
                'Cold diagnostic overrides must be finite numeric scalars.');
        end
        if ismember(field_name,gain_override_fields)
            assert(override_value < 0.0, ...
                'Cold diagnostic Kp overrides must be negative.');
        elseif ismember(field_name,blend_override_fields)
            assert(override_value >= 0.0 && override_value <= 1.0, ...
                'Stage4 endpoint-viscosity blend overrides must be within [0,1].');
        else
            assert(override_value >= 0.0, ...
                'Cold diagnostic transition times must be nonnegative.');
        end
    end
    if isfield(diagnostic_branch_overrides, ...
            'se_stage4_endpoint_viscosity_blend_duration_s') && ...
            diagnostic_branch_overrides.se_stage4_endpoint_viscosity_blend_duration_s > 0.0
        assert(all(isfield(diagnostic_branch_overrides, ...
            {'se_stage4_endpoint_viscosity_blend_start_s', ...
             'se_stage4_endpoint_viscosity_blend_initial', ...
             'se_stage4_endpoint_viscosity_blend_final'})), ...
            'A Stage4 viscosity-blend transition requires explicit start, duration, initial, and final weights.');
    end
    for route = {'stage2','stage4'}
        prefix = ['se_' route{1} '_pressure_pi_'];
        start_field = [prefix 'transition_start_s'];
        duration_field = [prefix 'transition_duration_s'];
        if isfield(diagnostic_branch_overrides,duration_field) && ...
                diagnostic_branch_overrides.(duration_field) > 0.0
            final_field = [prefix 'kp_MPa_per_kgps'];
            initial_field = [prefix 'initial_kp_MPa_per_kgps'];
            assert(isfield(diagnostic_branch_overrides,start_field) && ...
                isfield(diagnostic_branch_overrides,final_field) && ...
                isfield(diagnostic_branch_overrides,initial_field), ...
                'A cold Kp transition requires explicit start, duration, initial Kp, and final Kp.');
            transition_end_s = diagnostic_branch_overrides.(start_field) + ...
                diagnostic_branch_overrides.(duration_field);
            transition_horizon_s = 10.0 * min(cycle_count,2);
            assert(transition_end_s <= transition_horizon_s, ...
                'A cold Kp transition must finish within the audited preflight horizon.');
        end
    end
    assert(~isfolder(output_root), 'Do not overwrite diagnostic evidence.');
    [code,commit]=system('git rev-parse HEAD'); assert(code==0,'Cannot record source.');
    % Ignore unrelated untracked user directories; tracked source must remain committed.
    [code,dirty]=system('git status --porcelain --untracked-files=no'); assert(code==0 && isempty(strtrim(dirty)),'Commit tracked source first.');
    mkdir(output_root); diary(fullfile(output_root,'matlab_diary.log'));
    diary_cleanup=onCleanup(@() diary('off'));
    old=pwd; oldpath=path; path_cleanup=onCleanup(@() restore_path(old,oldpath));
    addpath(repo);
    addpath(fullfile(repo,'verification'));
    generation=Simulink.fileGenControl('getConfig');
    generation_cleanup=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'cache'), ...
        'CodeGenFolder',fullfile(output_root,'codegen'),'createDir',true);
    record=struct('schema','heatdrive_ecc_independent_cold_chamber_v2', ...
        'execution_commit',strtrim(commit),'user_authorized_independent_cold_start',true, ...
        'c200_state_imported',false,'production_recovery_allowed',false, ...
        'diagnostic_simulation_mode',simulation_mode, ...
        'table4_reproduction_claim',false,'periodic_steady_state',false, ...
        'full_device_first_law_verified',false,'checkpoint_saved',false, ...
        'start_time_s',0,'stop_time_s',duration,'cycle_count',cycle_count, ...
        'collection_pass',false,'cases',{{}},'error_message','', ...
        'new_inventory_initialization','native_cold_t0_mass_energy_high_targets', ...
        'diagnostic_network_absolute_pressure_MPa',NaN, ...
        'diagnostic_network_absolute_pressure_source','', ...
        'diagnostic_branch_overrides',diagnostic_branch_overrides, ...
        'new_inventory_nominal_scaling',scale_inventory,'physical_buffer_mass_guess',buffer_mass_guess, ...
        'physical_buffer_mass_high_targets',buffer_mass_targets,'physical_pipe_energy_high_targets',pipe_energy_targets, ...
        'conservative_buffers',conservative_buffers,'inventory_formulation',formulation, ...
        'endpoint_chamber_diagnostic',endpoint_chamber_diagnostic, ...
        'endpoint_all_arms',endpoint_all_arms, ...
        'nonlinear_inventory_coordinates',nonlinear_inventory, ...
        'initial_flux_compensation',initial_flux_compensation, ...
        'buffer_mass_formulation',buffer_mass_formulation, ...
        'initialization_source_root','', ...
        'initialization_source_observation_sha256','', ...
        'endpoint_chamber_qualified_source_root',endpoint_qualified_source_root, ...
        'endpoint_chamber_qualified_source_observation_sha256',endpoint_qualified_source_observation_sha256, ...
        'simscape_log_window_start_s',0, ...
        'simscape_log_window_cycles',min(cycle_count,2), ...
        'pressure_probe_contracts',{{}}, ...
        'stage4_controller_probe_contracts',{{}});
    try
        contract=jsondecode(fileread(fullfile(repo,'verification','c200_mainline_freeze_contract.json')));
        raw=fullfile(repo,contract.result_relative_path); op=fullfile(repo,contract.checkpoint_relative_path);
        assert(strcmp(file_hash(raw),contract.result_sha256) && strcmp(file_hash(op),contract.checkpoint_sha256), ...
            'C200 authority hash mismatch.');
        frozen=load(raw,'options'); overrides=frozen.options;
        overrides.model_path=fullfile(repo,[overrides.model_name '.slx']);
        overrides.cycle_count=cycle_count; overrides.simulation.stop_time_s=duration;
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
        if endpoint_chamber_diagnostic
            audit_path=fullfile(repo,'outputs_storage_audit','compiled_specific_inventory_audit_20260909', ...
                'compiled_inventory_state_audit.json');
            compiled_audit=jsondecode(fileread(audit_path));
            assert(compiled_audit.evidence_audit_pass && compiled_audit.specific_inventory_compiled_gate_pass && ...
                ~compiled_audit.production_recovery_allowed,'Require passed compiled inventory coordinate gate.');
            source_variant=fullfile(repo,'verification','simscape_inventory_endpoint', ...
                '+ecc_inventory_endpoint','conservative_chamber.ssc');
            source_reference=fullfile(repo,'verification','simscape_inventory_specific', ...
                '+ecc_inventory_specific','conservative_chamber.ssc');
            endpoint_header=sprintf(['%% Endpoint-contract chamber diagnostic.\n' ...
                '%% This isolated variant exposes stored mass and energy as explicit states so\n' ...
                '%% endpoint inventories use the same state variables as the differential ledger.\n']);
            qualified_header=sprintf(['%% Conservative Inventory Chamber (TL)\n' ...
                '%% Diagnostic alternative: differentiate stored mass and energy themselves.\n']);
            qualified_source=strrep(fileread(source_reference),qualified_header,endpoint_header);
            assert(strcmp(strrep(fileread(source_variant),sprintf('\r\n'),newline), ...
                strrep(qualified_source,sprintf('\r\n'),newline)), ...
                'Endpoint chamber variant must match the qualified explicit-state equations.');
            record.compiled_inventory_gate_sha256=file_hash(audit_path);
            record.endpoint_chamber_source_sha256=file_hash(source_variant);
            package='ecc_inventory_endpoint';source_folder='simscape_inventory_endpoint';
        elseif specific_inventory
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
        library_path=fullfile(build,[library_name '.slx']);
        cd(build); ssc_build(package); addpath(build);
        if bdIsLoaded(library_name)
            close_system(library_name,0);
        end
        load_system(library_path); cd(repo);
        loaded_library_path=get_param(library_name,'FileName');
        assert(isfile(library_path) && isfile(loaded_library_path) && ...
            strcmp(file_hash(library_path),file_hash(loaded_library_path)), ...
            'Wrong chamber library loaded.');
        record.chamber_library_requested_path=library_path;
        record.chamber_library_loaded_path=loaded_library_path;
        record.chamber_source_file=chamber_source;
        record.chamber_library_sha256=file_hash(library_path);
        if endpoint_chamber_diagnostic
            record.endpoint_chamber_library_sha256=file_hash(library_path);
        end
        if conservative_buffers
            component_audit=jsondecode(fileread(fullfile(repo,'outputs_storage_audit', ...
                'conservative_buffer_audit_20260909_v2','conservative_buffer_audit.json')));
            assert(component_audit.isolated_component_conservation_pass && ~component_audit.production_recovery_allowed, ...
                'Require independently qualified buffer candidate.');
            if strcmp(buffer_mass_formulation,'direct')
                package='ecc_buffer_coupled'; source_folder='simscape_buffer_coupled';
            else
                package='ecc_buffer_coupled_offset'; source_folder='simscape_buffer_coupled_offset';
            end
            original=fileread(fullfile(repo,'verification','simscape_buffer','+ecc_buffer','conservative_buffer.ssc'));
            aligned=fileread(fullfile(repo,'verification',source_folder,['+' package],'conservative_buffer.ssc'));
            if strcmp(buffer_mass_formulation,'direct')
                assert(strcmp(strrep(original,'% H:left','% H:right'),aligned), ...
                    'Aligned component changed more than the port location.');
            else
                assert(contains(aligned,'mass_offset = {value = {0, ''kg''}, priority = priority.high}') && ...
                    contains(aligned,'der(mass_offset) == mdot_A;') && ...
                    contains(aligned,'stored_mass == initial_stored_mass + mass_offset;'), ...
                    'Offset mass component does not expose the declared zero-based state contract.');
            end
            buffer_build=fullfile(output_root,'buffer_component_build');mkdir(buffer_build);
            copyfile(fullfile(repo,'verification',source_folder,['+' package]),fullfile(buffer_build,['+' package]));
            cd(buffer_build);ssc_build(package);addpath(buffer_build);load_system([package '_lib']);cd(repo);
        end
        for kind={'native','conservative'}
            name=kind{1}; arm=fullfile(output_root,name); mkdir(arm);
            use_endpoint_arm=strcmp(name,'conservative') || (endpoint_chamber_diagnostic && endpoint_all_arms);
            % Keep the native arm as the unmodified hydraulic/thermal
            % baseline. The endpoint chamber and offset buffers belong only
            % to the conservative comparison arm; otherwise the diagnostic
            % changes both arms and cannot localize the chamber effect.
            overrides.branch.independent_conservative_chamber_diagnostic= ...
                use_endpoint_arm;
            [model,options]=Build_HeatDriveECC_EighthRound_Simulink_Model(overrides);
            model_cleanup=onCleanup(@() close_system(model,0));
            arm_simulation_mode=simulation_mode;
            % The conservative arm initializes public Simscape operating
            % points. Keep that diagnostic arm in normal mode because
            % accelerator startup cannot guarantee a time-origin-compatible
            % operating point; the native arm remains accelerated.
            if use_endpoint_arm && pipe_energy_targets
                arm_simulation_mode='normal';
            end
            changed={};buffer_records={};buffer_paths={};
            if use_endpoint_arm
                changed={[model '/SMA_PumpInletConnectingPipeVolume'],[model '/SMA_PumpOutletConnectingPipeVolume']};
                for k=1:2
                    assert(strcmp(get_param(changed{k},'SourceFile'),chamber_source), ...
                        'Wrong diagnostic component.');
                end
                if cycle_count==1 && ~endpoint_chamber_diagnostic
                    initial_observation_root=output_root;
                    initial_observation_path=fullfile(initial_observation_root,'native','observations.mat');
                end
                if cycle_count==1 && endpoint_chamber_diagnostic && strcmp(name,'conservative')
                    % The endpoint native arm is the authoritative cold-start
                    % observation for the paired arm. The qualified v22 seed
                    % remains a prerequisite, but is not a false provenance
                    % source for this independently generated initial state.
                    initial_observation_root=output_root;
                    initial_observation_path=fullfile(initial_observation_root,'native','observations.mat');
                    assert(isfile(initial_observation_path), ...
                        'Endpoint native cold observation is missing.');
                end
                initial_observation_sha256=file_hash(initial_observation_path);
                record.initialization_source_root=initial_observation_root;
                record.initialization_source_observation_sha256=initial_observation_sha256;
                prior=load(initial_observation_path,'native');
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
                        'source_sha256',initial_observation_sha256);
                end
                write_json(fullfile(arm,'cold_inventory_targets.json'),initial_targets);
                if buffer_mass_guess
                    tanks={'ColdFluidBuffer','HotFluidBuffer','SHEXFluidBuffer','SMAHotFluidBuffer'};
                    guesses=cell(size(tanks));
                    for k=1:numel(tanks)
                        p=[model '/' tanks{k}];
                        rows=prior.native(cellfun(@(r) strcmp(r.block_path,p),prior.native));
                        mass=initial_value_any(rows,{'mass','stored_mass'},'kg');
                        assert(strcmp(get_param(p,'mass_specify'),'off') && strcmp(get_param(p,'mass_priority'),'None') && ...
                            strcmp(get_param(p,'level_priority'),'High') && strcmp(get_param(p,'T_I_priority'),'High'), ...
                            'Unexpected original buffer initial-state contract.');
                        guesses{k}=struct('block_path',p,'old_guess',get_param(p,'mass'), ...
                            'old_unit',get_param(p,'mass_unit'),'new_guess_kg',mass, ...
                            'mass_specify','off','mass_priority','None','source_time_s',0, ...
                            'source_sha256',initial_observation_sha256);
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
                    buffer_records=Apply_HeatDriveECC_ColdConservativeBuffers(model,prior.native, ...
                        [package '_lib'],buffer_mass_formulation);
                    buffer_paths=cellfun(@(b) b.block_path,buffer_records,'UniformOutput',false);
                    write_json(fullfile(arm,'buffer_replacement_contract.json'),struct('buffers',{buffer_records}, ...
                        'source_sha256',initial_observation_sha256,'source_time_s',0));
                end
                if pipe_energy_targets
                    [cold_public_targets,targets]=Build_HeatDriveECC_ColdInventoryTargets(model,prior.native, ...
                        options.branch.sma_pump_manifold_volume_m3,buffer_records,chamber_source);
                    write_json(fullfile(arm,'public_inventory_targets.json'),struct('targets',{targets}, ...
                        'source_sha256',initial_observation_sha256, ...
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
                v=evalin('base',names{k}); assert(v.Time(1)==0 && ...
                    abs(v.Time(end)-options.schedule.total_time_s)<=1.0e-9 && ...
                    v.Time(end)>=duration-1.0e-9, ...
                    'Require a schedule covering the declared diagnostic window.');
                commands.(names{k})=struct('time_s',v.Time,'values',v.Data);
            end
            save(fullfile(arm,'configuration.mat'),'options','commands','-v7.3');
            log_window_cycles=min(cycle_count,2);
            log_window_start=max(0,duration-log_window_cycles*10);
            record.simscape_log_window_start_s=log_window_start;
            set_param(model,'LoadInitialState','off','SimscapeUseOperatingPoints','off', ...
                'StartTime','0','StopTime',num2str(duration,'%.17g'), ...
                'Solver',options.simulation.solver,'FixedStep',num2str(options.simulation.fixed_step_s,'%.17g'), ...
                'SimulationMode',arm_simulation_mode,'ReturnWorkspaceOutputs','on', ...
                'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
                'SaveFinalState','off','SaveOperatingPoint','off','SaveState','off', ...
                'SaveTime','off','SaveOutput','off','SignalLogging','off');
            if cycle_count>1
                set_param(model,'SimscapeLogLimitData','on', ...
                    'SimscapeLogDataHistory',ceil(log_window_cycles*10/ ...
                    options.simscape.local_solver_sample_time_s)+2);
            end
            if use_endpoint_arm && pipe_energy_targets
                assignin('base','cold_public_targets',cold_public_targets);
                set_param(model,'SimscapeUseOperatingPoints','on','SimscapeOperatingPoint','cold_public_targets');
            end
            pressure_probe_contract=Instrument_HeatDriveECC_PumpPressureProbes(model,arm);
            stage4_controller_probe_contract= ...
                Instrument_HeatDriveECC_Stage4ControllerProbes(model,arm);
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
            input=input.setModelParameter('CaptureErrors','on', ...
                'SimulationMode',arm_simulation_mode);
            if use_endpoint_arm && pipe_energy_targets
                input=input.setVariable('cold_public_targets',cold_public_targets);
            end
            output=sim(input);
            if ~isempty(output.ErrorMessage)
                failure_message=output.ErrorMessage;
                Export_HeatDriveECC_FailedColdObservations(output,model,metadata, ...
                    fullfile(arm,'failed_public_observations.mat'));
                error('HeatDriveECC:ColdDiagnosticSimulationFailed','%s',failure_message);
            end
            if specific_inventory && use_endpoint_arm
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
                    variables=inventory_variables;
                    if strcmp(buffer_mass_formulation,'zero_based_offset') && ismember(block{1},buffer_paths)
                        variables={'mass_offset','stored_energy','T_I','p_I'};
                    end
                    for variable=variables
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
            probe_names=fieldnames(signals);
            probe_names=probe_names(startsWith(probe_names,'pump_pressure_'));
            pressure_probe_signals=struct();
            for probe_idx=1:numel(probe_names)
                pressure_probe_signals.(probe_names{probe_idx})=signals.(probe_names{probe_idx});
            end
            pressure_probe_contract.simulation_run=true;
            pressure_probe_contract.observation_signal_names=probe_names;
            write_json(fullfile(arm,'pump_pressure_probe_contract.json'),pressure_probe_contract);
            record.pressure_probe_contracts{end+1}=pressure_probe_contract;
            controller_probe_names=fieldnames(signals);
            controller_probe_names=controller_probe_names(startsWith( ...
                controller_probe_names,'stage4_'));
            stage4_controller_probe_signals=struct();
            for probe_idx=1:numel(controller_probe_names)
                stage4_controller_probe_signals.(controller_probe_names{probe_idx})= ...
                    signals.(controller_probe_names{probe_idx});
            end
            stage4_controller_probe_contract.simulation_run=true;
            stage4_controller_probe_contract.observation_signal_names= ...
                controller_probe_names;
            write_json(fullfile(arm,'stage4_controller_probe_contract.json'), ...
                stage4_controller_probe_contract);
            record.stage4_controller_probe_contracts{end+1}= ...
                stage4_controller_probe_contract;
            save(fullfile(arm,'observations.mat'),'native','source_traces','boundary_metadata', ...
                'signals','pressure_probe_signals','stage4_controller_probe_signals','-v7.3');
            record.cases{end+1}=struct('arm',name,'simulation_mode',arm_simulation_mode, ...
                'topology_update_pass',true, ...
                'storage_components',numel(metadata.storage_blocks),'native_trace_count',numel(native), ...
                'source_count',boundary_metadata.source_count, ...
                'pressure_probe_count',numel(probe_names), ...
                'pressure_probe_signal_names',{probe_names}, ...
                'stage4_controller_probe_count',numel(controller_probe_names), ...
                'stage4_controller_probe_signal_names',{controller_probe_names}, ...
                'observation_sha256',file_hash(fullfile(arm,'observations.mat')));
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
        'port_area','p_environment','gravity','reference_temperature','auxiliary_depth', ...
        'initial_stored_mass'};
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
                if ~isempty(regexp(n,'^(p_I|T_I|u_I|mass|mass_offset|stored_mass|initial_stored_mass|stored_energy|level)(_|$)','once'))
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

function v=initial_value_any(rows,names,unit)
    for name_idx=1:numel(names)
        selected=rows(cellfun(@(r) strcmp(r.state_name,names{name_idx}),rows));
        if isscalar(selected)
            assert(selected{1}.time_s(1)==0,'Require actual native cold initial sample.');
            v=value(simscape.Value(selected{1}.values(1),selected{1}.unit),unit);
            assert(isfinite(v),'Nonfinite cold coordinate.');
            return;
        end
    end
    error('HeatDriveECC:MissingColdInitialCoordinate', ...
        'Require one declared native cold initial coordinate.');
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
function value=canonical_path(path)
    value=char(java.io.File(path).getCanonicalPath());
end
function restore_path(folder,oldpath)
    cd(folder);path(oldpath);
end
