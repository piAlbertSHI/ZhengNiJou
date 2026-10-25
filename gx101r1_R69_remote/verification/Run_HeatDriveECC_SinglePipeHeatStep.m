function record=Run_HeatDriveECC_SinglePipeHeatStep(repo, source_root, folder, study, integration, observe_energy)
% Independent native/probe pipe comparison. No production model or state load.
    if nargin<4,study='native_probe';end
    if nargin<5,integration='local_BE';end
    if nargin<6,observe_energy=false;end
    assert(any(strcmp(study,{'native_probe','heat_law_reference'})),'Unknown independent study.');
    reference_study=strcmp(study,'heat_law_reference');
    assert(any(strcmp(integration,{'local_BE','global_ODE3'})),'Unknown integration contract.');
    assert(reference_study || strcmp(integration,'local_BE'),'Global integration requires the explicit reference study.');
    assert(islogical(observe_energy) && isscalar(observe_energy));
    assert(~observe_energy || strcmp(integration,'global_ODE3'),'Energy stage observer requires the global study.');
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
    record.study=study;
    record.integration=integration;
    record.one_way_energy_observer_enabled=observe_energy;
    record.reference_heat_laws_independently_integrated=reference_study;
    if reference_study,record.schema='heatdrive_ecc_single_pipe_reference_v1';end
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
        assert(count(text,header)==1);
        renamed=strrep(text,header,'component observed_pipe');
        position=regexp(renamed,'(?m)^intermediates \(Access = private, ExternalAccess = none\)','start');
        assert(isscalar(position),'Require one unindented heat-transfer intermediate section.');
        observable=[renamed(1:position-1) 'intermediates (Access = private)' ...
            renamed(position+numel(visibility):end)];
        probe=observable;
        anchor='    Q_cond = k_I * surface_area / Dh * (H.T - T_I);';
        assert(count(probe,anchor)==1);
        additions=sprintf('\n    probe_wall_T = H.T;\n    probe_A_T = A.T;\n    probe_B_T = B.T;');
        probe=strrep(probe,anchor,[anchor additions]);
        undo=strrep(probe,[anchor additions],anchor);
        % Compare the whole generated source after removing only the declared aliases.
        assert(strcmp(observable,undo), ...
            'Probe modified an equation rather than logging visibility.');
        if observe_energy
            marker='% Internal components that calculate energy convection at ports A and B';
            assert(count(probe,marker)==1);
            observer=sprintf(['variables (Access = private)\n', ...
                '    observer_energy = {value = {0, ''J''}, priority = priority.high};\nend\n', ...
                'equations\n    der(observer_energy) == Phi_A + Phi_B + Q_H;\nend\n\n']);
            original_probe=probe;probe=strrep(probe,marker,[observer marker]);
            assert(strcmp(strrep(probe,observer,''),original_probe) && count(probe,'observer_energy')==2, ...
                'Energy observer is not a strictly one-way added coordinate.');
            record.energy_observer_equation='der(observer_energy)=Phi_A+Phi_B+Q_H; no physical feedback or capacity';
            record.observer_state_is_not_a_production_checkpoint=true;
        end
        build=fullfile(folder,'component_build');mkdir(build);
        package=fullfile(build,'+ecc_pipe_probe');mkdir(package);
        generated=fullfile(package,'observed_pipe.ssc');write_text(generated,probe);
        record.probe_source_sha256=file_hash(generated);
        record.probe_recipe='component rename, one private visibility declaration, three read-only port-temperature aliases';
        if reference_study
            native_heat='    Q_H == Q_conv + Q_cond;';
            reference_heat='    Q_H == Nu_lam * k_I * surface_area / Dh * (H.T - T_I);';
            native_label='% Pipe (TL) : 2.5';reference_label='% Reference Heat Pipe (TL) : 2.5';
            assert(count(probe,native_heat)==1 && count(probe,native_label)==1);
            reference=strrep(probe,'component observed_pipe','component reference_pipe');
            reference=strrep(reference,native_label,reference_label);
            reference=strrep(reference,native_heat,reference_heat);
            undo=strrep(reference,reference_heat,native_heat);
            undo=strrep(undo,reference_label,native_label);
            assert(strcmp(probe,strrep(undo,'component reference_pipe','component observed_pipe')), ...
                'Reference changed more than the declared wall heat equation.');
            generated=fullfile(package,'reference_pipe.ssc');write_text(generated,reference);
            record.reference_source_sha256=file_hash(generated);
            record.reference_heat_equation=reference_heat;
            record.reference_display_name='Reference Heat Pipe (TL)';
            record.other_pipe_equations='unchanged native fluid storage, ports, momentum and property equations';
        end
        cd(build);ssc_build('ecc_pipe_probe');addpath(build);load_system('ecc_pipe_probe_lib');cd(repo);
        candidates=find_system('ecc_pipe_probe_lib','SearchDepth',1,'Type','Block');
        candidates=setdiff(candidates,{'ecc_pipe_probe_lib'});
        probe_library=select_component(candidates,'ecc_pipe_probe.observed_pipe');
        if reference_study
            reference_library=select_component(candidates,'ecc_pipe_probe.reference_pipe');
            arms={'Native','Probe','ReferenceSavedNu','ReferenceQ01'};
            steps=[.001 .0005 .00025];
        else
            assert(isscalar(candidates));arms={'Native','Probe'};steps=.001;
        end
        model='ecc_single_pipe_heat_step';assert(~bdIsLoaded(model));
        for material={'SMA','SE'}
            name=material{1};prefix=lower(name);
            new_system(model);model_cleanup=onCleanup(@() close_system(model,0));
            add_block('fl_lib/Thermal Liquid/Utilities/Thermal Liquid Settings (TL)',[model '/Settings']);
            fluid_record=configure_fluid([model '/Settings'],metadata.settings_tables,name);
            add_block('nesl_utility/Solver Configuration',[model '/Solver']);
            add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference',[model '/Reference']);
            add_block('fl_lib/Thermal/Thermal Sources/Controlled Temperature Source',[model '/Wall']);
            add_block('nesl_utility/Simulink-PS Converter',[model '/WallPS'],'Unit','K', ...
                'FilteringAndDerivatives','provide','UdotUserProvided','0','AffineConversion','off');
            if strcmp(integration,'global_ODE3')
                % The actual input is a Step, not a sampled approximation to a smooth signal.
                set_param([model '/WallPS'],'FilteringAndDerivatives','zero');
            end
            add_block('simulink/Sources/Step',[model '/WallStep'], ...
                'Time','.02','Before','303.15','After','308.15');
            add_line(model,'WallStep/1','WallPS/1');
            p=get_param([model '/WallPS'],'PortHandles');q=get_param([model '/Wall'],'PortHandles');
            add_line(model,p.RConn(1),q.RConn(1));
            % Native controlled_temperature enforces B.T-A.T=S, not A.T-B.T.
            simscape.addConnection([model '/Wall'],'A',[model '/Reference'],only_port([model '/Reference']));
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
            for arm=arms
                kind=arm{1};pipe=[model '/' kind];flow=[pipe 'Flow'];
                library='fl_lib/Thermal Liquid/Elements/Pipe (TL)';
                if strcmp(kind,'Probe'),library=probe_library;end
                if startsWith(kind,'Reference'),library=reference_library;end
                add_block(library,pipe);
                set_param(pipe,'length',num2str(length,17),'length_unit','m', ...
                    'area',num2str(area,17),'area_unit','m^2','Dh',num2str(diameter,17),'Dh_unit','m', ...
                    'length_add','0','length_add_unit','m','Nu_lam',num2str(nu,17), ...
                    'dynamic_compressibility','false','p_nominal',num2str(o.branch.network_absolute_pressure_MPa,17), ...
                    'p_nominal_unit','MPa','T_nominal','293.15','T_nominal_unit','K','T0','303.15','T0_unit','K');
                if strcmp(kind,'ReferenceQ01'),set_param(pipe,'Nu_lam','3.66');end
                add_block('fl_lib/Thermal Liquid/Sources/Flow Rate Source (TL)',flow);
                set_param(flow,'source_type','foundation.enum.constant_controlled.constant', ...
                    'flow_type','foundation.enum.mass_volumetric_flow.mass', ...
                    'mass_flow','0','mass_flow_unit','kg/s','power_spec','foundation.enum.power_spec.none');
                simscape.addConnection([model '/Inlet'],'A',flow,'A');
                simscape.addConnection(flow,'B',pipe,'A');
                simscape.addConnection(pipe,'B',[model '/Outlet'],'A');
                simscape.addConnection(pipe,'H',[model '/Wall'],'B');
            end
            set_param([model '/Solver'],'UseLocalSolver','on', ...
                'LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER','LocalSolverSampleTime','.001');
            if strcmp(integration,'global_ODE3'),set_param([model '/Solver'],'UseLocalSolver','off');end
            set_param(model,'Solver','ode3','FixedStep','.001','StartTime','0','StopTime','.1', ...
                'SimulationMode','normal','ReturnWorkspaceOutputs','on','SaveTime','off','SaveOutput','off', ...
                'SaveState','off','SaveFinalState','off','LoadInitialState','off', ...
                'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off','SimscapeLogToSDI','off');
            mdot=o.branch.(['m_dot_' prefix '_the_kg_per_s']);
            flows=[-mdot 0 mdot];if reference_study,flows=[-mdot mdot];end
            for dt=steps
            set_param(model,'FixedStep',num2str(dt,17));
            set_param([model '/Solver'],'LocalSolverSampleTime',num2str(dt,17));
            for flow=flows
                for delta=[-5 5]
                    for arm=arms
                        set_param([model '/' arm{1} 'Flow'],'mass_flow',num2str(flow,17));
                    end
                    set_param([model '/WallStep'],'After',num2str(303.15+delta,17));
                    solver_contract=struct('integration_request',integration, ...
                        'global_solver',get_param(model,'Solver'),'solver_type',get_param(model,'SolverType'), ...
                        'global_fixed_step',get_param(model,'FixedStep'), ...
                        'local_solver_enabled',get_param([model '/Solver'],'UseLocalSolver'), ...
                        'local_solver_choice_parameter',get_param([model '/Solver'],'LocalSolverChoice'), ...
                        'local_step_parameter',get_param([model '/Solver'],'LocalSolverSampleTime'), ...
                        'wall_converter_handling',get_param([model '/WallPS'],'FilteringAndDerivatives'), ...
                        'wall_converter_provided_derivatives',get_param([model '/WallPS'],'UdotUserProvided'));
                    expected_local='on';if strcmp(integration,'global_ODE3'),expected_local='off';end
                    assert(strcmp(solver_contract.global_solver,'ode3') && ...
                        strcmp(solver_contract.local_solver_enabled,expected_local));
                    write_text(fullfile(folder,'solver_contract_preflight.json'),jsonencode(solver_contract,'PrettyPrint',true));
                    elapsed=tic;input=Simulink.SimulationInput(model);
                    output=sim(input.setModelParameter('CaptureErrors','on'));seconds=toc(elapsed);
                    if ~isempty(output.ErrorMessage)
                        failed_case_context=struct('material',name,'mass_flow_command_kgps',flow, ...
                            'wall_step_K',delta,'fixed_step_s',dt,'study',study, ...
                            'solver_contract',solver_contract,'resume_allowed',false); %#ok<NASGU>
                        save(fullfile(folder,'failed_simulation.mat'),'output','failed_case_context','-v7.3');
                        error('HeatDriveECC:SinglePipeSimulationError','%s',output.ErrorMessage);
                    end
                    native=simscape.logging.findNode(output.simlog,[model '/Native']);
                    observed=simscape.logging.findNode(output.simlog,[model '/Probe']);
                    common={'T_I','p_I','u_I','rho_I','Phi_A','Phi_B','Q_H','mdot_A','mdot_B'};
                    extra={'Q_conv','Q_cond','cp_I','mu_I','k_I','Pr_I','Re_avg', ...
                        'probe_wall_T','probe_A_T','probe_B_T'};
                    if observe_energy,extra=[extra {'observer_energy'}];end
                    native_traces=extract(native,common);probe_traces=extract(observed,[common extra]);
                    wall=probe_traces{find(strcmp([common extra],'probe_wall_T'),1)};
                    assert(strcmp(wall.unit,'K'));
                    before=wall.time_s<=.02-dt;after=wall.time_s>=.02+dt;
                    assert(any(before) && any(after) && ...
                        max(abs(wall.values(before)-303.15),[],'all')<1e-9 && ...
                        max(abs(wall.values(after)-(303.15+delta)),[],'all')<1e-9, ...
                        'Actual wall temperature does not witness the requested heat step.');
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
                        'initial_temperature_K',303.15,'step_time_s',.02,'fixed_step_s',dt, ...
                        'stop_time_s',.1,'simulation_wall_seconds',seconds,'area_m2',area,'length_m',length, ...
                        'Dh_m',diameter,'saved_Nu',nu,'surface_area_m2',4*area/diameter*length, ...
                        'fluid_settings',fluid_record,'native_probe_comparisons',{comparisons}, ...
                        'native_probe_equivalence_pass',true,'power_spec','none','production_recovery_allowed',false);
                    row.solver_contract=solver_contract;
                    row.one_way_energy_observer_enabled=observe_energy;
                    file=sprintf('case_%02d.mat',numel(record.cases)+1);
                    if reference_study
                        row.study=study;row.reference_saved_Nu=nu;row.reference_Q01_Nu=3.66;
                        row.reference_states_independently_integrated=true;
                        row.nominal_inventory_temperature_K=293.15;
                        row.nominal_inventory_pressure_Pa=o.branch.network_absolute_pressure_MPa*1e6;
                        reference_saved_Nu_traces=extract(simscape.logging.findNode( ...
                            output.simlog,[model '/ReferenceSavedNu']),[common extra]); %#ok<NASGU>
                        reference_q01_traces=extract(simscape.logging.findNode( ...
                            output.simlog,[model '/ReferenceQ01']),[common extra]); %#ok<NASGU>
                        record_json=jsonencode(row);
                        save(fullfile(folder,file),'native_traces','probe_traces','record_json', ...
                            'reference_saved_Nu_traces','reference_q01_traces','-v7.3');
                    else
                        record_json=jsonencode(row);
                        save(fullfile(folder,file),'native_traces','probe_traces','record_json','-v7.3');
                    end
                    row.file=file;row.sha256=file_hash(fullfile(folder,file));record.cases{end+1}=row;
                    write_text(fullfile(folder,'completed_case_progress.json'),jsonencode(struct( ...
                        'completed_cases',numel(record.cases),'last_measured_time_s',t(end), ...
                        'simulation_completed',false,'checkpoint_saved',false)));
                    clear output native observed native_traces probe_traces
                end
            end
            end
            clear model_cleanup
        end
        assert(strcmp(file_hash(source),record.native_source_sha256),'Installed library changed.');
        expected=12;if reference_study,expected=24;end
        record.collection_pass=numel(record.cases)==expected;
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

function block=select_component(candidates,source)
    selected=cellfun(@(b) strcmp(get_param(b,'SourceFile'),source),candidates);
    assert(nnz(selected)==1,'Expected a unique generated component %s.',source);block=candidates{selected};
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
