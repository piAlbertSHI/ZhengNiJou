function authority = Resolve_HeatDriveECC_MainlineAuthority(settings)
% Resolve and verify the sole C200 mainline recovery authority.

    if nargin < 1
        settings = struct();
    end
    verification_dir = fileparts(mfilename('fullpath'));
    repo_root = fileparts(verification_dir);
    defaults = struct( ...
        'contract_path', fullfile(verification_dir, ...
            'c200_mainline_freeze_contract.json'), ...
        'verify_checkpoint_hash', true, ...
        'verify_large_result_hash', false);
    settings = merge_structs(defaults, settings);

    contract_path = char(string(settings.contract_path));
    assert(isfile(contract_path), 'HeatDriveECC:MissingFreezeContract', ...
        'Mainline freeze contract is missing: %s', contract_path);
    contract = jsondecode(fileread(contract_path));
    assert(strcmp(contract.schema, 'heatdrive_ecc_mainline_freeze_v1'), ...
        'HeatDriveECC:UnsupportedFreezeContract', ...
        'Unsupported mainline freeze schema: %s', contract.schema);

    result_path = resolve_inside_repo(repo_root, ...
        contract.result_relative_path);
    checkpoint_path = resolve_inside_repo(repo_root, ...
        contract.checkpoint_relative_path);
    report_path = resolve_inside_repo(repo_root, ...
        contract.validation_report_relative_path);
    progress_path = resolve_inside_repo(repo_root, ...
        contract.continuation_progress_relative_path);
    required = {result_path, checkpoint_path, report_path, progress_path};
    assert(all(cellfun(@isfile, required)), ...
        'HeatDriveECC:MissingFrozenArtifact', ...
        'One or more frozen C200 artifacts are missing.');

    report = fileread(report_path);
    mechanism_pass = ~isempty(regexp(report, ...
        '(?m)^coupled_mechanism_pass:\s*1\s*$', 'once'));
    periodic_pass = ~isempty(regexp(report, ...
        '(?m)^\s*periodic steady state:\s*1\s*$', 'once'));
    strict_not_claimed = ~isempty(regexp(report, ...
        '(?m)^\s*strict_table4_reproduction_pass:\s*0\s*$', 'once'));
    assert(mechanism_pass && periodic_pass && strict_not_claimed, ...
        'HeatDriveECC:FrozenGateMismatch', ...
        'Frozen C200 report does not satisfy its declared gate contract.');

    if logical(settings.verify_checkpoint_hash)
        actual = powershell_sha256(checkpoint_path);
        assert(strcmpi(actual, contract.checkpoint_sha256), ...
            'HeatDriveECC:FrozenCheckpointHashMismatch', ...
            'Frozen C200 Operating Point SHA-256 mismatch.');
    end
    if logical(settings.verify_large_result_hash)
        actual = powershell_sha256(result_path);
        assert(strcmpi(actual, contract.result_sha256), ...
            'HeatDriveECC:FrozenResultHashMismatch', ...
            'Frozen C200 physical result SHA-256 mismatch.');
    end

    checkpoint = load(checkpoint_path, 'checkpoint_meta');
    assert(isfield(checkpoint, 'checkpoint_meta') && ...
        checkpoint.checkpoint_meta.cycle_count == contract.completed_cycles, ...
        'HeatDriveECC:FrozenCheckpointCycleMismatch', ...
        'Frozen Operating Point metadata is not the declared C200 state.');

    authority = struct();
    authority.schema = contract.schema;
    authority.contract_path = contract_path;
    authority.result_path = result_path;
    authority.checkpoint_path = checkpoint_path;
    authority.report_path = report_path;
    authority.progress_path = progress_path;
    authority.result_sha256 = contract.result_sha256;
    authority.checkpoint_sha256 = contract.checkpoint_sha256;
    authority.completed_cycles = contract.completed_cycles;
    authority.mechanism_pass = mechanism_pass;
    authority.periodic_steady_state = periodic_pass;
    authority.strict_table4_reproduction = false;
    authority.resume_policy = contract.resume_policy;
end

function path = resolve_inside_repo(repo_root, relative_path)
    relative_path = strrep(char(string(relative_path)), '/', filesep);
    path = char(java.io.File(fullfile(repo_root, relative_path)).getCanonicalPath());
    canonical_root = char(java.io.File(repo_root).getCanonicalPath());
    assert(startsWith(lower(path), [lower(canonical_root), filesep]), ...
        'HeatDriveECC:FreezePathEscape', ...
        'Freeze-contract path escapes the repository: %s', relative_path);
end

function hash = powershell_sha256(path)
    escaped = strrep(path, '''', '''''');
    script = sprintf([ ...
        '$s=[IO.File]::OpenRead(''%s'');try{', ...
        '$h=[Security.Cryptography.SHA256]::Create();', ...
        '[BitConverter]::ToString($h.ComputeHash($s)).Replace(''-'','''')', ...
        '}finally{$s.Dispose()}'], escaped);
    encoded = matlab.net.base64encode(unicode2native(script, 'UTF-16LE'));
    command = sprintf([ ...
        'powershell -NoProfile -NonInteractive -EncodedCommand %s'], ...
        encoded);
    [status, output] = system(command);
    assert(status == 0, 'HeatDriveECC:HashCommandFailed', ...
        'Unable to compute SHA-256 for %s.', path);
    hash = upper(strtrim(output));
end

function out = merge_structs(out, overrides)
    names = fieldnames(overrides);
    for idx = 1:numel(names)
        out.(names{idx}) = overrides.(names{idx});
    end
end
