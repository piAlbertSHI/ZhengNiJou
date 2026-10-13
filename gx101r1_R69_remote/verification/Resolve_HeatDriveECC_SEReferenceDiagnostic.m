function options = Resolve_HeatDriveECC_SEReferenceDiagnostic(options, state_mode, cycle_count, duration, arm, endpoint_all_arms)
    assert(isstruct(options) && isscalar(options),'Require scalar SE reference diagnostic options.');
    assert(all(ismember(fieldnames(options),{'mode','cold_followup_audit_path','rebuilt_state_audit_path'})),'Unknown SE reference diagnostic option.');
    if isempty(fieldnames(options)),return;end
    assert(isscalar(string(options.mode)) && strcmp(options.mode,'coherent_envelope'), ...
        'Only the explicit coherent-envelope reference experiment is supported.');
    cold_one=strcmp(state_mode,'off') && cycle_count==1 && duration==10;
    cold_two=strcmp(state_mode,'restore_preflight') && cycle_count==2 && duration==20;
    rebuilding=strcmp(state_mode,'rebuilt_cycle_preflight') && cycle_count==2 && duration==20;
    assert((cold_one || cold_two || rebuilding) && strcmp(arm,'native') && endpoint_all_arms, ...
        'Reference changes require cold qualification or a source-bound rebuilt-cycle proof, never arbitrary state import.');
    assert(~isfield(options,'rebuilt_state_audit_path') || rebuilding, ...
        'Rebuilt authority is forbidden outside the complete-cycle state experiment.');
    if cold_two || rebuilding
        assert(isfield(options,'cold_followup_audit_path'),'Two-cycle reference experiment needs passed cold evidence.');
        audit=jsondecode(fileread(options.cold_followup_audit_path));
        assert(strcmp(audit.schema,'heatdrive_ecc_se_reference_comparison_v1') && ...
            audit.two_cycle_cold_followup_allowed && ~audit.production_recovery_allowed && ...
            audit.cold_initialization.actual_initial_coordinates_match, 'Cold reference gates did not pass.');
        manifest=jsondecode(fileread(fullfile(audit.source_root,'reference_execution.json')));
        assert(strcmp(file_hash(fullfile(manifest.candidate_root,'native','observations.mat')), ...
            audit.cases(2).input_sha256.observations_mat), 'Cold followup observations changed.');
        if rebuilding
            assert(isfield(options,'rebuilt_state_audit_path'), ...
                'The rebuilt reference case requires the passed paired C2 physics/state audit.');
            paired=jsondecode(fileread(options.rebuilt_state_audit_path));
            if strcmp(paired.schema,'heatdrive_ecc_storage_closure_state_qualification_audit_v1')
                Require_HeatDriveECC_StorageClosureCheckpoint(paired.source_root,options.rebuilt_state_audit_path);
            else
                Require_HeatDriveECC_SEReferenceCheckpoint( ...
                    fullfile(paired.source_root,'coherent'),options.rebuilt_state_audit_path);
            end
        end
    else
        assert(~isfield(options,'cold_followup_audit_path'),'Do not attach a followup authority to a single cold case.');
    end
end

function result=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
