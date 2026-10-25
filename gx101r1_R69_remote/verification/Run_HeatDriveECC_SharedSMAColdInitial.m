function result=Run_HeatDriveECC_SharedSMAColdInitial(repo, source_root, seed_zip, folder, requested_arm)
% Fresh, matched-bed-temperature native initialization; no old OP or seed.
    if nargin<5,requested_arm='both';end
    assert(ismember(requested_arm,{'dual','shared','both'}));
    assert(~isfolder(folder),'Never overwrite an experiment.');mkdir(folder);
    old=pwd;oldpath=path;restore=onCleanup(@() restore_path(old,oldpath));
    generation=Simulink.fileGenControl('getConfig');
    restore_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(folder,'cache'), ...
        'CodeGenFolder',fullfile(folder,'codegen'),'createDir',true);
    result=struct('schema','heatdrive_ecc_shared_SMA_cold_initial_execution_v1', ...
        'collection_complete',false,'production_recovery_allowed',false, ...
        'checkpoint_loaded_or_saved',false,'stop_time_s',.01,'completed_arms',{{}});
    protected=fullfile(repo,'heatdrive_ecc_coupled_se21.slx');protected_hash=file_hash(protected);
    try
        cd(repo);addpath(repo,fullfile(repo,'verification'));
        [code,commit]=system('git rev-parse HEAD');assert(code==0);result.execution_commit=strtrim(commit);
        % A conservative-arm options struct is NOT a native constructor:
        % its buffer replacements/public targets/flux compensation are later
        % explicit pipeline steps. Use and check the actual native variant.
        cfg=fullfile(source_root,'native','configuration.mat');
        assert(strcmp(file_hash(cfg),'CF93E644F3A09DE7A21337BF7F7E83FDDA654E81693F9DCCF5D91D3B2EAAC384'));
        saved=load(cfg,'options');o=saved.options;
        assert(~o.branch.independent_conservative_chamber_diagnostic, ...
            'Native cold probe cannot silently construct a conservative arm without its initialization pipeline.');
        source_execution=fullfile(source_root,'cold_chamber_execution.json');
        recipe=jsondecode(fileread(source_execution));assert(recipe.collection_pass && recipe.cycle_count==20);
        result.input_dependencies=struct('configuration_path',cfg,'configuration_sha256',file_hash(cfg), ...
            'source_execution_path',source_execution,'source_execution_sha256',file_hash(source_execution), ...
            'seed_zip',seed_zip,'seed_zip_sha256',file_hash(seed_zip));
        result.hydraulic_storage_variant='native_foundation_chambers_and_buffers';
        result.conservative_variant_or_its_old_initial_state_replayed=false;
        result.source_sha256=struct('runner',file_hash([mfilename('fullpath') '.m']), ...
            'applicator',file_hash(fullfile(repo,'verification','Apply_HeatDriveECC_SharedSMAFluidDiagnostic.m')), ...
            'observer',file_hash(fullfile(repo,'verification','HeatDriveECC_ShortColdTimeObserver.m')), ...
            'observer_delegate',file_hash(fullfile(repo,'verification','HeatDriveECC_ProcessLocalTimeObserver.m')));
        arms={'dual','shared'};if ~strcmp(requested_arm,'both'),arms={requested_arm};end
        for a=1:numel(arms)
            name=arms{a};arm=fullfile(folder,name);mkdir(arm);
            unzip(seed_zip,fullfile(arm,'seed'));
            isolated=fullfile(arm,'seed','gx101r1_R69_remote','heatdrive_ecc_coupled_se21.slx');
            assert(isfile(isolated));isolated_hash=file_hash(isolated);
            assert(~bdIsLoaded(o.model_name),'Never close another loaded model.');
            cd(fileparts(isolated));o.model_path=isolated;o.cycle_count=1;
            o.simulation.stop_time_s=.01;o.simulation.persist_model_configuration=false;
            o.simulation.resume_checkpoint_path='';
            model_cleanup=onCleanup(@() close_isolated(o.model_name,isolated));
            [model,options]=Build_HeatDriveECC_EighthRound_Simulink_Model(o);
            assert(~options.branch.independent_conservative_chamber_diagnostic);
            assert(options.branch.se_distributed_pressure_feedforward_diagnostic, ...
                'Require the explicit distributed controller of the saved native source.');
            ff=Configure_HeatDriveECC_DistributedPressureFeedforward(model,options);
            assert(numel(ff.sources)==21);
            write_json(fullfile(arm,'distributed_pressure_ff_contract.json'),ff);
            set_param(model,'LoadInitialState','off','SaveState','off','SaveFinalState','off', ...
                'SaveOperatingPoint','off','StartTime','0','StopTime','.01', ...
                'SimulationMode','normal','ReturnWorkspaceOutputs','on','SaveTime','on','TimeSaveName','tout', ...
                'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off','SimscapeLogToSDI','off');
            if strcmp(name,'shared')
                tl=Export_HeatDriveECC_TLConnectivity(model);
                th=Export_HeatDriveECC_TLConnectivity(model,'foundation.thermal.thermal');
                intervention=Apply_HeatDriveECC_SharedSMAFluidDiagnostic(model,isolated,tl,th);
                write_json(fullfile(arm,'intervention.json'),intervention);
            end
            % Fresh IC only. Do not lower Tshex or rewrite a resumed state.
            paths=find_system([model '/SMA'],'SearchDepth',1,'RegExp','on', ...
                'Name','^(Hold|Cooldown)Pipe_[0-9]{3}$');
            expected=42;if strcmp(name,'shared'),expected=21;end
            assert(numel(paths)==expected);initial=cell(1,numel(paths));
            for k=1:numel(paths)
                p=paths{k};initial{k}=struct('block_path',p,'old_T0_expression',get_param(p,'T0'), ...
                    'declared_new_T0_K',options.system.T0_K,'T0_priority','native high, unchanged');
                set_param(p,'T0',num2str(options.system.T0_K,17),'T0_unit','K');
                assert(slResolve(get_param(p,'T0'),p)==303.15);
            end
            [geometry,fluid_tables]=inventory_contract(model,paths);
            preflight=struct('arm',name,'fresh_initial_temperature_only',true, ...
                'matched_bed_T0_K',options.system.T0_K,'Tshex_K',options.system.Tshex_K, ...
                'Thhex_K',options.system.Thhex_K,'Tchex_K',options.system.Tchex_K, ...
                'initialization_intervention',{initial},'pipe_geometry',{geometry},'fluid_tables',fluid_tables, ...
                'local_solver_step_s',options.simscape.local_solver_sample_time_s, ...
                'hydraulic_storage_variant',result.hydraulic_storage_variant, ...
                'actual_distributed_temperature_source_count',numel(ff.sources), ...
                'actual_constitutive_step_function',get_param([model '/ECC_Constitutive21_VectorStep'],'MATLABFcn'), ...
                'global_solver',get_param(model,'Solver'),'production_recovery_allowed',false, ...
                'native_pipe_source_sha256',file_hash(fullfile(matlabroot,'toolbox','physmod','simscape','library','m', ...
                '+foundation','+thermal_liquid','+elements','pipe.ssc')));
            assert(options.simscape.local_solver_enabled && options.simscape.local_solver_sample_time_s==.001);
            write_json(fullfile(arm,'cold_preflight.json'),preflight);
            observer=[model '/SharedSMAColdTimeObserver'];
            add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function',observer, ...
                'FunctionName','HeatDriveECC_ShortColdTimeObserver','Parameters','');
            HeatDriveECC_ObserverContext('register',model,fullfile(arm,'solver_time.json'));
            elapsed=tic;input=Simulink.SimulationInput(model);
            output=sim(input.setModelParameter('CaptureErrors','on'));wall=toc(elapsed);
            if ~isempty(output.ErrorMessage)
                failure=struct('arm',name,'simulation_wall_seconds',wall,'error_message',output.ErrorMessage, ...
                    'production_recovery_allowed',false,'raw_complete_observations_available',false);
                if ismember('tout',output.who),failure.returned_time_s=double(output.tout);end
                write_json(fullfile(arm,'simulation_error.json'),failure);
                error('HeatDriveECC:SharedSMAColdInitialFailure', ...
                    'Native simulation failed. Full error is in simulation_error.json. %s', ...
                    output.ErrorMessage(1:min(500,numel(output.ErrorMessage))));
            end
            rows={};
            fields={'T_I','p_I','u_I','rho_I','Phi_A','Phi_B','Q_H','mdot_A','mdot_B'};
            units={'K','Pa','J/kg','kg/m^3','W','W','W','kg/s','kg/s'};
            for k=1:numel(paths)
                node=simscape.logging.findNode(output.simlog,paths{k});
                rows=[rows extract(node,paths{k},fields,units)]; %#ok<AGROW>
            end
            for part={'SMA','SE'}
                for k=1:21
                    p=sprintf('%s/%s/Subsystem2/NodeMass_%02d',model,part{1},k);
                    rows=[rows extract(simscape.logging.findNode(output.simlog,p),p,{'T'},{'K'})]; %#ok<AGROW>
                end
            end
            for n={'SMA_PumpInletConnectingPipeVolume','SMA_PumpOutletConnectingPipeVolume'}
                p=[model '/' n{1}];node=simscape.logging.findNode(output.simlog,p);
                rows=[rows extract(node,p,fields,units)]; %#ok<AGROW>
            end
            traces=struct('schema','heatdrive_ecc_native_cold_initial_observations_v1', ...
                'arm',name,'series',{rows},'tout_s',double(output.tout), ...
                'constitutive_output',output.get('ECC_constitutive21_output'), ...
                'not_an_OP_or_restart_state',true);
            % Persist each actual arm before any gate, next arm or final manifest.
            raw=fullfile(arm,'selected_observations.json');write_json(raw,traces);
            t=double(output.tout);assert(t(1)==0 && abs(t(end)-.01)<1e-12 && all(diff(t)>=0));
            max_initial_T_error=0;
            for k=1:numel(rows)
                r=rows{k};if strcmp(r.state_name,'T_I') && any(strcmp(r.block_path,paths))
                    assert(r.time_s(1)==0);
                    max_initial_T_error=max(max_initial_T_error,abs(r.values(1)-options.system.T0_K));
                end
            end
            assert(max_initial_T_error<1e-6,'Actual native initialization did not match the declared cold protocol.');
            state=HeatDriveECC_ObserverContext('get',model);assert(state.terminated && abs(state.last_time-.01)<1e-12);
            assert(strcmp(file_hash(protected),protected_hash) && strcmp(file_hash(isolated),isolated_hash));
            completed=struct('arm',name,'actual_stop_time_s',t(end),'simulation_wall_seconds',wall, ...
                'native_pipe_observation_count',numel(paths),'maximum_initial_pipe_temperature_error_K',max_initial_T_error, ...
                'raw_file',raw,'raw_sha256',file_hash(raw),'compiled_and_simulated',true, ...
                'full_mechanism_periodic_or_twenty_cycle_seed_allowed',false);
            write_json(fullfile(arm,'completed_initial_probe.json'),completed);
            result.completed_arms{end+1}=completed;
            clear output rows traces model_cleanup
            HeatDriveECC_ObserverContext('clear',model);
        end
        result.collection_complete=true;result.protected_model_sha256_unchanged=protected_hash;
        write_json(fullfile(folder,'cold_initial_execution.json'),result);
    catch e
        result.error_identifier=e.identifier;result.error_message=e.message;
        result.error_report=getReport(e,'extended','hyperlinks','off');
        write_json(fullfile(folder,'FAILED_DO_NOT_RESUME.json'),result);rethrow(e);
    end
    disp(jsonencode(struct('collection_complete',true,'completed_arms',numel(result.completed_arms), ...
        'stop_time_s',.01,'production_recovery_allowed',false)));
