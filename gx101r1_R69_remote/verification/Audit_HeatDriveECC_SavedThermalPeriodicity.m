function record = Audit_HeatDriveECC_SavedThermalPeriodicity(source_root, mechanism_root, pair_receipt, output_root)
% Public signals retain twenty cycles; native ledgers retain two. Keep these scopes separate.
    assert(~isfolder(output_root), 'Never overwrite a thermal-periodicity decision.');
    execution=jsondecode(fileread(fullfile(source_root,'cold_chamber_execution.json')));
    mechanism=jsondecode(fileread(fullfile(mechanism_root,'saved_mechanism_audit.json')));
    original=jsondecode(fileread(pair_receipt));
    assert(execution.requested_arm_collection_pass && isempty(execution.error_message) && ...
        mechanism.mechanism_pass && numel(fieldnames(mechanism.checks))==73 && ...
        all(structfun(@logical,mechanism.checks)) && ...
        strcmp(mechanism.source_execution_sha256,file_hash(fullfile(source_root,'cold_chamber_execution.json'))) && ...
        strcmp(mechanism.source_observation_sha256,file_hash(fullfile(source_root,'native','observations.mat'))) && ...
        strcmp(mechanism.source_configuration_sha256,file_hash(fullfile(source_root,'native','configuration.mat'))) && ...
        strcmp(original.mechanism_receipt_sha256,file_hash(fullfile(mechanism_root,'saved_mechanism_audit.json'))), ...
        'Require the same complete mechanism-passing trajectory.');
    saved=load(fullfile(source_root,'native','observations.mat'),'signals');
    configured=load(fullfile(source_root,'native','configuration.mat'),'options');
    view_saved=load(fullfile(mechanism_root,'mechanism_view.mat'),'physical','options','provenance');
    stop=execution.stop_time_s;
    pair_options=configured.options;pair_options.cycle_count=2;
    pair=public_core(saved.signals,stop-20,stop,pair_options);
    names=fieldnames(pair);
    for k=1:numel(names)
        if strcmp(names{k},'cycle_index'), continue; end
        expected=view_saved.physical.(names{k});
        if strcmp(names{k},'time_s'), expected=expected-(stop-20); end
        assert(isequaln(pair.(names{k}),expected),'Direct public field differs from physical extraction: %s',names{k});
    end
    pair_result=Evaluate_HeatDriveECC_Periodicity(pair,pair_options);
    old_values=cellfun(@(name) original.predicates.(name).value, ...
        {'temperature_endpoint','temperature_p99','temperature_rms','phase_extrema','phase_p99','phase_rms'});
    assert(isequaln(periodic_values(pair_result),old_values) && ...
        pair_result.last_cycle_same_phase_temperature_drift_K==original.diagnostic_temperature_peak_K && ...
        pair_result.last_cycle_same_phase_phase_drift==original.diagnostic_phase_peak, ...
        'Shared production statistics changed the immutable pre-refactor pair.');
    % Independently compare the complete original summarizer with its refactored version.
    repo=fileparts(fileparts(mfilename('fullpath')));
    legacy_repo=char(java.io.File(fullfile(source_root,'..','..')).getCanonicalPath());
    if ~strcmp(file_hash(fullfile(legacy_repo,'Summarize_HeatDriveECC_EighthRound_Output.m')), ...
            original.original_summarizer_sha256)
        legacy_repo=fullfile(repo,'outputs_storage_audit',['periodicity_producer_source_',execution.execution_commit]);
    end
    old_path=path;restore_path=onCleanup(@() path(old_path));
    addpath(legacy_repo,'-begin');clear Summarize_HeatDriveECC_EighthRound_Output
    assert(strcmp(file_hash(which('Summarize_HeatDriveECC_EighthRound_Output')),original.original_summarizer_sha256), ...
        'Require the original producer summarizer for the equivalence check.');
    view=Make_HeatDriveECC_MechanismWindow(view_saved.physical,view_saved.options,view_saved.provenance,output_root);
    before=Summarize_HeatDriveECC_EighthRound_Output(view.physical,view.options);
    addpath(repo,'-begin');clear Summarize_HeatDriveECC_EighthRound_Output
    after=Summarize_HeatDriveECC_EighthRound_Output(view.physical,view.options);
    assert(isequaln(before,after), 'Full original summary changed during the statistics extraction.');
    options=configured.options;options.cycle_count=10;
    physical=public_core(saved.signals,stop-100,stop,options);
    p=Evaluate_HeatDriveECC_Periodicity(physical,options);
    values=periodic_values(p);
    limits=[p.periodic_endpoint_limit_K,p.periodic_same_phase_temperature_p99_limit_K, ...
        p.periodic_same_phase_temperature_rms_limit_K,p.periodic_phase_limit, ...
        p.periodic_same_phase_phase_p99_limit,p.periodic_same_phase_phase_rms_limit];
    names={'temperature_endpoint','temperature_p99','temperature_rms','phase_extrema','phase_p99','phase_rms'};
    predicates=struct();
    for k=1:numel(names),predicates.(names{k})=struct('value',values(k),'limit',limits(k),'pass_gate',values(k)<=limits(k));end
    record=struct('schema','heatdrive_ecc_saved_ten_cycle_thermal_periodicity_v1', ...
        'source_execution_commit',execution.execution_commit,'total_cycles',execution.cycle_count, ...
        'source_execution_sha256',mechanism.source_execution_sha256, ...
        'source_observation_sha256',mechanism.source_observation_sha256, ...
        'source_configuration_sha256',mechanism.source_configuration_sha256, ...
        'original_pair_receipt_sha256',file_hash(pair_receipt), ...
        'shared_statistics_sha256',file_hash(which('Evaluate_HeatDriveECC_Periodicity')), ...
        'refactored_summarizer_sha256',file_hash(which('Summarize_HeatDriveECC_EighthRound_Output')), ...
        'pre_refactor_pair_exactly_equal',true,'full_summary_before_after_exactly_equal',true, ...
        'public_material_fields_exactly_equal',true,'original_periodic_predicates_used',true, ...
        'absolute_window_s',[stop-100,stop],'periodic_window_cycles',p.periodic_window_cycles, ...
        'exact_grid_sample_count',numel(physical.time_s),'time_shift_for_analysis_only',true, ...
        'predicates',predicates,'production_temperature_phase_periodic_gate_pass',p.periodic_steady_state, ...
        'phase_attribution',phase_attribution(physical,options,execution.cycle_count,p), ...
        'diagnostic_temperature_peak_K',p.last_cycle_same_phase_temperature_drift_K, ...
        'diagnostic_phase_peak',p.last_cycle_same_phase_phase_drift, ...
        'native_ledger_window_cycles',2,'full_device_first_law_verified',false, ...
        'complete_internal_state_periodicity_verified',false,'simulation_executed',false, ...
        'operating_point_loaded',false,'physical_tolerances_changed',false,'production_recovery_allowed',false, ...
        'outer_solve_eligible',false,'table4_reproduction_claim',false, ...
        'interpretation','Exact ten-cycle public temperature/phase statistics only; native energy/hidden-state qualifications remain separate.');
    mkdir(output_root);write_json(fullfile(output_root,'ten_cycle_thermal_periodicity_audit.json'),record);
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end

