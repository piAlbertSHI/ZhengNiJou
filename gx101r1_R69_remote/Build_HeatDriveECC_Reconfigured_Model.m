function model_path = Build_HeatDriveECC_Reconfigured_Model(force_rebuild)
% Copy the mature solver101 model and assemble isolated SMA/SE fluid loops.

    if nargin < 1
        force_rebuild = false;
    end

    root_dir = fileparts(mfilename('fullpath'));
    source_name = 'nixunhuan_solver101_internal';
    source_path = fullfile(root_dir, [source_name '.slx']);
    model_name = 'heatdrive_ecc_reconfigured_from_solver101';
    model_path = fullfile(root_dir, [model_name '.slx']);

    if exist(model_path, 'file') && ~force_rebuild
        return;
    end
    if ~exist(source_path, 'file')
        error('Build_HeatDriveECC_Reconfigured_Model:MissingSource', ...
            'Mature source model not found: %s', source_path);
    end

    source_hash_before = file_hash(source_path);
    close_if_loaded(model_name);
    copyfile(source_path, model_path, 'f');

    load_system(source_path);
    load_system(model_path);
    set_param(model_name, 'Description', sprintf([ ...
        'Fifth-round heat-driven ECC assembly. Byte-copied from %s; ', ...
        'mature fluid components are reused and assigned to isolated SMA/SE loops.'], ...
        source_name));

    rename_block_if_present([model_name '/SMA'], 'SE_Refrigerant_1D51');
    rename_block_if_present([model_name '/Tank (TL)'], 'ColdFluidBuffer');
    adapt_mature_object_to_axial51([model_name '/SE_Refrigerant_1D51'], 'se');
    add_axial_heat_interface([model_name '/SE_Refrigerant_1D51'], 'se');
    configure_axial_thermal_gate_schedule([model_name '/SE_Refrigerant_1D51'], 'se');
    prefix_workspace_sinks(model_name, 'se_loop_');
    set_from_workspace_variable([model_name '/ValveCommandFromWorkspace'], ...
        'L_valve_command_se');

    sma_loop_path = [model_name '/SMA_Actuator_MatureLoop'];
    delete_block_if_present(sma_loop_path);
    add_block('simulink/Ports & Subsystems/Subsystem', sma_loop_path, ...
        'Position', [1780 80 2060 330], ...
        'BackgroundColor', 'cyan');
    Simulink.SubSystem.deleteContents(sma_loop_path);
    Simulink.BlockDiagram.copyContentsToSubsystem(source_name, sma_loop_path);
    rename_block_if_present([sma_loop_path '/SMA'], 'SMA_Actuator_1D51');
    rename_block_if_present([sma_loop_path '/Tank (TL)'], 'ColdFluidBuffer');
    prefix_initial_temperature_variables(sma_loop_path, 'sma_');
    adapt_mature_object_to_axial51([sma_loop_path '/SMA_Actuator_1D51'], 'sma');
    add_axial_heat_interface([sma_loop_path '/SMA_Actuator_1D51'], 'sma');
    configure_axial_thermal_gate_schedule([sma_loop_path '/SMA_Actuator_1D51'], 'sma');
    expose_object_interface_through_loop(sma_loop_path, ...
        [sma_loop_path '/SMA_Actuator_1D51']);
    prefix_workspace_sinks(sma_loop_path, 'sma_loop_');
    set_from_workspace_variable([sma_loop_path '/ValveCommandFromWorkspace'], ...
        'L_valve_command_sma');

    add_role_subsystem(model_name, 'ValveAndRouteController', [1780 510 1990 600], ...
        'Drives independent mature V1-V6 and Pressure PI target enables.');
    add_role_subsystem(model_name, 'DynamicEnergyAudit', [1780 750 1990 840], ...
        'Stage/cycle solid, fluid, HX, mechanical, and system energy audit.');
    add_role_subsystem(model_name, 'ProbeSemanticLogger', [1780 870 1990 960], ...
        'Physical probe aliases and semantic table source paths.');

    add_annotation(model_name, [1780 1000 2290 1110], sprintf([ ...
        'Fifth-round assembly origin: %s\\n', ...
        'Root mature network role: SE loop (HHEX_SE / CHEX-RHE).\\n', ...
        'Nested mature network role: SMA actuator loop (SHEX / HHEX_SMA).\\n', ...
        'Fluid networks are independent; only mechanical coupling crosses loops.'], ...
        source_name));

    configure_stage_scheduler(model_name);
    configure_pi_target_sources(model_name, 'se');
    configure_pi_target_sources(sma_loop_path, 'sma');
    configure_mechanical_coupling(model_name, sma_loop_path, ...
        [model_name '/SE_Refrigerant_1D51']);

    save_system(model_name, model_path);
    close_system(model_name, 0);
    close_system(source_name, 0);

    source_hash_after = file_hash(source_path);
    if ~strcmp(source_hash_before, source_hash_after)
        error('Build_HeatDriveECC_Reconfigured_Model:SourceModified', ...
            'The mature source model changed while assembling the target model.');
    end