end

function [pipes,fluid]=inventory_contract(model,paths)
    settings=[model '/SMA_ThermalLiquidSettings'];
    source=fullfile(matlabroot,'toolbox','physmod','simscape','library','m', ...
        '+foundation','+thermal_liquid','+utilities','thermal_liquid_settings.ssc');
    source_hash=file_hash(source);
    assert(strcmp(source_hash,'D0B8A66CBD6AFE7BBF14402A78BFE975BCBE009A5817D346CCBC5F64A85E1693'), ...
        'Recheck native 30-pressure-point expansion before using a changed settings source.');
    names={'T_TLU','rho_TLU_4','beta_const_4','p_ref_4','p_min_1D','p_max_1D'};
    fluid=struct();for k=1:numel(names),fluid.(names{k})=slResolve(get_param(settings,names{k}),settings);end
    assert(strcmp(get_param(settings,'T_TLU_unit'),'K') && strcmp(get_param(settings,'rho_TLU_4_unit'),'kg/m^3'));
    assert(strcmp(get_param(settings,'beta_const_4_unit'),'GPa') && strcmp(get_param(settings,'p_ref_4_unit'),'MPa'));
    fluid.pressure_axis_count=30; % Native 1-D settings expansion, not a fitted density.
    fluid.native_settings_source_sha256=source_hash;
    pressure=logspace(log10(fluid.p_min_1D*1e6),log10(fluid.p_max_1D*1e6),30);
    density=fluid.rho_TLU_4(:)*exp((pressure-fluid.p_ref_4*1e6)/(fluid.beta_const_4*1e9));
    pipes=cell(1,numel(paths));
    for k=1:numel(paths)
        p=paths{k};assert(strcmp(get_param(p,'dynamic_compressibility'),'false'));
        assert(strcmp(get_param(p,'area_unit'),'m^2') && strcmp(get_param(p,'length_unit'),'m'));
        assert(strcmp(get_param(p,'p_nominal_unit'),'MPa') && strcmp(get_param(p,'T_nominal_unit'),'K'));
        a=slResolve(get_param(p,'area'),p);l=slResolve(get_param(p,'length'),p);
        pn=slResolve(get_param(p,'p_nominal'),p)*1e6;tn=slResolve(get_param(p,'T_nominal'),p);
        rho=interp2(pressure,fluid.T_TLU(:),density,pn,tn,'linear');assert(isfinite(rho) && rho>0);
        pipes{k}=struct('block_path',p,'volume_m3',a*l,'nominal_temperature_K',tn,'nominal_pressure_Pa',pn, ...
            'native_nominal_density_kg_m3',rho,'mass_inventory_contract','rho_nominal*volume constant; mdot_A+mdot_B=0', ...
            'energy_inventory_contract','rho_nominal*volume*u_I; native quasisteady pipe, not rho_I*volume*u_I');
    end
