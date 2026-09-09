function record=Inspect_HeatDriveECC_ColdCompiledStates(repo,output_root,prefer_inventory,component_priorities,formulation,consistency_tolerance,residual_tolerance,capture_runtime,tighten_global,scale_buffers,normal_mode,momentum_buffers,disable_regularization,half_step,global_implicit,projection,initial_derivative,analytic_derivative,duration,ps_controller,initial_bias_only,export_initial_flux,initial_mdot_probe,constant_bias_derivative,bias_value_path,remove_inactive_controller,passive_ps_observer,separate_observer_network,live_observer_flow,actuate_ps_output,algebraic_structure_only,external_lag,held_max_step,held_error_control,held_error_control_level,held_solver_method)
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
    if nargin<13,disable_regularization=false;end
    if nargin<14,half_step=false;end
    if nargin<15,global_implicit=false;end
    if nargin<16,projection=false;end
    if nargin<17,initial_derivative=false;end
    if nargin<18,analytic_derivative=false;end
    if nargin<19,duration=0;end
    if nargin<20,ps_controller=false;end
    if nargin<21,initial_bias_only=false;end
    if nargin<22,export_initial_flux=false;end
    if nargin<23,initial_mdot_probe=false;end
    if nargin<24,constant_bias_derivative=false;end
    if nargin<25,bias_value_path=false;end
    if nargin<26,remove_inactive_controller=false;end
    if nargin<27,passive_ps_observer=false;end
    if nargin<28,separate_observer_network=false;end
    if nargin<29,live_observer_flow=false;end
    if nargin<30,actuate_ps_output=false;end
    if nargin<31,algebraic_structure_only=false;end
    if nargin<32,external_lag=false;end
    if nargin<33,held_max_step=[];end
    if nargin<34,held_error_control=false;end
    if nargin<35,held_error_control_level='tight';end
    if nargin<36,held_solver_method='ode15s';end
    assert(ischar(held_solver_method) && any(strcmp(held_solver_method,{'ode15s','ode23t'})) && ...
        (strcmp(held_solver_method,'ode15s') || (held_error_control && strcmp(held_error_control_level,'moderate'))), ...
        'The one-step solver trial requires the qualified moderate held-interval controls.');
    assert(ischar(held_error_control_level) && any(strcmp(held_error_control_level,{'tight','moderate'})) && ...
        (held_error_control || strcmp(held_error_control_level,'tight')), ...
        'Only predeclared held error-control levels are allowed.');
    held_interval=external_lag && duration==.04;
    assert(islogical(held_error_control) && isscalar(held_error_control) && ...
        (~held_error_control || (held_interval && isequal(held_max_step,.00025) && ~tighten_global)), ...
        'Global error-control trial is limited to the declared quarter-step held interval.');
    assert(isempty(held_max_step) || (held_interval && isnumeric(held_max_step) && isscalar(held_max_step) && ...
        ismember(held_max_step,[.0005,.00025]) && ~tighten_global && ~half_step), ...
        'Only the declared held-interval global-step convergence trial is allowed.');
    assert(islogical(external_lag) && isscalar(external_lag) && ...
        (~external_lag || (actuate_ps_output && ~tighten_global && (duration==0 || held_interval) && capture_runtime)), ...
        'External lag requires a separate cold-only actual-actuation diagnostic.');
    assert(islogical(algebraic_structure_only) && isscalar(algebraic_structure_only) && ...
        (~algebraic_structure_only || (actuate_ps_output && ~tighten_global && duration==0 && capture_runtime)), ...
        'Structure-only inspection requires the unchanged initial-actuation baseline.');
    assert(islogical(actuate_ps_output) && isscalar(actuate_ps_output) && (~actuate_ps_output || live_observer_flow));
    assert(islogical(live_observer_flow) && isscalar(live_observer_flow) && (~live_observer_flow || separate_observer_network));
    assert(islogical(separate_observer_network) && isscalar(separate_observer_network) && ...
        (~separate_observer_network || passive_ps_observer));
    assert(islogical(passive_ps_observer) && isscalar(passive_ps_observer) && ...
        (~passive_ps_observer || remove_inactive_controller),'Passive observer requires the qualified inactive-controller removal.');
    assert(islogical(remove_inactive_controller) && isscalar(remove_inactive_controller) && ...
        (~remove_inactive_controller || bias_value_path),'Inactive controller removal requires the bounded bias-value path.');
    assert(islogical(bias_value_path) && isscalar(bias_value_path) && ...
        (~bias_value_path || (initial_derivative && ~ps_controller && (duration==0 || held_interval) && ~export_initial_flux)), ...
        'Value-edge isolation requires the original initial-derivative controller and t=0 only.');
    assert(islogical(constant_bias_derivative) && isscalar(constant_bias_derivative) && ...
        (~constant_bias_derivative || initial_mdot_probe),'Constant bias derivative requires the frozen-flow t=0 diagnostic.');
    assert(islogical(initial_mdot_probe) && isscalar(initial_mdot_probe) && ...
        (~initial_mdot_probe || (ps_controller && initial_bias_only && duration==0 && ~export_initial_flux)), ...
        'Frozen measured flow is only admissible in the passive t=0 observer diagnostic.');
    assert(islogical(export_initial_flux) && isscalar(export_initial_flux) && ...
        (~export_initial_flux || (duration==0 && initial_derivative && ~ps_controller && ~initial_bias_only)), ...
        'Initial flux export is read-only on the qualified initial-derivative configuration.');
    assert(islogical(initial_bias_only) && isscalar(initial_bias_only) && (~initial_bias_only || ps_controller));
    assert(islogical(ps_controller) && isscalar(ps_controller) && ...
        (~ps_controller || (projection && ~initial_derivative && ~analytic_derivative && duration==0)), ...
        'PS controller requires its own cold initialization-only diagnostic.');
    assert(islogical(analytic_derivative) && isscalar(analytic_derivative) && ...
        (~analytic_derivative || (projection && ~initial_derivative)),'Separate analytic derivative diagnostic required.');
    assert(isscalar(duration) && (duration==0 || held_interval || (analytic_derivative && duration==.2)), ...
        'Only declared initial/onset diagnostics are allowed.');
    assert(islogical(initial_derivative) && isscalar(initial_derivative) && (~initial_derivative || projection), ...
        'Initial pressure derivative diagnostic requires global Projection.');
    assert(islogical(capture_runtime) && isscalar(capture_runtime),'Require explicit callback capture choice.');
    assert(any(strcmp(formulation,{'explicit','specific_inventory'})),'Unknown inventory formulation.');
    specific_inventory=strcmp(formulation,'specific_inventory');
    assert(islogical(projection) && isscalar(projection) && (~projection || global_implicit), ...
        'Projection diagnostic must use the declared global implicit configuration.');
    assert(islogical(global_implicit) && isscalar(global_implicit) && (~global_implicit || ...
        (specific_inventory && capture_runtime && ~half_step && ~disable_regularization && ~momentum_buffers && ...
        ~normal_mode && ~scale_buffers && (~tighten_global || actuate_ps_output) && isempty(consistency_tolerance) && isempty(residual_tolerance))), ...
        'Global implicit initialization diagnostic must retain physics and all original targets.');
    assert(islogical(half_step) && isscalar(half_step) && (~half_step || ...
        (specific_inventory && capture_runtime && ~disable_regularization && ~momentum_buffers && ~normal_mode && ...
        ~scale_buffers && ~tighten_global && isempty(consistency_tolerance) && isempty(residual_tolerance))), ...
        'Half-step diagnostic must retain physics, targets, priorities and all other solver options.');
    assert(islogical(disable_regularization) && isscalar(disable_regularization) && (~disable_regularization || ...
        (specific_inventory && capture_runtime && ~momentum_buffers && ~normal_mode && ~scale_buffers && ~tighten_global && ...
        isempty(consistency_tolerance) && isempty(residual_tolerance))), ...
        'Regularization-only diagnostic must retain all targets, physics, tolerances and scaling.');
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
    [code,dirty]=system(sprintf('git -C "%s" status --porcelain -- .',repo));
    assert(code==0 && isempty(strtrim(dirty)),'Commit relevant source first.');
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
    record.global_tolerance_override=tighten_global || held_error_control;
    record.buffer_nominal_scaling_requested=scale_buffers;
    record.normal_mode_requested=normal_mode;
    record.momentum_buffers_requested=momentum_buffers;
    record.momentum_contract=momentum_contract;
    record.disable_regularization_requested=disable_regularization;
    record.half_step_requested=half_step;
    record.global_implicit_requested=global_implicit;
    record.projection_requested=projection;
    record.initial_pressure_derivative_requested=initial_derivative;
    record.analytic_pressure_derivative_requested=analytic_derivative;
    record.ps_controller_requested=ps_controller;
    record.initial_bias_only_requested=initial_bias_only;
    record.initial_flux_export_requested=export_initial_flux;
    record.initial_mdot_probe_requested=initial_mdot_probe;
    record.constant_bias_derivative_requested=constant_bias_derivative;
    record.bias_value_path_requested=bias_value_path;
    record.remove_inactive_controller_requested=remove_inactive_controller;
    record.passive_ps_observer_requested=passive_ps_observer;
    record.separate_observer_network_requested=separate_observer_network;
    record.live_observer_flow_requested=live_observer_flow;
    record.actuate_ps_output_requested=actuate_ps_output;
    record.tight_actuation_tolerance_trial=tighten_global && actuate_ps_output;
    record.algebraic_structure_only=algebraic_structure_only;
    record.external_lag_requested=external_lag;
    record.held_interval_requested=held_interval;
    record.held_max_step_override_s=held_max_step;
    record.held_error_control_trial=held_error_control;
    record.held_error_control_level=held_error_control_level;
    record.held_solver_method=held_solver_method;
    if strcmp(held_solver_method,'ode23t')
        rejected=fullfile(repo,'outputs_storage_audit','hybrid_held_moderate_control_audit_20260910','held_interval_audit.json');
        assert(strcmp(file_hash(rejected),'48ECCCA5D663B1F423CA838D5A84F7EECD9A74D59B4564079B4F941FC8E7A2F9'), ...
            'The moderate NDF rejection evidence changed.');
        record.held_ndf_rejection_sha256=file_hash(rejected);
    end
    if held_error_control
        qualified=fullfile(repo,'outputs_storage_audit','hybrid_held_quarterstep_audit_20260910','held_interval_audit.json');
        assert(strcmp(file_hash(qualified),'6C6A9CA6885AFD49693F014F15EC66C2A39C73784A3742E2667AD705BAAAA975'), ...
            'The measured quarter-step rejection evidence changed.');
        q=jsondecode(fileread(qualified));
        assert(q.evidence_audit_pass && q.initial_coordinate_audit.strict_initial_coordinate_gate && ...
            q.compiled_algebraic_loops==0 && ~q.local_balance_gate && ~q.production_recovery_allowed);
        record.held_error_control_reference_sha256=file_hash(qualified);
        if strcmp(held_error_control_level,'moderate')
            rejected=fullfile(repo,'outputs_storage_audit','hybrid_held_error_control_audit_20260910','held_error_control_audit.json');
            assert(strcmp(file_hash(rejected),'0788BA8C9DC025CA20F61894581DE40E3CEF283EE75214AF6C4E2FCD4CAA5B50'), ...
                'The tight-control rejection evidence changed.');
            record.held_tight_control_rejection_sha256=file_hash(rejected);
        end
    end
    record.diagnostic_stop_time_s=duration;
    record.initialization_only=duration==0;
    record.loaded_chamber_library=selected_library;record.loaded_library_sha256=file_hash(selected_library);
    record.chamber_package_resolution=evalc('which(chamber_source,''-all'')');
    record.chamber_source_file=chamber_source;
    try
        [model,options]=Build_HeatDriveECC_EighthRound_Simulink_Model(config.options);
        mc=onCleanup(@() close_system(model,0));
        solvers=find_system(model,'LookUnderMasks','all','FollowLinks','on','MaskType','Solver Configuration');
        assert(isscalar(solvers),'Require the single coupled physical solver.');
        runtime_names={'ResolveIndetEquations','DoFixedCost','ComputeImpulses','ImpulseIterations','IndexReductionMethod','DoDC'};
        runtime_before=struct();
        for k=1:numel(runtime_names),runtime_before.(runtime_names{k})=get_param(solvers{1},runtime_names{k});end
        record.runtime_solver_options_before=runtime_before;
        if disable_regularization
            assert(strcmp(runtime_before.ResolveIndetEquations,'on') && strcmp(get_param(solvers{1},'UseLocalSolver'),'on'), ...
                'Require the known local-solver regularization baseline.');
            set_param(solvers{1},'ResolveIndetEquations','off');
        end
        if projection
            assert(strcmp(runtime_before.IndexReductionMethod,'DerivativeReplacement'),'Unexpected index reduction baseline.');
            set_param(solvers{1},'IndexReductionMethod','Projection');
        end
        runtime_after=struct();
        for k=1:numel(runtime_names),runtime_after.(runtime_names{k})=get_param(solvers{1},runtime_names{k});end
        record.runtime_solver_options_after=runtime_after;
        names={'ConsistencyTolSource','ConsistencyAbsTol','ConsistencyRelTol','ConsistencyTolFactor', ...
            'ResidualTolerance','UseLocalSolver','LocalSolverChoice','LocalSolverSampleTime'};
        before=struct();for k=1:numel(names),before.(names{k})=get_param(solvers{1},names{k});end
        record.consistency_settings_before=before;
        if half_step
            assert(strcmp(before.LocalSolverSampleTime,'0.001'),'Unexpected baseline local step.');
            set_param(solvers{1},'LocalSolverSampleTime','0.0005');
        end
        if global_implicit
            assert(strcmp(before.UseLocalSolver,'on'),'Unexpected local solver baseline.');
            set_param(solvers{1},'UseLocalSolver','off');
        end
        record.global_tolerances=struct('RelTol',get_param(model,'RelTol'),'AbsTol',get_param(model,'AbsTol'));
        if tighten_global || held_error_control
            assert(strcmp(record.global_tolerances.RelTol,'1e-2') && strcmp(record.global_tolerances.AbsTol,'1e-3'), ...
                'Unexpected global baseline tolerances.');
            if held_error_control && strcmp(held_error_control_level,'moderate')
                set_param(model,'RelTol','1e-6','AbsTol','1e-8');
            else
                set_param(model,'RelTol','1e-10','AbsTol','1e-12');
            end
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
        fixed_step=options.simulation.fixed_step_s;
        record.fixed_step_before=fixed_step;
        if half_step
            assert(fixed_step==.001,'Unexpected baseline global fixed step.');
            fixed_step=.0005;
        end
        record.fixed_step_after=fixed_step;
        assembly_stop=duration;if held_interval,assembly_stop=0;end
        set_param(model,'LoadInitialState','off','SimscapeUseOperatingPoints','on','SimscapeOperatingPoint','cold_public_targets', ...
            'StartTime','0','StopTime',num2str(assembly_stop,'%.17g'),'SimulationMode',simulation_mode, ...
            'Solver',options.simulation.solver,'FixedStep',num2str(fixed_step,'%.17g'), ...
            'SaveState','on','StateSaveName','states','SaveFormat','Dataset','SaveFinalState','off','SaveOperatingPoint','off', ...
            'ReturnWorkspaceOutputs','on','SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off');
        if global_implicit
            assert(strcmp(get_param(model,'Solver'),'ode3'),'Unexpected baseline global solver.');
            set_param(model,'SolverType','Variable-step','Solver','ode15s','MaxStep','0.001','InitialStep','auto');
            if ~isempty(held_max_step),set_param(model,'MaxStep',num2str(held_max_step,'%.17g'));end
            if strcmp(held_solver_method,'ode23t'),set_param(model,'Solver','ode23t');end
        end
        record.global_solver_configuration=struct('Solver',get_param(model,'Solver'), ...
            'SolverType',get_param(model,'SolverType'),'MaxStep',get_param(model,'MaxStep'), ...
            'InitialStep',get_param(model,'InitialStep'));
        record.solver_iteration_options=struct('SolverResetMethod',get_param(model,'SolverResetMethod'), ...
            'MaxOrder',get_param(model,'MaxOrder'));
        record.solver_failure_policy_before=struct('MinStepSizeMsg',get_param(model,'MinStepSizeMsg'), ...
            'MaxConsecutiveMinStep',get_param(model,'MaxConsecutiveMinStep'),'MinStep',get_param(model,'MinStep'));
        if held_error_control
            set_param(model,'MinStepSizeMsg','error');
        end
        record.solver_failure_policy_after=struct('MinStepSizeMsg',get_param(model,'MinStepSizeMsg'), ...
            'MaxConsecutiveMinStep',get_param(model,'MaxConsecutiveMinStep'),'MinStep',get_param(model,'MinStep'));
        record.output_sampling_settings=struct();
        for key={'OutputOption','OutputTimes','Refine','Decimation','SimscapeLogDecimation','SimscapeLogLimitData'}
            record.output_sampling_settings.(key{1})=get_param(model,key{1});
        end
        if initial_derivative
            record.initial_pressure_derivative_contract=Configure_HeatDriveECC_ColdInitialPressureDerivative(model);
        end
        if bias_value_path
            record.pressure_value_path_contract=Configure_HeatDriveECC_ColdPressureValuePath(repo,model,record.initial_pressure_derivative_contract);
        end
        if remove_inactive_controller
            record.inactive_controller_removal_contract=Configure_HeatDriveECC_ColdInactiveControllerRemoval(model,record.pressure_value_path_contract);
        end
        if passive_ps_observer
            record.passive_ps_observer_contract=Configure_HeatDriveECC_ColdPassivePSObserver(repo,model,record.inactive_controller_removal_contract,separate_observer_network,live_observer_flow,external_lag);
        end
        if actuate_ps_output
            record.ps_initial_actuation_contract=Configure_HeatDriveECC_ColdPSInitialActuation(repo,model,record.passive_ps_observer_contract);
        end
        if analytic_derivative
            record.analytic_pressure_derivative_contract=Configure_HeatDriveECC_ColdPressureDerivative(repo,model);
        end
        if ps_controller
            record.ps_controller_contract=Configure_HeatDriveECC_ColdPSController(repo,model,initial_bias_only,initial_mdot_probe,constant_bias_derivative);
        end
        if capture_runtime
            assignin('base','cold_initialization_context',{});
            assignin('base','cold_public_target_records',public_targets);
            for callback={'InitFcn','StartFcn','StopFcn'}
                assert(isempty(strtrim(get_param(model,callback{1}))),'Do not replace an existing model callback.');
                set_param(model,callback{1},sprintf('Capture_HeatDriveECC_ColdInitializationContext(''%s'',''%s'');',model,callback{1}));
            end
        end
        if algebraic_structure_only
            record.stage='compiled_algebraic_structure';
            record.algebraic_structure=Inspect_HeatDriveECC_CompiledAlgebraicStructure(model);
            record.runtime_callbacks=evalin('base','cold_initialization_context');
        else
        if external_lag
            record.stage='hybrid_compiled_algebraic_structure';
            record.algebraic_structure=Inspect_HeatDriveECC_CompiledAlgebraicStructure(model);
            record.pre_simulation_compile_callbacks=evalin('base','cold_initialization_context');
            assignin('base','cold_initialization_context',{});
        end
        if held_interval
            record.held_interval_contract=Configure_HeatDriveECC_HybridHeldInterval(repo,model,duration);
        end
        if held_error_control
            record.stage='ready_for_held_error_control_simulation';
            destination=fullfile(output_root,'pre_simulation_inspection.json');
            assert(~isfile(destination),'Do not overwrite pre-simulation evidence.');
            fid=fopen(destination,'w','n','UTF-8');assert(fid>=0);fc=onCleanup(@() fclose(fid));
            fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));clear fc
        end
        record.stage='initialization_state_logging';record.simulation_run=true;
        input=Simulink.SimulationInput(model);input=input.setVariable('cold_public_targets',cold_public_targets);
        input=input.setModelParameter('CaptureErrors','on');simulation_clock=tic;output=sim(input);
        record.simulation_wall_seconds=toc(simulation_clock);
        record.simulation_error_message=output.ErrorMessage;
        if capture_runtime,record.runtime_callbacks=evalin('base','cold_initialization_context');end
        if duration>0 || export_initial_flux
            record.stage='export_onset_observations';
            if export_initial_flux,record.stage='export_initial_flux_observations';end
            changed=cellfun(@(t) t.block_path,buffers,'UniformOutput',false);
            chamber_paths=arrayfun(@(t) t.block_path,targets,'UniformOutput',false);
            if ~isempty(output.ErrorMessage)
                metadata=jsondecode(fileread(fullfile(source,'conservative','inventory_metadata.json')));
                metadata.storage_blocks=num2cell(metadata.storage_blocks);
                Export_HeatDriveECC_FailedColdObservations(output,model,metadata,fullfile(output_root,'failed_public_observations.mat'));
            else
                native=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model,false,chamber_paths,changed);
                [source_traces,boundary_metadata]=Extract_HeatDriveECC_BoundaryTraces(output.simlog,model);
                signals=struct();names=output.who;
                for k=1:numel(names)
                    v=output.get(names{k});
                    if isa(v,'timeseries'),signals.(names{k})=struct('time_s',v.Time,'values',v.Data);
                    elseif isstruct(v) && isscalar(v) && isfield(v,'time') && isfield(v,'signals') && ...
                            isscalar(v.signals) && isfield(v.signals,'values')
                        signals.(names{k})=struct('time_s',v.time,'values',v.signals.values);
                    end
                end
                save(fullfile(output_root,'observations.mat'),'native','source_traces','boundary_metadata','signals','-v7.3');
                record.observations_sha256=file_hash(fullfile(output_root,'observations.mat'));
            end
        end
        assert(isempty(output.ErrorMessage),output.ErrorMessage);
        if initial_mdot_probe || live_observer_flow
            signal=output.get('mass_flow_sma_stage13_kgps');
            if isa(signal,'timeseries'),t=signal.Time;v=signal.Data;
            else,t=signal.time;v=signal.signals.values;end
            assert(t(1)==0 && t(end)==duration && isvector(v) && numel(v)==numel(t) && all(isfinite(v)) && ...
                ((duration==0 && isscalar(t)) || held_interval));
            record.actual_initial_sensor_mdot_kg_s=v(1);
        end
        for k=1:numel(targets)
            assert(strcmp(get_param(targets(k).block_path,'SourceFile'),chamber_source), ...
                'Actual chamber source changed during initialization.');
        end
        record.post_initialization_source_file_verified=true;
        states=output.get('states');
        state_file='compiled_initial_state_dataset.mat';if held_interval,state_file='compiled_state_dataset.mat';end
        save(fullfile(output_root,state_file),'states','-v7.3');
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
        if ps_controller || passive_ps_observer
            node_name='ColdSMAPSController';if passive_ps_observer,node_name='ColdSMAPassiveObserver';end
            node=log.child(node_name);record.ps_controller_initial={};
            variables={'mdot','target','bias','enable','reset','pressure','lag','integral'};
            units={'kg/s','kg/s','MPa','1','1','MPa','1','MPa'};
            if external_lag
                variables={'lag_input','bias','enable','reset','pressure','lag','integral'};
                units={'1','MPa','1','1','MPa','1','MPa'};
            end
            for j=1:numel(variables)
                child=node.child(variables{j});series=child.series;t=double(time(series));v=double(values(series));
                assert(t(1)==0 && t(end)==duration && isvector(v) && numel(v)==numel(t) && all(isfinite(v)) && ...
                    ((duration==0 && isscalar(t)) || held_interval));
                record.ps_controller_initial{end+1}=struct('name',variables{j},'unit',units{j}, ...
                    'actual',value(simscape.Value(v(1),series.unit),units{j}),'source_time_s',t(1), ...
                    'tag_names',{child.tagNames},'tag_values',{child.tags});
            end
            record.ps_controller_child_ids=node.childIds;
        end
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
            assert(times(1)==0 && isvector(observed) && all(isfinite(observed)) && ...
                ((duration==0 && isscalar(times)) || (duration>0 && times(end)==duration)), ...
                'Require the actual finite t=0 sample and complete diagnostic endpoint.');
            times=times(1);observed=observed(1);
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
