function audit=Audit_HeatDriveECC_PublicOPAccess(repo,output_root)
% Read documented OP properties and query a named block; never modify OP data.
    assert(~isfolder(output_root),'Do not overwrite API evidence.');
    [code,commit]=system('git rev-parse HEAD');assert(code==0,'Cannot record source.');
    [code,dirty]=system('git status --porcelain');assert(code==0 && isempty(strtrim(dirty)),'Commit source first.');
    source=fullfile(repo,'outputs_storage_audit','c200_source_compatibility_20260907', ...
        'archived_source_probe_v4','DO_NOT_RESUME_FOR_PRODUCTION.mat');
    expected='8ACBED525F7F45170EF308B5F6BCB8E008AAEB87A4A90900982052786273E321';
    assert(strcmp(file_sha256(source),expected),'Source diagnostic OP changed.');
    mkdir(output_root);load_system('simulink');
    data=load(source,'diagnostic_op','production_recovery_allowed');
    assert(~data.production_recovery_allowed,'Unexpected production authorization.');
    point=data.diagnostic_op;original=point.loggedStates;
    audit=struct('schema','heatdrive_ecc_public_op_access_v1','execution_commit',strtrim(commit), ...
        'matlab_release',version('-release'),'source_sha256',expected,'read_only',true, ...
        'model_simulation_executed',false,'private_fields_read_or_written',false, ...
        'production_recovery_allowed',false,'start_time_s',point.startTime,'snapshot_time_s',point.snapshotTime, ...
        'properties',{{}},'queries',{{}});
    visible=properties(point);
    audit.time_read_only_contract='Official documentation; no runtime write attempted.';
    audit.runtime_set_access_reflection_available=false;
    for name={'startTime','snapshotTime','loggedStates'}
        assert(any(strcmp(visible,name{1})),'Missing documented public property.');
        audit.properties{end+1}=struct('name',name{1},'publicly_enumerated',true); %#ok<AGROW>
    end
    targets={};
    for k=1:original.numElements
        item=original.getElement(k);block=char(item.BlockPath.getBlock(1));
        if endsWith(block,'/Solver Configuration'),targets{end+1}=block;end %#ok<AGROW>
    end
    assert(numel(targets)==1,'Require the recorded solver block identity.');
    for k=1:numel(targets)
        row=struct('block_path',targets{k},'public_get_succeeded',false,'error_identifier','','error_message','');
        try
            value=get(point,targets{k});
            row.public_get_succeeded=true;row.result_class=class(value);row.result_size=size(value);
            if isstruct(value),row.result_field_names=fieldnames(value);
            elseif isobject(value),row.result_public_property_names=properties(value);end
        catch ME
            row.error_identifier=ME.identifier;row.error_message=ME.message;
        end
        audit.queries{end+1}=row; %#ok<AGROW>
    end
    assert(point.startTime==0 && point.snapshotTime==2000.001 && isequaln(original,point.loggedStates), ...
        'Source public state changed.');
    assert(strcmp(file_sha256(source),expected),'Source file changed.');
    fid=fopen(fullfile(output_root,'public_op_access.json'),'w','n','UTF-8');assert(fid>=0,'Cannot save evidence.');
    cleanup_file=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(audit,'PrettyPrint',true));
    fprintf('%s\n',jsonencode(audit));
end

function result=file_sha256(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');
    assert(fid>=0,'Cannot read source.');cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
