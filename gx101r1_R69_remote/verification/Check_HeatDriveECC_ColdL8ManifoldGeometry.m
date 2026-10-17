function [allowed,review]=Check_HeatDriveECC_ColdL8ManifoldGeometry(options)
% Construction permission only; this grants no mechanism, state or performance pass.
    allowed=false;review=struct('schema','heatdrive_ecc_cold_L8_geometry_permission_v1', ...
        'allowed',false,'physical_gates_evaluated',false,'recovery_authority_granted',false,'reason','');
    try
        assert(options.branch.independent_conservative_chamber_diagnostic && ...
            ~options.simulation.persist_model_configuration && isempty(options.simulation.resume_checkpoint_path));
        assert(isfield(options.branch,'cold_L8_geometry_contract_path') && ...
            isfile(options.branch.cold_L8_geometry_contract_path));
        path=options.branch.cold_L8_geometry_contract_path;c=jsondecode(fileread(path));
        assert(strcmp(c.schema,'heatdrive_ecc_runtime_sensitivity_cold_case_v1') && ...
            ~c.source_state_imported && ~c.production_recovery_allowed && ~c.C200_gap_attribution_authorized && ...
            ~c.original_scientific_thresholds_changed && c.fixed_Tc_K==276.95 && ...
            options.system.Tchex_K==c.fixed_Tc_K);
        index=c.design.run_index;assert(index>=1 && index<=8 && index==round(index));
        row=Build_HeatDriveECC_L8Case(index);declared=c.design;
        declared.levels=declared.levels(:).';declared.fractions=declared.fractions(:).';
        assert(isequaln(row,declared));
        assert(strcmp(file_hash(c.source_qualification_path),c.source_qualification_sha256));
        q=jsondecode(fileread(c.source_qualification_path));
        assert(strcmp(q.schema,'heatdrive_ecc_runtime_Tc_candidate_endpoint_v1') && ...
            q.all_original_packet_mechanism_flow_phase_energy_gates_pass && q.original_public_thermal_periodic_pass && ...
            q.current_target_window_stability.precision_pass && ~q.source_state_edited && ~q.production_recovery_allowed);
        cfg=fullfile(q.source_packet_root,'native','configuration.mat');
        assert(strcmp(file_hash(cfg),c.parameter_source_configuration_sha256));
        rows=q.files;chosen=strcmp({rows.path},cfg);assert(nnz(chosen)==1 && strcmp(rows(chosen).sha256,file_hash(cfg)));
        original=load(cfg,'plant_build_options');request=struct('case_index',index,'candidate_qualification_path',c.source_qualification_path);
        [~,expected]=Apply_HeatDriveECC_RuntimeSensitivity(original.plant_build_options,request);
        assert(isequaln([expected.parameters{:}],c.parameters(:).'));
        fields={c.parameters.field};assert(numel(fields)==27 && numel(unique(fields))==27);
        assert(options.validation.sensitivity_mode && ...
            isequal(sort(string(options.validation.sensitivity_declared_transition_fields(:))),sort(string(fields(:)))) && ...
            isequal(sort(string(options.simulation.checkpoint_transition_fields(:))),sort(string(fields(:)))));
        for k=1:numel(c.parameters)
            r=c.parameters(k);v=options;parts=strsplit(r.field,'.');
            for j=1:numel(parts),v=v.(parts{j});end
            assert(isequaln(v,r.after),'A declared L8 value did not reach the constructor.');
        end
        nominal=options.branch.connecting_pipe_flow_area_m2*options.branch.connecting_pipe_length_m;
        selected=c.parameters(strcmp(fields,'branch.sma_pump_manifold_volume_m3'));
        assert(isscalar(selected) && abs(selected.before-nominal)<1e-15 && ...
            ismember(row.fluid_inventory_multiplier,[.9 1.1]) && ...
            abs(options.branch.sma_pump_manifold_volume_m3-nominal*row.fluid_inventory_multiplier)<1e-15);
        allowed=true;review.allowed=true;review.case_index=index;review.checked_declared_fields=27;
        review.contract_sha256=file_hash(path);review.nominal_volume_m3=nominal;
        review.actual_volume_m3=options.branch.sma_pump_manifold_volume_m3;
        review.volume_multiplier=row.fluid_inventory_multiplier;
    catch ME
        review.reason=ME.message;
    end
end
function h=file_hash(path)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
