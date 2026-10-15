function record=Compare_HeatDriveECC_RuntimeBoundaryRecipe(reference,candidate,output)
% Compare the actual saved construction recipes, not a claim about matching defaults.
    assert(~isfile(output));a=load(reference,'options');b=load(candidate,'options');
    old=a.options;new=b.options;
    numeric_validation_names=fieldnames(old.validation);
    numeric_validation_equal=struct();
    for k=1:numel(numeric_validation_names)
        name=numeric_validation_names{k};value=old.validation.(name);
        if isnumeric(value) || islogical(value)
            numeric_validation_equal.(name)=isfield(new.validation,name) && isequaln(value,new.validation.(name));
        end
    end
    record=struct('schema','heatdrive_ecc_runtime_boundary_recipe_comparison_v1', ...
        'reference_configuration_sha256',file_hash(reference),'candidate_configuration_sha256',file_hash(candidate), ...
        'reference_configurability',old.system.cold_boundary_temperature_configurability, ...
        'candidate_configurability',new.system.cold_boundary_temperature_configurability, ...
        'excluded_nonphysical_fields',{{'model_path','outputs_dir','report_path','output','validation'}}, ...
        'intentional_physical_group_difference','system.cold_boundary_temperature_configurability', ...
        'other_option_groups_equal',struct(),'unmatched_groups',{{}},'simulation_executed',false);
    record.numeric_validation_fields_equal=numeric_validation_equal;
    record.numeric_validation_thresholds_equal=all(structfun(@logical,numeric_validation_equal));
    old.system=rmfield(old.system,'cold_boundary_temperature_configurability');
    new.system=rmfield(new.system,'cold_boundary_temperature_configurability');
    names=fieldnames(old);
    for k=1:numel(names)
        name=names{k};if ismember(name,record.excluded_nonphysical_fields),continue;end
        same=isfield(new,name) && isequaln(old.(name),new.(name));
        record.other_option_groups_equal.(name)=same;
        if ~same,record.unmatched_groups{end+1}=name;end
    end
    record.only_declared_change=isempty(record.unmatched_groups);
    fid=fopen(output,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));fprintf('FINAL_JSON=%s\n',jsonencode(record));
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
