function record=Verify_HeatDriveECC_RuntimeBoundaryColdFamily(input,options,folder,chambers,buffers,request,producer)
% Qualify one cold baseline before testing intact same-family boundary tuning.
    model=input.ModelName;source=options.validation.cold_boundary_audit.fixed_source_path;
    assert(options.system.Tchex_K==276.95 && ...
        strcmp(get_param(source,'temperature_conf'),'runtime') && ...
        strcmp(get_param(model,'LoadInitialState'),'off') && ...
        strcmp(get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error') && ...
        Resolve_HeatDriveECC_ObservationCount(get_param(model,'SimscapeLogDataHistory'))==20002 && ...
        Resolve_HeatDriveECC_ObservationCount(get_param(model,'MaxDataPoints'))==110002);
    root=fullfile(folder,'runtime_boundary_family');assert(~isfolder(root));mkdir(root);
    baseline=fullfile(root,'cold_C002');
    record=struct('schema','heatdrive_ecc_runtime_boundary_cold_family_v1','producer',producer, ...
        'independent_cold_start',true,'old_complete_state_imported',false, ...
        'source_probe_sha256',file_hash(request.boundary_probe_path),'actual_cold_window_s',[0 20], ...
        'temperature_K',276.95,'temperature_configurability','runtime','checksum_policy','error/error', ...
        'cold_baseline_all_original_gates_pass',false,'baseline_complete_OP_path','', ...
        'baseline_complete_OP_sha256','','same_family_parameter_compatible',false,'cases',{{}}, ...
        'experiment_completed',false,'production_recovery_allowed',false,'outer_solve_eligible',false, ...
        'periodic_steady_state_claim',false,'table4_reproduction_claim',false);
    write_json(fullfile(root,'runtime_boundary_family.json'),record);
    try
        Collect_HeatDriveECC_ObservationPacket(input,[],0,20,baseline,options,folder,chambers,buffers,producer, ...
            request.python_executable,'runtime_boundary_cold_baseline','');
        [initial,manifest]=Load_HeatDriveECC_GatedObservationPacket(baseline,false);
        record.cold_baseline_all_original_gates_pass=true;
        record.baseline_complete_OP_path=fullfile(baseline,'comparison_only_complete_op.mat');
        record.baseline_complete_OP_sha256=manifest.complete_OP_sha256;
        write_json(fullfile(root,'runtime_boundary_family.json'),record);
    catch ME
        write_json(fullfile(root,'REJECTED_DO_NOT_RESUME.json'),struct('reason',ME.message, ...
            'failed_baseline_may_propagate',false,'production_recovery_allowed',false));
        rethrow(ME);
    end
    saved=load(fullfile(baseline,'observed_states.mat'),'observation');
    original=load(fullfile(baseline,'native','observations.mat'),'native');
    values=[276.95 276.85];labels={'runtime_positive_control','runtime_Tc_candidate'};
    for k=1:2
        destination=fullfile(root,labels{k});mkdir(destination);
        row=struct('declared_Tc_K',values(k),'strict_vendor_restore_pass',false,'error_message','', ...
            'retained_memories_initial_bitwise_equal',false,'boundary_value_applied',false);
        try
            candidate=input.setVariable('cold_sink_T_init',values(k)).setInitialState(initial);
            output=sim(candidate.setModelParameter('StopTime','20.002'));
            assert(isempty(output.ErrorMessage),'HeatDriveECC:RuntimeBoundaryRestoreError','%s',output.ErrorMessage);
            row.actual_final_snapshot_s=output.diagnostic_final_op.snapshotTime;
            assert(abs(row.actual_final_snapshot_s-20.002)<=16*eps(20.002));
            observation=Extract_HeatDriveECC_ObservedStates(output.diagnostic_state_log,10,1);
            observation.states=slice_probe(observation.states);
            [native,~]=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model,false,chambers,buffers);
            native=slice_probe(native);
            states=Compare_HeatDriveECC_DiagnosticTraces(ends(saved.observation.states,false),ends(observation.states,true));
            fluids=Compare_HeatDriveECC_DiagnosticTraces(ends(original.native,false),ends(native,true));
            memory_names={'/ECC_Constitutive21_StateDelay::','/SMAPressurePI_Integrator::', ...
                '/SEStage2PressurePI_Integrator::','/SEStage4PressurePI_Integrator::'};
            memory=cellfun(@(r) any(contains(r.key,memory_names)),states.traces);
            row.retained_memories_initial_bitwise_equal=nnz(memory)==4 && ...
                all(cellfun(@(r) r.bitwise_values_equal,states.traces(memory)));
            selected=cellfun(@(r) endsWith(r.block_path,'/ColdSinkMass') && strcmp(r.state_name,'T'),native);
            assert(nnz(selected)==1 && strcmp(native{selected}.unit,'K'));
            row.observed_fixed_Tc_K=native{selected}.values(:,1).';
            row.boundary_value_applied=all(abs(row.observed_fixed_Tc_K-values(k))<=1e-10);
            row.strict_vendor_restore_pass=true;
            row.initial_states_bitwise_equal=states.bitwise_values_equal;
            row.initial_native_bitwise_equal=fluids.bitwise_values_equal;
            row.changed_initial_states=states.traces(~cellfun(@(r) r.bitwise_values_equal,states.traces));
            row.changed_initial_native=fluids.traces(~cellfun(@(r) r.bitwise_values_equal,fluids.traces));
            save(fullfile(destination,'measured_probe.mat'),'observation','native','-v7.3');
            row.measured_probe_sha256=file_hash(fullfile(destination,'measured_probe.mat'));
            if k==1,assert(states.bitwise_values_equal && fluids.bitwise_values_equal && row.boundary_value_applied);end
        catch ME
            row.error_message=ME.message;row.error_identifier=ME.identifier;row.error_report=getReport(ME,'extended','hyperlinks','off');
        end
        write_json(fullfile(destination,'probe_result.json'),row);record.cases{end+1}=row;
        write_json(fullfile(destination,'NOT_AN_OUTER_OR_RESUME_POINT.json'),struct( ...
            'reason','Short interface probe only. No complete-cycle gates, no saved candidate OP.','production_recovery_allowed',false));
        if k==1 && (~row.strict_vendor_restore_pass || ~isempty(row.error_message))
            write_json(fullfile(root,'runtime_boundary_family.json'),record);
            error('HeatDriveECC:RuntimePositiveControlFailed','Diagnose unchanged runtime-family recovery.');
        end
        if k==2
            record.same_family_parameter_compatible=row.strict_vendor_restore_pass && ...
                isempty(row.error_message) && row.retained_memories_initial_bitwise_equal && row.boundary_value_applied;
        end
        clear output candidate native observation
    end
    assert(strcmp(file_hash(record.baseline_complete_OP_path),record.baseline_complete_OP_sha256));
    record.experiment_completed=true;write_json(fullfile(root,'runtime_boundary_family.json'),record);
end

function traces=slice_probe(traces)
    for k=1:numel(traces)
        r=traces{k};selected=r.time_s>=20-1e-10 & r.time_s<=20.002+1e-10;
        r.time_s=r.time_s(selected);r.values=r.values(selected,:);
        assert(numel(r.time_s)==3);if isfield(r,'complete_requested_window'),r.complete_requested_window=false;end
        traces{k}=r;
    end
end

function traces=ends(traces,first)
    for k=1:numel(traces)
        r=traces{k};index=numel(r.time_s);if first,index=1;end
        r.time_s=r.time_s(index);r.values=r.values(index,:);traces{k}=r;
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
