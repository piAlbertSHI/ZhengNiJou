function [candidate,records]=Apply_HeatDriveECC_ObservedFluxTargets(candidate,repo,model)
% Diagnostic low-priority algebraic targets; do not change physical equations.
    base=fullfile(repo,'outputs_storage_audit','c200_source_compatibility_20260907');
    source_path=fullfile(base,'archived_source_probe_v4','restored_step_signals.mat');
    capture=jsondecode(fileread(fullfile(base,'c200_state_capture_v1.json')));
    assert(strcmp(file_sha256(source_path),capture.input_sha256.observed),'Frozen native reference changed.');
    loaded=load(source_path,'native');
    declared=jsondecode(fileread(fullfile(repo,'outputs_storage_audit','state_target_catalog_20260908','target_catalog.json')));
    paths={'SMA_PumpInletConnectingPipeVolume/mdot_B','SMA_PumpOutletConnectingPipeVolume/mdot_A','SHEX/HotSinkMass/Q'};
    units={'kg/s','kg/s','W'};records={};
    for k=1:numel(paths)
        path=paths{k};idx=find(strcmp({declared.targets.path},path));
        assert(isscalar(idx) && strcmp(declared.targets(idx).priority,'None'),'Target already has active priority.');
        matches=find(cellfun(@(r) strcmp([r.block_path '/' r.state_name],[model '/' path]),loaded.native));
        assert(isscalar(matches),'Missing unique observed flux.');row=loaded.native{matches};
        assert(isequal(row.time_s(:),[2000;2000.001]),'Wrong flux sample window.');
        target=value(simscape.Value(row.values(1),row.unit),units{k});
        assert(isfinite(target),'Nonfinite flux.');
        candidate=set(candidate,path,simscape.op.Target(target,units{k},'Low'));
        records{end+1}=struct('path',path,'unit',units{k},'value',target, ...
            'original_priority','None','new_priority','Low','reference_sha256',capture.input_sha256.observed); %#ok<AGROW>
    end
end

function result=file_sha256(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');
    assert(fid>=0,'Cannot read reference.');cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
