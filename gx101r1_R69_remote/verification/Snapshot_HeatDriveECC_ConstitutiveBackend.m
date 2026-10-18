function record=Snapshot_HeatDriveECC_ConstitutiveBackend(model,options)
% Read the actual function block and the workspace consumed by its interpreter.
    path=[model '/ECC_Constitutive21_VectorStep'];actual=get_param(path,'MATLABFcn');
    requested='HeatDriveECC_ConstitutiveStateVectorStep21';
    if isfield(options.constitutive,'diagnostic_step_function') && ~isempty(options.constitutive.diagnostic_step_function)
        requested=char(options.constitutive.diagnostic_step_function);
    end
    base=evalin('base','EIGHTH_ROUND_OPTIONS');
    same=base.node_count==options.node_count && isequaln(base.material,options.material) && ...
        isequaln(base.geometry,options.geometry) && isequaln(base.constitutive,options.constitutive) && ...
        isequaln(base.schedule.stage_end_s,options.schedule.stage_end_s) && ...
        base.schedule.tau_cycle_s==options.schedule.tau_cycle_s;
    type=get_param(path,'BlockType');paths=find_system(model,'LookUnderMasks','all','FollowLinks','on','BlockType',type);
    blocks=cell(numel(paths),1);
    for k=1:numel(paths),blocks{k}=struct('path',paths{k},'function',get_param(paths{k},'MATLABFcn'));end
    source=which(actual);
    record=struct('schema','heatdrive_ecc_constitutive_backend_snapshot_v1','block_path',path, ...
        'requested_function',requested,'actual_function',actual,'actual_source_path',source, ...
        'actual_source_sha256',file_hash(source),'function_matches_request',strcmp(actual,requested), ...
        'base_kernel_parameters_match',same,'node_count',base.node_count, ...
        'sample_time_s',base.constitutive.simulink_sample_time_s,'substeps',base.constitutive.diagnostic_substeps, ...
        'interpreted_function_blocks',{blocks},'simulation_settings_changed',false,'source_state_edited',false);
    if strcmp(requested,'HeatDriveECC_ConstitutiveStateVectorStep21_KernelCandidate')
        assert(record.function_matches_request && same,'HeatDriveECC:CandidateBackendBinding', ...
            'Actual interpreted function or base kernel parameters differ from the declared candidate.');
    end
end
function h=file_hash(path)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
