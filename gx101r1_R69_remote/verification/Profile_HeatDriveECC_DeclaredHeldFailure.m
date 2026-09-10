function record=Profile_HeatDriveECC_DeclaredHeldFailure(model,output_root,profile_case)
% Capture one declared failed configuration; no repair, restart, or OP export.
    if nargin<3,profile_case='split';end
    assert(any(strcmp(profile_case,{'split','moderate'})),'Undeclared profiling case.');
    expected=struct('Solver','ode23t','RelTol','1e-10','AbsTol','1e-12', ...
        'MinStepSizeMsg','error','MaxConsecutiveMinStep','1','MinStep','auto', ...
        'LoadInitialState','off','SaveOperatingPoint','off');
    if strcmp(profile_case,'moderate'),expected.RelTol='1e-6';expected.AbsTol='1e-8';end
    keys=fieldnames(expected);
    for k=1:numel(keys)
        assert(strcmp(get_param(model,keys{k}),expected.(keys{k})),'Unexpected profiling configuration.');
    end
    assert(str2double(get_param(model,'StartTime'))==0 && str2double(get_param(model,'StopTime'))==.04 && ...
        str2double(get_param(model,'MaxStep'))==.00025,'Profiling may not extend the held window.');
    destination=fullfile(output_root,'solver_profile.mat');
    assert(~isfile(destination),'Do not overwrite profiler evidence.');
    record=struct('profile_case',profile_case,'capture_pass',false,'api_returned',false,'data_file',destination, ...
        'AutoScaleAbsTol_before',get_param(model,'AutoScaleAbsTol'),'expected_settings',expected, ...
        'requested_options',struct('SaveStates','on','SaveSimscapeStates','on','SaveJacobian','on', ...
            'SaveZCSignals','off','OpenSP','off','BufferSize',50000), ...
        'science_gate_pass',false,'full_jacobian_analyzed',false,'production_recovery_allowed',false, ...
        'error_message','','error_report','');
    ids_before=Simulink.sdi.getAllRunIDs;
    clock=tic;
    try
        result=solverprofiler.profileModel(model,'SaveStates','on','SaveSimscapeStates','on', ...
            'SaveJacobian','on','SaveZCSignals','off','OpenSP','off','BufferSize',50000, ...
            'DataFullFile',destination);
        record.api_returned=true;record.api_result=result;
    catch ME
        record.error_message=ME.message;record.error_report=getReport(ME,'extended','hyperlinks','off');
    end
    record.wall_seconds=toc(clock);
    record.AutoScaleAbsTol_after=get_param(model,'AutoScaleAbsTol');
    record.settings_after=struct();
    for k=1:numel(keys),record.settings_after.(keys{k})=get_param(model,keys{k});end
    record.data_file_exists=isfile(destination);
    if record.data_file_exists
        info=dir(destination);record.data_file_bytes=info.bytes;
        digest=java.security.MessageDigest.getInstance('SHA-256');
        fid=fopen(destination,'rb');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
        while ~feof(fid),digest.update(fread(fid,1048576,'*uint8'));end
        clear cleanup
        record.data_sha256=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
        record.mat_file_variables=whos('-file',destination);
    end
    record.capture_pass=record.api_returned && record.data_file_exists && ...
        isequal(record.settings_after,expected) && ...
        strcmp(record.AutoScaleAbsTol_before,record.AutoScaleAbsTol_after);
    record.sdi=Export_HeatDriveECC_ProfilerSDI(model,output_root,ids_before);
    record.capture_pass=record.capture_pass && record.sdi.export_pass;
end
