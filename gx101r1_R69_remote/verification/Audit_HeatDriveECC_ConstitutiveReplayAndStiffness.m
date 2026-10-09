function record = Audit_HeatDriveECC_ConstitutiveReplayAndStiffness(input_root, output_root)
% Local constitutive replay and frozen-temperature stability, never coupled state recovery.
    assert(~isfolder(output_root),'Never overwrite constitutive evidence.');
    contract=jsondecode(fileread(fullfile(input_root,'replay_input_contract.json')));
    fixture=fullfile(input_root,'constitutive_replay_inputs.mat');
    assert(strcmp(file_hash(fixture),contract.replay_fixture_sha256) && ...
        ~contract.interpolation_used && all([contract.bindings.exact_previous_public_match]), ...
        'Unverified exact causal replay inputs.');
    configured=load(fullfile(contract.source_root,'native','configuration.mat'),'options');
    assert(strcmp(file_hash(fullfile(contract.source_root,'native','configuration.mat')),contract.source_sha256.configuration));
    options=configured.options;assignin('base','EIGHTH_ROUND_OPTIONS',options);
    repo=fileparts(fileparts(mfilename('fullpath')));workspace=fileparts(repo);
    files={'HeatDriveECC_ConstitutiveStateVectorStep21.m','HeatDriveECC_ConstitutiveCompatibilityStep51.m', ...
        'Initialize_HeatDriveECC_ConstitutiveVector21.m','Initialize_HeatDriveECC_EighthRound_State.m'};
    hashes=struct();
    for k=1:numel(files)
        [status,~]=system(sprintf('git -C "%s" diff --quiet %s HEAD -- "gx101r1_R69_remote/%s"',workspace,contract.producer,files{k}));
        assert(status==0,'Constitutive code changed since the actual producer.');
        hashes.(sprintf('file%d',k))=file_hash(fullfile(repo,files{k}));
    end
    input=load(fixture);count=numel(input.time_s);dt=options.constitutive.simulink_sample_time_s;
    assert(dt==.001 && size(input.memory,2)==210 && size(input.observed_output,2)==252);
    replay=zeros(count,252);
    for idx=1:count
        replay(idx,:)=HeatDriveECC_ConstitutiveStateVectorStep21([input.time_s(idx); ...
            input.temperature_sma(idx,:).';input.temperature_se(idx,:).';input.memory(idx,:).']).';
    end
    equal=isequaln(replay,input.observed_output);
    blocks={'heat_SMA_W','heat_SE_W','phase_SMA','phase_SE','stress_SMA_Pa','stress_SE_Pa', ...
        'strain_SMA','strain_SE','driving_SMA_Pa','driving_SE_Pa','rate_SMA_per_s','rate_SE_per_s'};
    differences=struct();
    for k=1:12
        columns=(k-1)*21+(1:21);
        differences.(blocks{k})=max(abs(replay(:,columns)-input.observed_output(:,columns)),[],'all');
    end
    record=struct('schema','heatdrive_ecc_constitutive_replay_stiffness_v1', ...
        'producer',contract.producer,'source_input_contract_sha256',file_hash(fullfile(input_root,'replay_input_contract.json')), ...
        'source_fixture_sha256',contract.replay_fixture_sha256,'constitutive_source_sha256',hashes, ...
        'replay_samples',count,'all_252_output_coordinates_exact',equal,'maximum_differences_by_physical_unit',differences, ...
        'production_sample_time_s',dt,'simulation_executed',false,'operating_point_loaded',false, ...
        'source_state_edited',false,'physical_tolerances_changed',false,'production_recovery_allowed',false, ...
        'local_test_is_not_full_coupled_step_convergence',true);
    mkdir(output_root);
    if ~equal
        record.local_stability_evaluated=false;write_json(fullfile(output_root,'constitutive_replay_stiffness.json'),record);
        error('HeatDriveECC:ReplayMismatch','Diagnose replay clock/options mismatch before a stability inference.');
    end
    local_phase=mod(input.time_s,10);
    selected=find(any(abs(mod(local_phase,5)-[.15,.2,.225,.25,.3,.35])<1e-8,2));
    rows=cell(numel(selected),1);
    for k=1:numel(selected)
        idx=selected(k);state=unpack(input,idx,options);
        phase=[state.xM_a_21;state.xM_r_21];
        stage_id=1+2*(local_phase(idx)>=5);
        [jac1,derivative]=jacobian(state,options,1e-6,stage_id);
        jac2=jacobian(state,options,1e-7,stage_id);
        eigenvalues=eig(jac2);z=dt*eigenvalues;
        amplification=abs(1+z+.5*z.^2+z.^3/6);
        negative=real(eigenvalues)<-1e-8;
        refinements=[1,2,4,8,16,32];endpoints=zeros(42,numel(refinements));
        for r=1:numel(refinements)
            trial=state;
            for sub=1:refinements(r)
                trial=HeatDriveECC_ConstitutiveCompatibilityStep51(trial,options,dt/refinements(r),stage_id);
            end
            endpoints(:,r)=[trial.xM_a_21;trial.xM_r_21];
        end
        rows{k}=struct('time_s',input.time_s(idx),'global_cycle',floor(input.time_s(idx)/10)+1, ...
            'local_phase_s',local_phase(idx),'stage_id',stage_id,'jacobian_relative_step_difference', ...
            norm(jac1-jac2,'fro')/max(norm(jac2,'fro'),eps), ...
            'most_negative_real_eigenvalue_per_s',min(real(eigenvalues)), ...
            'max_ode3_amplification_negative_modes',max([amplification(negative);0]), ...
            'negative_mode_outside_ode3_stability_region',any(amplification(negative)>1+1e-8), ...
            'maximum_instantaneous_phase_rate_per_s',max(abs(derivative)), ...
            'substep_counts',refinements,'max_phase_increment',max(abs(endpoints-phase),[],1), ...
            'max_adjacent_refinement_difference',max(abs(diff(endpoints,1,2)),[],1), ...
            'max_difference_from_32_substep',max(abs(endpoints-endpoints(:,end)),[],1));
    end
    record.local_stability_evaluated=true;record.selected_frames=vertcat(rows{:});
    record.negative_mode_unstable_frame_count=sum(cellfun(@(r) r.negative_mode_outside_ode3_stability_region,rows));
    record.selected_frame_count=numel(rows);
    record.interpretation='Frozen-temperature 42-phase Jacobian and local substep diagnostics only; no parameters, gates, model, OP or recoverable coupled endpoint modified.';
    write_json(fullfile(output_root,'constitutive_replay_stiffness.json'),record);
    fprintf('FINAL_JSON=%s\n',jsonencode(struct('replay_exact',equal,'replay_samples',count, ...
        'local_frames',numel(rows),'negative_mode_unstable_frames',record.negative_mode_unstable_frame_count)));
end

function state = unpack(input,idx,options)
    state=Initialize_HeatDriveECC_EighthRound_State(options);
    state.Ta_21=input.temperature_sma(idx,:).';state.Tr_21=input.temperature_se(idx,:).';
    fields={'xM_a_21','xM_r_21','sigma_a_21','sigma_r_21','epsilon_a_21','epsilon_r_21', ...
        'pai_a_21','pai_r_21','r_xi_a_21','r_xi_r_21'};
    for k=1:10,state.(fields{k})=input.memory(idx,(k-1)*21+(1:21)).';end
end

function [jac,base] = jacobian(state,options,h,stage_id)
    x=[state.xM_a_21;state.xM_r_21];base=phase_rate(state,options,stage_id);jac=zeros(42);
    for k=1:42
        left=x;right=x;left(k)=max(0,x(k)-h);right(k)=min(1,x(k)+h);
        assert(right(k)>left(k),'Degenerate physical phase perturbation.');
        a=state;b=state;a.xM_a_21=left(1:21);a.xM_r_21=left(22:42);
        b.xM_a_21=right(1:21);b.xM_r_21=right(22:42);
        jac(:,k)=(phase_rate(b,options,stage_id)-phase_rate(a,options,stage_id))/(right(k)-left(k));
    end
end

function rate = phase_rate(state,options,stage_id)
    state=HeatDriveECC_ConstitutiveCompatibilityStep51(state,options,0,stage_id);
    rate=[state.r_xi_a_21;state.r_xi_r_21];
end

function write_json(path,record)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
