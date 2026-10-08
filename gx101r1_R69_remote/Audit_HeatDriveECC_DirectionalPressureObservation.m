function record=Audit_HeatDriveECC_DirectionalPressureObservation(physical,options)
% Static reference head is a hypothesis; actual named source faces must satisfy it.
    c=options.validation.pressure_command_domain_contract;
    assert(strcmp(c.schema,'heatdrive_ecc_pressure_command_domain_v2') && ...
        HeatDriveECC_SEPressureLowerBoundContract(options));
    record=struct('schema','heatdrive_ecc_directional_pressure_observation_v1', ...
        'pass',false,'all_six_source_faces_observed',false, ...
        'source_face_domain_pass',false,'reference_head_budget_pass',false, ...
        'source_difference_interval_pass',false,'sources',{{}}, ...
        'entire_network_pressure_proven',false,'production_recovery_allowed',false);
    required={'pump_pressure_port_names','pump_pressure_port_A_MPa','pump_pressure_port_B_MPa'};
    if ~all(isfield(physical,required)),return;end
    a=physical.pump_pressure_port_A_MPa;b=physical.pump_pressure_port_B_MPa;
    if ~isequal(size(a),size(b)) || size(a,2)~=3 || size(a,1)<2 || ...
            ~all(isfinite(a(:))) || ~all(isfinite(b(:))),return;end
    names=c.named_reference_topology.source_names;
    ports=c.named_reference_topology.reference_ports;
    if ~isequal(ports,{'A','B','B'}) || numel(unique(physical.pump_pressure_port_names))~=3,return;end
    domain=true;head=true;interval=true;rows=cell(3,1);tolerance=1e-8;
    for k=1:3
        index=find(strcmp(physical.pump_pressure_port_names,names{k}));
        if ~isscalar(index),return;end
        reference=a(:,index);allowed=c.sma_interval_MPa;
        if strcmp(ports{k},'B'),reference=b(:,index);allowed=c.se_interval_MPa;end
        faces=[a(:,index);b(:,index)];difference=b(:,index)-a(:,index);
        face_ok=min(faces)>=c.minimum_absolute_MPa+c.declared_margin_MPa-tolerance && ...
            max(faces)<=c.maximum_absolute_MPa-c.declared_margin_MPa+tolerance;
        head_error=max(abs(reference-c.datum_MPa));
        head_ok=head_error<=c.reference_head_budget_MPa+tolerance;
        difference_ok=min(difference)>=allowed(1)-tolerance && max(difference)<=allowed(2)+tolerance;
        rows{k}=struct('source',names{k},'reference_port',ports{k}, ...
            'minimum_face_pressure_MPa',min(faces),'maximum_face_pressure_MPa',max(faces), ...
            'maximum_reference_head_MPa',head_error,'reference_head_budget_MPa',c.reference_head_budget_MPa, ...
            'minimum_B_minus_A_MPa',min(difference),'maximum_B_minus_A_MPa',max(difference), ...
            'source_face_domain_pass',face_ok,'reference_head_budget_pass',head_ok, ...
            'source_difference_interval_pass',difference_ok);
        domain=domain && face_ok;head=head && head_ok;interval=interval && difference_ok;
    end
    record.sources=rows;record.all_six_source_faces_observed=true;
    record.source_face_domain_pass=domain;record.reference_head_budget_pass=head;
    record.source_difference_interval_pass=interval;record.pass=domain && head && interval;
end
