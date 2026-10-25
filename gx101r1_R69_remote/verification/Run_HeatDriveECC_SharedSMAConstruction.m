function result=Run_HeatDriveECC_SharedSMAConstruction(repo, source_root, seed_zip, folder)
% Construct and export an isolated topology. No simulation/OP/large state data.
    assert(~isfolder(folder),'Never reuse an experiment directory.');mkdir(folder);
    old=pwd;oldpath=path;cleanup=onCleanup(@() restore(old,oldpath));
    generation=Simulink.fileGenControl('getConfig');
    generation_cleanup=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(folder,'cache'), ...
        'CodeGenFolder',fullfile(folder,'codegen'),'createDir',true);
    result=struct('schema','heatdrive_ecc_shared_SMA_constructor_execution_v1', ...
        'construction_complete',false,'simulated',false,'compiled',false, ...
        'checkpoint_loaded',false,'production_recovery_allowed',false);
    try
        cd(repo);addpath(repo,fullfile(repo,'verification'));
        [code,commit]=system('git rev-parse HEAD');assert(code==0);result.execution_commit=strtrim(commit);
        assert(~bdIsLoaded('heatdrive_ecc_coupled_se21'),'Never close another loaded model.');
        cfg=fullfile(source_root,'conservative','configuration.mat');
        assert(strcmp(file_hash(cfg),'82A096E37867063D357C138B4C97EEC13234B9CC659B8135891D47C55C4D4256'));
        result.input_dependencies=struct('configuration_path',cfg,'configuration_sha256',file_hash(cfg), ...
            'seed_zip',seed_zip,'seed_zip_sha256',file_hash(seed_zip));
        protected=fullfile(repo,'heatdrive_ecc_coupled_se21.slx');protected_hash=file_hash(protected);
        unzip(seed_zip,fullfile(folder,'seed'));
        isolated=fullfile(folder,'seed','gx101r1_R69_remote','heatdrive_ecc_coupled_se21.slx');
        assert(isfile(isolated));isolated_hash=file_hash(isolated);
        saved=load(cfg,'options');o=saved.options;
        o.model_path=isolated;o.cycle_count=1;o.simulation.stop_time_s=.01;
        o.simulation.persist_model_configuration=false;o.simulation.resume_checkpoint_path='';
        library=o.branch.independent_conservative_chamber_library;
        assert(o.branch.independent_conservative_chamber_diagnostic && strcmp(library,'ecc_inventory_specific_lib'), ...
            'Load the same retained chamber library, not an alternative storage formulation.');
        build=fullfile(source_root,'component_build');
        library_path=fullfile(build,[library '.slx']);
        component_path=fullfile(build,'+ecc_inventory_specific','conservative_chamber.ssc');
        assert(isfile(library_path) && isfile(component_path));
        result.retained_chamber_library=struct('path',library_path,'sha256',file_hash(library_path), ...
            'component_path',component_path,'component_sha256',file_hash(component_path),'rebuilt',false);
        addpath(build);load_system(library_path);
        library_cleanup=onCleanup(@() close_system(library,0));
        % Current folder precedes the MATLAB path: keep the isolated model's
        % folder current rather than suppressing a model-shadowing warning.
        cd(fileparts(isolated));
        model_cleanup=onCleanup(@() close_isolated(o.model_name,isolated));
        [model,options]=Build_HeatDriveECC_EighthRound_Simulink_Model(o);
        assert(strcmp(get_param(model,'SimulationStatus'),'stopped'));
        set_param(model,'LoadInitialState','off','SaveState','off','SaveFinalState','off');
        before_tl=Export_HeatDriveECC_TLConnectivity(model);
        before_th=Export_HeatDriveECC_TLConnectivity(model,'foundation.thermal.thermal');
        write_json(fullfile(folder,'before_tl.json'),before_tl);
        write_json(fullfile(folder,'before_thermal.json'),before_th);
        change=Apply_HeatDriveECC_SharedSMAFluidDiagnostic(model,isolated,before_tl,before_th);
        write_json(fullfile(folder,'intervention.json'),change);
        write_json(fullfile(folder,'after_tl.json'),Export_HeatDriveECC_TLConnectivity(model));
        write_json(fullfile(folder,'after_thermal.json'), ...
            Export_HeatDriveECC_TLConnectivity(model,'foundation.thermal.thermal'));
        parent=[model '/SMA'];
        blocks=find_system(parent,'SearchDepth',1,'Type','Block');
        destinations={'SharedSMAActiveThermalGate/1','SharedSMAActiveThermalGate/2','HoldThermalGateCommandPS/1'};
        source_names=cell(1,3);
        for i=1:3
            parts=strsplit(destinations{i},'/');p=get_param([parent '/' parts{1}],'PortHandles');
            line=get_param(p.Inport(str2double(parts{2})),'Line');
            source_names{i}=getfullname(get_param(line,'SrcBlockHandle'));
        end
        result.construction_complete=true;result.intervention=change;
        result.retained_SMA_blocks=blocks;result.actual_gate_input_sources=source_names;
        result.actual_gate_function=get_param([parent '/SharedSMAActiveThermalGate'],'Function');
        result.gate_command_variables={get_param([parent '/HoldThermalGateCommandFromWorkspace'],'VariableName'), ...
            get_param([parent '/CooldownThermalGateCommandFromWorkspace'],'VariableName')};
        result.original_dual_route_builder_audit_not_reused=true;
        result.shared_diagnostic_structural_review_pending=true;
        result.new_compile_and_switch_simulation_still_required=true;
        result.parameter_source_role='constructor parameters only; no old state coordinates';
        result.node_count=options.node_count;
        assert(strcmp(file_hash(protected),protected_hash) && strcmp(file_hash(isolated),isolated_hash), ...
            'Construction must not save changes to either disk model.');
        result.protected_model_disk_sha256=protected_hash;
        result.isolated_seed_model_sha256=isolated_hash;
        result.source_sha256=struct('applicator',file_hash(fullfile(repo,'verification', ...
            'Apply_HeatDriveECC_SharedSMAFluidDiagnostic.m')), ...
            'runner',file_hash([mfilename('fullpath') '.m']));
        write_json(fullfile(folder,'construction_execution.json'),result);
    catch e
        result.error_identifier=e.identifier;result.error_message=e.message;
        result.error_report=getReport(e,'extended','hyperlinks','off');
        write_json(fullfile(folder,'FAILED_DO_NOT_RESUME.json'),result);rethrow(e);
    end
    disp(jsonencode(struct('construction_complete',true,'simulated',false,'folder',folder, ...
        'single_bed_volume_m3',change.single_bed_volume_m3,'production_recovery_allowed',false)));
end

function close_isolated(name,file)
    if bdIsLoaded(name)
        actual=char(java.io.File(get_param(name,'FileName')).getCanonicalPath());
        assert(strcmpi(actual,char(java.io.File(file).getCanonicalPath())));
        close_system(name,0);
    end
end

function restore(old,oldpath)
    cd(old);path(oldpath);
end

function h=file_hash(p)
    fid=fopen(p,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    md=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(fid),md.update(fread(fid,1048576,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end

function write_json(p,r)
    assert(~isfile(p),'Never overwrite diagnostic evidence.');
    fid=fopen(p,'w','n','UTF-8');assert(fid>=0);c=onCleanup(@() fclose(fid));
    fprintf(fid,'%s',jsonencode(r,'PrettyPrint',true));
end