end

function prefix_initial_temperature_variables(system_path, prefix)
    names = {
        'ambient_T_init'
        'hot_sink_T_init'
        'cold_sink_T_init'
        'cold_load_T_init'
        'chip_T_init'
        'hot_fluid_buffer_T_init'
        'cold_fluid_buffer_T_init'
        'hot_side_fluid_T_init'
        'cold_hx_pipe_T_init'
        'cold_return_pipe_T_init'
        'transit_pipe_T_init'
        'cold_load_heat_W'
        'chip_heat_W'};
    blocks = find_system(system_path, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'Type', 'Block');
    for block_idx = 1:numel(blocks)
        params = get_param(blocks{block_idx}, 'DialogParameters');
        if ~isstruct(params)
            continue;
        end
        param_names = fieldnames(params);
        for param_idx = 1:numel(param_names)
            param_name = param_names{param_idx};
            try
                value = get_param(blocks{block_idx}, param_name);
                if ~(ischar(value) || isstring(value))
                    continue;
                end
                updated = char(value);
                for name_idx = 1:numel(names)
                    updated = regexprep(updated, ...
                        ['(?<![A-Za-z0-9_])' names{name_idx} '(?![A-Za-z0-9_])'], ...
                        [prefix names{name_idx}]);
                end
                if ~strcmp(updated, char(value))
                    set_param(blocks{block_idx}, param_name, updated);
                end
            catch
                % Some library-derived dialog fields are read-only.
            end
        end
    end
end