function physical = public_core(signals,start,stop,options)
    names={'SMA_Tx21_internal','SE_Tx21_internal','SHEX_hot_sink_temp_out', ...
        'hot_sink_temp_out','cold_sink_temp_out','ECC_constitutive21_output'};
    fields={'SMA_T_21_K','SE_T_21_K','SHEX_T_K','HHEX_T_K','CHEX_T_K'};
    widths=[21,21,1,1,1,252];physical=struct();reference=[];
    tolerance=16*eps(max([abs(start),abs(stop),1]));dt=options.simulation.fixed_step_s;
    for k=1:numel(names)
        row=signals.(names{k});t=row.time_s(:);
        assert(all(isfinite(t)) && all(diff(t)>0) && size(row.values,1)==numel(t), 'Invalid public clock.');
        selected=t>=start-tolerance & t<=stop+tolerance;t=t(selected);
        assert(numel(t)==round((stop-start)/dt)+1 && abs(t(1)-start)<=tolerance && ...
            abs(t(end)-stop)<=tolerance && all(abs(diff(t)-dt)<=tolerance), 'Incomplete public window.');
        if isempty(reference),reference=t;else,assert(isequal(reference,t),'Inconsistent public clocks.');end
        values=row.values(selected,:);
        assert(size(values,2)==widths(k) && all(isfinite(values),'all'), 'Invalid physical public coordinates.');
        if k<=5,physical.(fields{k})=values;
        else,physical.xM_SMA_21=values(:,43:63);physical.xM_SE_21=values(:,64:84);end
    end
    physical.time_s=reference-start;
    physical.cycle_index=HeatDriveECC_CycleStageFromTime(physical.time_s,options);
