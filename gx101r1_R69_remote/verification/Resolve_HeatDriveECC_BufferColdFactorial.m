function options=Resolve_HeatDriveECC_BufferColdFactorial(options,state_mode,cycles,duration,arm,endpoint_all)
% Explicit cold-only factors; an empty struct leaves the legacy runner unchanged.
    assert(isstruct(options) && isscalar(options),'Require scalar buffer-factor options.');
    if isempty(fieldnames(options)),return;end
    assert(isequal(sort(fieldnames(options)),sort({'geometry';'precision';'component_audit_path'})), ...
        'Unknown or incomplete cold buffer factors.');
    assert(strcmp(state_mode,'off') && cycles==1 && duration==10 && strcmp(arm,'native') && endpoint_all, ...
        'Buffer factors are a new cold ten-second experiment, never checkpoint recovery.');
    options.geometry=char(string(options.geometry));options.precision=char(string(options.precision));
    assert(ismember(options.geometry,{'inherited','sma_pipe_matched'}) && ...
        ismember(options.precision,{'inherited','local_tight'}),'Unknown cold factor level.');
    proof=jsondecode(fileread(options.component_audit_path));
    assert(strcmp(proof.schema,'heatdrive_ecc_buffer_geometry_fixture_audit_v1') && ...
        proof.isolated_component_equations_pass && proof.observed_area_response_monotone && ...
        numel(proof.cases)==8 && all([proof.cases.component_equation_pass]) && ...
        ~proof.production_recovery_allowed && ~proof.checkpoint_qualified, ...
        'Require passed isolated component evidence, not failed fixture output.');
    assert(~isfile(fullfile(proof.source_root,'REJECTED_DO_NOT_RESUME.json')), ...
        'A rejected component experiment cannot authorize construction.');
    source=fullfile(proof.source_root,'fixture_execution.json');
    assert(strcmp(file_hash(source),proof.input_sha256.fixture_execution),'Component evidence changed.');
end

function result=file_hash(file)
    md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),md.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
