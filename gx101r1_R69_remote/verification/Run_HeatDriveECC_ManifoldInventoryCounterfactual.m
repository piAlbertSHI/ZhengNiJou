function study = Run_HeatDriveECC_ManifoldInventoryCounterfactual(config_path, output_root)
% Paired independent cold experiments; no OP/history imports or gate relaxation.
    config_path=char(java.io.File(config_path).getCanonicalPath());
    output_root=char(java.io.File(output_root).getCanonicalPath());
    assert(~isfolder(output_root),'Never overwrite a counterfactual study.');
    base=jsondecode(fileread(config_path));
    compiled_path=fullfile(output_root,'volume_0p1','cache','slprj','_sfprj', ...
        'heatdrive_ecc_coupled_se21','_self','sfun','src','c1_heatdrive_ecc_coupled_se21.c');
    assert(strlength(string(compiled_path))<260, ...
        'Use a shorter counterfactual output root before starting the Windows Stateflow compiler.');
    assert(strcmp(base.diagnostic_constitutive_step_function, ...
        'HeatDriveECC_ConstitutiveStateVectorStep21_StableDiagnostic') && ...
        base.diagnostic_constitutive_substeps==32 && base.endpoint_all_arms && ...
        base.initial_flux_compensation && base.distributed_pressure_feedforward_diagnostic, ...
        'Require the current stability-qualified physical configuration.');
    base=rmfield(base,intersect(fieldnames(base),{'stable_constitutive_parent'}));
    base.duration_s=10;base.cycle_count=1;base.diagnostic_arm='native';
    base.diagnostic_state_options=struct('mode','off','command_horizon_cycles',1);
    mkdir(output_root);
    study=struct('schema','heatdrive_ecc_manifold_inventory_counterfactual_v1', ...
        'status','running','parent_configuration_path',config_path, ...
        'parent_configuration_sha256',file_hash(config_path), ...
        'state_imported',false,'c200_state_imported',false, ...
        'production_recovery_allowed',false,'outer_solve_eligible',false, ...
        'hypothesis','Shared switched finite chamber thermal mass displacement scales with its volume.', ...
        'changed_physical_field','branch.sma_pump_manifold_volume_m3', ...
        'cold_initialization_source',base.initial_observation_root,'cases',{{}});
    names={'baseline','volume_0p1'};factors=[1 0.1];
    try
        for k=1:2
            config=base;config.output_root=fullfile(output_root,names{k});
            config.diagnostic_inventory_options=struct('volume_factor',factors(k));
            path=fullfile(output_root,[names{k},'_config.json']);
            write_json(path,config);
            result=Run_HeatDriveECC_IndependentColdDiagnosticFromConfig(path);
            item=struct('name',names{k},'volume_factor',factors(k),'config_sha256',file_hash(path), ...
                'requested_arm_collection_pass',result.requested_arm_collection_pass, ...
                'error_message',result.error_message,'execution_sha256', ...
                file_hash(fullfile(config.output_root,'cold_chamber_execution.json')));
            study.cases{end+1}=item;
            write_json(fullfile(output_root,'counterfactual_execution.json'),study);
            assert(result.requested_arm_collection_pass && isempty(result.error_message), ...
                'Stop and diagnose a failed collection; never reuse it as a continuation seed.');
        end
        study.status='collected_requires_physical_comparison';
    catch exception
        study.status='failed_requires_diagnosis';study.error_message=getReport(exception,'extended','hyperlinks','off');
        write_json(fullfile(output_root,'counterfactual_execution.json'),study);
        rethrow(exception);
    end
    write_json(fullfile(output_root,'counterfactual_execution.json'),study);
    fprintf('%s\n',jsonencode(study));
end

function write_json(path,value)
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