end

function values = periodic_values(p)
    values=[p.last_cycle_endpoint_drift_K,p.last_cycle_same_phase_temperature_p99_drift_K, ...
        p.last_cycle_same_phase_temperature_rms_drift_K,p.last_cycle_phase_drift, ...
        p.last_cycle_same_phase_phase_p99_drift,p.last_cycle_same_phase_phase_rms_drift];
end

function record = phase_attribution(physical,options,total_cycles,p)
    phase=linspace(0,options.schedule.tau_cycle_s,401).';
    fields={'xM_SMA_21','xM_SE_21'};names={'SMA','SE'};groups=struct();sum_squares=zeros(1,2);
    for k=1:2
        delta=zeros(401*9,21);
        for c=2:10
            current=interp1(physical.time_s,physical.(fields{k}),(c-1)*options.schedule.tau_cycle_s+phase,'linear','extrap');
            prior=interp1(physical.time_s,physical.(fields{k}),(c-2)*options.schedule.tau_cycle_s+phase,'linear','extrap');
            delta((c-2)*401+(1:401),:)=current-prior;
        end
        magnitudes=sort(abs(delta),1);
        nodes=repmat(struct('node',0,'rms',0,'p99',0,'maximum',0, ...
            'peak_current_global_cycle',0,'peak_local_phase_s',0),21,1);
        for node=1:21
            [peak,idx]=max(abs(delta(:,node)));comparison=ceil(idx/401);
            nodes(node)=struct('node',node,'rms',sqrt(mean(delta(:,node).^2)), ...
                'p99',magnitudes(ceil(.99*size(delta,1)),node),'maximum',peak, ...
                'peak_current_global_cycle',total_cycles-9+comparison, ...
                'peak_local_phase_s',phase(mod(idx-1,401)+1));
        end
        sum_squares(k)=sum(delta.^2,'all');
        groups.(names{k})=struct('rms',sqrt(mean(delta.^2,'all')),'nodes',nodes);
    end
    combined=sqrt(sum(sum_squares)/(2*401*9*21));
    assert(abs(combined-p.last_cycle_same_phase_phase_rms_drift)<=32*eps(1), ...
        'Phase attribution does not reproduce the production RMS.');
    groups.SMA.squared_drift_fraction=sum_squares(1)/max(sum(sum_squares),realmin);
    groups.SE.squared_drift_fraction=sum_squares(2)/max(sum(sum_squares),realmin);
    record=struct('groups',groups,'combined_rms',combined,'production_rms_reconstructed',true, ...
        'different_units_combined',false,'causal_parameter_identified',false);
end

function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0,'Cannot save audit.');cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
