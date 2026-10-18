function record=Verify_HeatDriveECC_StableKernelCandidate(benchmark,qualification,output)
% Numerical implementation comparison only; synthetic states are never resume states.
    assert(~isfolder(output),'Never overwrite kernel comparison evidence.');
    source=jsondecode(fileread(fullfile(benchmark,'kernel_benchmark.json')));
    path=fullfile(benchmark,'causal_replay_fixture.mat');
    assert(source.all_252_output_coordinates_bitwise_equal && strcmp(file_hash(path),source.fixture_sha256));
    data=load(path);fixture=data.fixture;options=data.options;
    inputs=[fixture.time_s fixture.temperature_sma fixture.temperature_se fixture.memory];
    q=jsondecode(fileread(qualification));baseline=load(fullfile(q.source_packet_root,'native','configuration.mat'),'plant_build_options');
    mkdir(output);record=struct('schema','heatdrive_ecc_stable_kernel_candidate_comparison_v1', ...
        'benchmark_sha256',file_hash(fullfile(benchmark,'kernel_benchmark.json')),'fixture_sha256',source.fixture_sha256, ...
        'qualification_sha256',file_hash(qualification),'candidate_source_sha256',file_hash(which('HeatDriveECC_StableKernelCandidate')), ...
        'all_captured_samples_bitwise_equal',false,'all_original_L8_option_cases_bitwise_equal',false, ...
        'source_state_edited',false,'operating_point_loaded',false,'simulation_executed',false, ...
        'production_constitutive_sources_changed',false,'physical_thresholds_changed',false, ...
        'coupled_acceleration_qualified',false,'production_recovery_allowed',false,'error_message','');
    try
        assignin('base','EIGHTH_ROUND_OPTIONS',options);
        reference=evaluate(inputs,options,false);candidate=evaluate(inputs,options,true);
        record.captured_samples=size(inputs,1);
        record.reference_matches_captured_physical_output=same_bits(reference,fixture.observed_output);
        record.all_captured_samples_bitwise_equal=same_bits(reference,candidate);
        record.maximum_captured_output_difference=max(abs(reference-candidate),[],'all');
        assert(record.reference_matches_captured_physical_output && record.all_captured_samples_bitwise_equal, ...
            'HeatDriveECC:KernelCandidateDifference','Candidate differs from exact captured reference; diagnose before use.');
        rows=cell(9,1);ends=options.schedule.stage_end_s(:).';
        times=([0 ends(1:end-1)]+ends)/2;edge_count=0;
        for index=0:8
            request=struct('case_index',index,'candidate_qualification_path',qualification);
            actual=Apply_HeatDriveECC_RuntimeSensitivity(baseline.plant_build_options,request);
            built=Build_HeatDriveECC_EighthRound_Defaults(actual);assignin('base','EIGHTH_ROUND_OPTIONS',built);
            frames=zeros(0,253);
            for time=times
                for edge=1:5
                    u=inputs(1,:);u(1)=time;
                    switch edge
                        case 1,u(44:64)=0;u(65:85)=0;
                        case 2,u(44:64)=1;u(65:85)=1;
                        case 3,u(44:64)=linspace(0,1,21);u(65:85)=linspace(1,0,21);
                        case 4,u(2:22)=350;u(23:43)=270;
                        case 5,u(2:22)=270;u(23:43)=350;
                    end
                    frames(end+1,:)=u; %#ok<AGROW>
                end
            end
            a=evaluate(frames,built,false);b=evaluate(frames,built,true);
            rows{index+1}=struct('case_index',index,'samples',size(frames,1),'bitwise_equal',same_bits(a,b), ...
                'maximum_output_difference',max(abs(a-b),[],'all'));
            assert(rows{index+1}.bitwise_equal,'HeatDriveECC:KernelEdgeDifference','Candidate differs at an original case edge.');
            edge_count=edge_count+size(frames,1);
        end
        record.original_L8_option_cases=vertcat(rows{:});record.edge_samples=edge_count;
        record.all_original_L8_option_cases_bitwise_equal=all([record.original_L8_option_cases.bitwise_equal]);
        record.invalid_contracts_rejected=invalid_contracts(inputs(1,:).',options);
        assignin('base','EIGHTH_ROUND_OPTIONS',options);
        HeatDriveECC_StableKernelCandidate(inputs(1,:).',options);
        seconds=zeros(3,2);
        for run=1:3
            order=1:2;if mod(run,2)==0,order=2:-1:1;end
            for backend=order
                clock=tic;value=evaluate(inputs,options,backend==2);seconds(run,backend)=toc(clock);
                assert(same_bits(value,reference));
            end
        end
        record.unprofiled_paired_wall_seconds=seconds;
        record.reference_median_s=median(seconds(:,1));record.candidate_median_s=median(seconds(:,2));
        record.sampled_kernel_speedup=record.reference_median_s/record.candidate_median_s;
        record.scope='200 actual causal points plus 180 synthetic edge points across original nominal/L8 options; not a coupled trajectory or solver speedup';
        record.synthetic_states_may_propagate=false;record.candidate_installed_in_model=false;
    catch ME
        record.error_message=ME.message;record.error_identifier=ME.identifier;
        record.error_report=getReport(ME,'extended','hyperlinks','off');
        write_json(fullfile(output,'kernel_candidate_comparison.json'),record);rethrow(ME);
    end
    write_json(fullfile(output,'kernel_candidate_comparison.json'),record);
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end
function y=evaluate(inputs,options,candidate)
    y=zeros(size(inputs,1),252);
    for k=1:size(inputs,1)
        if candidate,y(k,:)=HeatDriveECC_StableKernelCandidate(inputs(k,:).',options).';
        else,y(k,:)=HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic(inputs(k,:).').';end
    end
end
function count=invalid_contracts(u,options)
    bad=cell(8,1);
    for k=1:8
        v=u;o=options;
        switch k
            case 1,o.node_count=20;
            case 2,o.constitutive.simulink_sample_time_s=.002;
            case 3,o.constitutive.diagnostic_substeps=16;
            case 4,o.constitutive.phase_front_smoothing_1_per_s=1;
            case 5,o.constitutive.integration_scheme='explicit_euler';
            case 6,v(44)=-.01;
            case 7,v(65)=1.01;
            case 8,v(1)=NaN;
        end
        try,HeatDriveECC_StableKernelCandidate(v,o);bad{k}=false;catch,bad{k}=true;end
    end
    count=sum([bad{:}]);assert(count==8,'Candidate contract has an unintended fallback.');
end
function yes=same_bits(a,b)
    yes=isequal(size(a),size(b)) && isequal(typecast(a(:),'uint64'),typecast(b(:),'uint64'));
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
