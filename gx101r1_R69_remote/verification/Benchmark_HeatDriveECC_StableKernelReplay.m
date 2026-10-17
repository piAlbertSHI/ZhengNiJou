function record=Benchmark_HeatDriveECC_StableKernelReplay(packet,output)
% Exact causal samples from a sealed packet, without loading its Operating Point.
    assert(~isfolder(output),'Never overwrite a kernel benchmark.');
    manifest_path=fullfile(packet,'packet_manifest.json');gate_path=fullfile(packet,'packet_gate.json');
    manifest=jsondecode(fileread(manifest_path));gate=jsondecode(fileread(gate_path));
    assert(gate.gate_pass && strcmp(gate.input_sha256.manifest,file_hash(manifest_path)) && ...
        strcmp(manifest.packet_role,'runtime_sensitivity_continuation') && ...
        ~manifest.source_state_edited && ~manifest.production_recovery_allowed);
    for k=1:numel(manifest.input_files)
        item=manifest.input_files(k);
        assert(strcmp(file_hash(fullfile(packet,item.path)),item.sha256),'Changed packet evidence.');
    end
    configuration=load(fullfile(packet,'native','configuration.mat'),'options');options=configuration.options;
    assert(options.constitutive.diagnostic_substeps==32 && ...
        options.constitutive.simulink_sample_time_s==.001 && options.node_count==21);
    repo=fileparts(fileparts(mfilename('fullpath')));workspace=fileparts(repo);
    files={'HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic.m', ...
        'HeatDriveECC_ConstitutiveCompatibilityStep51.m','Initialize_HeatDriveECC_EighthRound_State.m', ...
        'verification/Integrate_HeatDriveECC_StableConstitutiveSample.m', ...
        'verification/HeatDriveECC_ConstitutiveStabilityBound.m'};
    for k=1:numel(files)
        [status,message]=system(sprintf('git -C "%s" diff --quiet %s HEAD -- "gx101r1_R69_remote/%s"', ...
            workspace,manifest.producer,files{k}));assert(status==0,'%s',message);
    end
    observed=load(fullfile(packet,'observed_states.mat'),'observation');
    saved=load(fullfile(packet,'native','observations.mat'),'signals');signals=saved.signals;clear saved
    wanted=(manifest.window_s(1)+.01:.1:manifest.window_s(2)-.001).';
    identities={'ECC_Constitutive21_StateDelay','ECC_Constitutive21_SMA_TempDelay','ECC_Constitutive21_SE_TempDelay'};
    source_names={'ECC_constitutive21_output','SMA_Tx21_internal','SE_Tx21_internal'};
    widths=[210 21 21];offsets=[42 0 0];parts=cell(1,3);bindings=cell(1,3);
    states=observed.observation.states;if isstruct(states),states=num2cell(states);end
    for k=1:3
        found=find(cellfun(@(r) endsWith(r.block_path,['/' identities{k}]),states));assert(isscalar(found));
        row=states{found};assert(size(row.values,2)==widths(k));
        series=signals.(source_names{k});current=row.values(indices(row.time_s,wanted),:);
        expected=series.values(indices(series.time_s,wanted-.001),offsets(k)+(1:widths(k)));
        same_now=isequaln(current,series.values(indices(series.time_s,wanted),offsets(k)+(1:widths(k))));
        same_previous=isequaln(current,expected);
        assert(xor(same_now,same_previous),'Ambiguous named-delay causal clock.');
        shift=0;if same_now,shift=-.001;end
        parts{k}=row.values(indices(row.time_s,wanted+shift),:);
        assert(isequaln(parts{k},expected),'Causal input differs from exact previous output.');
        bindings{k}=struct('block',identities{k},'width',widths(k),'history_clock_shift_s',shift, ...
            'exact_previous_output_match',true);
    end
    series=signals.ECC_constitutive21_output;
    fixture=struct('time_s',wanted,'memory',parts{1},'temperature_sma',parts{2}, ...
        'temperature_se',parts{3},'observed_output',series.values(indices(series.time_s,wanted),:));
    clear observed signals parts
    inputs=[wanted fixture.temperature_sma fixture.temperature_se fixture.memory];
    assert(size(inputs,2)==253 && size(fixture.observed_output,2)==252);
    assignin('base','EIGHTH_ROUND_OPTIONS',options);
    HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic(inputs(1,:).');
    clock=tic;replay=evaluate(inputs);unprofiled_s=toc(clock);
    mkdir(output);save(fullfile(output,'causal_replay_fixture.mat'),'fixture','options','-v7.3');
    exact=isequaln(replay,fixture.observed_output);
    record=struct('schema','heatdrive_ecc_stable_kernel_benchmark_v1','source_packet',packet, ...
        'source_producer',manifest.producer,'source_manifest_sha256',file_hash(manifest_path), ...
        'source_gate_sha256',file_hash(gate_path),'fixture_sha256',file_hash(fullfile(output,'causal_replay_fixture.mat')), ...
        'sample_count',numel(wanted),'bindings',{bindings},'unprofiled_replay_wall_s',unprofiled_s, ...
        'all_252_output_coordinates_bitwise_equal',exact,'maximum_output_difference',max(abs(replay-fixture.observed_output),[],'all'), ...
        'original_substeps',32,'sample_time_s',.001,'operating_point_loaded',false,'simulation_executed',false, ...
        'physical_sources_changed',false,'physical_thresholds_changed',false,'production_recovery_allowed',false, ...
        'coupled_acceleration_qualified',false,'full_objective_complete',false);
    write_json(fullfile(output,'kernel_benchmark.json'),record);
    assert(exact,'HeatDriveECC:KernelReplayMismatch','Diagnose causal/options mapping before profiling.');
    profile clear;profile on;cleanup=onCleanup(@() profile('off'));
    evaluate(inputs);profile off;statistics=profile('info');clear cleanup
    save(fullfile(output,'matlab_profile.mat'),'statistics','-v7.3');
    table=statistics.FunctionTable;rows=cell(numel(table),1);
    for k=1:numel(table)
        r=table(k);children=sum([r.Children.TotalTime]);
        rows{k}=struct('function',r.FunctionName,'file',r.FileName,'calls',r.NumCalls, ...
            'inclusive_time_s',r.TotalTime,'direct_children_time_s',children, ...
            'exclusive_time_estimate_s',r.TotalTime-children,'partial_data',r.PartialData);
    end
    rows=vertcat(rows{:});[~,order]=sort([rows.exclusive_time_estimate_s],'descend');
    record.profile_functions=rows(order);record.profile_sha256=file_hash(fullfile(output,'matlab_profile.mat'));
    record.profile_timing_scope='Offline exact causal sample replay; inclusive times overlap and profiler overhead is not production solver cost';
    record.profiler_reference='https://www.mathworks.com/help/releases/R2025b/matlab/ref/profile.html';
    write_json(fullfile(output,'kernel_benchmark.json'),record);
    fprintf('FINAL_JSON=%s\n',jsonencode(rmfield(record,'profile_functions')));
end
function y=evaluate(inputs)
    y=zeros(size(inputs,1),252);
    for k=1:size(inputs,1),y(k,:)=HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic(inputs(k,:).').';end
end
function selected=indices(clock,wanted)
    clock=clock(:);assert(all(isfinite(clock)) && all(diff(clock)>0));
    selected=round((wanted-clock(1))/median(diff(clock)))+1;
    assert(all(selected>=1 & selected<=numel(clock)) && all(abs(clock(selected)-wanted)<=1e-9), ...
        'Missing exact causal sample; interpolation is forbidden.');
end
function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
function h=file_hash(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