end

function rows=extract(node,path,names,units)
    rows=cell(1,numel(names));
    for k=1:numel(names)
        series=node.child(names{k}).series;t=double(time(series));native=double(values(series));
        v=value(simscape.Value(native,series.unit),units{k});
        assert(numel(t)==numel(v) && numel(t)<=200000 && all(diff(t)>=0) && all(isfinite(v),'all'));
        rows{k}=struct('block_path',path,'state_name',names{k},'unit',units{k},'time_s',t(:),'values',v(:));
    end
end

function close_isolated(name,file)
    if bdIsLoaded(name)
        assert(strcmpi(char(java.io.File(get_param(name,'FileName')).getCanonicalPath()), ...
            char(java.io.File(file).getCanonicalPath())));close_system(name,0);
    end
end

function restore_path(old,oldpath)
    cd(old);path(oldpath);
end

function h=file_hash(p)
    fid=fopen(p,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));md=java.security.MessageDigest.getInstance('SHA-256');
    while ~feof(fid),md.update(fread(fid,1048576,'*uint8'));end
    h=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end

function write_json(p,r)
    assert(~isfile(p),'Never overwrite diagnostic evidence.');fid=fopen(p,'w','n','UTF-8');assert(fid>=0);
    c=onCleanup(@() fclose(fid));fprintf(fid,'%s',jsonencode(r,'PrettyPrint',true));
end
