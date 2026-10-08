function record = Verify_HeatDriveECC_RebuiltCycleRestore(input, source_root, folder)
% Exact full-period comparison on a new MATLAB process and rebuilt runtime model.
    source=fullfile(source_root,'native');
    capture=jsondecode(fileread(fullfile(source,'diagnostic_state_capture.json')));
    bounded_candidate=~isfile(fullfile(source,'state_restore_preflight.json'));
    candidate_contract=struct();
    if bounded_candidate
        candidate_contract=Require_HeatDriveECC_BoundedStateCandidate(source_root);
    else
        preflight=jsondecode(fileread(fullfile(source,'state_restore_preflight.json')));
        assert(preflight.same_model_restore_preflight_pass && preflight.snapshot_time_s==20 && ...
            ~preflight.production_recovery_allowed && ~preflight.source_state_edited && ...
            ~preflight.partial_state_restore_used && ...
            strcmp(preflight.source_operating_point_sha256,capture.operating_point_sha256), ...
            'Source was not a passed intact state-interface candidate.');
    end
    op_file=fullfile(source,'diagnostic_complete_operating_point.mat');
    history_file=fullfile(source,'diagnostic_state_observation.mat');
    assert(strcmp(file_hash(op_file),capture.operating_point_sha256) && ...
        strcmp(file_hash(history_file),capture.history_sha256), ...
        'Source candidate or bounded history changed.');
    saved=load(op_file,'diagnostic_operating_point','production_recovery_allowed');
    assert(~saved.production_recovery_allowed,'Source carries forbidden production authority.');
    start=20;stop=30;model=input.ModelName;
    configured=evalin('base','EIGHTH_ROUND_OPTIONS');
    qualify_mechanism=isfield(configured.branch,'pressure_command_domain_closure_enabled') && ...
        configured.branch.pressure_command_domain_closure_enabled;
    assert(strcmp(get_param(model,'OperatingPointContentsChecksumMismatchMsg'),'error') && ...
        strcmp(get_param(model,'OperatingPointInterfaceChecksumMismatchMsg'),'error'), ...
        'Both strict checksum policies must be retained.');
    record=struct('schema','heatdrive_ecc_rebuilt_cycle_restore_v1', ...
        'source_root',source_root,'source_operating_point_sha256',capture.operating_point_sha256, ...
        'source_history_sha256',capture.history_sha256,'start_time_s',start,'stop_time_s',stop, ...
        'checksum_policy','error/error','source_state_edited',false,'partial_state_restore_used',false, ...
        'rebuilt_complete_cycle_pass',false,'state_comparisons',{{}},'signal_comparisons',{{}}, ...
        'continuous_reference_pass',false,'strict_restore_completed',false, ...
        'all_mechanism_gates_evaluated',false,'periodic_state_verified',false, ...
        'candidate_contract',candidate_contract, ...
        'diagnostic_continuation_allowed',false,'production_recovery_allowed',false,'error_message','');
    reference_states=struct();resumed_states=struct();reference_signals=struct();resumed_signals=struct();
    try
        resumed=sim(input.setModelParameter('StopTime',num2str(stop,'%.17g')).setInitialState(saved.diagnostic_operating_point));
        assert(isempty(resumed.ErrorMessage),'Strict rebuilt restore failed: %s',resumed.ErrorMessage);
        resumed_states=window_states(resumed,start,stop);
        resumed_signals=window_signals(resumed,start,stop);
        if qualify_mechanism
            metadata=jsondecode(fileread(fullfile(folder,'inventory_metadata.json')));
            blocks=metadata.storage_blocks;blocks=blocks([blocks.conservative_diagnostic]);
            paths={blocks.block_path};buffers=paths(contains(paths,'FluidBuffer'));
            chambers=setdiff(paths,buffers,'stable');assert(numel(buffers)==4 && numel(chambers)==2);
            physical=Extract_HeatDriveECC_PhysicalLogs(resumed,configured,model,false);
            [native,~]=Extract_HeatDriveECC_NativeStorageTraces(resumed.simlog,model,false,chambers,buffers);
            [source_traces,boundary_metadata]=Extract_HeatDriveECC_BoundaryTraces(resumed.simlog,model);
            native_file=fullfile(folder,'restored_native_ledger_observation.mat');assert(~isfile(native_file));
            save(native_file,'native','source_traces','boundary_metadata','-v7.3');
            record.native_ledger_persistence=Audit_HeatDriveECC_NativeLedgerPersistence( ...
                native_file,native,source_traces,boundary_metadata);
            record.native_ledger_observation_sha256=file_hash(native_file);
            clear native source_traces
        end
        clear resumed
        record.strict_restore_completed=true;
        reference=sim(input.setModelParameter('StopTime',num2str(stop,'%.17g')));
        assert(isempty(reference.ErrorMessage),'Continuous reference failed: %s',reference.ErrorMessage);
        reference_states=window_states(reference,start,stop);
        reference_signals=window_signals(reference,start,stop);clear reference
        record.continuous_reference_pass=true;
        keys=cellfun(@state_key,reference_states.states,'UniformOutput',false);
        assert(numel(unique(keys))==numel(keys) && numel(resumed_states.states)==numel(keys), ...
            'Named state coverage changed.');
        for k=1:numel(resumed_states.states)
            a=resumed_states.states{k};idx=find(strcmp(keys,state_key(a)));
            assert(isscalar(idx),'Missing named reference state.');b=reference_states.states{idx};
            record.state_comparisons{end+1}=compare(a.block_path,a.state_name,a,b); %#ok<AGROW>
        end
        names=fieldnames(reference_signals);
        assert(isequal(sort(names),sort(fieldnames(resumed_signals))) && ~isempty(names), ...
            'Public observation coverage changed.');
        for k=1:numel(names)
            record.signal_comparisons{end+1}=compare(names{k},'', ...
                resumed_signals.(names{k}),reference_signals.(names{k})); %#ok<AGROW>
        end
        record.rebuilt_complete_cycle_pass= ...
            all(cellfun(@(r) r.values_exact,record.state_comparisons)) && ...
            all(cellfun(@(r) r.values_exact,record.signal_comparisons));
        if qualify_mechanism && record.rebuilt_complete_cycle_pass
            physical.authority='physical_simscape_to_workspace_logs';
            physical.legacy_surrogate_used_for_results=false;physical.sim_call_count=1;physical.walltime_s=NaN;
            provenance=struct('checkpoint_restart_used',true,'checkpoint_chain_verified',true, ...
                'sim_call_count',1,'solver',configured.simulation.solver, ...
                'fixed_step_s',configured.simulation.fixed_step_s,'simulation_mode',configured.simulation.mode);
            view=Make_HeatDriveECC_MechanismWindow(physical,configured,provenance,folder);
            audit=Validate_HeatDriveECC_EighthRound_Physics(view);
            record.bounded_restored_cycle_mechanism_pass=audit.passed;
            record.bounded_restored_cycle_mechanism_checks=audit.checks;
            signals=resumed_signals;
            save(fullfile(folder,'restored_physical_observation.mat'), ...
                'physical','configured','provenance','signals','-v7.3');
            assert(audit.passed,'HeatDriveECC:BoundedRestoredMechanismFailed', ...
                'Full-cycle state proof passed, but the actual restored mechanism failed.');
        end
    catch ME
        record.error_message=ME.message;record.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    assert(strcmp(file_hash(op_file),capture.operating_point_sha256) && ...
        strcmp(file_hash(history_file),capture.history_sha256),'Source evidence changed during experiment.');
    save(fullfile(folder,'rebuilt_cycle_comparison.mat'),'reference_states','resumed_states', ...
        'reference_signals','resumed_signals','record','-v7.3');
    fid=fopen(fullfile(folder,'rebuilt_cycle_restore.json'),'w','n','UTF-8');
    assert(fid>=0,'Cannot save rebuilt-cycle evidence.');cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    assert(record.rebuilt_complete_cycle_pass && isempty(record.error_message), ...
        'Rebuilt-cycle qualification incomplete; inspect preserved state/transport/mechanism evidence.');
