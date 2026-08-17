function result = Run_HeatDriveECC_EighthRound_Simulink_Cycles(overrides)
% Run continuous coupled cycles and accept only physical Simscape logs.

    if nargin < 1
        overrides = struct();
    end
    [model_name, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(overrides);
    model_cleanup = onCleanup(@() discard_runtime_model_changes(model_name));
    if ~exist(options.outputs_dir, 'dir')
        mkdir(options.outputs_dir);
    end

    clear HeatDriveECC_EighthRound_SimulinkStep
    assignin('base', 'EIGHTH_ROUND_OPTIONS', options);
    sim_in = Simulink.SimulationInput(model_name);
    simulation_mode = get_struct_option( ...
        options.simulation, 'mode', 'normal');
    sim_in = sim_in.setModelParameter( ...
        'StartTime', '0', ...
        'StopTime', num2str(options.simulation.stop_time_s, '%.15g'), ...
        'Solver', options.simulation.solver, ...
        'SimulationMode', simulation_mode, ...
        'ReturnWorkspaceOutputs', 'on', ...
        'CaptureErrors', 'on');
    if get_struct_option(options.simulation, ...
            'disable_redundant_model_logging', true)
        sim_in = sim_in.setModelParameter( ...
            'SaveTime', 'off', ...
            'SaveOutput', 'off', ...
            'SignalLogging', 'off');
    end
    fixed_step_solvers = {'ode1','ode2','ode3','ode4','ode5','ode8', ...
        'ode14x','FixedStepDiscrete'};
    if any(strcmpi(options.simulation.solver, fixed_step_solvers))
        sim_in = sim_in.setModelParameter( ...
            'FixedStep', num2str(options.simulation.fixed_step_s, '%.15g'));
    else
        sim_in = sim_in.setModelParameter( ...
            'MaxStep', num2str(options.simulation.fixed_step_s, '%.15g'), ...
            'RelTol', '1e-2', ...
            'AbsTol', '1e-3');
    end
    sim_in = sim_in.setVariable('EIGHTH_ROUND_OPTIONS', options);
    [sim_in, checkpoint_context] = configure_checkpoint_resume( ...
        sim_in, model_name, options);
    if options.simulation.save_final_operating_point
        sim_in = sim_in.setModelParameter( ...
            'SaveFinalState', 'on', ...
            'FinalStateName', 'xFinal', ...
            'SaveOperatingPoint', 'on');
    end

    wall_start = tic;
    sim_out = sim(sim_in);
    walltime_s = toc(wall_start);
    if isprop(sim_out, 'ErrorMessage') && ~isempty(sim_out.ErrorMessage)
        error('Run:EighthRound:SimulinkFailed', '%s', sim_out.ErrorMessage);
    end

    segment_physical = extract_physical_simscape_logs(sim_out, options);
    [physical, prior_provenance] = combine_checkpoint_history( ...
        segment_physical, checkpoint_context, options);
    physical.segment_walltime_s = walltime_s;
    physical.walltime_s = walltime_s + checkpoint_context.prior_walltime_s;
    physical.authority = 'physical_simscape_to_workspace_logs';
    physical.sim_call_count = checkpoint_context.prior_sim_call_count + 1;
    physical.legacy_surrogate_used_for_results = false;
    summary = Summarize_HeatDriveECC_EighthRound_Output(physical, options);

    stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    output_dir = fullfile(options.outputs_dir, ...
        sprintf('qian2019_table2_table4_simscape_%dcycle_%s', ...
        options.cycle_count, stamp));
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    output_mat = fullfile(output_dir, 'physical_simscape_result.mat');
    available_simulink_variables = sim_out.who;
    provenance = struct( ...
        'authority', physical.authority, ...
        'legacy_surrogate_used_for_results', false, ...
        'sim_call_count', physical.sim_call_count, ...
        'continuous_full_cycle_simulation', ~checkpoint_context.resumed, ...
        'checkpoint_restart_used', checkpoint_context.resumed, ...
        'checkpoint_chain_verified', checkpoint_context.verified, ...
        'checkpoint_prior_provenance', prior_provenance, ...
        'walltime_s', physical.walltime_s, ...
        'segment_walltime_s', walltime_s, ...
        'model_name', model_name, ...
        'simulation_mode', simulation_mode, ...
        'redundant_model_logging_disabled', logical(get_struct_option( ...
            options.simulation, 'disable_redundant_model_logging', true)), ...
        'solver', options.simulation.solver, ...
        'fixed_step_s', options.simulation.fixed_step_s);
    checkpoint_path = '';
    if options.simulation.save_final_operating_point
        checkpoint_path = fullfile(output_dir, 'final_operating_point.mat');
        operating_point = sim_out.xFinal;
        checkpoint_meta = make_checkpoint_metadata(model_name, options, ...
            physical, output_mat);
        save(checkpoint_path, 'operating_point', 'checkpoint_meta', '-v7.3');
        provenance.final_checkpoint_path = checkpoint_path;
    end
    save(output_mat, 'physical', 'summary', 'options', 'provenance', ...
        'available_simulink_variables', '-v7.3');

    result = struct();
    result.model_name = model_name;
    result.model_path = options.model_path;
    result.options = options;
    result.time_s = physical.time_s;
    result.physical = physical;
    result.summary = summary;
    result.sim_out = sim_out;
    result.output_dir = output_dir;
    result.output_mat = output_mat;
    result.used_simulink_sim = true;
    result.authority = physical.authority;
    result.legacy_surrogate_used_for_results = false;
    result.provenance = provenance;
    result.checkpoint_path = checkpoint_path;
    if get_struct_option(options.output, 'generate_figures', true)
        result.figures = Plot_HeatDriveECC_EighthRound_Result(result, ...
            sprintf('%dcycle', options.cycle_count));
    else
        result.figures = {};
    end
    clear model_cleanup
end

function [sim_in, context] = configure_checkpoint_resume(sim_in, model_name, options)
    context = struct('resumed', false, 'verified', true, ...
        'prior_physical', struct(), 'prior_provenance', struct(), ...
        'prior_walltime_s', 0.0, 'prior_sim_call_count', 0);
    checkpoint_path = char(string(options.simulation.resume_checkpoint_path));
    prior_result_path = char(string(options.simulation.prior_result_path));
    if isempty(strtrim(checkpoint_path)) && isempty(strtrim(prior_result_path))
        return;
    end
    if isempty(strtrim(checkpoint_path)) || isempty(strtrim(prior_result_path))
        error('Run:EighthRound:IncompleteCheckpointResume', ...
            'Both resume_checkpoint_path and prior_result_path are required.');
    end
    if ~exist(checkpoint_path, 'file') || ~exist(prior_result_path, 'file')
        error('Run:EighthRound:MissingCheckpointResumeFile', ...
            'Checkpoint or prior result file is missing.');
    end
    checkpoint = load(checkpoint_path, 'operating_point', 'checkpoint_meta');
    prior = load(prior_result_path, 'physical', 'options', 'provenance');
    required_checkpoint = {'operating_point','checkpoint_meta'};
    required_prior = {'physical','options','provenance'};
    if ~all(isfield(checkpoint, required_checkpoint)) || ...
            ~all(isfield(prior, required_prior))
        error('Run:EighthRound:InvalidCheckpointResumeFile', ...
            'Checkpoint or prior result does not contain the required contract.');
    end
    expected = checkpoint_contract(model_name, options);
    if ~isequaln(normalize_controller_retune_contract( ...
            checkpoint.checkpoint_meta.contract), expected)
        error('Run:EighthRound:CheckpointContractMismatch', ...
            'Model, solver, material, geometry, route, or thermal contract changed.');
    end
    if ~isequaln(normalize_controller_retune_contract( ...
            checkpoint_contract(model_name, prior.options)), expected)
        error('Run:EighthRound:PriorResultContractMismatch', ...
            'Prior physical result parameters do not match the checkpoint contract.');
    end
    bound_prior_path = char(string(checkpoint.checkpoint_meta.prior_result_path));
    if ~strcmpi(canonical_path(bound_prior_path), canonical_path(prior_result_path))
        error('Run:EighthRound:CheckpointPriorResultMismatch', ...
            'Checkpoint is not bound to the supplied prior physical result.');
    end
    prior_end_s = prior.physical.time_s(end);
    if abs(prior_end_s - checkpoint.checkpoint_meta.time_s) > ...
            10.0 * eps(max(abs(prior_end_s), 1.0)) || ...
            abs(prior_end_s - prior.options.simulation.stop_time_s) > ...
            10.0 * eps(max(abs(prior_end_s), 1.0)) || ...
            options.simulation.stop_time_s <= prior_end_s
        error('Run:EighthRound:CheckpointTimeMismatch', ...
            'Checkpoint, prior result, and requested stop time are inconsistent.');
    end
    sim_in = sim_in.setInitialState(checkpoint.operating_point);
    context.resumed = true;
    context.verified = true;
    context.prior_physical = prior.physical;
    context.prior_provenance = prior.provenance;
    context.prior_walltime_s = prior.physical.walltime_s;
    context.prior_sim_call_count = prior.physical.sim_call_count;
end

function [physical, prior_provenance] = combine_checkpoint_history( ...
        segment, context, options)
    prior_provenance = struct();
    if ~context.resumed
        physical = segment;
        return;
    end
    prior = context.prior_physical;
    prior_provenance = context.prior_provenance;
    boundary_s = prior.time_s(end);
    boundary_tolerance_s = 10.0 * eps(max(abs(boundary_s), 1.0));
    boundary_idx = find(abs(segment.time_s - boundary_s) <= ...
        boundary_tolerance_s, 1, 'last');
    if isempty(boundary_idx)
        error('Run:EighthRound:MissingCheckpointBoundarySample', ...
            'The resumed segment does not contain the checkpoint time sample.');
    end
    keep = segment.time_s > boundary_s + ...
        boundary_tolerance_s;
    if ~any(keep)
        error('Run:EighthRound:EmptyCheckpointContinuation', ...
            'The resumed simulation produced no samples after the checkpoint.');
    end
    physical = append_physical_struct(prior, segment, keep, boundary_idx, ...
        numel(prior.time_s), numel(segment.time_s));
    [physical.cycle_index, physical.stage_id, physical.stage_elapsed_s] = ...
        cycle_stage_from_time(physical.time_s, options);
end

function out = append_physical_struct( ...
        prior, segment, keep, boundary_idx, n_prior, n_segment)
    prior_names = fieldnames(prior);
    segment_names = fieldnames(segment);
    ignored = {'walltime_s','segment_walltime_s','sim_call_count', ...
        'authority','legacy_surrogate_used_for_results'};
    names = setdiff(intersect(prior_names, segment_names, 'stable'), ignored);
    missing = setxor(setdiff(prior_names, ignored), setdiff(segment_names, ignored));
    if ~isempty(missing)
        error('Run:EighthRound:CheckpointSignalContractMismatch', ...
            'Physical signal sets differ across checkpoint: %s.', strjoin(missing, ', '));
    end
    out = struct();
    for idx = 1:numel(names)
        name = names{idx};
        a = prior.(name);
        b = segment.(name);
        if strcmp(name, 'probes')
            out.(name) = append_probe_struct( ...
                a, b, keep, boundary_idx, n_prior, n_segment);
        elseif (isnumeric(a) || islogical(a)) && ...
                (isnumeric(b) || islogical(b)) && ...
                ~isscalar(a) && ~isscalar(b) && ...
                size(a, 1) == n_prior && size(b, 1) == n_segment
            subs = repmat({':'}, 1, ndims(b));
            subs{1} = keep;
            boundary_subs = repmat({':'}, 1, ndims(b));
            boundary_subs{1} = boundary_idx;
            prior_boundary_subs = repmat({':'}, 1, ndims(a));
            prior_boundary_subs{1} = n_prior;
            a(prior_boundary_subs{:}) = b(boundary_subs{:});
            out.(name) = cat(1, a, b(subs{:}));
        else
            if ~isequaln(a, b)
                error('Run:EighthRound:CheckpointMetadataMismatch', ...
                    'Physical metadata differs across checkpoint: %s.', name);
            end
            out.(name) = a;
        end
    end
end

function out = append_probe_struct( ...
        prior, segment, keep, boundary_idx, n_prior, n_segment)
    names = fieldnames(prior);
    if ~isequal(names, fieldnames(segment))
        error('Run:EighthRound:CheckpointProbeContractMismatch', ...
            'Temperature probe sets differ across checkpoint.');
    end
    out = struct();
    for idx = 1:numel(names)
        a = prior.(names{idx});
        b = segment.(names{idx});
        if size(a, 1) ~= n_prior || size(b, 1) ~= n_segment
            error('Run:EighthRound:CheckpointProbeShapeMismatch', ...
                'Probe shape differs across checkpoint: %s.', names{idx});
        end
        a(end, :) = b(boundary_idx, :);
        out.(names{idx}) = [a; b(keep, :)];
    end
end

function meta = make_checkpoint_metadata(model_name, options, physical, output_mat)
    meta = struct('schema', 'heatdrive_ecc_operating_point_v1', ...
        'time_s', physical.time_s(end), ...
        'cycle_count', options.cycle_count, ...
        'prior_result_path', output_mat, ...
        'contract', checkpoint_contract(model_name, options));
end

function contract = checkpoint_contract(model_name, options)
    contract = struct();
    contract.model_name = model_name;
    contract.model_file_sha256 = file_sha256(options.model_path);
    contract.node_count = options.node_count;
    contract.solver = options.simulation.solver;
    contract.fixed_step_s = options.simulation.fixed_step_s;
    contract.simulation_mode = get_struct_option( ...
        options.simulation, 'mode', 'normal');
    contract.schedule = options.schedule.stage_durations_s;
    contract.geometry = options.geometry;
    contract.material = options.material;
    contract.fluid = options.fluid;
    contract.branch = options.branch;
    contract = normalize_controller_retune_contract(contract);
    contract.system = rmfield_if_present(options.system, ...
        {'cold_load_heat_reference_W'});
    contract.constitutive = options.constitutive;
end

function contract = normalize_controller_retune_contract(contract)
% Route PI gains are retunable controller state, not plant-state geometry.
% Preserve checkpoint continuity when a validated cold-state controller is
% retuned; all material, fluid, thermal, route and constitutive fields remain
% part of the contract.
    if isfield(contract, 'branch')
        names = { ...
            'se_pressure_pi_kp_MPa_per_kgps', ...
            'se_pressure_pi_ki_MPa_per_kgps_s', ...
            'se_stage2_pressure_pi_kp_MPa_per_kgps', ...
            'se_stage2_pressure_pi_ki_MPa_per_kgps_s', ...
            'se_stage4_pressure_pi_kp_MPa_per_kgps', ...
            'se_stage4_pressure_pi_ki_MPa_per_kgps_s', ...
            'se_pressure_feedforward_enabled', ...
            'se_pressure_feedforward_temperature_K', ...
            'se_pressure_feedforward_mu_Pa_s', ...
            'se_pressure_feedforward_reference_mu_Pa_s', ...
            'se_pressure_feedforward_initial_temperature_K', ...
            'se_pressure_feedforward_sample_time_s', ...
            'se_pressure_feedforward_interpolation', ...
            'se_pressure_integrator_reset_mode', ...
            'se_stage4_pressure_integrator_min_MPa', ...
            'se_pressure_pi_tuning_source'};
        present = intersect(fieldnames(contract.branch), names);
        if ~isempty(present)
            contract.branch = rmfield(contract.branch, present);
        end
    end
end

function value = get_struct_option(value_struct, name, default_value)
    if isstruct(value_struct) && isfield(value_struct, name)
        value = value_struct.(name);
    else
        value = default_value;
    end
end

function value = file_sha256(path)
    fid = fopen(path, 'rb');
    if fid < 0
        error('Run:EighthRound:CheckpointModelHashFailed', ...
            'Cannot open canonical model for hashing: %s.', path);
    end
    cleanup = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8');
    digest = java.security.MessageDigest.getInstance('SHA-256');
    digest.update(typecast(bytes, 'int8'));
    value = lower(reshape(dec2hex(typecast(digest.digest(), 'uint8'), 2).', 1, []));
    clear cleanup
end

function value = canonical_path(path)
    file = java.io.File(path);
    value = char(file.getCanonicalPath());
end

function value = rmfield_if_present(value, names)
    present = intersect(fieldnames(value), names);
    if ~isempty(present)
        value = rmfield(value, present);
    end
end

function discard_runtime_model_changes(model_name)
    if bdIsLoaded(model_name)
        set_param(model_name, 'Dirty', 'off');
        close_system(model_name, 0);
    end
end

function physical = extract_physical_simscape_logs(sim_out, options)
    required = { ...
        'SMA_Tx21_internal', 'SE_Tx21_internal', ...
        'ECC_constitutive21_output', ...
        'ECC_Q_SMA_constitutive_W', 'ECC_Q_SE_constitutive_W', ...
        'SHEX_hot_sink_temp_out', 'hot_sink_temp_out', ...
        'cold_sink_temp_out', 'shex_buffer_temp_out', ...
        'hot_buffer_temp_out', 'sma_hot_buffer_temp_out', ...
        'cold_buffer_temp_out', ...
        'mass_flow_sma_stage13_kgps', ...
        'mass_flow_sma_stage1_route_kgps', ...
        'mass_flow_sma_stage3_route_kgps', ...
        'mass_flow_v1_cold_inlet_kgps', ...
        'mass_flow_v3_sma_to_hot_kgps', ...
        'mass_flow_v4_hot_inlet_kgps', ...
        'mass_flow_v6_sma_to_chip_cold_kgps', ...
        'pressure_command_se_MPa', 'pressure_command_sma_MPa', ...
        'sma_stage1_inlet_fluid_temp_out', ...
        'sma_stage1_outlet_fluid_temp_out', ...
        'sma_stage3_inlet_fluid_temp_out', ...
        'sma_stage3_outlet_fluid_temp_out', ...
        'probe_sma_stage2_port1_v1_side_T_K', ...
        'probe_sma_stage2_port2_v3_side_T_K', ...
        'probe_sma_stage4_port3_v4_side_T_K', ...
        'probe_sma_stage4_port4_v6_side_T_K'};
    required = [required, pipe_heat_flow_variable_names()];
    required = [required, sma_pressure_probe_names()];
    available = sim_out.who;
    missing = setdiff(required, available);
    if ~isempty(missing)
        error('Run:EighthRound:MissingPhysicalSignals', ...
            'Missing required physical Simscape logs: %s', ...
            strjoin(missing, ', '));
    end

    [time_s, sma_T_21] = read_raw_signal(sim_out, ...
        'SMA_Tx21_internal');
    if size(sma_T_21, 2) ~= options.node_count
        error('Run:EighthRound:BadSMANodeCount', ...
            'SMA physical log has %d columns; expected %d.', ...
            size(sma_T_21, 2), options.node_count);
    end

    physical = struct();
    physical.time_s = time_s;
    physical.SMA_T_21_K = sma_T_21;
    physical.SE_T_21_K = read_on_grid(sim_out, ...
        'SE_Tx21_internal', time_s, 'linear');
    [physical.cycle_index, physical.stage_id, ...
        physical.stage_elapsed_s] = cycle_stage_from_time(time_s, options);

    physical.SHEX_T_K = read_on_grid(sim_out, ...
        'SHEX_hot_sink_temp_out', time_s, 'linear');
    physical.HHEX_T_K = read_on_grid(sim_out, ...
        'hot_sink_temp_out', time_s, 'linear');
    physical.CHEX_T_K = read_on_grid(sim_out, ...
        'cold_sink_temp_out', time_s, 'linear');
    physical.SHEX_buffer_T_K = read_on_grid(sim_out, ...
        'shex_buffer_temp_out', time_s, 'linear');
    physical.HHEX_buffer_T_K = read_on_grid(sim_out, ...
        'hot_buffer_temp_out', time_s, 'linear');
    physical.SMA_HHEX_buffer_T_K = read_on_grid(sim_out, ...
        'sma_hot_buffer_temp_out', time_s, 'linear');
    physical.CHEX_buffer_T_K = read_on_grid(sim_out, ...
        'cold_buffer_temp_out', time_s, 'linear');

    physical.mdot_SMA_kgps = read_on_grid(sim_out, ...
        'mass_flow_sma_stage13_kgps', time_s, 'linear');
    physical.mdot_SMA_stage1_route_kgps = read_on_grid(sim_out, ...
        'mass_flow_sma_stage1_route_kgps', time_s, 'linear');
    physical.mdot_SMA_stage3_route_kgps = read_on_grid(sim_out, ...
        'mass_flow_sma_stage3_route_kgps', time_s, 'linear');
    physical.mdot_SE_stage2_in_kgps = read_on_grid(sim_out, ...
        'mass_flow_v1_cold_inlet_kgps', time_s, 'linear');
    physical.mdot_SE_stage2_out_kgps = read_on_grid(sim_out, ...
        'mass_flow_v3_sma_to_hot_kgps', time_s, 'linear');
    physical.mdot_SE_stage4_in_kgps = read_on_grid(sim_out, ...
        'mass_flow_v4_hot_inlet_kgps', time_s, 'linear');
    physical.mdot_SE_stage4_out_kgps = read_on_grid(sim_out, ...
        'mass_flow_v6_sma_to_chip_cold_kgps', time_s, 'linear');
    physical.pressure_command_SE_MPa = read_on_grid(sim_out, ...
        'pressure_command_se_MPa', time_s, 'previous');
    physical.pressure_command_SMA_MPa = read_on_grid(sim_out, ...
        'pressure_command_sma_MPa', time_s, 'previous');
    pressure_names = sma_pressure_probe_names();
    physical.SMA_water_pressure_MPa = zeros( ...
        numel(time_s), numel(pressure_names));
    for pressure_idx = 1:numel(pressure_names)
        physical.SMA_water_pressure_MPa(:, pressure_idx) = read_on_grid( ...
            sim_out, pressure_names{pressure_idx}, time_s, 'linear');
    end
    physical.SMA_water_pressure_names = pressure_names;

    physical.SMA_stage1_Tin_K = read_on_grid(sim_out, ...
        'sma_stage1_inlet_fluid_temp_out', time_s, 'linear');
    physical.SMA_stage1_Tout_K = read_on_grid(sim_out, ...
        'sma_stage1_outlet_fluid_temp_out', time_s, 'linear');
    physical.SMA_stage3_Tin_K = read_on_grid(sim_out, ...
        'sma_stage3_inlet_fluid_temp_out', time_s, 'linear');
    physical.SMA_stage3_Tout_K = read_on_grid(sim_out, ...
        'sma_stage3_outlet_fluid_temp_out', time_s, 'linear');
    physical.SE_stage2_Tin_K = read_on_grid(sim_out, ...
        'probe_sma_stage2_port1_v1_side_T_K', time_s, 'linear');
    physical.SE_stage2_Tout_K = read_on_grid(sim_out, ...
        'probe_sma_stage2_port2_v3_side_T_K', time_s, 'linear');
    physical.SE_stage4_Tin_K = read_on_grid(sim_out, ...
        'probe_sma_stage4_port3_v4_side_T_K', time_s, 'linear');
    physical.SE_stage4_Tout_K = read_on_grid(sim_out, ...
        'probe_sma_stage4_port4_v6_side_T_K', time_s, 'linear');

    physical.Q_SMA_constitutive_21_W = read_on_grid(sim_out, ...
        'ECC_Q_SMA_constitutive_W', time_s, 'previous');
    physical.Q_SE_constitutive_21_W = read_on_grid(sim_out, ...
        'ECC_Q_SE_constitutive_W', time_s, 'previous');
    physical.Q_SMA_hold_pipe_to_solid_21_W = read_pipe_heat_flow_matrix( ...
        sim_out, time_s, 'sma', 'hold', options.node_count);
    physical.Q_SMA_cooldown_pipe_to_solid_21_W = read_pipe_heat_flow_matrix( ...
        sim_out, time_s, 'sma', 'cooldown', options.node_count);
    physical.Q_SE_hold_pipe_to_solid_21_W = read_pipe_heat_flow_matrix( ...
        sim_out, time_s, 'se', 'hold', options.node_count);
    physical.Q_SE_cooldown_pipe_to_solid_21_W = ...
        zeros(numel(time_s), options.node_count);
    constitutive = read_on_grid(sim_out, ...
        'ECC_constitutive21_output', time_s, 'previous');
    physical.constitutive_output_252 = constitutive;
    physical = unpack_constitutive_state(physical, constitutive, options);
    physical = collect_temperature_probes(physical, sim_out, available, time_s);

    rho_fluid = 997.0;
    physical.fluid_density_kg_per_m3 = rho_fluid;
    physical.pump_power_SMA_W = abs(physical.pressure_command_SMA_MPa) * ...
        1.0e6 .* abs(physical.mdot_SMA_kgps) / rho_fluid;
    se_flow = max(abs(physical.mdot_SE_stage2_in_kgps), ...
        abs(physical.mdot_SE_stage4_in_kgps));
    physical.pump_power_SE_W = abs(physical.pressure_command_SE_MPa) * ...
        1.0e6 .* se_flow / rho_fluid;
end

function physical = unpack_constitutive_state(physical, values, options)
    N = options.node_count;
    expected_width = 12 * N;
    if size(values, 2) ~= expected_width
        error('Run:EighthRound:BadConstitutiveWidth', ...
            'Physical constitutive output has %d columns; expected %d.', ...
            size(values, 2), expected_width);
    end
    offset = 2 * N;
    names = {'xM_SMA_21','xM_SE_21','sigma_SMA_21_Pa', ...
        'sigma_SE_21_Pa','epsilon_SMA_21','epsilon_SE_21', ...
        'drive_SMA_21_Pa','drive_SE_21_Pa', ...
        'rate_xM_SMA_21_per_s','rate_xM_SE_21_per_s'};
    for idx = 1:numel(names)
        columns = offset + (1:N);
        physical.(names{idx}) = values(:, columns);
        offset = offset + N;
    end
end

function names = pipe_heat_flow_variable_names()
    names = cell(1, 3 * 21);
    cursor = 0;
    pairs = {'sma','hold'; 'sma','cooldown'; 'se','hold'};
    for pair_idx = 1:size(pairs, 1)
        component = pairs{pair_idx, 1};
        group = pairs{pair_idx, 2};
            for node_idx = 1:21
                cursor = cursor + 1;
                names{cursor} = sprintf('%s_%s_node%02d_heatflow_W', ...
                    component, group, node_idx);
            end
    end
end

function names = sma_pressure_probe_names()
    names = { ...
        'sma_hold_pipe_node01_pressure_MPa', ...
        'sma_hold_pipe_node11_pressure_MPa', ...
        'sma_hold_pipe_node21_pressure_MPa', ...
        'sma_cooldown_pipe_node01_pressure_MPa', ...
        'sma_cooldown_pipe_node11_pressure_MPa', ...
        'sma_cooldown_pipe_node21_pressure_MPa', ...
        'shex_hot_pipe_portA_pressure_MPa', ...
        'shex_hot_pipe_portB_pressure_MPa'};
end

function values = read_pipe_heat_flow_matrix(sim_out, time_s, ...
        component, group, node_count)
    values = zeros(numel(time_s), node_count);
    for node_idx = 1:node_count
        variable_name = sprintf('%s_%s_node%02d_heatflow_W', ...
            component, group, node_idx);
        values(:, node_idx) = read_on_grid(sim_out, variable_name, ...
            time_s, 'linear');
    end
end

function physical = collect_temperature_probes(physical, sim_out, available, time_s)
    probe_names = available(contains(available, 'temp', 'IgnoreCase', true) | ...
        contains(available, 'probe_', 'IgnoreCase', true));
    probes = struct();
    for idx = 1:numel(probe_names)
        name = probe_names{idx};
        try
            values = read_on_grid(sim_out, name, time_s, 'linear');
            if size(values, 2) == 1
                probes.(matlab.lang.makeValidName(name)) = values;
            end
        catch
            % Required probes are checked before this optional collection.
        end
    end
    physical.probes = probes;
    physical.probe_names = fieldnames(probes);
end

function values = read_on_grid(sim_out, name, query_time_s, method)
    [time_s, raw_values] = read_raw_signal(sim_out, name);
    if isscalar(time_s)
        values = repmat(raw_values(1, :), numel(query_time_s), 1);
        return;
    end
    [time_s, unique_idx] = unique(time_s, 'last');
    raw_values = raw_values(unique_idx, :);
    values = interp1(time_s, raw_values, query_time_s, method, 'extrap');
end

function [time_s, values] = read_raw_signal(sim_out, name)
    raw = sim_out.get(name);
    if isa(raw, 'timeseries')
        time_s = double(raw.Time(:));
        values = double(raw.Data);
    elseif isstruct(raw) && isfield(raw, 'time') && isfield(raw, 'signals')
        time_s = double(raw.time(:));
        values = double(raw.signals.values);
    else
        error('Run:EighthRound:UnsupportedPhysicalSignal', ...
            'Signal %s has unsupported class %s.', name, class(raw));
    end
    values = squeeze(values);
    if isvector(values)
        values = values(:);
    elseif size(values, 1) ~= numel(time_s) && ...
            size(values, 2) == numel(time_s)
        values = values.';
    end
    if size(values, 1) ~= numel(time_s)
        error('Run:EighthRound:BadPhysicalSignalShape', ...
            'Signal %s has %d time samples and data size [%d %d].', ...
            name, numel(time_s), size(values, 1), size(values, 2));
    end
end

function [cycle_index, stage_id, stage_elapsed_s] = ...
        cycle_stage_from_time(time_s, options)
    tau = options.schedule.tau_cycle_s;
    ncycles = options.cycle_count;
    final_time = ncycles * tau;
    cycle_index = floor(time_s ./ tau) + 1;
    cycle_index = min(max(cycle_index, 1), ncycles);
    local_time = time_s - (cycle_index - 1) .* tau;
    final_mask = time_s >= final_time - 10.0 * eps(max(final_time, 1.0));
    local_time(final_mask) = tau;

    stage_id = 4 * ones(size(time_s));
    stage_elapsed_s = zeros(size(time_s));
    starts = options.schedule.stage_start_s(:).';
    ends = options.schedule.stage_end_s(:).';
    for stage = 1:4
        if stage < 4
            mask = local_time >= starts(stage) & local_time < ends(stage);
        else
            mask = local_time >= starts(stage) & local_time <= ends(stage) + eps(tau);
        end
        stage_id(mask) = stage;
        stage_elapsed_s(mask) = local_time(mask) - starts(stage);
    end
end
