function [model_name, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(overrides)
% Build the heat-driven ECC Simulink mainline from the mature solver model.
%
% The target model is the single canonical Simulink model for this workspace.
% It was seeded from the mature heatdrive_ecc_coupled_se21 network and now
% must be maintained in-place: verified TL pump/pressure source, V1-V6
% valves, buffers, hot/cold heat exchangers, probes, and the SMA dual-path
% exchanger shell stay in this one .slx. The heat-driven ECC work extends
% this physical network; it must not create synthetic per-stage signal
% diagrams or additional .slx files.

    if nargin < 1
        overrides = struct();
    end
    options = Build_HeatDriveECC_EighthRound_Defaults(overrides);
    model_name = options.model_name;
    model_path = options.model_path;

    if ~exist(model_path, 'file')
        error('Build:ECC:MissingCanonicalModel', ...
            ['The canonical model is missing: %s\n', ...
            'Do not create a new .slx. Restore this file from git, then modify it in-place.'], ...
            model_path);
    end

    close_if_loaded(model_name, false);

    assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
    assign_mature_exchange_workspace(options, model_path);
    assign_constitutive_workspace(options);

    load_system(model_name);
    set_param(model_name, ...
        'Solver', 'ode23t', ...
        'RelTol', '1e-2', ...
        'AbsTol', '1e-3', ...
        'MaxStep', '0.4', ...
        'InitialStep', 'auto', ...
        'ZeroCross', 'on', ...
        'StopTime', num2str(options.simulation.stop_time_s, '%.15g'), ...
        'SaveTime', 'on', ...
        'TimeSaveName', 'tout', ...
        'ReturnWorkspaceOutputs', 'on');

    mark_ecc_mainline(model_name);
    Integrate_HeatDriveECC_Constitutive21_Interface(model_name, options, false);
    save_system(model_name, model_path);
end

function close_if_loaded(model_name, save_changes)
    if bdIsLoaded(model_name)
        if save_changes
            close_system(model_name, 1);
        else
            set_param(model_name, 'Dirty', 'off');
            close_system(model_name, 0);
        end
    end
end

function assign_mature_exchange_workspace(options, model_path)
    exchange_options = struct( ...
        'model_path', model_path, ...
        'exchange_backend_kind', 'simulink_axial_21', ...
        'ambient_T_init', options.system.T0_K, ...
        'hot_sink_T_init', options.system.T0_K, ...
        'cold_sink_T_init', options.system.Tc_K, ...
        'cold_load_T_init', options.system.Tc_K, ...
        'hotflush_stop_time_s', options.schedule.stage_durations_s(2), ...
        'coldflush_stop_time_s', options.schedule.stage_durations_s(4), ...
        'probe_sample_count', options.validation.min_samples_per_stage);
    runtime = Create_Simulink_Exchange_Runtime(exchange_options);
    exchange_options.runtime = runtime;

    stage_info = struct( ...
        'stage_name', 'cooldown_exchange', ...
        't_start', options.schedule.stage_start_s(4), ...
        't_end', options.schedule.stage_end_s(4));
    stage_config = Resolve_Exchange_Stage_Config(stage_info, exchange_options);
    state_in = struct('T', options.system.T0_K * ones(21, 1));
    sim_params = Build_Simulink_Exchange_Params(state_in, stage_config, exchange_options);
    if ~isfield(sim_params, 'mdot_source_kgps')
        sim_params.mdot_source_kgps = sim_params.mdot_target_kgps;
    end

    names = fieldnames(sim_params);
    for idx = 1:numel(names)
        assignin('base', names{idx}, sim_params.(names{idx}));
    end
end

function assign_constitutive_workspace(options)
    sample_time_s = options.constitutive.simulink_sample_time_s;
    assignin('base', 'constitutive_sample_time_s', sample_time_s);
    assignin('base', 'constitutive_state21_initial', ...
        Initialize_HeatDriveECC_ConstitutiveVector21(options));
    assignin('base', 'constitutive_output_width', ...
        options.constitutive.simulink_output_width);
end

function mark_ecc_mainline(model_name)
    add_or_update_note(model_name, 'ECC_Mainline_Note', ...
        ['ECC mainline is heatdrive_ecc_coupled_se21.slx.', newline, ...
        'Retained verified TL network: pressure source, V1-V6, active SE21 shell, hot/cold HX, buffers, and probes.', newline, ...
        'SMA/SE remain separate thermal modules; the coupled constitutive interface injects 21-node latent/mechanical heat sources.'], ...
        [40 10 820 75]);

    add_or_update_note(model_name, 'ECC_Route_Map', ...
        ['Article route target on one static valve-controlled network:', newline, ...
        'S1: SHEX -> SMA actuator during SMA heat/load.', newline, ...
        'S2: SE refrigerant -> THE/HHEX during loaded heat rejection.', newline, ...
        'S3: THE/HHEX -> SMA actuator during SMA cool/unload.', newline, ...
        'S4: CHEX -> SE refrigerant during cold-side heat absorption.'], ...
        [840 10 1480 105]);

    tag_block(model_name, 'Pressure Source (TL)', ...
        'ECC pump / pressure source retained from mature model');
    tag_block(model_name, 'ValveCommandFromWorkspace', ...
        'Four-stage valve command input for route gates');
    tag_block(model_name, 'V1_cold_inlet', ...
        'Retained mature route gate V1');
    tag_block(model_name, 'V2_hot_return', ...
        'Retained mature route gate V2');
    tag_block(model_name, 'V3_sma_to_hot', ...
        'Retained mature route gate V3');
    tag_block(model_name, 'V4_hot_inlet', ...
        'Retained mature route gate V4');
    tag_block(model_name, 'V5_cold_return', ...
        'Retained mature route gate V5');
    tag_block(model_name, 'V6_sma_to_chip_cold', ...
        'Retained mature route gate V6');
    tag_block(model_name, 'SE', ...
        'Active dual-path SE21 exchanger shell; ECC solid law is handled separately');
    tag_heat_exchanger_blocks(model_name);
end

function tag_heat_exchanger_blocks(model_name)
    hx_blocks = find_system(model_name, 'SearchDepth', 1, 'BlockType', 'SubSystem');
    for idx = 1:numel(hx_blocks)
        block_name = get_param(hx_blocks{idx}, 'Name');
        block_type = lower(block_name);
        if contains(block_name, '热端') || contains(block_type, 'hot')
            tag_block(model_name, block_name, ...
                'HHEX/THE exchanger retained from mature model');
        elseif contains(block_name, '冷端') || contains(block_type, 'cold')
            tag_block(model_name, block_name, ...
                'CHEX exchanger retained from mature model');
        end
    end
end

function add_or_update_note(model_name, tag, text, position)
    existing = find_system(model_name, 'FindAll', 'on', ...
        'Type', 'annotation', 'Tag', tag);
    for idx = 1:numel(existing)
        try
            delete(existing(idx));
        catch
        end
    end
    ann = Simulink.Annotation(model_name, text);
    ann.Tag = tag;
    ann.Position = position;
end

function tag_block(model_name, block_name, text)
    block_path = [model_name '/' block_name];
    if ~bdIsLoaded(model_name) || ~exist_block(block_path)
        return;
    end
    try
        set_param(block_path, 'AttributesFormatString', text);
    catch
        % Cosmetic tags are optional; topology is carried by the copied model.
    end
end

function tf = exist_block(block_path)
    try
        get_param(block_path, 'Handle');
        tf = true;
    catch
        tf = false;
    end
end