end

function result=compare(name,state,a,b)
    clock=isequal(size(a.time_s),size(b.time_s)) && all(abs(a.time_s-b.time_s)<=1e-9);
    shape=isequal(size(a.values),size(b.values));difference=NaN;
    if shape,difference=max(abs(a.values-b.values),[],'all');end
    result=struct('name',name,'state_name',state,'channels',size(a.values,2), ...
        'samples',numel(a.time_s),'clock_pass',clock,'max_absolute_difference',difference, ...
        'values_exact',clock && shape && isequaln(a.values,b.values));
end

function observation=window_states(output,start,stop)
    observation=Extract_HeatDriveECC_ObservedStates(output.diagnostic_state_log,10,1);
    bytes=0;
    for k=1:numel(observation.states)
        row=observation.states{k};selected=row.time_s>=start-1e-9 & row.time_s<=stop+1e-9;
        row.time_s=row.time_s(selected);row.values=row.values(selected,:);
        check_clock(row.time_s,start,stop);assert(all(isfinite(row.values),'all'),'Nonfinite state.');
        row.complete_requested_window=true;observation.states{k}=row;
        bytes=bytes+8*(numel(row.time_s)+numel(row.values));
    end
    observation.numeric_bytes=bytes;observation.requested_window_cycles=1;
    observation.scope='One complete strict restore comparison, not periodic evidence.';
end

function signals=window_signals(output,start,stop)
    signals=struct();names=output.who;
    for k=1:numel(names)
        value=output.get(names{k});
        if isa(value,'timeseries')
            t=double(value.Time(:));data=value.Data;
            if ~value.IsTimeFirst,data=permute(data,[ndims(data),1:ndims(data)-1]);end
        elseif isstruct(value) && isscalar(value) && isfield(value,'time') && ...
                isfield(value,'signals') && isscalar(value.signals) && isfield(value.signals,'values')
            t=double(value.time(:));data=value.signals.values;
        else,continue
        end
        data=reshape(double(data),numel(t),[]);selected=t>=start-1e-9 & t<=stop+1e-9;
        check_clock(t(selected),start,stop);assert(all(isfinite(data(selected,:)),'all'),'Nonfinite observation.');
        signals.(names{k})=struct('time_s',t(selected),'values',data(selected,:));
    end
end

function check_clock(t,start,stop)
    expected=(start:.001:stop).';
    assert(numel(t)==numel(expected) && all(abs(t-expected)<=1e-9), ...
        'Require all 10001 physical samples, including both period endpoints.');
end

function key=state_key(row)
    key=[row.block_path,char(9),row.state_name];
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');
    assert(fid>=0,'Missing hash-bound evidence.');cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
