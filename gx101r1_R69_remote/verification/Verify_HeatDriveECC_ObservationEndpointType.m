function record=Verify_HeatDriveECC_ObservationEndpointType(packet,output)
% Independently load the untouched endpoint after the split comparison has completed.
    assert(~isfile(output),'Never overwrite endpoint-type evidence.');
    manifest_path=fullfile(packet,'packet_manifest.json');manifest=jsondecode(fileread(manifest_path));
    gate=jsondecode(fileread(fullfile(packet,'packet_gate.json')));
    file=fullfile(packet,'comparison_only_complete_op.mat');hash=file_hash(file);
    assert(gate.gate_pass && gate.original_mechanism_count==73 && gate.original_mechanism_pass && ...
        gate.modeled_energy_balance.model_equation_energy_closure_pass && ...
        strcmp(gate.input_sha256.manifest,file_hash(manifest_path)) && ...
        strcmp(hash,manifest.complete_OP_sha256) && ~gate.production_recovery_allowed, ...
        'Only a complete gated split packet may be inspected.');
    saved=load(file,'diagnostic_operating_point','production_recovery_allowed');
    op=saved.diagnostic_operating_point;
    actual_class=class(op);snapshot=op.snapshotTime;
    assert(~saved.production_recovery_allowed && snapshot==manifest.window_s(2) && ...
        (isa(op,'Simulink.op.ModelOperatingPoint') || isa(op,'Simulink.SimulationOperatingPoint')));
    record=struct('schema','heatdrive_ecc_observation_endpoint_actual_type_v1', ...
        'packet_root',packet,'actual_class',actual_class,'snapshot_time_s',snapshot, ...
        'complete_vendor_OP_loaded',true,'operating_point_sha256',hash, ...
        'packet_manifest_sha256',file_hash(manifest_path),'source_state_edited',false, ...
        'simulation_executed',false,'production_recovery_allowed',false);
    assert(strcmp(file_hash(file),hash));
    fid=fopen(output,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    fprintf('FINAL_JSON=%s\n',jsonencode(record));
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
