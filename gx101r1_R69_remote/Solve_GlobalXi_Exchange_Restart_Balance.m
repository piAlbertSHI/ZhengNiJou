function [balanced_checkpoint, balanced_checkpoint_path, report, result] = Solve_GlobalXi_Exchange_Restart_Balance( ...
        source_checkpoint_input, exchange_checkpoint_input, balanced_checkpoint_path, metadata, balance_options)
% Solve the post-exchange GlobalXi restart equilibrium at a stage boundary.
% This wrapper keeps file I/O outside GlobalXi_TimeStep_Core while the core
% reuses the existing residual/Jacobian/material update path.

    if nargin < 3
        balanced_checkpoint_path = '';
    end
    if nargin < 4 || isempty(metadata)
        metadata = struct();
    end
    if nargin < 5 || isempty(balance_options)
        balance_options = struct();
    end

    stage_name = get_struct_field(metadata, 'stage_name', '');
    boundary_kind = get_struct_field(metadata, 'balance_boundary_kind', ...
        infer_balance_boundary_kind(stage_name));
    target_pressure_MPa = get_struct_field(metadata, 'target_pressure_MPa', NaN);
    if ~isfinite(target_pressure_MPa)
        target_pressure_MPa = get_struct_field(metadata, 'pressure_MPa', NaN);
    end

    core_options = struct( ...
        'source_checkpoint_input', source_checkpoint_input, ...
        'exchange_checkpoint_input', exchange_checkpoint_input, ...
        'stage_name', stage_name, ...
        'balance_boundary_kind', boundary_kind, ...
        'target_pressure_MPa', target_pressure_MPa, ...
        'balance_options', balance_options);
    result = GlobalXi_TimeStep_Core('exchange_restart_balance', core_options);
    balanced_checkpoint = result.balanced_checkpoint;
    report = result.balance_report;

    if ~isempty(balanced_checkpoint_path)
        balanced_checkpoint_path = char(string(balanced_checkpoint_path));
        checkpoint_dir = fileparts(balanced_checkpoint_path);
        if ~isempty(checkpoint_dir) && ~exist(checkpoint_dir, 'dir')
            mkdir(checkpoint_dir);
        end
        report = maybe_write_pressure_trials_csv(report, checkpoint_dir, balanced_checkpoint_path);
        result.balance_report = report;
        if result.ok
            balanced_checkpoint.path = balanced_checkpoint_path;
            checkpoint = balanced_checkpoint; %#ok<NASGU>
            save(balanced_checkpoint_path, 'checkpoint', 'balanced_checkpoint', 'report', 'result', '-v7.3');
        else
            [folder, base, ~] = fileparts(balanced_checkpoint_path);
            failure_path = fullfile(folder, [base, '_balance_failed.mat']);
            failure_report = report; %#ok<NASGU>
            save(failure_path, 'failure_report', 'result', '-v7.3');
            report.balance_failure_checkpoint_path = failure_path;
        end
    else
        balanced_checkpoint_path = '';
    end
    report.balanced_checkpoint_path = balanced_checkpoint_path;
    report.restart_checkpoint_path = balanced_checkpoint_path;
end

function report = maybe_write_pressure_trials_csv(report, checkpoint_dir, checkpoint_path)
    if ~isstruct(report) || ~isfield(report, 'pressure_trial_table') || ...
            isempty(report.pressure_trial_table) || isempty(checkpoint_dir)
        return;
    end
    [~, base, ~] = fileparts(checkpoint_path);
    trial_csv_path = fullfile(checkpoint_dir, [base, '_pressure_trials.csv']);
    trial_table = struct2table(report.pressure_trial_table);
    writetable(trial_table, trial_csv_path, 'Encoding', 'UTF-8');
    report.pressure_trial_csv_path = trial_csv_path;
end

function boundary_kind = infer_balance_boundary_kind(stage_name)
    switch char(string(stage_name))
        case 'hold_exchange'
            boundary_kind = 'hold_closed_hydraulic_volume_simplified';
        case 'cooldown_exchange'
            boundary_kind = 'cooldown_zero_pressure_free_recovery';
        otherwise
            boundary_kind = '';
    end
end

function value = get_struct_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
