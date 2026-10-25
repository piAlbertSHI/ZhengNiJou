function record=Run_HeatDriveECC_SinglePipeHeatStep(repo, source_root, folder)
% Independent native/probe pipe comparison. No production model or state load.
    assert(~isfolder(folder),'Never overwrite a fixture.');mkdir(folder);
    old=pwd;oldpath=path;restore=onCleanup(@() restore_path(old,oldpath));
    generation=Simulink.fileGenControl('getConfig');
    restore_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(folder,'cache'), ...
        'CodeGenFolder',fullfile(folder,'codegen'),'createDir',true);
    record=struct('schema','heatdrive_ecc_single_pipe_heat_step_v1','collection_pass',false, ...
        'production_model_loaded',false,'production_state_loaded',false,'checkpoint_saved',false, ...
        'production_recovery_allowed',false,'coupled_model_validated',false, ...
        'error_identifier','','error_message','','cases',{{}});
    try
        [code,commit]=system('git rev-parse HEAD');assert(code==0);record.execution_commit=strtrim(commit);
        configuration=fullfile(source_root,'conservative','configuration.mat');
        metadata_file=fullfile(source_root,'conservative','inventory_metadata.json');
        record.configuration_sha256=file_hash(configuration);
        record.inventory_metadata_sha256=file_hash(metadata_file);
        saved=load(configuration,'options');o=saved.options;
        metadata=jsondecode(fileread(metadata_file));
        assert(o.node_count==21 && o.branch.pipe_dynamic_compressibility==false);
        builder=fullfile(repo,'Build_HeatDriveECC_EighthRound_Simulink_Model.m');
        record.property_transport_vector_source_sha256=file_hash(builder);
        assert(strcmp(record.property_transport_vector_source_sha256, ...
            'F9E8437055F63739609CA8940E61AB7B5BD61B391EF1E29C24DED6F40726E78B'), ...
            'Recheck manually transcribed transport vectors if source changes.');
        source=fullfile(matlabroot,'toolbox','physmod','simscape','library','m', ...
            '+foundation','+thermal_liquid','+elements','pipe.ssc');
        record.native_source_sha256=file_hash(source);
        assert(strcmp(record.native_source_sha256, ...
            'CC478BAB8A9B5DD6156ACE2239BF837FE0849843EF5BDBFE6F55C315343FAC3E'));
        text=fileread(source);header='component pipe';visibility='intermediates (Access = private, ExternalAccess = none)';
        assert(count(text,header)==1 && count(text,visibility)==1);
        probe=strrep(text,header,'component observed_pipe');
        probe=strrep(probe,visibility,'intermediates (Access = private)');
        anchor='    Q_cond = k_I * surface_area / Dh * (H.T - T_I);';
        assert(count(probe,anchor)==1);
        additions=sprintf('\n    probe_wall_T = H.T;\n    probe_A_T = A.T;\n    probe_B_T = B.T;');
        probe=strrep(probe,anchor,[anchor additions]);
        undo=strrep(probe,[anchor additions],anchor);
        % Compare the whole generated source after removing only the declared aliases.
        renamed=strrep(text,header,'component observed_pipe');
        assert(strcmp(strrep(renamed,visibility,'intermediates (Access = private)'),undo), ...
            'Probe modified an equation rather than logging visibility.');
        build=fullfile(folder,'component_build');mkdir(build);
        package=fullfile(build,'+ecc_pipe_probe');mkdir(package);
        generated=fullfile(package,'observed_pipe.ssc');write_text(generated,probe);
        record.probe_source_sha256=file_hash(generated);
        record.probe_recipe='component rename, one private visibility declaration, three read-only port-temperature aliases';
        cd(build);ssc_build('ecc_pipe_probe');addpath(build);load_system('ecc_pipe_probe_lib');cd(repo);
        candidates=find_system('ecc_pipe_probe_lib','SearchDepth',1,'Type','Block');
        candidates=setdiff(candidates,{'ecc_pipe_probe_lib'});assert(isscalar(candidates));
        model='ecc_single_pipe_heat_step';assert(~bdIsLoaded(model));
        for material={'SMA','SE'}
            name=material{1};prefix=lower(name);
            new_system(model);model_cleanup=onCleanup(@() close_system(model,0));
            add_block('fl_lib/Thermal Liquid/Utilities/Thermal Liquid Settings (TL)',[model '/Settings']);
            fluid_record=configure_fluid([model '/Settings'],metadata.settings_tables,name);
            add_block('nesl_utility/Solver Configuration',[model '/Solver']);
            add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference',[model '/Reference']);
            add_block('fl_lib/Thermal/Thermal Sources/Controlled Temperature Source',[model '/Wall']);
            add_block('nesl_utility/Simulink-PS Converter',[model '/WallPS'],'Unit','K');
            add_block('simulink/Sources/Step',[model '/WallStep'], ...
                'Time','.02','Before','303.15','After','308.15');
            add_line(model,'WallStep/1','WallPS/1');
            p=get_param([model '/WallPS'],'PortHandles');q=get_param([model '/Wall'],'PortHandles');
            add_line(model,p.RConn(1),q.RConn(1));
            simscape.addConnection([model '/Wall'],'B',[model '/Reference'],only_port([model '/Reference']));
            for reservoir={'Inlet','Outlet'}
                block=[model '/' reservoir{1}];
                add_block('fl_lib/Thermal Liquid/Elements/Reservoir (TL)',block);
                set_param(block,'pressure_spec','foundation.enum.pressure_spec.specified', ...
                    'reservoir_pressure',num2str(o.branch.network_absolute_pressure_MPa,17), ...
                    'reservoir_pressure_unit','MPa','reservoir_temperature','303.15','reservoir_temperature_unit','K');
            end
            simscape.addConnection([model '/Inlet'],'A',[model '/Settings'],only_port([model '/Settings']));
            simscape.addConnection([model '/Inlet'],'A',[model '/Solver'],only_port([model '/Solver']));
            area=o.branch.([prefix '_pipe_flow_area_m2']);
            length=o.branch.([prefix '_pipe_length_m'])/o.node_count;
            diameter=o.branch.([prefix '_pipe_hydraulic_diameter_m']);nu=o.branch.([prefix '_pipe_Nu']);
            for arm={'Native','Probe'}
                kind=arm{1};pipe=[model '/' kind];flow=[pipe 'Flow'];
                library='fl_lib/Thermal Liquid/Elements/Pipe (TL)';
                if strcmp(kind,'Probe'),library=candidates{1};end
                add_block(library,pipe);
                set_param(pipe,'length',num2str(length,17),'length_unit','m', ...
                    'area',num2str(area,17),'area_unit','m^2','Dh',num2str(diameter,17),'Dh_unit','m', ...
                    'length_add','0','length_add_unit','m','Nu_lam',num2str(nu,17), ...
                    'dynamic_compressibility','false','p_nominal',num2str(o.branch.network_absolute_pressure_MPa,17), ...
                    'p_nominal_unit','MPa','T_nominal','293.15','T_nominal_unit','K','T0','303.15','T0_unit','K');
                add_block('fl_lib/Thermal Liquid/Sources/Flow Rate Source (TL)',flow);
                set_param(flow,'source_type','foundation.enum.constant_controlled.constant', ...
                    'flow_type','foundation.enum.mass_volumetric_flow.mass', ...
                    'mass_flow','0','mass_flow_unit','kg/s','power_spec','foundation.enum.power_spec.none');
                simscape.addConnection([model '/Inlet'],'A',flow,'A');
                simscape.addConnection(flow,'B',pipe,'A');
                simscape.addConnection(pipe,'B',[model '/Outlet'],'A');
                simscape.addConnection(pipe,'H',[model '/Wall'],'A');
            end
            set_param([model '/Solver'],'UseLocalSolver','on', ...
                'LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER','LocalSolverSampleTime','.001');
            set_param(model,'Solver','ode3','FixedStep','.001','StartTime','0','StopTime','.1', ...
                'SimulationMode','normal','ReturnWorkspaceOutputs','on','SaveTime','off','SaveOutput','off', ...
                'SaveState','off','SaveFinalState','off','LoadInitialState','off', ...
                'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off','SimscapeLogToSDI','off');
            mdot=o.branch.(['m_dot_' prefix '_the_kg_per_s']);
            for flow=[-mdot 0 mdot]
                for delta=[-5 5]
                    set_param([model '/NativeFlow'],'mass_flow',num2str(flow,17));
                    set_param([model '/ProbeFlow'],'mass_flow',num2str(flow,17));
                    set_param([model '/WallStep'],'After',num2str(303.15+delta,17));
                    elapsed=tic;output=sim(model);seconds=toc(elapsed);
                    native=simscape.logging.findNode(output.simlog,[model '/Native']);
                    observed=simscape.logging.findNode(output.simlog,[model '/Probe']);
                    common={'T_I','p_I','u_I','rho_I','Phi_A','Phi_B','Q_H','mdot_A','mdot_B'};
                    extra={'Q_conv','Q_cond','cp_I','mu_I','k_I','Pr_I','Re_avg', ...
                        'probe_wall_T','probe_A_T','probe_B_T'};
                    native_traces=extract(native,common);probe_traces=extract(observed,[common extra]);
                    comparisons=cell(size(common));
                    for k=1:numel(common)
                        a=native_traces{k};b=probe_traces{k};
                        assert(isequal(a.time_s,b.time_s) && strcmp(a.unit,b.unit));
                        difference=max(abs(a.values-b.values),[],'all');
                        allowance=1e-10*max(1,max(abs(a.values),[],'all'));
                        assert(difference<=allowance,'Logging probe changed native trajectory: %s',common{k});
                        comparisons{k}=struct('name',common{k},'maximum_difference',difference,'allowance',allowance);
                    end
                    t=native_traces{1}.time_s;assert(t(1)==0 && abs(t(end)-.1)<1e-12);
                    row=struct('material',name,'mass_flow_command_kgps',flow,'wall_step_K',delta, ...
                        'initial_temperature_K',303.15,'step_time_s',.02,'fixed_step_s',.001, ...
                        'stop_time_s',.1,'simulation_wall_seconds',seconds,'area_m2',area,'length_m',length, ...
                        'Dh_m',diameter,'saved_Nu',nu,'surface_area_m2',4*area/diameter*length, ...
                        'fluid_settings',fluid_record,'native_probe_comparisons',{comparisons}, ...
                        'native_probe_equivalence_pass',true,'power_spec','none','production_recovery_allowed',false);
                    file=sprintf('case_%02d.mat',numel(record.cases)+1);record_json=jsonencode(row);
                    save(fullfile(folder,file),'native_traces','probe_traces','record_json','-v7.3');
                    row.file=file;row.sha256=file_hash(fullfile(folder,file));record.cases{end+1}=row;
                    write_text(fullfile(folder,'completed_case_progress.json'),jsonencode(struct( ...
                        'completed_cases',numel(record.cases),'last_measured_time_s',t(end), ...
                        'simulation_completed',false,'checkpoint_saved',false)));
                    clear output native observed native_traces probe_traces
                end
            end
            clear model_cleanup
        end
        assert(strcmp(file_hash(source),record.native_source_sha256),'Installed library changed.');
        record.collection_pass=numel(record.cases)==12;
        record.passive_probe_equivalence_pass=all(cellfun(@(c) c.native_probe_equivalence_pass,record.cases));
        record.scientific_gate_or_reference_equivalence_pass_claimed=false;
    catch exception
        record.error_identifier=exception.identifier;
        record.error_message=getReport(exception,'extended','hyperlinks','off');
    end
    write_text(fullfile(folder,'single_pipe_execution.json'),jsonencode(record,'PrettyPrint',true));
    fprintf('FINAL_JSON=%s\n',jsonencode(struct('collection_pass',record.collection_pass, ...
        'completed_cases',numel(record.cases),'error_message',record.error_message,'production_recovery_allowed',false)));
    assert(record.collection_pass,'HeatDriveECC:SinglePipeHeatStepFailed','%s',record.error_message);