function add_axial_heat_interface(object_path, role)
    solid_path = [object_path '/Subsystem2'];
    node_count = 51;
    delete_block_if_present([solid_path '/Q_phase_mech_W_51_in']);
    delete_block_if_present([solid_path '/QPhaseDemux51']);
    delete_block_if_present([solid_path '/T_nodes_51_out']);
    add_block('simulink/Sources/In1', [solid_path '/Q_phase_mech_W_51_in'], ...
        'Position', [680 35 710 55]);
    add_block('simulink/Signal Routing/Demux', [solid_path '/QPhaseDemux51'], ...
        'Outputs', num2str(node_count), 'Position', [740 20 745 20 + 16 * node_count]);
    add_block('simulink/Sinks/Out1', [solid_path '/T_nodes_51_out'], ...
        'Position', [1120 255 1150 275]);
    add_line(solid_path, 'Q_phase_mech_W_51_in/1', 'QPhaseDemux51/1', ...
        'autorouting', 'on');
    add_line(solid_path, 'TempMux51/1', 'T_nodes_51_out/1', 'autorouting', 'on');

    ref_port = get_port([solid_path '/ThermalReference51'], 'LConn', 1);
    demux_ports = get_param([solid_path '/QPhaseDemux51'], 'PortHandles');
    for idx = 1:node_count
        converter_path = [solid_path sprintf('/QPhasePS_%02d', idx)];
        source_path = [solid_path sprintf('/QPhaseSource_%02d', idx)];
        add_block('nesl_utility/Simulink-PS Converter', converter_path, ...
            'Unit', 'W', 'Position', [780 60 + 32 * idx 810 80 + 32 * idx]);
        add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source', ...
            source_path, 'Position', [850 50 + 32 * idx 900 90 + 32 * idx]);
        converter_ports = get_param(converter_path, 'PortHandles');
        source_ports = get_param(source_path, 'PortHandles');
        add_line(solid_path, demux_ports.Outport(idx), converter_ports.Inport(1), ...
            'autorouting', 'on');
        add_line(solid_path, converter_ports.RConn(1), source_ports.RConn(1), ...
            'autorouting', 'on');
        add_line(solid_path, source_ports.LConn(1), ref_port, 'autorouting', 'on');
        add_line(solid_path, source_ports.RConn(2), ...
            get_port([solid_path sprintf('/NodeMass_%02d', idx)], 'LConn', 1), ...
            'autorouting', 'on');
    end

    delete_block_if_present([object_path '/Q_phase_mech_W_51_in']);
    delete_block_if_present([object_path '/T_nodes_51_out']);
    add_block('simulink/Sources/In1', [object_path '/Q_phase_mech_W_51_in'], ...
        'Position', [30 40 60 60]);
    add_block('simulink/Sinks/Out1', [object_path '/T_nodes_51_out'], ...
        'Position', [760 40 790 60]);
    add_line(object_path, 'Q_phase_mech_W_51_in/1', 'Subsystem2/1', ...
        'autorouting', 'on');
    add_line(object_path, 'Subsystem2/1', 'T_nodes_51_out/1', ...
        'autorouting', 'on');

    set_param(object_path, 'Description', sprintf([ ...
        '%s axial 51-node solid. Mature hold/cooldown Pipe and thermal-gate ', ...
        'implementation retained; top-level phase/mechanical heat enters in W.'], upper(role)));
end

function configure_axial_thermal_gate_schedule(object_path, role)
    node_count = 51;
    hold_source_path = [object_path '/HoldGateGFromWorkspace'];
    cooldown_source_path = [object_path '/CooldownGateGFromWorkspace'];
    hold_converter_path = [object_path '/HoldGateG_PS'];
    cooldown_converter_path = [object_path '/CooldownGateG_PS'];
    delete_block_if_present(hold_source_path);
    delete_block_if_present(cooldown_source_path);
    delete_block_if_present(hold_converter_path);
    delete_block_if_present(cooldown_converter_path);
    add_block('simulink/Sources/From Workspace', hold_source_path, ...
        'VariableName', [role '_hold_gate_G_ts'], ...
        'Interpolate', 'on', ...
        'OutputAfterFinalValue', 'Holding final value', ...
        'Position', [30 95 155 125]);
    add_block('simulink/Sources/From Workspace', cooldown_source_path, ...
        'VariableName', [role '_cool_gate_G_ts'], ...
        'Interpolate', 'on', ...
        'OutputAfterFinalValue', 'Holding final value', ...
        'Position', [30 140 155 170]);
    add_block('nesl_utility/Simulink-PS Converter', hold_converter_path, ...
        'Unit', 'W/(K*m)', 'Position', [185 92 215 128]);
    add_block('nesl_utility/Simulink-PS Converter', cooldown_converter_path, ...
        'Unit', 'W/(K*m)', 'Position', [185 137 215 173]);
    add_line(object_path, 'HoldGateGFromWorkspace/1', 'HoldGateG_PS/1', ...
        'autorouting', 'on');
    add_line(object_path, 'CooldownGateGFromWorkspace/1', 'CooldownGateG_PS/1', ...
        'autorouting', 'on');
    hold_converter_ports = get_param(hold_converter_path, 'PortHandles');
    cooldown_converter_ports = get_param(cooldown_converter_path, 'PortHandles');
    for idx = 1:node_count
        hold_gate = [object_path sprintf('/HoldThermalGate_%03d', idx)];
        cooldown_gate = [object_path sprintf('/CooldownThermalGate_%03d', idx)];
        set_gate_to_variable_conductance(hold_gate);
        set_gate_to_variable_conductance(cooldown_gate);
        connect_if_unconnected(object_path, hold_converter_ports.RConn(1), ...
            get_gate_control_port(hold_gate));
        connect_if_unconnected(object_path, cooldown_converter_ports.RConn(1), ...
            get_gate_control_port(cooldown_gate));
    end
    set_param(object_path, 'Description', sprintf([ ...
        '%s axial 51-node solid. Mature hold/cooldown Pipe and thermal-gate ', ...
        'implementation retained; gate conductance follows four-stage route schedule.'], ...
        upper(role)));
