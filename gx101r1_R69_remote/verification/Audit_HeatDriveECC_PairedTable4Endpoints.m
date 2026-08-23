function audit = Audit_HeatDriveECC_PairedTable4Endpoints(settings) %#ok<*MSNU>
% Require paired, gate-valid Table 4 endpoints on one model contract.

% The audit never constructs a missing endpoint from rejected or transient
% candidates. Zero-load and zero-lift roots must each be accepted by the
% mechanism-gated outer solver before the paired strict audit can pass.

    if nargin < 1
        settings = struct();
    end
    repo_root = fileparts(fileparts(mfilename('fullpath')));
    defaults = struct( ...
        'zero_load_summary', fullfile(repo_root, 'outputs', ...
            'qian_table4_zero_load_outer_solve_v3_20260822', ...
            'outer_solve_summary.json'), ...
        'zero_lift_summary', fullfile(repo_root, 'outputs', ...
            'qian_table4_zero_lift_outer_solve_20260824', ...
            'outer_solve_summary.json'), ...
        'output_dir', fullfile(repo_root, 'outputs_storage_audit', ...
            'paired_table4_endpoint_audit'), ...
        'expected_window_cycles', 10, ...
        'qian_zero_load_lift_K', 26.2, ...
        'qian_zero_lift_SCP_W_per_g', 0.64, ...
        'lift_relative_tolerance', 0.02, ...
        'SCP_relative_tolerance', 0.02, ...
        'authority_settings', struct());
    settings = merge_structs(defaults, settings);
    authority = Resolve_HeatDriveECC_MainlineAuthority( ...
        settings.authority_settings);
    if ~exist(settings.output_dir, 'dir')
        mkdir(settings.output_dir);
    end

    [zero_load, zero_load_reason] = read_endpoint( ...
        settings.zero_load_summary, 'zero_load', authority);
    [zero_lift, zero_lift_reason] = read_endpoint( ...
        settings.zero_lift_summary, 'zero_lift', authority);
    roots_available = zero_load.accepted && zero_lift.accepted;
    common_authority = roots_available && strcmp( ...
        zero_load.authority_contract_path, ...
        zero_lift.authority_contract_path) && strcmp( ...
        zero_load.authority_contract_path, authority.contract_path);
    common_window = roots_available && ...
        zero_load.window_cycles == settings.expected_window_cycles && ...
        zero_lift.window_cycles == settings.expected_window_cycles;
    common_parameter_contract = roots_available && ...
        ~isempty(zero_load.parameter_contract_sha256) && strcmp( ...
        zero_load.parameter_contract_sha256, ...
        zero_lift.parameter_contract_sha256);
    all_endpoint_gates = roots_available && zero_load.all_gates && ...
        zero_lift.all_gates;

    lift_error = NaN;
    SCP_error = NaN;
    quantitative_pass = false;
    if roots_available
        lift_error = abs(zero_load.eq9_lift_K - ...
            settings.qian_zero_load_lift_K) / ...
            settings.qian_zero_load_lift_K;
        SCP_error = abs(zero_lift.eq10_SCP_W_per_g - ...
            settings.qian_zero_lift_SCP_W_per_g) / ...
            settings.qian_zero_lift_SCP_W_per_g;
        quantitative_pass = lift_error <= ...
            settings.lift_relative_tolerance && SCP_error <= ...
            settings.SCP_relative_tolerance;
    end
    paired_contract_pass = all([roots_available, common_authority, ...
        common_window, common_parameter_contract, all_endpoint_gates]);
    paired_strict_pass = paired_contract_pass && quantitative_pass;

    reasons = strings(0, 1);
    if ~zero_load.accepted
        reasons(end + 1) = "zero_load: " + zero_load_reason; %#ok<MSNU>
    end
    if ~zero_lift.accepted
        reasons(end + 1) = "zero_lift: " + zero_lift_reason; %#ok<MSNU>
    end
    if roots_available && ~common_authority
        reasons(end + 1) = "endpoint authority contracts differ"; %#ok<MSNU>
    end
    if roots_available && ~common_window
        reasons(end + 1) = "endpoint sampling windows differ"; %#ok<MSNU>
    end
    if roots_available && ~common_parameter_contract
        reasons(end + 1) = "endpoint parameter contracts differ"; %#ok<MSNU>
    end
    if roots_available && ~all_endpoint_gates
        reasons(end + 1) = "one or both endpoint gate sets failed"; %#ok<MSNU>
    end
    if paired_contract_pass && ~quantitative_pass
        reasons(end + 1) = "paired endpoints miss Qian Table 4 tolerances"; %#ok<MSNU>
    end
    if isempty(reasons)
        reasons = "none";
    end

    audit = struct();
    audit.schema = 'heatdrive_ecc_paired_table4_endpoint_audit_v1';
    audit.generated_at = char(datetime('now', 'TimeZone', 'local'));
    audit.zero_load = zero_load;
    audit.zero_lift = zero_lift;
    audit.roots_available = roots_available;
    audit.common_authority = common_authority;
    audit.common_window = common_window;
    audit.common_parameter_contract = common_parameter_contract;
    audit.all_endpoint_gates = all_endpoint_gates;
    audit.paired_contract_pass = paired_contract_pass;
    audit.quantitative_pass = quantitative_pass;
    audit.paired_strict_pass = paired_strict_pass;
    audit.zero_load_lift_relative_error = lift_error;
    audit.zero_lift_SCP_relative_error = SCP_error;
    audit.reasons = cellstr(reasons);
    audit.claim = claim_text(paired_strict_pass);
    json_path = fullfile(settings.output_dir, ...
        'paired_table4_endpoint_audit.json');
    mat_path = fullfile(settings.output_dir, ...
        'paired_table4_endpoint_audit.mat');
    txt_path = fullfile(settings.output_dir, ...
        'paired_table4_endpoint_audit.txt');
    write_json(json_path, audit);
    save(mat_path, 'audit', 'settings', '-v7');
    write_text(txt_path, audit);
    fprintf(['PAIRED_TABLE4_AUDIT roots=%d contract=%d ', ...
        'quantitative=%d strict=%d\n'], roots_available, ...
        paired_contract_pass, quantitative_pass, paired_strict_pass);
