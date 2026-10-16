function [reference,extended,record]=Build_HeatDriveECC_CommandHorizonPayload(model,options,source_s,root)
% Use the existing generator; preserve actual past data rather than regenerating it.
    assert(~isfolder(root));mkdir(root);
    assert(options.cycle_count==200 && options.schedule.total_time_s==2000 && source_s+20<1990);
    closure=jsondecode(fileread(fullfile(fileparts(root),'se_reference_contract.json')));
    assert(strcmp(closure.schema,'heatdrive_ecc_se_coherent_reference_v1'));
    regenerated=Export_HeatDriveECC_RuntimeFamilyCommands(options);
    future_options=options;future_options.cycle_count=1000;
    future_options.schedule.total_time_s=10000;future_options.simulation.stop_time_s=10000;
    future=Export_HeatDriveECC_RuntimeFamilyCommands(future_options);
    checked=future_options;checked.cycle_count=options.cycle_count;
    checked.schedule.total_time_s=options.schedule.total_time_s;
    checked.simulation.stop_time_s=options.simulation.stop_time_s;assert(isequaln(options,checked));
    paths=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block','BlockType','FromWorkspace');
    assert(~isempty(paths));reference=struct();extended=struct();rows={};bindings={};payload=struct('reference',struct(),'extended',struct());
    workspace=get_param(model,'ModelWorkspace');
    for k=1:numel(paths)
        name=get_param(paths{k},'VariableName');assert(~isempty(regexp(name,'^[A-Za-z]\w*$','once')));
        bindings{end+1}=struct('block_path',paths{k},'variable',name,'block_interpolation',get_param(paths{k},'Interpolate')); %#ok<AGROW>
        if isfield(reference,name),continue;end
        value=slResolve(name,paths{k});assert(isa(value,'timeseries') && value.Time(end)==2000);
        local=hasVariable(workspace,name);
        if local,declared=getVariable(workspace,name);else,declared=evalin('base',name);end
        assert(isequaln(value.Time,declared.Time) && isequaln(value.Data,declared.Data),'Unexpected masked command scope.');
        if isfield(regenerated,name)
            old=regenerated.(name);assert(isequaln(value.Time,old.Time) && isequaln(value.Data,old.Data), ...
                'HeatDriveECC:CommandRecipeMismatch','Runtime recipe differs for %s at %s.',name,paths{k});
            next=future.(name);
        else
            assert(all(value.Data==value.Data(1,:),'all'),'HeatDriveECC:UnknownCommand', ...
                'Unknown nonconstant command %s at %s.',name,paths{k});
            next=timeseries([value.Data(1,:);value.Data(1,:)],[0;10000]);
            next=setinterpmethod(next,getinterpmethod(value));next.DataInfo.Units=value.DataInfo.Units;
            next.TimeInfo.Units=value.TimeInfo.Units;
        end
        [next,proof]=Extend_HeatDriveECC_CommandTimeseries(value,next,source_s,source_s+20);
        proof.variable=name;proof.model_workspace=local;
        proof.old_time_sha256=array_hash(value.Time);proof.old_values_sha256=array_hash(value.Data);
        proof.new_time_sha256=array_hash(next.Time);proof.new_values_sha256=array_hash(next.Data);
        rows{end+1}=proof;reference.(name)=value;extended.(name)=next; %#ok<AGROW>
        payload.reference.(name)=struct('time_s',value.Time,'values',value.Data);
        payload.extended.(name)=struct('time_s',next.Time,'values',next.Data);
    end
    clear regenerated future
    file=fullfile(root,'command_payload.mat');save(file,'payload','-v7.3');clear payload
    record=struct('schema','heatdrive_ecc_future_command_prefix_v1','source_snapshot_s',source_s, ...
        'comparison_stop_s',source_s+20,'old_horizon_cycles',200,'new_horizon_cycles',1000, ...
        'actual_command_blocks',numel(paths),'unique_command_variables',numel(rows),'commands',{rows}, ...
        'bindings',{bindings},'generator_source_sha256',file_hash(which('Integrate_HeatDriveECC_Constitutive21_Interface')), ...
        'runtime_export_source_sha256',file_hash(which('Export_HeatDriveECC_RuntimeFamilyCommands')), ...
        'envelope_source_sha256',file_hash(which('Build_HeatDriveECC_DistributedPressureEnvelope')), ...
        'reference_closure_source_sha256',file_hash(which('Build_HeatDriveECC_CoherentReferenceCommand')), ...
        'payload_sha256',file_hash(file),'source_state_edited',false,'resampling_used',false, ...
        'generation_option_fields_changed',{{'cycle_count','schedule.total_time_s','simulation.stop_time_s'}}, ...
        'physical_parameters_changed',false,'past_horizon_crossing_physically_executed',false);
    write_json(fullfile(root,'command_prefix.json'),record);
end

function result=array_hash(value)
    assert(isa(value,'double') && all(isfinite(value),'all'));
    digest=java.security.MessageDigest.getInstance('SHA-256');digest.update(typecast(value(:),'uint8'));
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
function write_json(file,value)
    fid=fopen(file,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