end

function set_gate_to_variable_conductance(gate_path)
    set_param(gate_path, 'thermal_type', ...
        'foundation.enum.ConstantVariableTabulated.Variable');
end

function port = get_gate_control_port(gate_path)
    ports = get_param(gate_path, 'PortHandles');
    if numel(ports.LConn) < 2
        error('Build_HeatDriveECC_Reconfigured_Model:MissingGateControlPort', ...
            'Variable thermal gate has no physical-signal control port: %s', gate_path);
    end
    port = ports.LConn(2);
end

function expose_object_interface_through_loop(loop_path, object_path)
    add_block('simulink/Sources/In1', [loop_path '/Q_phase_mech_W_51_in'], ...
        'Position', [20 20 50 40]);
    add_block('simulink/Sinks/Out1', [loop_path '/T_nodes_51_out'], ...
        'Position', [2100 20 2130 40]);
    object_name = get_param(object_path, 'Name');
    add_line(loop_path, 'Q_phase_mech_W_51_in/1', [object_name '/1'], ...
        'autorouting', 'on');
    add_line(loop_path, [object_name '/1'], 'T_nodes_51_out/1', ...
        'autorouting', 'on');
end

function configure_stage_scheduler(model_name)
    path_value = [model_name '/StageScheduler'];
    delete_block_if_present(path_value);
    add_block('simulink/Ports & Subsystems/Subsystem', path_value, ...
        'Position', [1780 390 1990 480], 'BackgroundColor', 'green');
    Simulink.SubSystem.deleteContents(path_value);
    add_block('simulink/Sources/From Workspace', [path_value '/StageIdFromWorkspace'], ...
        'VariableName', 'fifth_stage_id_ts', 'Interpolate', 'off', ...
        'OutputAfterFinalValue', 'Holding final value', ...
        'Position', [30 30 140 60]);
    add_block('simulink/Sinks/Out1', [path_value '/stage_id'], ...
        'Position', [230 30 260 50]);
    add_block('simulink/Sinks/To Workspace', [path_value '/StageIdLog'], ...
        'VariableName', 'fifth_stage_id_log', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [160 80 260 110]);
    add_line(path_value, 'StageIdFromWorkspace/1', 'stage_id/1', 'autorouting', 'on');
    add_line(path_value, 'StageIdFromWorkspace/1', 'StageIdLog/1', 'autorouting', 'on');
end

function configure_pi_target_sources(system_path, role)
    replace_constant_with_workspace([system_path '/PressurePI_TargetHold'], ...
        [role '_mdot_hold_target_ts']);
    replace_constant_with_workspace([system_path '/PressurePI_TargetCooldown'], ...
        [role '_mdot_cooldown_target_ts']);
end

function replace_constant_with_workspace(block_path, variable_name)
    if getSimulinkBlockHandle(block_path) <= 0
        return;
    end
    parent_path = get_param(block_path, 'Parent');
    position = get_param(block_path, 'Position');
    ports = get_param(block_path, 'PortHandles');
    line_handle = get_param(ports.Outport(1), 'Line');
    destinations = [];
    if line_handle ~= -1
        destinations = get_param(line_handle, 'DstPortHandle');
        delete_line(line_handle);
    end
    delete_block(block_path);
    add_block('simulink/Sources/From Workspace', block_path, ...
        'VariableName', variable_name, 'Interpolate', 'on', ...
        'OutputAfterFinalValue', 'Holding final value', 'Position', position);
    new_ports = get_param(block_path, 'PortHandles');
    for idx = 1:numel(destinations)
        add_line(parent_path, new_ports.Outport(1), destinations(idx), ...
            'autorouting', 'on');
    end
