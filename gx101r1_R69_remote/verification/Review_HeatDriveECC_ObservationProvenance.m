function proof=Review_HeatDriveECC_ObservationProvenance(source,output_root)
% Read-only re-evaluation of missing numerical metadata, never a waveform/state repair.
    assert(~isfolder(output_root),'Never overwrite provenance-review evidence.');mkdir(output_root);
    original_file=fullfile(source,'mechanism.json');manifest_file=fullfile(source,'packet_manifest.json');
    manifest=jsondecode(fileread(manifest_file));
    assert(isequal(manifest.window_s(:),[620;640]) && manifest.source_snapshot_s==620 && ...
        manifest.simulation_returned_without_error && manifest.strict_vendor_restore && ...
        manifest.history_cap_cycles==2 && manifest.state_history_cap_cycles==11 && ~manifest.source_state_edited);
    for k=1:numel(manifest.input_files)
        row=manifest.input_files(k);assert(strcmp(file_hash(fullfile(source,row.path)),row.sha256));
    end
    previous=jsondecode(fileread(original_file));names=fieldnames(previous.checks);
    failed=names(~cellfun(@(name) previous.checks.(name),names));
    assert(numel(names)==73 && isequal(failed,{'qian_numerical_time_step_contract'}), ...
        'This review cannot repair any physical failure.');
    configured=load(fullfile(source,'native','configuration.mat'),'options');
    original_view=previous.result;physical=original_view.physical;
    physical.time_s=physical.time_s(:)+manifest.window_s(1);
    saved=load(fullfile(source,'native','observations.mat'),'signals');
    expected=saved.signals.SMA_Tx21_internal;
    assert(numel(physical.time_s)==20001 && max(abs(physical.time_s-expected.time_s))<1e-9);
    % JSON is retained only as the old actual analysis view. Bound its material coordinates to the raw MAT.
    pairs={{physical.SMA_T_21_K,expected.values}, ...
        {physical.SE_T_21_K,saved.signals.SE_Tx21_internal.values}, ...
        {physical.xM_SMA_21,saved.signals.ECC_constitutive21_output.values(:,43:63)}, ...
        {physical.xM_SE_21,saved.signals.ECC_constitutive21_output.values(:,64:84)}};
    for k=1:numel(pairs)
        a=pairs{k}{1};b=pairs{k}{2};
        assert(isequal(size(a),size(b)) && all(abs(a-b)<=8*eps(max(1,abs(b))),'all'), ...
            'Serialized material values disagree with actual raw coordinates.');
    end
    provenance=original_view.provenance;
    assert(~any(isfield(provenance,{'solver','fixed_step_s','simulation_mode'})));
    provenance.solver=configured.options.simulation.solver;
    provenance.fixed_step_s=configured.options.simulation.fixed_step_s;
    provenance.simulation_mode=configured.options.simulation.mode;
    view=Make_HeatDriveECC_MechanismWindow(physical,configured.options,provenance,output_root);
    checked=Validate_HeatDriveECC_EighthRound_Physics(view);
    unchanged=setdiff(names,failed);
    assert(checked.passed && all(cellfun(@(name) checked.checks.(name)==previous.checks.(name),unchanged)));
    proof=struct('schema','heatdrive_ecc_observation_provenance_review_v1','source_packet_root',source, ...
        'mechanism_pass',checked.passed,'checks',checked.checks,'other_72_predicates_unchanged',true, ...
        'metadata_fields_added',{{'solver','fixed_step_s','simulation_mode'}},'actual_configuration',provenance, ...
        'serialized_material_max_roundoff_ULPs_allowed',8,'raw_material_MAT_unchanged',true, ...
        'simulation_executed',false,'operating_point_loaded',false,'source_state_edited',false, ...
        'reference_comparison_only',true,'production_recovery_allowed',false, ...
        'input_sha256',struct('original_manifest',file_hash(manifest_file), ...
            'original_mechanism',file_hash(original_file)));
    fid=fopen(fullfile(output_root,'mechanism_review.json'),'w','n','UTF-8');assert(fid>=0);
    fprintf(fid,'%s\n',jsonencode(proof,'PrettyPrint',true));fclose(fid);
    fprintf('FINAL_JSON=%s\n',jsonencode(struct('mechanism_pass',proof.mechanism_pass, ...
        'unchanged_predicates',numel(unchanged),'simulation_executed',false)));
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
