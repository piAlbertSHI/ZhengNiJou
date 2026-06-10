function audit = Audit_HeatDriveECC_FifthRound_Baseline(options)
% Audit the fifth-round mature-model baseline without modifying the SLX.

    if nargin < 1
        options = struct();
    end
    root_dir = fileparts(mfilename('fullpath'));
    model_name = 'nixunhuan_solver101_internal';
    model_path = fullfile(root_dir, [model_name '.slx']);
    outputs_dir = get_field(options, 'outputs_dir', ...
        fullfile(root_dir, 'Output', 'fifth_round_baseline_audit'));
    if ~isfolder(outputs_dir)
        mkdir(outputs_dir);
    end

    required_root_blocks = {
        'HotFluidBuffer'
        'ColdFluidBuffer'
        'Pressure Source (TL)'
        'PressurePI_TargetHold'
        'PressurePI_TargetCooldown'
        'PressurePI_ErrorSum'
        'PressurePI_Kp'
        'PressurePI_Ki'
        'PressurePI_Integrator'
        'PressurePI_Saturation'
        'V1_cold_inlet'
        'V2_hot_return'
        'V3_sma_to_hot'
        'V4_hot_inlet'
        'V5_cold_return'
        'V6_sma_to_chip_cold'
        'ValveCommandFromWorkspace'
        'SMA'
        '热端换热器'
        '冷端换热器'};

    digest_before = file_digest(model_path);
    load_system(model_path);
    root_blocks = find_system(model_name, 'SearchDepth', 1, 'Type', 'Block');
    root_names = cellfun(@(p) get_param(p, 'Name'), root_blocks(2:end), ...
        'UniformOutput', false);

    present = false(size(required_root_blocks));
    for idx = 1:numel(required_root_blocks)
        present(idx) = any(strcmp(root_names, required_root_blocks{idx}));
    end

    hold_pipe_count = numel(find_system([model_name '/SMA'], ...
        'LookUnderMasks', 'all', 'FollowLinks', 'on', 'RegExp', 'on', ...
        'Name', '^HoldPipe_[0-9]+$'));
    cooldown_pipe_count = numel(find_system([model_name '/SMA'], ...
        'LookUnderMasks', 'all', 'FollowLinks', 'on', 'RegExp', 'on', ...
        'Name', '^CooldownPipe_[0-9]+$'));
    node_mass_count = numel(find_system([model_name '/SMA/Subsystem2'], ...
        'LookUnderMasks', 'all', 'FollowLinks', 'on', 'RegExp', 'on', ...
        'Name', '^NodeMass_[0-9]+$'));
    probe_count = numel(find_system(model_name, 'LookUnderMasks', 'all', ...
        'FollowLinks', 'on', 'RegExp', 'on', 'Name', '.*(TempSensor|FlowSensor).*'));
    close_system(model_name, 0);
    digest_after = file_digest(model_path);

    audit = struct();
    audit.schema_version = 'heatdrive_ecc_fifth_round_baseline_audit_v1';
    audit.model_name = model_name;
    audit.model_path = model_path;
    audit.sha256_before = digest_before;
    audit.sha256_after = digest_after;
    audit.original_model_unchanged = strcmp(digest_before, digest_after);
    audit.required_root_blocks = required_root_blocks;
    audit.required_root_blocks_present = present;
    audit.missing_required_root_blocks = required_root_blocks(~present);
    audit.required_root_blocks_ok = all(present);
    audit.baseline_gap_count = sum(~present);
    audit.hold_pipe_count = hold_pipe_count;
    audit.cooldown_pipe_count = cooldown_pipe_count;
    audit.node_mass_count = node_mass_count;
    audit.probe_count = probe_count;
    audit.mature_nodewise_exchange_template_ok = ...
        hold_pipe_count >= 51 && cooldown_pipe_count >= 51 && node_mass_count >= 51;
    audit.ok = audit.original_model_unchanged && ...
        audit.mature_nodewise_exchange_template_ok;

    save(fullfile(outputs_dir, 'fifth_round_baseline_audit.mat'), 'audit');
    write_json(fullfile(outputs_dir, 'fifth_round_baseline_audit.json'), audit);
end

function digest = file_digest(path_value)
    command = sprintf(['powershell -NoProfile -Command ', ...
        '"(Get-FileHash -Algorithm SHA256 -LiteralPath ''%s'').Hash"'], ...
        strrep(path_value, '''', ''''''));
    [status, text] = system(command);
    if status ~= 0
        error('Audit_HeatDriveECC_FifthRound_Baseline:HashFailed', ...
            'Cannot calculate SHA256 for %s.', path_value);
    end
    digest = upper(strtrim(text));
end

function value = get_field(s, name, default_value)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        value = s.(name);
    else
        value = default_value;
    end
end

function write_json(path_value, value)
    fid = fopen(path_value, 'w', 'n', 'UTF-8');
    if fid < 0
        error('Audit_HeatDriveECC_FifthRound_Baseline:CannotWriteJson', ...
            'Cannot write %s.', path_value);
    end
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', jsonencode(value, 'PrettyPrint', true));
end
