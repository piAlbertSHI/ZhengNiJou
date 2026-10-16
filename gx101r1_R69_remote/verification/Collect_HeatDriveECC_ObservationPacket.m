function result=Collect_HeatDriveECC_ObservationPacket(input,initial,a,b,destination,options,prepared_folder,chambers,buffers,producer,python,role,parent_hash,trial)
% Identical measured packet path shared with the qualified C62 split test.
    if nargin<12,role='split_comparison';end
    if nargin<13,parent_hash='';end
    if nargin<14,trial=struct();end
    sensitivity=any(strcmp(role,{'runtime_sensitivity_cold','runtime_sensitivity_transient'}));
    cold=strcmp(role,'runtime_boundary_cold_baseline') || strcmp(role,'runtime_sensitivity_cold');
    assert(any(strcmp(role,{'split_comparison','bounded_transient_observation','runtime_boundary_cold_baseline','runtime_boundary_transient','runtime_boundary_Tc_candidate','runtime_boundary_Tc_continuation','runtime_horizon_comparison','runtime_sensitivity_cold','runtime_sensitivity_transient'})));
    candidate=any(strcmp(role,{'runtime_boundary_Tc_candidate','runtime_boundary_Tc_continuation'}));
    horizon=strcmp(role,'runtime_horizon_comparison');
    assert(candidate || horizon || isempty(fieldnames(trial)));
    if candidate
        Require_HeatDriveECC_RuntimeTcTrial(trial);
        assert(trial.candidate_Tc_K==options.system.Tchex_K);
    end
    assert(strcmp(role,'split_comparison') || cold || ~isempty(regexp(parent_hash,'^[A-F0-9]{64}$','once')));
    assert(~isfolder(destination),'Never overwrite a measured packet.');
    model=input.ModelName;
    mkdir(destination);arm=fullfile(destination,'native');mkdir(arm);
    if cold
        assert(isempty(initial) && a==0 && b==20 && isempty(parent_hash));source_snapshot=0;
    else
        assert(~isempty(initial));source_snapshot=initial.snapshotTime;
    end
    write_json(fullfile(destination,'simulation_start.json'),struct('window_s',[a b], ...
        'parent_snapshot_s',source_snapshot,'independent_cold_start',cold,'simulation_returned_without_error',false));
    simulation_clock=tic;
    if cold
        output=sim(input.setModelParameter('StopTime',num2str(b,'%.17g')));
    else
        output=sim(input.setModelParameter('StopTime',num2str(b,'%.17g')).setInitialState(initial));
    end
    simulation_wall_s=toc(simulation_clock);
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
    native=slice_traces(native,a,b);source_traces=slice_traces(source_traces,a,b);
    assert(numel(observation.states)==74 && numel(fieldnames(signals))==201 && ...
        numel(native)==1262 && numel(source_traces)==162,'Incomplete actual packet.');
    save(fullfile(arm,'observations.mat'),'native','source_traces','boundary_metadata','signals','-v7.3');
    for item={'configuration.mat','inventory_metadata.json','tl_connectivity.json', ...
            'thermal_connectivity.json','buffer_replacement_contract.json'}
        copyfile(fullfile(prepared_folder,item{1}),fullfile(arm,item{1}));
    end
    physical=Extract_HeatDriveECC_PhysicalLogs(output,options,model,false);
    physical.authority='physical_simscape_to_workspace_logs';physical.legacy_surrogate_used_for_results=false;
    physical.sim_call_count=1;physical.walltime_s=NaN;
    provenance=struct('checkpoint_restart_used',~cold,'checkpoint_chain_verified',~cold,'sim_call_count',1, ...
        'solver',options.simulation.solver,'fixed_step_s',options.simulation.fixed_step_s, ...
        'simulation_mode',options.simulation.mode);
    timing_path=fullfile(destination,'simulation_timing.json');
    timing=struct('schema','heatdrive_ecc_packet_simulation_timing_v1','window_s',[a b], ...
        'sim_call_wall_s',simulation_wall_s,'metadata_available',false, ...
        'timing_is_physical_gate',false,'simulation_settings_changed',false,'source_state_edited',false);
    try
        timing.vendor_timing=output.SimulationMetadata.TimingInfo;
        timing.vendor_timing=rmfield(timing.vendor_timing,'ProfilerData');
        timing.actual_simulation_mode=output.SimulationMetadata.ModelInfo.SimulationMode;
        timing.metadata_available=true;
    catch ME
        timing.metadata_error=ME.message;
    end
    write_json(timing_path,timing);
    if candidate || horizon
        config_path=fullfile(arm,'configuration.mat');saved=load(config_path);
        saved.plant_build_options=saved.options;saved.options=options;
        if candidate,saved.runtime_boundary_trial=trial;else,saved.runtime_horizon_comparison=trial;end
        save(config_path,'-struct','saved','-v7.3');clear saved
    end
    view=Make_HeatDriveECC_MechanismWindow(physical,options,provenance,destination);
    checked=Validate_HeatDriveECC_EighthRound_Physics(view);
    mechanism=struct('checks',checked.checks,'passed',checked.passed,'diagnostics',checked.diagnostics, ...
        'analysis_window',view.analysis_window,'provenance',provenance, ...
        'full_result_arrays_duplicated_in_JSON',false);
    write_json(fullfile(destination,'mechanism.json'),mechanism);
    manifest=struct('schema','heatdrive_ecc_split_observation_packet_v1','producer',producer, ...
        'window_s',[a b],'source_snapshot_s',source_snapshot,'history_cap_cycles',2, ...
        'state_history_cap_cycles',11,'simulation_returned_without_error',true, ...
        'strict_vendor_restore',~cold,'checksum_policy','error/error','source_state_edited',false,'production_recovery_allowed',false, ...
        'complete_OP_sha256',file_hash(fullfile(destination,'comparison_only_complete_op.mat')), ...
        'packet_role',role,'parent_complete_OP_sha256',parent_hash);
    manifest.independent_cold_start=cold;
    manifest.simulation_timing_sha256=file_hash(timing_path);
    manifest.temperature_configurability=options.system.cold_boundary_temperature_configurability;
    manifest.prescribed_Tc_K=options.system.Tchex_K;manifest.command_horizon_cycles=options.cycle_count;
    if horizon
        assert(trial.source_snapshot_s==a && b==a+20 && trial.source_state_edited==false && trial.comparison_only);
        manifest.horizon_comparison=trial;manifest.source_generation_horizon_cycles=trial.source_horizon_cycles;
        manifest.command_horizon_cycles=trial.actual_horizon_cycles;
    end
    if candidate
        manifest.boundary_trial=trial;
        if strcmp(role,'runtime_boundary_Tc_continuation')
            manifest.continuation=trial.continuation;manifest.boundary_trial=rmfield(trial,'continuation');
        end
    end
    paths={'native/observations.mat','native/configuration.mat','native/inventory_metadata.json', ...
        'native/tl_connectivity.json','native/thermal_connectivity.json', ...
        'native/buffer_replacement_contract.json','mechanism.json','observed_states.mat'};
    if sensitivity
        copyfile(fullfile(prepared_folder,'sensitivity_case_contract.json'),fullfile(arm,'sensitivity_case_contract.json'));
        manifest.sensitivity_case_scope_only=true;
        manifest.sensitivity_case_contract_sha256=file_hash(fullfile(arm,'sensitivity_case_contract.json'));
        paths{end+1}='native/sensitivity_case_contract.json';
    end
    % JSON struct keys cannot contain slashes. Persist path/hash rows, then normalize in Python.
    entries=cell(size(paths));
    for k=1:numel(paths),entries{k}=struct('path',paths{k},'sha256',file_hash(fullfile(destination,paths{k})));end
    manifest.input_files=entries;
    write_json(fullfile(destination,'packet_manifest.json'),manifest);
    clear output physical native source_traces signals observation diagnostic_operating_point
    validator=fullfile(fileparts(mfilename('fullpath')),'Verify_HeatDriveECC_ObservationPacket.py');
    [status,message]=system(sprintf('"%s" "%s" --packet-root "%s"',python,validator,destination));
    fid=fopen(fullfile(destination,'packet_gate_stdout.log'),'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s',message);fclose(fid);
    gate_file=fullfile(destination,'packet_gate.json');
    assert(status==0 && isfile(gate_file),'Packet gate failed; inspect %s',destination);
    gate=jsondecode(fileread(gate_file));assert(gate.gate_pass,'A failed packet cannot propagate.');
    result=destination;
end

function traces=slice_traces(traces,start,stop)
    for k=1:numel(traces)
        row=traces{k};t=row.time_s(:);tolerance=16*eps(max([abs(start),abs(stop),1]));
        selected=t>=start-tolerance & t<=stop+tolerance;
        row.time_s=t(selected);row.values=row.values(selected,:);
        assert(numel(row.time_s)==round((stop-start)/.001)+1 && ...
            abs(row.time_s(1)-start)<=tolerance && abs(row.time_s(end)-stop)<=tolerance, ...
            'Only complete measured packet samples may be exported.');
        traces{k}=row;
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
