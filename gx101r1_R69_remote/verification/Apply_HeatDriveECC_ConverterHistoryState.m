function [initial,records]=Apply_HeatDriveECC_ConverterHistoryState(initial,model,root)
% Use complete public digital snapshots, not output samples or a physical OP.
    proof_path=fullfile(root,'independent_digital_history_audit.json');
    proof=jsondecode(fileread(proof_path));
    assert(strcmp(proof.schema,'heatdrive_ecc_digital_converter_history_audit_v1') && ...
        proof.diagnostic_digital_memory_observation_pass && proof.digital_input_exact && ...
        proof.thermal_control_energy_pass && proof.initial_temperature_K==340 && ...
        ~proof.production_recovery_allowed && ~proof.whole_model_migration_verified && numel(proof.rows)==42, ...
        'Unqualified digital-memory observation.');
    raw_path=fullfile(root,'converter_history_snapshots.mat');
    assert(strcmp(file_sha256(raw_path),proof.input_sha256.raw) && ...
        strcmp(file_sha256(fullfile(root,'converter_history_replay.json')),proof.input_sha256.producer), ...
        'Digital-memory evidence changed.');
    loaded=load(raw_path,'snapshots');assert(numel(loaded.snapshots)==42,'Incomplete snapshot set.');
    records={};expected=struct('Unit','W','FilteringAndDerivatives','provide','UdotUserProvided','0', ...
        'SimscapeFilterOrder','1','InputFilterTimeConstant','0.001','AffineConversion','off');
    for k=1:initial.numElements
        state=initial.getElement(k);block=char(state.BlockPath.getBlock(1));
        match=regexp(block,['^' model '/(SMA|SE)/Subsystem2/ConstitutiveHeatPS_(\d{2})$'],'tokens','once');
        if isempty(match),continue;end
        assert(str2double(match{2})>=1 && str2double(match{2})<=21,'Wrong converter index.');
        fields=fieldnames(expected);
        for j=1:numel(fields)
            assert(strcmp(get_param(block,fields{j}),expected.(fields{j})),'Converter configuration differs.');
        end
        indices=find(cellfun(@(r) strcmp(r.block_path,block),loaded.snapshots));
        assert(isscalar(indices),'Require unique replay snapshot.');
        source=loaded.snapshots{indices};series=state.Values;snapshot=source.snapshot;
        assert(isa(series,'timeseries') && isa(snapshot,'timeseries') && ...
            series.Time==2000 && snapshot.Time==2000 && series.IsTimeFirst && snapshot.IsTimeFirst && ...
            numel(series.Data)==2 && isequal(size(series.Data),size(snapshot.Data)) && ...
            isa(snapshot.Data,'double') && all(isfinite(snapshot.Data(:))) && ...
            isequal(snapshot.Data,source.snapshot_values),'Typed converter snapshot mismatch.');
        prior=series.Data;series.Data=snapshot.Data;state.Values=series;
        initial=initial.setElement(k,state);
        records{end+1}=struct('block_path',block,'prior_output_sample',prior, ...
            'replayed_snapshot',snapshot.Data,'time_s',snapshot.Time,'raw_sha256',proof.input_sha256.raw, ...
            'proof_sha256',file_sha256(proof_path)); %#ok<AGROW>
    end
    assert(numel(records)==42 && initial.numElements==72,'Do not change other named memory groups.');
end

function result=file_sha256(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(path,'rb');assert(fid>=0,'Cannot read evidence.');cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
