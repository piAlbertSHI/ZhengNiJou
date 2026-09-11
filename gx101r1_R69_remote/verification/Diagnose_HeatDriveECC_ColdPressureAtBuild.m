function report = Diagnose_HeatDriveECC_ColdPressureAtBuild(repo, output_root)
% Read-only build diagnostic for the t=0 thermal-liquid pressure assertion.
    arguments
        repo (1,1) string
        output_root (1,1) string
    end
    assert(isfolder(repo), 'Repository does not exist.');
    assert(~isfolder(output_root), 'Do not overwrite diagnostic evidence.');
    mkdir(output_root);
    old = pwd;
    cleanup = onCleanup(@()cd(old));
    cd(repo);
    options = Build_HeatDriveECC_EighthRound_Defaults(struct());
    options.simulation.persist_model_configuration = false;
    [model, options] = Build_HeatDriveECC_EighthRound_Simulink_Model(options);
    cleanup_model = onCleanup(@()close_without_save(model));
    report = struct('schema','heatdrive_ecc_cold_pressure_build_diagnostic_v1', ...
        'model',model,'network_absolute_pressure_MPa',options.branch.network_absolute_pressure_MPa, ...
        'pressure_sources',{{}},'blocks',{{}},'solver_settings',struct(), ...
        'base_workspace',struct());
    base_names = {'tank_pressure_MPa','pressure_differential_MPa', ...
        'pressure_differential_MPa_initial_guess_source', ...
        'pressure_differential_MPa_uncached', ...
        'pressure_differential_MPa_analytic_guess', ...
        'pressure_differential_MPa_cached_guess', ...
        'mdot_source_kgps','mdot_root_source_kgps','Q_source_m3ps', ...
        'pressure_pi_bias_MPa','pressure_pi_dp_guess_MPa', ...
        'pressure_pi_bias_ref_MPa'};
    for key = base_names
        try report.base_workspace.(key{1}) = evalin('base',key{1}); catch, end
    end
    solvers = find_system(model,'LookUnderMasks','all','FollowLinks','on', ...
        'MaskType','Solver Configuration');
    assert(isscalar(solvers),'Expected one coupled solver.');
    for name = {'Solver','RelTol','AbsTol','MaxStep','InitialStep','SimulationMode', ...
            'StopTime','SolverResetMethod','MaxOrder'}
        key=name{1};
        try report.solver_settings.(key)=get_param(model,key); catch, end
    end
    sources = find_system(model,'LookUnderMasks','all','FollowLinks','on', ...
        'MaskType','Pressure Source (TL)');
    for k=1:numel(sources)
        item=struct('path',sources{k},'mask',get_param(sources{k},'MaskType'), ...
            'parameters',struct());
        dp=get_param(sources{k},'DialogParameters');
        for key=fieldnames(dp).'
            try item.parameters.(key{1})=get_param(sources{k},key{1}); catch, end
        end
        report.pressure_sources{end+1}=item;
    end
    candidates = {'ColdFluidBuffer','HotFluidBuffer','SHEXFluidBuffer','SMAHotFluidBuffer', ...
        'SE/HoldPipe_001','SE/HoldPipe_002','SMA/CooldownPipe_001','SMA/HeatupPipe_001'};
    for k=1:numel(candidates)
        path=[model '/' candidates{k}];
        if getSimulinkBlockHandle(path)<0, continue; end
        item=struct('path',path,'parameters',struct());
        dp=get_param(path,'DialogParameters');
        for key=fieldnames(dp).'
            try item.parameters.(key{1})=get_param(path,key{1}); catch, end
        end
        report.blocks{end+1}=item;
    end
    write_json(fullfile(output_root,'pressure_build_diagnostic.json'),report);
    fprintf('%s\n',jsonencode(report));
end

function close_without_save(model)
    if bdIsLoaded(model)
        set_param(model,'Dirty','off');
        close_system(model,0);
    end
end

function write_json(path,value)
    fid=fopen(path,'w'); assert(fid>0,'Cannot write report.');
    cleanup=onCleanup(@()fclose(fid));
    fprintf(fid,'%s\n',jsonencode(value));
end