end

function configure_mechanical_coupling(model_name, sma_loop_path, se_object_path)
    block_path = [model_name '/MechanicalCouplingSolver'];
    delete_block_if_present(block_path);
    add_block('simulink/Ports & Subsystems/Subsystem', block_path, ...
        'Position', [2120 480 2390 720], 'BackgroundColor', 'yellow');
    Simulink.SubSystem.deleteContents(block_path);
    add_block('simulink/Sources/In1', [block_path '/Ta_51'], ...
        'Position', [25 35 55 55]);
    add_block('simulink/Sources/In1', [block_path '/Tr_51'], ...
        'Position', [25 80 55 100]);
    add_block('simulink/Sources/In1', [block_path '/stage_id'], ...
        'Position', [25 125 55 145]);
    add_block('simulink/Sources/In1', [block_path '/time_s'], ...
        'Position', [25 170 55 190]);
    add_block('simulink/Signal Routing/Mux', [block_path '/MechanicalInputMux'], ...
        'Inputs', '4', 'Position', [95 30 100 195]);
    add_block('simulink/User-Defined Functions/Interpreted MATLAB Function', ...
        [block_path '/CouplingConstitutiveKernel'], ...
        'MATLABFcn', 'HeatDriveECC_FifthRound_MechanicalStep', ...
        'OutputDimensions', '114', ...
        'SampleTime', '0.001', ...
        'Position', [145 70 320 155]);
    add_block('simulink/Signal Routing/Demux', [block_path '/MechanicalOutputDemux'], ...
        'Outputs', '[51 51 12]', 'Position', [360 45 365 180]);
    add_block('simulink/Sinks/Out1', [block_path '/qA_W_51'], ...
        'Position', [420 55 450 75]);
    add_block('simulink/Sinks/Out1', [block_path '/qR_W_51'], ...
        'Position', [420 100 450 120]);
    add_block('simulink/Sinks/Out1', [block_path '/audit'], ...
        'Position', [420 150 450 170]);
    input_names = {'Ta_51','Tr_51','stage_id','time_s'};
    for idx = 1:4
        add_line(block_path, sprintf('%s/1', input_names{idx}), ...
            sprintf('MechanicalInputMux/%d', idx), 'autorouting', 'on');
    end
    add_line(block_path, 'MechanicalInputMux/1', 'CouplingConstitutiveKernel/1', ...
        'autorouting', 'on');
    add_line(block_path, 'CouplingConstitutiveKernel/1', 'MechanicalOutputDemux/1', ...
        'autorouting', 'on');
    add_line(block_path, 'MechanicalOutputDemux/1', 'qA_W_51/1', 'autorouting', 'on');
    add_line(block_path, 'MechanicalOutputDemux/2', 'qR_W_51/1', 'autorouting', 'on');
    add_line(block_path, 'MechanicalOutputDemux/3', 'audit/1', 'autorouting', 'on');

    add_block('simulink/Sources/Clock', [model_name '/FifthRoundTime'], ...
        'Position', [2020 665 2050 695]);
    add_block('simulink/Discrete/Memory', [model_name '/SMA_TemperatureMemory'], ...
        'X0', 'sma_actuator_T_init_51', ...
        'Position', [2020 500 2070 530]);
    add_block('simulink/Discrete/Memory', [model_name '/SE_TemperatureMemory'], ...
        'X0', 'se_refrigerant_T_init_51', ...
        'Position', [2020 550 2070 580]);
    add_block('simulink/Sinks/To Workspace', [model_name '/MechanicalAuditLog'], ...
        'VariableName', 'fifth_mechanical_audit', ...
        'SaveFormat', 'Structure With Time', ...
        'Position', [2470 650 2600 690]);

    sma_ports = get_param(sma_loop_path, 'PortHandles');
    se_ports = get_param(se_object_path, 'PortHandles');
    mech_ports = get_param(block_path, 'PortHandles');
    stage_ports = get_param([model_name '/StageScheduler'], 'PortHandles');
    time_ports = get_param([model_name '/FifthRoundTime'], 'PortHandles');
    audit_ports = get_param([model_name '/MechanicalAuditLog'], 'PortHandles');
    sma_memory_ports = get_param([model_name '/SMA_TemperatureMemory'], 'PortHandles');
    se_memory_ports = get_param([model_name '/SE_TemperatureMemory'], 'PortHandles');

    add_line(model_name, sma_ports.Outport(1), sma_memory_ports.Inport(1), 'autorouting', 'on');
    add_line(model_name, sma_memory_ports.Outport(1), mech_ports.Inport(1), 'autorouting', 'on');
    add_line(model_name, se_ports.Outport(1), se_memory_ports.Inport(1), 'autorouting', 'on');
    add_line(model_name, se_memory_ports.Outport(1), mech_ports.Inport(2), 'autorouting', 'on');
    add_line(model_name, stage_ports.Outport(1), mech_ports.Inport(3), 'autorouting', 'on');
    add_line(model_name, time_ports.Outport(1), mech_ports.Inport(4), 'autorouting', 'on');
    add_line(model_name, mech_ports.Outport(1), sma_ports.Inport(1), 'autorouting', 'on');
    add_line(model_name, mech_ports.Outport(2), se_ports.Inport(1), 'autorouting', 'on');
    add_line(model_name, mech_ports.Outport(3), audit_ports.Inport(1), 'autorouting', 'on');
