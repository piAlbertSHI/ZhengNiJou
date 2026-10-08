function record=Evaluate_HeatDriveECC_ColdMechanism(output,options,model,folder,producer)
% Original production predicates on actual cold samples, before costly native export.
    assert(isempty(output.ErrorMessage) && ...
        options.branch.pressure_command_domain_closure_enabled);
    physical=Extract_HeatDriveECC_PhysicalLogs(output,options,model,false);
    physical.authority='physical_simscape_to_workspace_logs';
    physical.legacy_surrogate_used_for_results=false;
    physical.sim_call_count=1;physical.walltime_s=NaN;
    provenance=struct('checkpoint_restart_used',false,'checkpoint_chain_verified',false, ...
        'sim_call_count',1,'solver',options.simulation.solver, ...
        'fixed_step_s',options.simulation.fixed_step_s,'simulation_mode',options.simulation.mode, ...
        'execution_commit',producer,'production_recovery_allowed',false);
    result=Make_HeatDriveECC_MechanismWindow(physical,options,provenance,folder);
    audit=Validate_HeatDriveECC_EighthRound_Physics(result);
    names=fieldnames(audit.checks);failed=names(~cellfun(@(n) logical(audit.checks.(n)),names));
    file=fullfile(folder,'cold_mechanism_observation.mat');
    assert(~isfile(file),'Never overwrite actual mechanism evidence.');
    save(file,'physical','options','provenance','-v7.3');
    record=struct('schema','heatdrive_ecc_bounded_cold_production_mechanism_v1', ...
        'execution_commit',producer,'analysis_window',result.analysis_window, ...
        'original_production_predicates_evaluated',true,'checks',audit.checks, ...
        'diagnostics',audit.diagnostics,'failed_checks',{failed},'mechanism_pass',audit.passed, ...
        'pressure_domain',options.validation.pressure_command_domain_contract, ...
        'observation_file',file,'observation_sha256',file_hash(file), ...
        'full_native_inventory_ledger_evaluated',false,'source_port_ledger_evaluated',false, ...
        'periodic_steady_state_verified',false,'strict_table4_reproduction_pass',false, ...
        'production_recovery_allowed',false,'diagnostic_continuation_allowed',false);
    if strcmp(options.validation.pressure_command_domain_contract.schema,'heatdrive_ecc_pressure_command_domain_v2')
        record.directional_pressure_observation=Audit_HeatDriveECC_DirectionalPressureObservation(physical,options);
    end
    fid=fopen(fullfile(folder,'cold_mechanism_audit.json'),'w','n','UTF-8');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
end

function hash=file_hash(file)
    fid=fopen(file,'rb');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    digest=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