end

function [endpoint, reason] = read_endpoint(path, expected_name, authority)
    endpoint = endpoint_template(expected_name);
    reason = 'outer-solve summary is missing';
    if ~isfile(path)
        return;
    end
    outer = jsondecode(fileread(path));
    endpoint.summary_path = path;
    endpoint.status = char(string(outer.status));
    endpoint.authority_contract_path = char(string( ...
        outer.authority_contract_path));
    if isfield(outer, 'endpoint_name') && ...
            ~strcmp(outer.endpoint_name, expected_name)
        reason = 'outer-solve endpoint type does not match';
        return;
    end
    accepted_status = ['accepted_' expected_name '_root'];
    if ~strcmp(endpoint.status, accepted_status)
        reason = ['no accepted ' expected_name ' root'];
        return;
    end
    records = outer.records;
    if ~isstruct(records)
        reason = 'outer-solve records are malformed';
        return;
    end
    admitted = records([records.admissible]);
    if isempty(admitted)
        reason = 'accepted status has no admissible record';
        return;
    end
    [~, idx] = min(abs([admitted.Tc_K] - outer.root_Tc_K));
    root = admitted(idx);
    endpoint.Tc_K = root.Tc_K;
    endpoint.eq9_lift_K = root.eq9_lift_K;
    endpoint.eq10_SCP_W_per_g = root.eq10_SCP_W_per_g;
    endpoint.result_path = char(string(root.result_path));
    endpoint.report_path = char(string(root.report_path));
    endpoint.authority_contract_path = char(string( ...
        outer.authority_contract_path));
    endpoint.all_gates = all([root.mechanism_pass, ...
        root.periodic_steady_state, root.flow_gates_pass, ...
        root.phase_gates_pass, root.energy_gates_pass, ...
        root.observability_gates_pass]);
    endpoint.window_cycles = report_window(endpoint.report_path);
    parameter_path = fullfile(fileparts(endpoint.report_path), ...
        'qian2019_table2_table4_parameter_contract.csv');
    if isfile(parameter_path)
        endpoint.parameter_contract_path = parameter_path;
        endpoint.parameter_contract_sha256 = file_sha256(parameter_path);
    end
    endpoint.accepted = endpoint.all_gates && ...
        strcmp(endpoint.authority_contract_path, authority.contract_path);
    if endpoint.accepted
        reason = 'accepted';
    else
        reason = 'root record failed gates or authority contract';
    end
