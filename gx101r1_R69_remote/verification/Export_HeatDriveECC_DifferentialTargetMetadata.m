function audit=Export_HeatDriveECC_DifferentialTargetMetadata(repo,output_path)
% Read public differential/elimination attributes from the archived target tree.
    assert(~isfile(output_path),'Do not overwrite metadata evidence.');
    source=fullfile(repo,'outputs_storage_audit','state_target_catalog_20260908','public_targets.mat');
    assert(strcmp(file_sha256(source),'A02A0A6E8E6D8F8B64F8A665D3451253486EB7955F573EDA16ACCCFCAA398FFF'), ...
        'Archived target tree changed.');
    load_system('simulink');data=load(source,'targets');rows=walk(data.targets,'');
    assert(numel(rows)==2668,'Incomplete target metadata.');
    audit=struct('schema','heatdrive_ecc_differential_target_metadata_v1','targets',{rows}, ...
        'source_sha256',file_sha256(source),'simulation_run',false,'production_recovery_allowed',false);
    fid=fopen(output_path,'w','n','UTF-8');assert(fid>=0,'Cannot save metadata.');
    cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('TARGET_METADATA_COUNT=%d DIFFERENTIAL_COUNT=%d\n',numel(rows),sum(cellfun(@(r) r.differential,rows)));
end

function rows=walk(node,prefix)
    rows={};
    for k=1:numel(node.ChildIds)
        id=node.ChildIds{k};child=node.Children{k};
        if isempty(prefix),path=id;else,path=[prefix '/' id];end
        if isa(child,'simscape.op.Target')
            attr=child.Attributes;
            assert(isKey(attr,'Differential') && isKey(attr,'Eliminated'),'Missing public attributes.');
            rows{end+1}=struct('path',path,'unit',char(unit(child.Value)), ...
                'priority',char(child.Priority),'differential',logical(attr('Differential')), ...
                'eliminated',logical(attr('Eliminated'))); %#ok<AGROW>
        elseif isa(child,'simscape.op.OperatingPoint')
            rows=[rows walk(child,path)]; %#ok<AGROW>
        else,error('Unexpected public target class.');end
    end
end

function result=file_sha256(path)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');
    assert(fid>=0,'Cannot read source.');cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
