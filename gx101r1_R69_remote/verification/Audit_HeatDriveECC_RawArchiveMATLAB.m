function audit=Audit_HeatDriveECC_RawArchiveMATLAB(repo)
% Verify reconstructed MAT containers with MATLAB's own loader before retirement.
    root=fullfile(repo,'outputs_storage_audit','c40_c60_prefix_archive_20260908_v3');
    audit_path=fullfile(root,'matlab_materialization_audit.json');
    assert(~isfile(audit_path),'Do not overwrite archive evidence.');
    audit=struct('schema','heatdrive_ecc_raw_archive_matlab_v1','load_and_value_comparison_pass',false, ...
        'production_recovery_allowed',false,'original_container_hash_preserved',false,'cases',{{}},'error_message','');
    try
        for cycles=[40 60]
            folder=fullfile(root,sprintf('c%d',cycles));
            descriptor=jsondecode(fileread(fullfile(folder,'archive.json')));
            materialized=jsondecode(fileread(fullfile(folder,'materialized_validation.json')));
            source=fullfile(repo,descriptor.source_path);target=fullfile(folder,'restored_validation.mat');
            assert(strcmp(file_sha256(source),descriptor.source_sha256),'Original raw changed.');
            assert(strcmp(file_sha256(target),materialized.sha256),'Restored MAT changed.');
            names=fieldnames(descriptor.metadata_logical_sha256);records={};
            for k=1:numel(names)
                name=names{k};left=load(source,name);right=load(target,name);
                assert(isfield(left,name) && isfield(right,name),'Required MAT variable missing.');
                assert(isequaln(left.(name),right.(name)),'Restored MATLAB value changed: %s',name);
                records{end+1}=struct('name',name,'class',class(left.(name)),'isequaln_pass',true); %#ok<AGROW>
                clear left right
            end
            assert(numel(records)==5,'Unexpected top-level variable count.');
            audit.cases{end+1}=struct('cycles',cycles,'source_sha256',descriptor.source_sha256, ...
                'restored_sha256',materialized.sha256,'variables',{records}); %#ok<AGROW>
        end
        audit.load_and_value_comparison_pass=numel(audit.cases)==2;
    catch ME
        audit.error_message=ME.message;audit.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    fid=fopen(audit_path,'w','n','UTF-8');assert(fid>=0,'Cannot write audit.');
    cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(audit));
    assert(audit.load_and_value_comparison_pass,'See matlab_materialization_audit.json.');
end

function result=file_sha256(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');
    assert(fid>=0,'Cannot read evidence.');cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
