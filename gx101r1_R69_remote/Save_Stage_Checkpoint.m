function checkpoint_path = Save_Stage_Checkpoint(checkpoint_payload, runtime)
% Save one exchange-stage checkpoint as a MAT file.

    if nargin < 2 || isempty(runtime) || ~isstruct(runtime)
        error('Save_Stage_Checkpoint:MissingRuntime', ...
            'A runtime struct with checkpoints_dir is required.');
    end
    if ~isfield(runtime, 'checkpoints_dir') || isempty(runtime.checkpoints_dir)
        error('Save_Stage_Checkpoint:MissingCheckpointDir', ...
            'runtime.checkpoints_dir is required.');
    end

    if ~exist(runtime.checkpoints_dir, 'dir')
        mkdir(runtime.checkpoints_dir);
    end

    file_name_override = get_payload_field(checkpoint_payload, 'file_name_override', '');
    if ~isempty(file_name_override)
        file_name = char(string(file_name_override));
    else
        cycle_index = get_payload_field(checkpoint_payload, 'cycle_index', 0);
        stage_index = get_payload_field(checkpoint_payload, 'stage_index', 0);
        stage_name = char(string(get_payload_field(checkpoint_payload, 'stage_name', 'stage')));
        stage_name = regexprep(stage_name, '[^a-zA-Z0-9_]+', '_');
        file_name = sprintf('cycle_%03d_stage_%02d_%s.mat', cycle_index, stage_index, stage_name);
    end
    checkpoint_path = fullfile(runtime.checkpoints_dir, file_name);

    save_payload = checkpoint_payload;
    if isfield(save_payload, 'file_name_override')
        save_payload = rmfield(save_payload, 'file_name_override');
    end
    if isfield(save_payload, 'simOut') && ...
            (~isfield(runtime, 'store_raw_simout') || ~runtime.store_raw_simout)
        save_payload = rmfield(save_payload, 'simOut');
    end

    save(checkpoint_path, '-struct', 'save_payload');
end

function value = get_payload_field(payload, field_name, default_value)
    if isstruct(payload) && isfield(payload, field_name) && ~isempty(payload.(field_name))
        value = payload.(field_name);
    else
        value = default_value;
    end
end
