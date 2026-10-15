function record=Verify_HeatDriveECC_C72BoundaryParameter(input,options,folder,chambers,buffers,request,producer)
% Test vendor complete-state parameter compatibility; never edit or promote an OP.
    pointer=jsondecode(fileread(request.endpoint_contract_path));
    repo=fileparts(fileparts(request.endpoint_contract_path));
    qpath=fullfile(repo,pointer.qualification_relative);q=jsondecode(fileread(qpath));
    assert(strcmp(file_hash(qpath),pointer.qualification_sha256) && pointer.snapshot_time_s==720 && ...
        pointer.total_cycles==72 && ~pointer.production_recovery_allowed && ~pointer.outer_solve_eligible && ...
        q.all_original_packet_gates_pass && q.original_public_thermal_periodicity_pass && ...
        q.complete_native_ten_cycle_window_collected && ~q.source_state_edited);
    for k=1:numel(q.files),assert(strcmp(file_hash(q.files(k).path),q.files(k).sha256));end
    [initial,manifest]=Load_HeatDriveECC_GatedObservationPacket(q.source_packet_root,true);
    assert(initial.snapshotTime==720 && strcmp(manifest.complete_OP_sha256,pointer.operating_point_sha256));
    model=input.ModelName;
    assert(strcmp(get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error') && ...
        Resolve_HeatDriveECC_ObservationCount(get_param(model,'SimscapeLogDataHistory'))==20002 && ...
        Resolve_HeatDriveECC_ObservationCount(get_param(model,'MaxDataPoints'))==110002);
    source=options.validation.cold_boundary_audit.fixed_source_path;
    assert(strcmp(get_param(source,'temperature'),'cold_sink_T_init') && ...
        strcmp(get_param(source,'temperature_conf'),'compiletime') && ...
        options.system.Tchex_K==276.95 && evalin('base','cold_sink_T_init')==276.95);
    root=fullfile(folder,'boundary_parameter_probe');assert(~isfolder(root));mkdir(root);
    original=load(fullfile(q.source_packet_root,'observed_states.mat'),'observation');
    native_saved=load(fullfile(q.source_packet_root,'native','observations.mat'),'native');
    record=struct('schema','heatdrive_ecc_C72_boundary_parameter_probe_v1','producer',producer, ...
        'source_endpoint_contract_sha256',file_hash(request.endpoint_contract_path), ...
        'source_OP_sha256',manifest.complete_OP_sha256,'source_snapshot_s',720,'probe_stop_s',720.002, ...
        'checksum_policy','error/error','source_temperature_configurability','compiletime', ...
        'source_state_edited',false,'partial_state_restore_used',false,'initial_targets_changed',false, ...
        'cases',{{}},'experiment_completed',false,'candidate_compatible',false, ...
        'new_OP_saved',false,'production_recovery_allowed',false,'outer_solve_eligible',false, ...
        'complete_cycle_mechanism_gates_evaluated',false,'table4_reproduction_claim',false);
    values=[276.95 request.candidate_Tc_K];labels={'unchanged_control','candidate'};
    for k=1:2
        destination=fullfile(root,labels{k});mkdir(destination);
        row=struct('label',labels{k},'declared_Tc_K',values(k),'same_complete_initial_OP_used',true, ...
            'simulation_returned_without_error',false,'strict_vendor_restore_pass',false, ...
            'retained_memories_initial_bitwise_equal',false,'observed_fixed_Tc_K',[], ...
            'error_message','','error_identifier','','error_report','');
        write_json(fullfile(destination,'probe_start.json'),row);
        try
            candidate=input.setVariable('cold_sink_T_init',values(k)).setInitialState(initial);
            output=sim(candidate.setModelParameter('StopTime','720.002'));
            assert(isempty(output.ErrorMessage),'HeatDriveECC:BoundaryProbeSimulationError','%s',output.ErrorMessage);
            row.simulation_returned_without_error=true;
            assert(output.diagnostic_final_op.snapshotTime==720.002);
            observation=Extract_HeatDriveECC_ObservedStates(output.diagnostic_state_log,10,1);
            observation.states=slice_traces(observation.states,720,720.002);
            observation.short_probe_only=true;observation.complete_internal_state_periodicity_verified=false;
            [native,~]=Extract_HeatDriveECC_NativeStorageTraces(output.simlog,model,false,chambers,buffers);
            [source_traces,boundary_metadata]=Extract_HeatDriveECC_BoundaryTraces(output.simlog,model);
            native=slice_traces(native,720,720.002);source_traces=slice_traces(source_traces,720,720.002);
            assert(numel(observation.states)==74 && numel(native)==1262 && numel(source_traces)==162);
            initial_states=Compare_HeatDriveECC_DiagnosticTraces(ends(original.observation.states,false),ends(observation.states,true));
            initial_native=Compare_HeatDriveECC_DiagnosticTraces(ends(native_saved.native,false),ends(native,true));
            memory_names={'/ECC_Constitutive21_StateDelay::','/SMAPressurePI_Integrator::', ...
                '/SEStage2PressurePI_Integrator::','/SEStage4PressurePI_Integrator::'};
            selected=cellfun(@(r) any(contains(r.key,memory_names)),initial_states.traces);
            row.retained_memories_initial_bitwise_equal=nnz(selected)==4 && ...
                all(cellfun(@(r) r.bitwise_values_equal,initial_states.traces(selected)));
            fixed=cellfun(@(r) endsWith(r.block_path,'/ColdSinkMass') && strcmp(r.state_name,'T'),native);
            assert(nnz(fixed)==1);fixed_row=native{fixed};
            assert(strcmp(fixed_row.unit,'K'));row.observed_fixed_Tc_K=fixed_row.values(:,1).';
            row.strict_vendor_restore_pass=true;
            row.all_logged_initial_states_bitwise_equal=initial_states.bitwise_values_equal;
            row.all_native_initial_values_bitwise_equal=initial_native.bitwise_values_equal;
            row.initial_state_changes=changed(initial_states);row.initial_native_changes=changed(initial_native);
            row.boundary_value_applied=all(abs(row.observed_fixed_Tc_K-values(k))<=1e-10);
            save(fullfile(destination,'measured_probe.mat'),'observation','native','source_traces','boundary_metadata','-v7.3');
            row.measured_probe_sha256=file_hash(fullfile(destination,'measured_probe.mat'));
            if k==1
                assert(initial_states.bitwise_values_equal && initial_native.bitwise_values_equal && row.boundary_value_applied, ...
                    'Positive control did not reproduce the intact C72 endpoint.');
            end
        catch ME
            row.error_message=ME.message;row.error_identifier=ME.identifier;row.error_report=getReport(ME,'extended','hyperlinks','off');
        end
        write_json(fullfile(destination,'probe_result.json'),row);record.cases{end+1}=row;
        if k==1 && (~row.strict_vendor_restore_pass || ~isempty(row.error_message))
            write_json(fullfile(root,'boundary_parameter_probe.json'),record);
            error('HeatDriveECC:BoundaryPositiveControlFailed','Diagnose unchanged C72 restore before a new boundary experiment.');
        end
        if k==2
            record.candidate_compatible=row.strict_vendor_restore_pass && isempty(row.error_message) && ...
                row.retained_memories_initial_bitwise_equal && row.boundary_value_applied;
            write_json(fullfile(destination,'NOT_A_RESUME_OR_OUTER_POINT.json'),struct( ...
                'reason','A 2 ms parameter probe does not evaluate complete-cycle mechanism or periodicity gates.', ...
                'probe_compatible',record.candidate_compatible,'production_recovery_allowed',false));
        end
        clear output candidate native source_traces observation
    end
    assert(strcmp(file_hash(pointer.operating_point_path),pointer.operating_point_sha256));
    record.experiment_completed=true;write_json(fullfile(root,'boundary_parameter_probe.json'),record);
end

function traces=slice_traces(traces,start,stop)
    for k=1:numel(traces)
        row=traces{k};selected=row.time_s>=start-1e-9 & row.time_s<=stop+1e-9;
        row.time_s=row.time_s(selected);row.values=row.values(selected,:);
        assert(numel(row.time_s)==3 && abs(row.time_s(1)-start)<1e-9 && abs(row.time_s(end)-stop)<1e-9);
        if isfield(row,'complete_requested_window'),row.complete_requested_window=false;end
        traces{k}=row;
    end
end

function traces=ends(traces,first)
    for k=1:numel(traces)
        row=traces{k};index=numel(row.time_s);if first,index=1;end
        row.time_s=row.time_s(index);row.values=row.values(index,:);traces{k}=row;
    end
end

function rows=changed(comparison)
    rows=comparison.traces(~cellfun(@(r) r.bitwise_values_equal,comparison.traces));
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
