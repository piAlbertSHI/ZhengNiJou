function contract=Apply_HeatDriveECC_BufferColdFactorial(model,buffers,options)
% Change two SMA port areas and/or public solver precision, never initial inventories.
    assert(~isempty(fieldnames(options)) && numel(buffers)==4,'Require explicit independent cold factors.');
    geometry=cell(size(buffers));names={'SHEXFluidBuffer','SMAHotFluidBuffer'};
    targets={'initial_stored_mass','mass_offset','stored_energy','T_I','reference_temperature','tank_area','auxiliary_depth'};
    for k=1:numel(buffers)
        b=buffers{k};block=b.block_path;before=struct();
        for j=1:numel(targets),before.(targets{j})=get_param(block,targets{j});end
        area=value(simscape.Value(str2double(get_param(block,'port_area')),get_param(block,'port_area_unit')),'m^2');
        assert(area==.01 && b.port_area_m2==area && endsWith(get_param(block,'SourceFile'),'.conservative_buffer'), ...
            'Unexpected inherited buffer geometry.');
        changed=strcmp(options.geometry,'sma_pipe_matched') && any(endsWith(block,strcat('/',names)));
        actual=area;
        if changed
            actual=pi*.0032^2/4;set_param(block,'port_area',num2str(actual,'%.17g'),'port_area_unit','m^2');
        end
        after=struct();for j=1:numel(targets),after.(targets{j})=get_param(block,targets{j});end
        assert(isequaln(before,after),'Geometry factor changed a state target or thermal inventory.');
        geometry{k}=struct('block_path',block,'inherited_port_area_m2',area,'actual_port_area_m2',actual, ...
            'intentionally_changed',changed,'initial_and_inventory_parameters_unchanged',true, ...
            'before_inventory_parameters',before,'after_inventory_parameters',after);
    end
    solvers=find_system(model,'LookUnderMasks','all','FollowLinks','on','MaskType','Solver Configuration');
    assert(isscalar(solvers),'Expected the original shared solver configuration.');solver=solvers{1};
    fields={'UseLocalSolver','LocalSolverChoice','LocalSolverSampleTime','DoFixedCost', ...
        'ConsistencyTolSource','ConsistencyAbsTol','ConsistencyRelTol','ResidualTolerance'};
    old=struct();for j=1:numel(fields),old.(fields{j})=get_param(solver,fields{j});end
    old.global_RelTol=get_param(model,'RelTol');old.global_AbsTol=get_param(model,'AbsTol');
    assert(strcmp(old.UseLocalSolver,'on') && strcmp(old.LocalSolverChoice,'NE_BACKWARD_EULER_ADVANCER') && ...
        str2double(old.LocalSolverSampleTime)==.001 && strcmp(old.DoFixedCost,'off'), ...
        'Unexpected solver/integration recipe.');
    if strcmp(options.precision,'local_tight')
        set_param(solver,'ConsistencyTolSource','LOCAL','ConsistencyAbsTol','1e-12', ...
            'ConsistencyRelTol','1e-9','ResidualTolerance','1e-12');
        set_param(model,'RelTol','1e-9','AbsTol','1e-12');
    end
    current=struct();for j=1:numel(fields),current.(fields{j})=get_param(solver,fields{j});end
    current.global_RelTol=get_param(model,'RelTol');current.global_AbsTol=get_param(model,'AbsTol');
    contract=struct('schema','heatdrive_ecc_cold_buffer_factor_contract_v1','factor_options',options, ...
        'buffer_geometry',{geometry},'solver_block',solver,'solver_before',old,'solver_after',current, ...
        'BE_and_time_step_unchanged',true,'material_constitutive_PI_unchanged',true, ...
        'initial_inventory_targets_unchanged',true,'source_state_imported',false, ...
        'pipe_matched_area_is_hypothesis_not_paper_buffer_spec',true, ...
        'production_recovery_allowed',false,'outer_solve_eligible',false);
end
