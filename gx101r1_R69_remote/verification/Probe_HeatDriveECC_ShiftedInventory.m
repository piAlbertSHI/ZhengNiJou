function record=Probe_HeatDriveECC_ShiftedInventory(repo,out,fixture_kind)
% Independent water fixtures. No production model or checkpoint is loaded.
    if nargin<3,fixture_kind='closed';end
    assert(ismember(fixture_kind,{'closed','flow'}),'Only declared component fixtures are allowed.');
    assert(~isfolder(out),'Never overwrite evidence.');
    [status,dirty]=system(sprintf('git -C "%s" status --porcelain -- .',repo));
    assert(status==0 && isempty(strtrim(dirty)),'Commit relevant code first.');
    [status,commit]=system('git rev-parse HEAD');assert(status==0);
    mkdir(out);diary(fullfile(out,'matlab_diary.log'));dc=onCleanup(@() diary('off'));
    old=pwd;oldpath=path;pc=onCleanup(@() restore(old,oldpath));
    generation=Simulink.fileGenControl('getConfig');
    gc=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(out,'cache'), ...
        'CodeGenFolder',fullfile(out,'codegen'),'createDir',true);
    record=struct('execution_commit',strtrim(commit),'collection_pass',false,'cases',{{}}, ...
        'error_message','','production_recovery_allowed',false,'main_model_run',false, ...
        'cold_main_targets_verified',false,'checkpoint_loaded',false,'checkpoint_saved',false);
    record.fixture_kind=fixture_kind;
    try
        build=fullfile(out,'build');record.variants=Build_HeatDriveECC_ShiftedInventoryVariants(repo,build);
        sources={'simscape_inventory_specific/+ecc_inventory_specific','simscape_buffer_coupled/+ecc_buffer_coupled'};
        packages={'ecc_inventory_specific','ecc_buffer_coupled'};kinds={'chamber','buffer'};
        for k=1:2
            copyfile(fullfile(repo,'verification',sources{k}),fullfile(build,['+' packages{k}]));
            cd(build);ssc_build(packages{k});
        end
        addpath(build);load_system('fl_lib');load_system('nesl_utility');
        for k=1:2
          for direction=[1 -1]
            heat=direction;flow=0;
            if strcmp(fixture_kind,'flow'),heat=0;flow=direction*1e-6;end
            origin=[];
            for shifted=[false true]
                package=packages{k};if shifted,package=['ecc_shifted_' kinds{k}];end
                lib=[package '_lib'];load_system(lib);
                blocks=find_system(lib,'SearchDepth',1,'Type','Block');blocks=setdiff(blocks,{lib});assert(isscalar(blocks));
                model='ecc_shifted_inventory_probe';assert(~bdIsLoaded(model));new_system(model);
                mc=onCleanup(@() close_system(model,0));
                component=[model '/Inventory'];add_block(blocks{1},component);
                if shifted
                    set_param(component,'mass_reference',num2str(origin(1),'%.17g'),'mass_reference_unit','kg', ...
                        'energy_reference',num2str(origin(2),'%.17g'),'energy_reference_unit','J');
                end
                add_block('fl_lib/Thermal Liquid/Utilities/Thermal Liquid Settings (TL)',[model '/Fluid']);
                add_block('nesl_utility/Solver Configuration',[model '/Solver'],'UseLocalSolver','off');
                simscape.addConnection(component,'A',[model '/Fluid'],only_port([model '/Fluid']));
                simscape.addConnection(component,'A',[model '/Solver'],only_port([model '/Solver']));
                add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source',[model '/Heat']);
                add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference',[model '/Reference']);
                add_block('nesl_utility/Simulink-PS Converter',[model '/HeatPS'],'Unit','W');
                add_block('simulink/Sources/Constant',[model '/Command'],'Value',num2str(-heat));
                simscape.addConnection(component,'H',[model '/Heat'],'A');
                simscape.addConnection([model '/Heat'],'B',[model '/Reference'],only_port([model '/Reference']));
                add_line(model,'Command/1','HeatPS/1');ps=get_param([model '/HeatPS'],'PortHandles');
                hp=get_param([model '/Heat'],'PortHandles');add_line(model,ps.RConn(1),hp.RConn(1));
                if flow~=0
                    add_block('fl_lib/Thermal Liquid/Sources/Flow Rate Source (TL)',[model '/Flow']);
                    set_param([model '/Flow'],'source_type','foundation.enum.constant_controlled.constant', ...
                        'flow_type','foundation.enum.mass_volumetric_flow.mass','mass_flow',num2str(flow,'%.17g'), ...
                        'mass_flow_unit','kg/s','power_spec','foundation.enum.power_spec.none');
                    add_block('fl_lib/Thermal Liquid/Elements/Reservoir (TL)',[model '/Reservoir']);
                    set_param([model '/Reservoir'],'pressure_spec','foundation.enum.pressure_spec.specified', ...
                        'reservoir_pressure','1','reservoir_pressure_unit','MPa', ...
                        'reservoir_temperature','300','reservoir_temperature_unit','K');
                    simscape.addConnection([model '/Reservoir'],'A',[model '/Flow'],'A');
                    simscape.addConnection([model '/Flow'],'B',component,'A');
                end
                set_param(model,'Solver','ode23t','RelTol','1e-6','AbsTol','1e-8','AutoScaleAbsTol','on', ...
                    'MaxStep','.00025','StartTime','0','StopTime','.04','SolverResetMethod','Fast', ...
                    'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
                    'ReturnWorkspaceOutputs','on','SaveOutput','off','SaveTime','off','LoadInitialState','off', ...
                    'SaveState','on','StateSaveName','states','SaveFormat','Dataset', ...
                    'SaveFinalState','off','SaveOperatingPoint','off');
                output=sim(model);node=simscape.logging.findNode(output.simlog,component);
                names={'stored_mass','stored_energy','T_I','p_I','rho_I','u_I','mdot_A','Phi_A','Q_H'};
                units={'kg','J','K','Pa','kg/m^3','J/kg','kg/s','W','W'};
                if k==1,names=[names {'mdot_B','Phi_B'}];units=[units {'kg/s','W'}];end %#ok<AGROW>
                if shifted,names=[names {'mass_delta','energy_delta'}];units=[units {'kg','J'}];end %#ok<AGROW>
                traces=cell(size(names));
                for n=1:numel(names)
                    series=node.child(names{n}).series;
                    traces{n}=struct('name',names{n},'unit',units{n},'time_s',double(time(series)), ...
                        'values',value(simscape.Value(double(values(series)),series.unit),units{n}));
                end
                if ~shifted,origin=[traces{1}.values(1) traces{2}.values(1)];end
                states=output.get('states');state_names=cell(1,states.numElements);
                for n=1:states.numElements,s=states.getElement(n);state_names{n}=s.Name;end
                file=sprintf('case_%02d.mat',numel(record.cases)+1);save(fullfile(out,file),'states','traces','-v7.3');
                record.cases{end+1}=struct('kind',kinds{k},'shifted',shifted,'heat_W',heat, ...
                    'flow_kg_s',flow,'origin_kg_J',origin,'state_names',{state_names},'traces',{traces},'file',file, ...
                    'solver',get_param(model,'Solver'),'max_step_s',str2double(get_param(model,'MaxStep')), ...
                    'rel_tol',str2double(get_param(model,'RelTol')),'abs_tol',str2double(get_param(model,'AbsTol')), ...
                    'local_solver',get_param([model '/Solver'],'UseLocalSolver'));
                clear mc output node states
            end
          end
        end
        record.collection_pass=numel(record.cases)==8;
    catch exception
        record.error_message=getReport(exception,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(out,'shifted_inventory_probe.json'),'w','n','UTF-8');assert(fid>=0);
    fc=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));clear fc
    fprintf('%s\n',jsonencode(struct('collection_pass',record.collection_pass,'cases',numel(record.cases), ...
        'production_recovery_allowed',false,'error_message',record.error_message)));
    assert(record.collection_pass,'HeatDriveECC:ShiftedFixtureFailed','%s',record.error_message);
end

function name=only_port(block)
    ports=simscape.connectionPortProperties(block);assert(isscalar(ports));name=ports.Name;
end

function restore(folder,oldpath)
    cd(folder);path(oldpath);
end