end

function script = mechanical_kernel_script()
    script = sprintf([ ...
        'function [qA_W_51,qR_W_51,audit] = fcn(Ta_51,Tr_51,stage_id,t)\n' ...
        '%%#codegen\n' ...
        'persistent xA xR last_t\n' ...
        'if isempty(last_t) || t < last_t\n' ...
        '  xA=ones(1,51); xR=zeros(1,51); last_t=t;\n' ...
        'end\n' ...
        'dt=max(t-last_t,0); Ta=mean(Ta_51); Tr=mean(Tr_51);\n' ...
        'Sa=1e-6; Sr=0.2e-6; La=1; Lr=0.4; E=30e9; epsT=0.03;\n' ...
        'ma=6500*Sa*La; mr=6500*Sr*Lr; dh=1e4; tau=0.08;\n' ...
        'xa=mean(xA); xr=mean(xR);\n' ...
        'den=(Sr/Sa)*La/E+Lr/E;\n' ...
        'sigR=(epsT*(1-xa)*La-epsT*xr*Lr)/den; sigA=(Sr/Sa)*sigR;\n' ...
        'eqA=xa; eqR=xr;\n' ...
        'if stage_id < 1.5\n' ...
        '  eqA=min(max((343+sigA/7.6e6-Ta)/20,0),1);\n' ...
        '  eqR=min(max((sigR-7.3e6*(Tr-258))/(7.3e6*20),0),1);\n' ...
        'elseif stage_id >= 2.5 && stage_id < 3.5\n' ...
        '  eqA=min(max((313+sigA/7.3e6-Ta)/20,0),1);\n' ...
        '  eqR=min(max((sigR-7.6e6*(Tr-268))/(7.6e6*20),0),1);\n' ...
        'end\n' ...
        'dxA=zeros(1,51); dxR=zeros(1,51);\n' ...
        'if dt>0 && (stage_id<1.5 || (stage_id>=2.5 && stage_id<3.5))\n' ...
        '  dxA=(eqA-xA)/tau; dxR=(eqR-xR)/tau;\n' ...
        '  dxA=min(max(dxA,-20),20); dxR=min(max(dxR,-20),20);\n' ...
        '  xA=min(max(xA+dt*dxA,0),1); xR=min(max(xR+dt*dxR,0),1);\n' ...
        'end\n' ...
        'qA_W_51=(ma/51)*dh*dxA; qR_W_51=(mr/51)*dh*dxR;\n' ...
        'epsA=epsT*(1-mean(xA))-sigA/E; epsR=epsT*mean(xR)+sigR/E;\n' ...
        'eq6=(sigA*Sa-sigR*Sr)/max(abs(sigR*Sr),1);\n' ...
        'eq7=(epsA*La-epsR*Lr)/max(abs(epsR*Lr),1e-12);\n' ...
        'audit=zeros(1,12); audit(1)=sigA; audit(2)=sigR; audit(3)=epsA; audit(4)=epsR;\n' ...
        'audit(5)=mean(xA); audit(6)=mean(xR); audit(7)=eq6; audit(8)=eq7;\n' ...
        'audit(9)=sum(qA_W_51); audit(10)=sum(qR_W_51);\n' ...
        'audit(11)=sigA*Sa*La*epsT*mean(dxA); audit(12)=sigR*Sr*Lr*epsT*mean(dxR);\n' ...
        'last_t=t;\n' ...
        'end\n']);
