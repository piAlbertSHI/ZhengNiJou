function [candidate,records]=Build_HeatDriveECC_DifferentialStateTargets(repo,model,sample_index)
% Prefer measured differential coordinates; retain old algebraic targets as Low.
    if nargin<3,sample_index=1;end
    assert(isscalar(sample_index) && any(sample_index==[1 2]),'Unsupported observed sample.');
    base=fullfile(repo,'outputs_storage_audit');
    metadata_path=fullfile(base,'c200_differential_target_metadata_20260908.json');
    metadata=jsondecode(fileread(metadata_path));
    assert(strcmp(metadata.schema,'heatdrive_ecc_differential_target_metadata_v1') && ...
        ~metadata.simulation_run && ~metadata.production_recovery_allowed && numel(metadata.targets)==2668, ...
        'Unverified differential metadata.');
    source_path=fullfile(base,'c200_source_compatibility_20260907','archived_source_probe_v4','restored_step_signals.mat');
    expected_sha='FA55320F51D2BB3CD2C997DAC98F54D3FD6C46109904A5D6BE63F86260ECD732';
    assert(strcmp(file_sha256(source_path),expected_sha),'Frozen native observations changed.');
    loaded=load(source_path,'native');candidate=simscape.op.OperatingPoint;records={};
    for k=1:numel(metadata.targets)
        declared=metadata.targets(k);
        if ~declared.differential && strcmp(declared.priority,'None'),continue;end
        assert(~declared.eliminated,'Selected target is an eliminated coordinate.');
        matches=find(cellfun(@(r) strcmp([r.block_path '/' r.state_name],[model '/' declared.path]),loaded.native));
        assert(isscalar(matches),'Missing unique differential/algebraic observation.');row=loaded.native{matches};
        assert(isequal(row.time_s(:),[2000;2000.001]) && strcmp(row.unit,declared.unit),'Wrong units/time.');
        observed=row.values(sample_index);assert(isfinite(observed),'Nonfinite target.');
        if declared.differential,priority='High';else,priority='Low';end
        candidate=set(candidate,declared.path,simscape.op.Target(observed,declared.unit,priority));
        records{end+1}=struct('path',declared.path,'unit',declared.unit,'value',observed, ...
            'original_priority',declared.priority,'new_priority',priority,'differential',declared.differential, ...
            'sample_time_s',row.time_s(sample_index), ...
            'metadata_sha256',file_sha256(metadata_path),'reference_sha256',expected_sha); %#ok<AGROW>
    end
    assert(numel(records)==196 && sum(cellfun(@(r) r.differential,records))==125 && ~hasPrivateData(candidate), ...
        'Unexpected dynamic-coordinate target coverage.');
end

function result=file_sha256(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');
    assert(fid>=0,'Cannot read evidence.');cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
