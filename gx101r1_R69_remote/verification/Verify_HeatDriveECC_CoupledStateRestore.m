function record = Verify_HeatDriveECC_CoupledStateRestore(input, original, capture, time_s, folder)
% Strict same-model disk roundtrip versus an uninterrupted cold reference.
% This preflight grants neither a recovery chain nor final mechanism/periodic authority.
    saved=load(capture.operating_point_file,'diagnostic_operating_point','production_recovery_allowed');
    assert(~saved.production_recovery_allowed && ...
        isequaln(saved.diagnostic_operating_point.loggedStates,original.diagnostic_final_op.loggedStates), ...
        'Saved candidate changed or has forbidden production authority.');
    stop=time_s+.001;
    reference=sim(input.setModelParameter('StopTime',num2str(stop,'%.17g')));
    assert(isempty(reference.ErrorMessage),'Continuous reference failed: %s',reference.ErrorMessage);
    reference_states=terminal_states(reference,time_s);
    reference_signals=terminal_signals(reference,time_s,stop);
    clear reference
    resumed=sim(input.setModelParameter('StopTime',num2str(stop,'%.17g')).setInitialState(saved.diagnostic_operating_point));
    assert(isempty(resumed.ErrorMessage),'Strict restore failed: %s',resumed.ErrorMessage);
    resumed_states=terminal_states(resumed,time_s);
    resumed_signals=terminal_signals(resumed,time_s,stop);
    clear resumed
    comparisons={};keys=cellfun(@state_key,reference_states.states,'UniformOutput',false);
    assert(numel(unique(keys))==numel(keys),'Duplicate reference state identities.');
    assert(numel(resumed_states.states)==numel(keys),'Restored state group count changed.');
    for k=1:numel(resumed_states.states)
        a=resumed_states.states{k};key=state_key(a);index=find(strcmp(keys,key));
        assert(isscalar(index),'Missing named reference state: %s',a.block_path);
        b=reference_states.states{index};selected=b.time_s>=time_s-1e-9;
        expected=[time_s;stop];
        clock=numel(a.time_s)==2 && all(abs(a.time_s-expected)<=1e-9) && sum(selected)==2;
        equal=clock && isequaln(a.values,b.values(selected,:));
        comparisons{end+1}=struct('block_path',a.block_path,'state_name',a.state_name, ...
            'channels',a.channel_count,'clock_pass',clock,'values_exact',equal); %#ok<AGROW>
    end
    names=fieldnames(reference_signals);other=fieldnames(resumed_signals);
    assert(isequal(sort(names),sort(other)) && ~isempty(names),'Public observation coverage differs.');
    signal_comparisons={};
    for k=1:numel(names)
        a=resumed_signals.(names{k});b=reference_signals.(names{k});
        equal=isequaln(a.values,b.values);
        signal_comparisons{end+1}=struct('name',names{k},'channels',size(a.values,2), ...
            'values_exact',equal); %#ok<AGROW>
    end
    record=struct('schema','heatdrive_ecc_coupled_state_restore_preflight_v1', ...
        'source_operating_point_sha256',capture.operating_point_sha256, ...
        'snapshot_time_s',time_s,'comparison_stop_s',stop, ...
        'same_model_restore_preflight_pass', ...
            all(cellfun(@(r) r.values_exact,comparisons)) && ...
            all(cellfun(@(r) r.values_exact,signal_comparisons)), ...
        'state_comparisons',{comparisons},'signal_comparisons',{signal_comparisons}, ...
        'checksum_policy','error/error','source_state_edited',false, ...
        'partial_state_restore_used',false,'complete_cycle_resume_verified',false, ...
        'periodic_state_verified',false,'all_mechanism_gates_evaluated',false, ...
        'diagnostic_continuation_allowed',false,'production_recovery_allowed',false);
    save(fullfile(folder,'restore_preflight_comparison.mat'),'reference_states','resumed_states', ...
        'reference_signals','resumed_signals','record','-v7.3');
    fid=fopen(fullfile(folder,'state_restore_preflight.json'),'w','n','UTF-8');
    assert(fid>=0,'Cannot save restore evidence.');cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    assert(record.same_model_restore_preflight_pass, ...
        'Coupled restored and continuous states differ; see state_restore_preflight.json.');
end

function observation=terminal_states(output,time_s)
    observation=Extract_HeatDriveECC_ObservedStates(output.diagnostic_state_log,10,1);
    bytes=0;
    for k=1:numel(observation.states)
        row=observation.states{k};selected=row.time_s>=time_s-1e-9;
        row.time_s=row.time_s(selected);row.values=row.values(selected,:);
        row.complete_requested_window=false;observation.states{k}=row;
        bytes=bytes+8*(numel(row.time_s)+numel(row.values));
    end
    observation.numeric_bytes=bytes;observation.requested_window_cycles=0;
    observation.scope='Terminal strict restore comparison only, never a complete periodic window.';
end

function key=state_key(row)
    key=[row.block_path,char(9),row.state_name];
end

function signals=terminal_signals(output,start,stop)
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
        data=reshape(double(data),numel(t),[]);
        selected=t>=start-1e-9 & t<=stop+1e-9;
        assert(sum(selected)==2 && all(abs(t(selected)-[start;stop])<=1e-9), ...
            'Missing terminal physical samples: %s',names{k});
        assert(all(isfinite(data(selected,:)),'all'),'Nonfinite restored observation.');
        signals.(names{k})=struct('time_s',t(selected),'values',data(selected,:));
    end
end
