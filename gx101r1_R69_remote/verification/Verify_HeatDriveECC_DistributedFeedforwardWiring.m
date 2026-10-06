function result = Verify_HeatDriveECC_DistributedFeedforwardWiring(repo, source_root)
% Compile-free wiring test; not a physical experiment or a usable cold seed.
    original=pwd; restore=onCleanup(@() cd(original));
    cd(repo);
    addpath(genpath(source_root));
    frozen=load(fullfile(source_root,'native','configuration.mat'),'options');
    overrides=frozen.options;
    overrides.model_path=fullfile(repo,[overrides.model_name '.slx']);
    overrides.simulation.persist_model_configuration=false;
    overrides.simulation.resume_checkpoint_path='';
    overrides.branch.se_distributed_pressure_feedforward_diagnostic=true;
    [model,options]=Build_HeatDriveECC_EighthRound_Simulink_Model(overrides);
    cleanup=onCleanup(@() close_system(model,0));
    contract=Configure_HeatDriveECC_DistributedPressureFeedforward(model,options);
    ports=get_param([model '/PressurePI_BiasSum'],'PortHandles');
    line=get_param(ports.Inport(3),'Line');
    source=get_param(get_param(line,'SrcPortHandle'),'Parent');
    assert(strcmp(source,[model '/SEPressureDynamicFeedforward']) && ...
        strcmp(get_param(source,'BlockType'),'Gain') && ...
        strcmp(get_param(source,'Gain'),'-1'), ...
        'HeatDriveECC:DistributedFFOutput','Wrong pressure-command authority.');
    names={'distributed_fluid_temperature21_K', ...
        'distributed_delayed_temperature21_K', ...
        'distributed_kinematic_viscosity21_m2_s', ...
        'distributed_bed_resistance_MPa_per_kgps', ...
        'distributed_target_flow_kg_s','distributed_pressure_feedforward_MPa'};
    for idx=1:numel(names)
        assert(getSimulinkBlockHandle([model '/ToWorkspace_' names{idx}])>0, ...
            'HeatDriveECC:DistributedFFObservation','Missing observation.');
    end
    result=struct('wiring_pass',true,'source_count',numel(contract.sources), ...
        'signal_count',numel(names),'simulation_run',false, ...
        'compile_verified',false,'production_recovery_allowed',false);
    fprintf('%s\n',jsonencode(result));
end
