function record=Analyze_HeatDriveECC_RecordedThermalPeriodicity(measured_file,output_file)
% Reuse the unmodified production statistics on an exact join of measured packets.
    assert(~isfile(output_file),'Never overwrite thermal statistics.');
    index=jsondecode(fileread(measured_file));assert(index.sample_count==100001 && isequal(index.window_s(:),[620;720]));
    names={'SMA_Tx21_internal','SE_Tx21_internal','SHEX_hot_sink_temp_out', ...
        'hot_sink_temp_out','cold_sink_temp_out','ECC_constitutive21_output'};
    fields={'SMA_T_21_K','SE_T_21_K','SHEX_T_K','HHEX_T_K','CHEX_T_K'};
    joined=cell(6,1);time=[];
    for k=1:numel(index.packets)
        p=index.packets(k);
        assert(strcmp(file_hash(p.observation_path),p.observation_sha256) && ...
            strcmp(file_hash(p.configuration_path),p.configuration_sha256));
        saved=load(p.observation_path,'signals');
        for n=1:6
            row=saved.signals.(names{n});t=row.time_s(:);
            selected=t>=p.window_s(1)-1e-9 & t<=p.window_s(2)+1e-9;
            t=t(selected);v=row.values(selected,:);
            assert(numel(t)==20001 && all(isfinite(v),'all'));
            if n==6,v=v(:,43:84);end
            if k>1
                assert(isequaln(joined{n}(end,:),v(1,:)),'Measured endpoint changed.');v=v(2:end,:);
            end
            joined{n}=[joined{n};v]; %#ok<AGROW>
            if n==1
                if k>1,assert(abs(t(1)-time(end))<=1e-9);t=t(2:end);end
                time=[time;t]; %#ok<AGROW>
            end
        end
        clear saved
    end
    assert(numel(time)==100001 && all(abs(diff(time)-.001)<=1e-9));
    for n=1:5,physical.(fields{n})=joined{n};end
    physical.xM_SMA_21=joined{6}(:,1:21);physical.xM_SE_21=joined{6}(:,22:42);
    physical.time_s=time-620;
    configured=load(index.packets(1).configuration_path,'options');options=configured.options;
    options.cycle_count=10;
    physical.cycle_index=HeatDriveECC_CycleStageFromTime(physical.time_s,options);
    p=Evaluate_HeatDriveECC_Periodicity(physical,options);
    record=struct('schema','heatdrive_ecc_recorded_ten_cycle_thermal_statistics_v1', ...
        'window_s',[620 720],'sample_count',numel(time),'statistics',p, ...
        'original_production_statistics_used',true,'physical_tolerances_changed',false, ...
        'measured_window_sha256',file_hash(measured_file), ...
        'statistics_source_sha256',file_hash(which('Evaluate_HeatDriveECC_Periodicity')), ...
        'simulation_executed',false,'operating_point_loaded',false,'source_state_edited',false, ...
        'complete_internal_state_periodicity_verified',false,'production_recovery_allowed',false, ...
        'outer_solve_eligible',false,'table4_reproduction_claim',false);
    fid=fopen(output_file,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    fprintf('FINAL_JSON=%s\n',jsonencode(p));
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
