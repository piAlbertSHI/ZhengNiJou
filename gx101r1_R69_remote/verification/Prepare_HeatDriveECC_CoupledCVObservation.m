function contract=Prepare_HeatDriveECC_CoupledCVObservation(model,options,variant,folder,inventory)
% Passive observation of all four exchanger channels and three pump sources.
    if nargin<5,inventory=[];end
    if isempty(inventory)
        contract=Build_HeatDriveECC_CoupledCVInventory(model,variant,options);
    else
        assert(strcmp(inventory.schema,'heatdrive_ecc_endpoint_CV_inventory_v1') && ...
            strcmp(variant,'shared') && strcmp(inventory.variant,variant));
        contract=inventory;
    end
    pump=Instrument_HeatDriveECC_PumpPressureProbes(model,folder);
    controller=Instrument_HeatDriveECC_Stage4ControllerProbes(model,folder);
    memory=cell(1,3);
    memory_blocks={'SMAPressurePI_Integrator','SEStage2PressurePI_Integrator','SEStage4PressurePI_Integrator'};
    memory_variables={'cv_PI_sma_state','cv_PI_se_stage2_state','stage4_integrator_state'};
    for k=1:3
        p=[model '/' memory_blocks{k}];assert(getSimulinkBlockHandle(p)>0);
        if k<3
            sink=[model '/ToWorkspace_' memory_variables{k}];
            add_block('simulink/Sinks/To Workspace',sink,'VariableName',memory_variables{k},'SaveFormat','Structure With Time');
            a=get_param(p,'PortHandles');b=get_param(sink,'PortHandles');
            add_line(model,a.Outport(1),b.Inport(1),'autorouting','on');
        end
        memory{k}=struct('block_path',p,'workspace_variable',memory_variables{k}, ...
            'initial_condition_expression',get_param(p,'InitialCondition'),'external_reset',get_param(p,'ExternalReset'), ...
            'controller_parameters_modified',false);
    end
    scratch='ecc_coupled_cv_port_map';assert(~bdIsLoaded(scratch));new_system(scratch);
    cleanup=onCleanup(@() close_system(scratch,0));probes={};
    for k=1:size(contract.hex_channels,1)
        pipe=contract.hex_channels{k,1};tag=contract.hex_channels{k,2};
        ports=Map_HeatDriveECC_PhysicalPortHandles(pipe,scratch,'foundation.thermal_liquid.thermal_liquid');
        assert(numel(ports)==2 && isequal(sort(cellfun(@(r)r.name,ports,'UniformOutput',false)),{'A','B'}));
        parent=get_param(pipe,'Parent');
        for j=1:2
            row=ports{j};stem=['CV_' tag '_' lower(row.name)];sensor=[parent '/' stem '_Sensor'];
            assert(getSimulinkBlockHandle(sensor)<0,'Never overwrite prior instrumentation.');
            add_block('fl_lib/Thermal Liquid/Sensors/Pressure & Temperature Sensor (TL)',sensor, ...
                'pressure','true','temperature','true', ...
                'reference','foundation.enum.MeasurementReference.absolute', ...
                'pressure_spec','foundation.enum.PressureMeasementSpec.Absolute');
            simscape.addConnection(pipe,row.name,sensor,'A');
            for field={'T','Pa'}
                key=field{1};unit='K';suffix='T_K';if strcmp(key,'Pa'),unit='Pa';suffix='P_Pa';end
                variable=['cv_' tag '_' lower(row.name) '_' suffix];
                converter=[parent '/' variable '_PS'];sink=[parent '/ToWorkspace_' variable];
                add_block('nesl_utility/PS-Simulink Converter',converter,'Unit',unit,'VectorFormat','1-D array');
                add_block('simulink/Sinks/To Workspace',sink,'VariableName',variable,'SaveFormat','Structure With Time');
                properties=simscape.connectionPortProperties(converter);assert(isscalar(properties));
                simscape.addConnection(sensor,key,converter,properties.Name);
                a=get_param(converter,'PortHandles');b=get_param(sink,'PortHandles');
                add_line(parent,a.Outport(1),b.Inport(1),'autorouting','on');
                probes{end+1}=struct('block_path',pipe,'port_name',row.name,'quantity',key, ...
                    'sensor_block',sensor,'sensor_output_port',key,'converter_block',converter, ...
                    'workspace_variable',variable,'unit',unit,'flow_direction_not_assumed',true); %#ok<AGROW>
            end
        end
    end
    clear cleanup
    blocks=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block','BlockType','ToWorkspace');
    variables=cellfun(@(p)get_param(p,'VariableName'),blocks,'UniformOutput',false);
    required={'ECC_constitutive21_output','ECC_Q_SMA_constitutive_W','ECC_Q_SE_constitutive_W', ...
        'SMA_Tx21_internal','SE_Tx21_internal','mass_flow_sma_stage13_kgps', ...
        'mass_flow_sma_stage1_route_kgps','mass_flow_sma_stage3_route_kgps', ...
        'mass_flow_v1_cold_inlet_kgps','mass_flow_v3_sma_to_hot_kgps', ...
        'mass_flow_v4_hot_inlet_kgps','mass_flow_v6_sma_to_chip_cold_kgps', ...
        'pressure_command_se_MPa','pressure_command_sma_MPa', ...
        'shex_source_heat_flow_W','Qdot_cold_sink_mass_to_hx_pipe_W'};
    required=[required,reshape(cellfun(@(r)r.workspace_variable,pump.probes,'UniformOutput',false),1,[]), ...
        reshape(cellfun(@(r)r.workspace_variable,probes,'UniformOutput',false),1,[]),memory_variables, ...
        reshape(cellfun(@(r)r.workspace_variable,controller.probes,'UniformOutput',false),1,[])];
    assert(isempty(setdiff(required,variables)),'Core flow, outlet or pump probes are not actually wired.');
    contract.pump_pressure_contract=pump;contract.hex_port_probes=probes;
    contract.PI_memory_probes=memory;contract.stage4_controller_contract=controller;
    contract.workspace_variables=unique(variables);contract.required_workspace_variables=unique(required);
    contract.flow_port_sign_rule='positive mdot into component; choose actual outlet by measured sign, never by A/B name';
    contract.tl_topology=Export_HeatDriveECC_TLConnectivity(model);
    contract.thermal_topology=Export_HeatDriveECC_TLConnectivity(model,'foundation.thermal.thermal');
    contract.measurement_changes_only=true;
end
