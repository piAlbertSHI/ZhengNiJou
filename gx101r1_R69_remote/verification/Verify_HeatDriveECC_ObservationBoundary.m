function record=Verify_HeatDriveECC_ObservationBoundary(previous,candidate)
% Compare only real shared endpoint samples; never reconstruct a state or resample.
    output=fullfile(candidate,'boundary_comparison.json');assert(~isfile(output));
    a=load(fullfile(previous,'observed_states.mat'),'observation');
    b=load(fullfile(candidate,'observed_states.mat'),'observation');
    states=Compare_HeatDriveECC_DiagnosticTraces(ends(a.observation.states,false),ends(b.observation.states,true));
    clear a b
    a=load(fullfile(previous,'native','observations.mat'),'native','source_traces','signals');
    b=load(fullfile(candidate,'native','observations.mat'),'native','source_traces','signals');
    native=Compare_HeatDriveECC_DiagnosticTraces(ends(a.native,false),ends(b.native,true));
    sources=Compare_HeatDriveECC_DiagnosticTraces(ends(a.source_traces,false),ends(b.source_traces,true));
    public=Compare_HeatDriveECC_DiagnosticTraces(ends(public_traces(a.signals),false),ends(public_traces(b.signals),true));
    memory_names={'/ECC_Constitutive21_StateDelay::','/SMAPressurePI_Integrator::', ...
        '/SEStage2PressurePI_Integrator::','/SEStage4PressurePI_Integrator::'};
    selected=cellfun(@(row) any(contains(row.key,memory_names)),states.traces);
    memory_exact=nnz(selected)==4 && all(cellfun(@(row) row.bitwise_values_equal,states.traces(selected)));
    record=struct('schema','heatdrive_ecc_observation_packet_boundary_v1', ...
        'previous_packet',previous,'candidate_packet',candidate, ...
        'states',compact(states),'native',compact(native),'sources',compact(sources),'public',compact(public), ...
        'retained_memories_bitwise_equal',memory_exact,'retained_memory_count',nnz(selected), ...
        'pass',states.pass && native.pass && sources.pass && public.pass && memory_exact, ...
        'candidate_observation_sha256',file_hash(fullfile(candidate,'native','observations.mat')), ...
        'candidate_state_sha256',file_hash(fullfile(candidate,'observed_states.mat')), ...
        'no_interpolation',true,'source_state_edited',false,'production_recovery_allowed',false);
    fid=fopen(output,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    assert(record.pass,'HeatDriveECC:ObservationBoundaryJump','Measured packet boundary or retained memory changed.');
end

function value=compact(value)
    changed=~cellfun(@(row) row.bitwise_values_equal,value.traces);
    value.changed_trace_details=value.traces(changed);value=rmfield(value,'traces');
end

function traces=ends(traces,first)
    for k=1:numel(traces)
        row=traces{k};index=numel(row.time_s);if first,index=1;end
        row.time_s=row.time_s(index);row.values=row.values(index,:);traces{k}=row;
    end
end

function traces=public_traces(signals)
    names=fieldnames(signals);traces=cell(size(names));
    for k=1:numel(names)
        row=signals.(names{k});traces{k}=struct('block_path',names{k},'state_name','', ...
            'unit','','time_s',row.time_s,'values',row.values,'channel_count',size(row.values,2));
    end
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