end

function adapt_mature_object_to_axial51(object_path, role)
% Keep mature nodewise exchange blocks 1..51 and remove the legacy mirror half.

    node_count = 51;
    solid_path = [object_path '/Subsystem2'];

    for idx = node_count + 1:101
        delete_block_if_present([object_path sprintf('/HoldPipe_%03d', idx)]);
        delete_block_if_present([object_path sprintf('/HoldThermalGate_%03d', idx)]);
        delete_block_if_present([object_path sprintf('/CooldownPipe_%03d', idx)]);
        delete_block_if_present([object_path sprintf('/CooldownThermalGate_%03d', idx)]);
        delete_block_if_present([solid_path sprintf('/NodeMass_%02d', idx)]);
        delete_block_if_present([solid_path sprintf('/NodeTempSensor_%02d', idx)]);
        delete_block_if_present([solid_path sprintf('/NodeTempPS_%02d', idx)]);
    end
    for idx = node_count:100
        delete_block_if_present([solid_path sprintf('/NodeCond_%02d_%02d', idx, idx + 1)]);
    end

    reconnect_trimmed_fluid_port(object_path, ...
        get_port([object_path '/Conn1'], 'RConn', 1), ...
        get_port([object_path '/HoldPipe_051'], 'RConn', 1));
    reconnect_trimmed_fluid_port(object_path, ...
        get_port([object_path '/CooldownPipe_051'], 'LConn', 1), ...
        get_port([object_path '/Conn4'], 'RConn', 1));

    mux_path = [solid_path '/TempMux51'];
    if getSimulinkBlockHandle(mux_path) > 0
        set_param(mux_path, 'Inputs', num2str(node_count));
    end

    if strcmp(role, 'sma')
        mass_expr = 'sma_actuator_node_mass_kg';
        cp_expr = 'sma_actuator_cp_J_per_kgK';
        T_expr = 'sma_actuator_T_init_51(%d)';
        cond_k_expr = 'sma_actuator_k_W_per_mK';
        cond_area_expr = 'sma_actuator_area_m2';
        cond_dx_expr = 'sma_actuator_dx_m';
        fluid_T_expr = 'sma_loop_fluid_T_init_K';
        output_var = 'sma_actuator_T_nodes_51';
    else
        mass_expr = 'se_refrigerant_node_mass_kg';
        cp_expr = 'se_refrigerant_cp_J_per_kgK';
        T_expr = 'se_refrigerant_T_init_51(%d)';
        cond_k_expr = 'se_refrigerant_k_W_per_mK';
        cond_area_expr = 'se_refrigerant_area_m2';
        cond_dx_expr = 'se_refrigerant_dx_m';
        fluid_T_expr = 'se_loop_fluid_T_init_K';
        output_var = 'se_refrigerant_T_nodes_51';
    end

    for idx = 1:node_count
        mass_path = [solid_path sprintf('/NodeMass_%02d', idx)];
        set_param(mass_path, 'mass', mass_expr, 'sp_heat', cp_expr, ...
            'T', sprintf(T_expr, idx));
        hold_pipe_path = [object_path sprintf('/HoldPipe_%03d', idx)];
        cooldown_pipe_path = [object_path sprintf('/CooldownPipe_%03d', idx)];
        set_param(hold_pipe_path, 'T0', fluid_T_expr);
        set_param(cooldown_pipe_path, 'T0', fluid_T_expr);
    end
    for idx = 1:node_count - 1
        cond_path = [solid_path sprintf('/NodeCond_%02d_%02d', idx, idx + 1)];
        set_param(cond_path, ...
            'area', cond_area_expr, ...
            'thickness', cond_dx_expr, ...
            'th_cond', cond_k_expr);
    end

    temp_sink = find_system(solid_path, 'SearchDepth', 1, ...
        'BlockType', 'ToWorkspace');
    if ~isempty(temp_sink)
        set_param(temp_sink{1}, 'VariableName', output_var);
    end
