function check=Check_HeatDriveECC_RuntimeRollingPeriodicity(root,origin,completed,Tc)
% Only measured same-temperature packets enter the unchanged public thermal criteria.
    if nargin<4,Tc=276.95;end
    if isempty(origin),packets={};else,packets=num2cell(origin.packets);end
    for k=1:numel(completed)
        row=completed{k};packet=row.packet_root;
        m=jsondecode(fileread(fullfile(packet,'packet_manifest.json')));
        same=strcmp(m.packet_role,'runtime_boundary_transient') && m.prescribed_Tc_K==276.95 && Tc==276.95;
        candidate=any(strcmp(m.packet_role,{'runtime_boundary_Tc_candidate','runtime_boundary_Tc_continuation'})) && m.prescribed_Tc_K==Tc;
        assert((same || candidate) && ...
            strcmp(m.temperature_configurability,'runtime') && ~m.source_state_edited);
        raw=fullfile(packet,'native','observations.mat');cfg=fullfile(packet,'native','configuration.mat');
        packets{end+1}=struct('packet_root',packet,'observation_path',raw,'observation_sha256',file_hash(raw), ...
            'configuration_path',cfg,'configuration_sha256',file_hash(cfg),'window_s',m.window_s); %#ok<AGROW>
    end
    packets=packets(end-4:end);window=[packets{1}.window_s(1) packets{end}.window_s(2)];
    assert(diff(window)==100);
    for k=2:5,assert(packets{k-1}.window_s(2)==packets{k}.window_s(1));end
    index=struct('schema','heatdrive_ecc_runtime_rolling_public_window_v1', ...
        'window_s',window,'sample_count',100001,'packets',{packets},'source_state_edited',false);
    base=fullfile(root,sprintf('periodicity_C%03d',window(2)/10));attempt=1;
    folder=sprintf('%s_attempt%02d',base,attempt);
    while isfolder(folder),attempt=attempt+1;folder=sprintf('%s_attempt%02d',base,attempt);end
    mkdir(folder);input_file=fullfile(folder,'measured_window.json');output_file=fullfile(folder,'original_thermal_statistics.json');
    fid=fopen(input_file,'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(index,'PrettyPrint',true));fclose(fid);
    statistics=Analyze_HeatDriveECC_RecordedThermalPeriodicity(input_file,output_file);
    check=struct('window_s',window,'periodic_steady_state',statistics.statistics.periodic_steady_state, ...
        'measured_window_path',input_file,'measured_window_sha256',file_hash(input_file), ...
        'thermal_statistics_path',output_file,'thermal_statistics_sha256',file_hash(output_file), ...
        'statistics',statistics.statistics,'physical_tolerances_changed',false, ...
        'complete_internal_state_periodicity_verified',false,'outer_solve_eligible',false);
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