end

function result=configure_fluid(block,settings,name)
    if iscell(settings),settings=[settings{:}];end
    water=endsWith({settings.block_path},'/SMA_ThermalLiquidSettings');
    selected=settings(water==strcmp(name,'SMA'));assert(isscalar(selected));p=selected.parameters;
    fields=fieldnames(p);
    for k=1:numel(fields)
        key=fields{k};
        if startsWith(key,'cp_TLU_5'),continue;end % Inactive under the saved u-vector parameterization.
        set_param(block,key,p.(key));
    end
    if strcmp(name,'SMA')
        viscosity=[1.790149606;1.305308358;1.002847726;.8003847494;.6576599304;.5530269976; ...
            .4739457078;.4127054691;.3643312332;.3254838619;.2938478789;.2677732136;.2460564680;.2278024090;.2123334626];
        conductivity=[555.9805115;579.0574270;598.2630374;614.6297471;628.7193807;640.8549223; ...
            651.2352248;659.9939082;667.2300958;673.0243742;677.4468439;680.5609271;682.4249382;683.0925227;682.6125620];
    else
        density=[1066.03926666667;1055.38;1039.77;1023.55;1004.39;977.53];
        viscosity=[43.3230278575076;7.2173;2.2389;1.1762;.7462;.5084]./density*1000;
        conductivity=[365.406333333333;393.6;415;426.2;431.3;429.4];
    end
    set_param(block,'nu_TLU_2',mat2str(viscosity,15),'nu_TLU_2_unit','mm^2/s', ...
        'k_TLU_2',mat2str(conductivity,15),'k_TLU_2_unit','mW/(m*K)', ...
        'p_atm','.5','p_atm_unit','MPa','properties_range_check','simscape.enum.assert.action.error');
    result=struct('source_settings',selected.block_path,'saved_inventory_parameters',p, ...
        'kinematic_viscosity_mm2_per_s',viscosity,'thermal_conductivity_mW_per_mK',conductivity, ...
        'cp_policy','derived from active u vector by original settings block, not inactive cp_TLU_5');
end

function rows=extract(node,names)
    rows=cell(size(names));
    for k=1:numel(names)
        series=node.child(names{k}).series;t=double(time(series));v=double(values(series));
        assert(all(isfinite(v),'all') && all(isfinite(t)) && all(diff(t)>=0) && any(diff(t)>0));
        rows{k}=struct('name',names{k},'unit',series.unit,'time_s',t(:),'values',v);
    end
end

function name=only_port(block)
    ports=simscape.connectionPortProperties(block);assert(isscalar(ports));name=ports.Name;
end

function hash=file_hash(file)
    digest=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));
    while ~feof(fid),digest.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end

function write_text(file,text)
    fid=fopen(file,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',text);
end

function restore_path(folder,oldpath)
    cd(folder);path(oldpath);
end