end

function port = get_port(block_path, field_name, index)
    ports = get_param(block_path, 'PortHandles');
    handles = ports.(field_name);
    port = handles(index);
end

function reconnect_trimmed_fluid_port(system_path, port_a, port_b)
% Removing pipes 52..101 leaves dangling physical lines on both retained ends.
    ports = [port_a, port_b];
    for idx = 1:numel(ports)
        line_handle = get_param(ports(idx), 'Line');
        if line_handle ~= -1
            delete_line(line_handle);
        end
    end
    add_line(system_path, port_a, port_b, 'autorouting', 'on');
end

function connect_if_unconnected(system_path, source_port, destination_port)
    if get_param(destination_port, 'Line') == -1
        add_line(system_path, source_port, destination_port, 'autorouting', 'on');
    end
end

function prefix_workspace_sinks(system_path, prefix)
    sinks = find_system(system_path, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'BlockType', 'ToWorkspace');
    for idx = 1:numel(sinks)
        variable_name = get_param(sinks{idx}, 'VariableName');
        if ~startsWith(variable_name, prefix)
            set_param(sinks{idx}, 'VariableName', [prefix variable_name]);
        end
    end
end

function set_from_workspace_variable(path_value, variable_name)
    if getSimulinkBlockHandle(path_value) <= 0
        error('Build_HeatDriveECC_Reconfigured_Model:MissingValveCommand', ...
            'Missing mature valve command block: %s', path_value);
    end
    set_param(path_value, 'VariableName', variable_name);
    try
        set_param(path_value, 'Interpolate', 'on', ...
            'OutputAfterFinalValue', 'Holding final value');
    catch
    end
end

function add_role_subsystem(model_name, block_name, position, description)
    path_value = [model_name '/' block_name];
    delete_block_if_present(path_value);
    add_block('simulink/Ports & Subsystems/Subsystem', path_value, ...
        'Position', position, ...
        'BackgroundColor', 'green');
    set_param(path_value, 'Description', description);
end

function add_annotation(model_name, position, text_value)
    annotation = Simulink.Annotation(model_name, text_value);
    annotation.Position = position;
    annotation.BackgroundColor = 'white';
end

function rename_block_if_present(path_value, new_name)
    if getSimulinkBlockHandle(path_value) <= 0
        return;
    end
    parent_path = get_param(path_value, 'Parent');
    target_path = [parent_path '/' new_name];
    if getSimulinkBlockHandle(target_path) <= 0
        set_param(path_value, 'Name', new_name);
    end
end

function delete_block_if_present(path_value)
    if getSimulinkBlockHandle(path_value) > 0
        delete_block(path_value);
    end
end

function close_if_loaded(model_name)
    if bdIsLoaded(model_name)
        set_param(model_name, 'Dirty', 'off');
        close_system(model_name, 0);
    end
end

function digest = file_hash(path_value)
    command = sprintf(['powershell -NoProfile -Command ', ...
        '"(Get-FileHash -Algorithm SHA256 -LiteralPath ''%s'').Hash"'], ...
        strrep(path_value, '''', ''''''));
    [status, text] = system(command);
    if status ~= 0
        error('Build_HeatDriveECC_Reconfigured_Model:HashFailed', ...
            'Cannot calculate SHA256 for %s.', path_value);
    end
    digest = upper(strtrim(text));
end
