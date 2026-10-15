function record=Verify_HeatDriveECC_ObservationBoundary(previous,candidate,intervention)
% Compare only real shared endpoint samples; never reconstruct a state or resample.
    output=fullfile(candidate,'boundary_comparison.json');assert(~isfile(output));
    if nargin<3,intervention=struct();end
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
    if ~isempty(fieldnames(intervention))
        manifest=jsondecode(fileread(fullfile(candidate,'packet_manifest.json')));
        previous_manifest=jsondecode(fileread(fullfile(previous,'packet_manifest.json')));
        assert(strcmp(manifest.packet_role,'runtime_boundary_Tc_candidate') && ...
            isequaln(manifest.boundary_trial,intervention) && ...
            manifest.source_snapshot_s==intervention.transition_time_s && ...
            strcmp(previous_manifest.complete_OP_sha256,intervention.source_complete_OP_sha256) && ...
            strcmp(manifest.parent_complete_OP_sha256,previous_manifest.complete_OP_sha256) && ...
            previous_manifest.prescribed_Tc_K==intervention.source_Tc_K && ...
            manifest.prescribed_Tc_K==intervention.candidate_Tc_K && manifest.strict_vendor_restore && ...
            strcmp(manifest.checksum_policy,'error/error'));
        selected_mass=cellfun(@(r) endsWith(r.block_path,'/ColdSinkMass') && strcmp(r.state_name,'T'),b.native);
        old_mass=cellfun(@(r) endsWith(r.block_path,'/ColdSinkMass') && strcmp(r.state_name,'T'),a.native);
        assert(nnz(selected_mass)==1 && nnz(old_mass)==1);
        applied=all(abs(b.native{selected_mass}.values-intervention.candidate_Tc_K)<=1e-10,'all') && ...
            abs(a.native{old_mass}.values(end)-intervention.source_Tc_K)<=1e-10;
        % Vendor consistency initialization may update the solver vector and fluid algebraic states.
        % Never reinterpret that deliberate boundary action as same-parameter repeatability.
        external=~cellfun(@(r) contains(r.key,'/Solver Configuration::'),states.traces);
        retained_external=all(cellfun(@(r) r.bitwise_values_equal,states.traces(external)));
        record.boundary_intervention=intervention;
        record.fixed_CHEX_temperature_step_K=intervention.candidate_Tc_K-intervention.source_Tc_K;
        record.actual_fixed_boundary_applied=applied;
        record.all_other_discrete_states_bitwise_equal=retained_external;
        record.source_heat_impulse_independently_closed=false;
        record.pass=memory_exact && retained_external && applied;
        record.scope='Strict vendor OP restoration with a declared external temperature intervention, not unchanged-boundary repeatability.';
    end
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
