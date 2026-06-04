function report_text = Build_CoupledSMA_SingleStage_Report(summary_or_path, output_path)
% Build a text report for a coupled single-stage SMA smoke result.

    if nargin < 1 || isempty(summary_or_path)
        summary_or_path = fullfile(fileparts(mfilename('fullpath')), ...
            'outputs_coupled_single_smoke', 'coupled_smoke_summary.json');
    end
    if ischar(summary_or_path) || isstring(summary_or_path)
        summary = jsondecode(fileread(char(string(summary_or_path))));
    else
        summary = summary_or_path;
    end
    if nargin < 2
        output_path = '';
    end

    lines = {};
    lines{end + 1} = 'Agent2 coupled single-stage SMA report';
    lines{end + 1} = '';
    lines{end + 1} = sprintf('ok: %d', logical(get_field(summary, 'ok', false)));
    lines{end + 1} = sprintf('outputs_dir: %s', char(string(get_field(summary, 'outputs_dir', ''))));
    lines{end + 1} = sprintf('stage_count: %g', get_field(summary, 'stage_count', NaN));
    lines{end + 1} = sprintf('surrogate_exchange_used: %d', logical(get_field(summary, 'surrogate_exchange_used', false)));
    lines{end + 1} = sprintf('pressure range MPa: %.6g .. %.6g', ...
        get_field(summary, 'pressure_min_MPa', NaN), get_field(summary, 'pressure_max_MPa', NaN));
    lines{end + 1} = sprintf('coupling residual median/max: %.6g / %.6g', ...
        get_field(summary, 'coupling_residual_norm_median', NaN), ...
        get_field(summary, 'coupling_residual_norm_max', NaN));
    lines{end + 1} = sprintf('actuator heat/latent/work J: %.6g / %.6g / %.6g', ...
        get_field(summary, 'actuator_heat_input_J', NaN), ...
        get_field(summary, 'actuator_latent_J', NaN), ...
        get_field(summary, 'actuator_mechanical_work_J', NaN));
    lines{end + 1} = sprintf('hot/cold/pump/COP: %.6g / %.6g / %.6g / %.6g', ...
        get_field(summary, 'hot_end_heat_J', NaN), ...
        get_field(summary, 'cold_end_heat_J', NaN), ...
        get_field(summary, 'pump_work_J', NaN), ...
        get_field(summary, 'COP_estimate', NaN));
    report_text = strjoin(lines, newline);

    if ~isempty(output_path)
        fid = fopen(output_path, 'w', 'n', 'UTF-8');
        if fid < 0
            error('Build_CoupledSMA_SingleStage_Report:OpenFailed', ...
                'Could not write %s.', output_path);
        end
        cleaner = onCleanup(@() fclose(fid));
        fprintf(fid, '%s', report_text);
        clear cleaner
    end
end

function value = get_field(s, field_name, default_value)
    if isstruct(s) && isfield(s, field_name) && ~isempty(s.(field_name))
        value = s.(field_name);
    else
        value = default_value;
    end
end