end

function endpoint = endpoint_template(name)
    endpoint = struct('name', name, 'accepted', false, 'status', '', ...
        'Tc_K', NaN, 'eq9_lift_K', NaN, ...
        'eq10_SCP_W_per_g', NaN, 'all_gates', false, ...
        'window_cycles', NaN, 'authority_contract_path', '', ...
        'parameter_contract_path', '', ...
        'parameter_contract_sha256', '', 'result_path', '', ...
        'report_path', '', 'summary_path', '');
end

function cycles = report_window(path)
    cycles = NaN;
    if ~isfile(path)
        return;
    end
    token = regexp(fileread(path), ...
        '(?m)^\s*periodic window:\s*last\s+(\d+)\s+complete cycles\s*$', ...
        'tokens', 'once');
    if ~isempty(token)
        cycles = str2double(token{1});
    end
end

function hash = file_sha256(path)
    stream = java.io.FileInputStream(java.io.File(path));
    cleaner = onCleanup(@() stream.close());
    digest = java.security.MessageDigest.getInstance('SHA-256');
    buffer = zeros(1, 1048576, 'int8');
    while true
        count = stream.read(buffer, 0, numel(buffer));
        if count < 0
            break;
        end
        digest.update(buffer(1:count));
    end
    clear cleaner
    bytes = typecast(digest.digest(), 'uint8');
    hash = lower(reshape(dec2hex(bytes, 2).', 1, []));
end

function text = claim_text(pass)
    if pass
        text = 'paired Table 4 strict audit passed';
    else
        text = ['not yet reproduced: paired endpoint evidence is ', ...
            'missing, contract-inconsistent, gate-invalid, or outside ', ...
            'the declared quantitative tolerance'];
    end
end

function write_json(path, value)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'HeatDriveECC:PairedAuditJsonOpenFailed', ...
        'Cannot write %s.', path);
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', jsonencode(value, 'PrettyPrint', true));
    clear cleaner
end

function write_text(path, audit)
    fid = fopen(path, 'w', 'n', 'UTF-8');
    assert(fid >= 0, 'HeatDriveECC:PairedAuditTextOpenFailed', ...
        'Cannot write %s.', path);
    cleaner = onCleanup(@() fclose(fid));
    fprintf(fid, 'schema=%s\n', audit.schema);
    fprintf(fid, 'roots_available=%d\n', audit.roots_available);
    fprintf(fid, 'common_authority=%d\n', audit.common_authority);
    fprintf(fid, 'common_window=%d\n', audit.common_window);
    fprintf(fid, 'common_parameter_contract=%d\n', ...
        audit.common_parameter_contract);
    fprintf(fid, 'all_endpoint_gates=%d\n', audit.all_endpoint_gates);
    fprintf(fid, 'paired_contract_pass=%d\n', audit.paired_contract_pass);
    fprintf(fid, 'quantitative_pass=%d\n', audit.quantitative_pass);
    fprintf(fid, 'paired_strict_pass=%d\n', audit.paired_strict_pass);
    fprintf(fid, 'claim=%s\n', audit.claim);
    for idx = 1:numel(audit.reasons)
        fprintf(fid, 'reason_%d=%s\n', idx, audit.reasons{idx});
    end
    clear cleaner
end

function out = merge_structs(out, overrides)
    names = fieldnames(overrides);
    for idx = 1:numel(names)
        name = names{idx};
        if isfield(out, name) && isstruct(out.(name)) && ...
                isstruct(overrides.(name))
            out.(name) = merge_structs(out.(name), overrides.(name));
        else
            out.(name) = overrides.(name);
        end
    end
end
