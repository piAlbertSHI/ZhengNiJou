function record=Run_HeatDriveECC_BufferGeometryFixture(repo,source_root,output_root)
% Eight isolated zero-flow tests; no coupled trajectory or checkpoint recovery.
    assert(~isfolder(output_root),'Never overwrite a component fixture.');
    workspace=fileparts(repo);
    [code,commit]=system(sprintf('git -C "%s" rev-parse HEAD',workspace));assert(code==0);
    [code,dirty]=system(sprintf('git -C "%s" status --porcelain',workspace));
    assert(code==0 && isempty(strtrim(dirty)),'Require committed isolated source.');
    mkdir(output_root);diary(fullfile(output_root,'matlab_diary.log'));d=onCleanup(@() diary('off'));
    old=pwd;oldpath=path;restore=onCleanup(@() restore_path(old,oldpath));
    generation=Simulink.fileGenControl('getConfig');
    restore_generation=onCleanup(@() Simulink.fileGenControl('setConfig','config',generation));
    Simulink.fileGenControl('set','CacheFolder',fullfile(output_root,'cache'), ...
        'CodeGenFolder',fullfile(output_root,'codegen'),'createDir',true);
    record=struct('schema','heatdrive_ecc_buffer_geometry_fixture_v1','execution_commit',strtrim(commit), ...
        'source_root',source_root,'cases',{{}},'collection_pass',false,'error_message','', ...
        'simulation_executed',true,'coupled_simulation_executed',false,'operating_point_loaded',false, ...
        'source_state_edited',false,'production_recovery_allowed',false,'table4_reproduction_claim',false);
    try
        execution=jsondecode(fileread(fullfile(source_root,'cold_chamber_execution.json')));
        assert(execution.cycle_count==62 && execution.stop_time_s==620 && execution.requested_arm_collection_pass && ...
            isempty(execution.error_message),'Use measured C62 conditions, not an incomplete trajectory.');
        capture=jsondecode(fileread(fullfile(source_root,'native','diagnostic_state_capture.json')));
        record.source_operating_point_sha256=file_hash(fullfile(source_root,'native','diagnostic_complete_operating_point.mat'));
        record.source_history_sha256=file_hash(fullfile(source_root,'native','diagnostic_state_observation.mat'));
        assert(strcmp(record.source_operating_point_sha256,capture.operating_point_sha256) && ...
            strcmp(record.source_history_sha256,capture.history_sha256),'Changed C62 source.');
        file=fullfile(source_root,'native','configuration.mat');record.configuration_sha256=file_hash(file);
        saved=load(file,'options');options=saved.options;
        options.simulation.persist_model_configuration=false;options.simulation.resume_checkpoint_path='';
        options.branch.independent_conservative_chamber_diagnostic=false;
        record.canonical_model_sha256=file_hash(options.model_path);
        saved=load(fullfile(source_root,'native','observations.mat'),'native');native=saved.native;
        record.observation_sha256=file_hash(fullfile(source_root,'native','observations.mat'));
        contract=jsondecode(fileread(fullfile(source_root,'native','buffer_replacement_contract.json')));
        [source,~]=Build_HeatDriveECC_EighthRound_Simulink_Model(options);
        close_source=onCleanup(@() close_system(source,0));
        water=[source '/SMA_ThermalLiquidSettings'];
        solvers=find_system(source,'LookUnderMasks','all','FollowLinks','on','MaskType','Solver Configuration');
        assert(isscalar(solvers),'Expected one source solver.');
        build=fullfile(output_root,'component_build');mkdir(build);
        package='ecc_buffer_geometry_boundary';folder=fullfile(build,['+' package]);mkdir(folder);
        buffer_source=fullfile(repo,'verification','simscape_buffer_coupled_offset','+ecc_buffer_coupled_offset','conservative_buffer.ssc');
        boundary_source=fullfile(repo,'verification','simscape_buffer_geometry',['+' package],'fixed_temperature_zero_mass_port.ssc');
        copyfile(buffer_source,fullfile(folder,'conservative_buffer.ssc'));copyfile(boundary_source,folder);
        record.buffer_source_sha256=file_hash(buffer_source);record.boundary_source_sha256=file_hash(boundary_source);
        cd(build);ssc_build(package);addpath(build);load_system([package '_lib']);cd(repo);
        blocks=find_system([package '_lib'],'SearchDepth',1,'Type','Block');blocks=setdiff(blocks,{[package '_lib']});
        buffer=blocks(cellfun(@(b) endsWith(get_param(b,'SourceFile'),'.conservative_buffer'),blocks));
        boundary=blocks(cellfun(@(b) endsWith(get_param(b,'SourceFile'),'.fixed_temperature_zero_mass_port'),blocks));
        assert(isscalar(buffer) && isscalar(boundary),'Expected the two isolated components.');
        for name={'SHEXFluidBuffer','SMAHotFluidBuffer'}
            block=[source '/' name{1}];c=contract.buffers(strcmp({contract.buffers.block_path},block));
            assert(isscalar(c),'Missing source geometry.');
            temperature=last_value(native,block,'T_I','K');mass=last_value(native,block,'stored_mass','kg');
            energy=last_value(native,block,'stored_energy','J');
            if strcmp(name{1},'SHEXFluidBuffer'),boundary_temp=303.15;else,boundary_temp=393.15;end
            areas=[c.port_area_m2,.001,.0001,pi*.0032^2/4];
            for j=1:4
                model='ecc_buffer_geometry_fixture';assert(~bdIsLoaded(model),'Fixture model is already in use.');
                new_system(model);close_fixture=onCleanup(@() close_system(model,0));
                tank=[model '/Buffer'];add_block(buffer{1},tank);
                set_param(tank,'tank_area',number(c.tank_area_m2),'tank_area_unit','m^2', ...
                    'port_area',number(areas(j)),'port_area_unit','m^2', ...
                    'p_environment',number(c.p_environment_Pa),'p_environment_unit','Pa', ...
                    'gravity',number(c.gravity_m_s2),'gravity_unit','m/s^2', ...
                    'reference_temperature',number(c.reference_temperature_K),'reference_temperature_unit','K', ...
                    'auxiliary_depth',number(c.auxiliary_depth_m),'auxiliary_depth_unit','m', ...
                    'initial_stored_mass',number(mass),'initial_stored_mass_unit','kg', ...
                    'mass_offset_specify','on','mass_offset_priority','High','mass_offset','0','mass_offset_unit','kg', ...
                    'stored_energy_specify','on','stored_energy_priority','High','stored_energy',number(energy),'stored_energy_unit','J', ...
                    'T_I_specify','on','T_I_priority','Low','T_I',number(temperature),'T_I_unit','K');
                add_block(boundary{1},[model '/Boundary'],'boundary_temperature',number(boundary_temp),'boundary_temperature_unit','K');
                add_block(water,[model '/FluidSettings']);add_block(solvers{1},[model '/Solver']);
                simscape.addConnection(tank,'A',[model '/Boundary'],'A');
                simscape.addConnection(tank,'A',[model '/FluidSettings'],only_port([model '/FluidSettings']));
                simscape.addConnection(tank,'A',[model '/Solver'],only_port([model '/Solver']));
                add_block('fl_lib/Thermal/Thermal Sources/Controlled Heat Flow Rate Source',[model '/Heat']);
                add_block('fl_lib/Thermal/Thermal Elements/Thermal Reference',[model '/Reference']);
                add_block('nesl_utility/Simulink-PS Converter',[model '/HeatPS'],'Unit','W');
                add_block('simulink/Sources/Constant',[model '/ZeroHeat'],'Value','0');
                simscape.addConnection(tank,'H',[model '/Heat'],'A');
                simscape.addConnection([model '/Heat'],'B',[model '/Reference'],only_port([model '/Reference']));
                add_line(model,'ZeroHeat/1','HeatPS/1');p=get_param([model '/HeatPS'],'PortHandles');h=get_param([model '/Heat'],'PortHandles');
                add_line(model,p.RConn(1),h.RConn(1));
                set_param([model '/Solver'],'UseLocalSolver','on','LocalSolverChoice','NE_BACKWARD_EULER_ADVANCER','LocalSolverSampleTime','.001');
                set_param(model,'Solver','ode3','FixedStep','.001','StartTime','0','StopTime','1', ...
                    'SimscapeLogType','all','SimscapeLogName','simlog','SimscapeLogLimitData','off', ...
                    'ReturnWorkspaceOutputs','on','SaveTime','off','SaveOutput','off', ...
                    'LoadInitialState','off','SaveState','off','SaveFinalState','off');
                output=sim(model);node=simscape.logging.findNode(output.simlog,tank);
                names={'T_I','stored_mass','mass_offset','stored_energy','p_A','mdot_A','Phi_A','Q_H','u_port'};
                traces=cell(size(names));
                for n=1:numel(names)
                    series=node.child(names{n}).series;
                    traces{n}=struct('name',names{n},'unit',series.unit,'time_s',double(time(series)), ...
                        'values',double(values(series)));
                end
                entry=struct('source_buffer',name{1},'source_time_s',620,'initial_temperature_K',temperature, ...
                    'initial_mass_kg',mass,'initial_energy_J',energy,'port_area_m2',areas(j), ...
                    'boundary_temperature_K',boundary_temp,'fixed_step_s',.001,'duration_s',1, ...
                    'boundary_mass_flow_kg_s',0,'boundary_heat_port_W',0, ...
                    'case_kind','isolated measured-condition experiment, never coupled OP recovery');
                record_json=jsonencode(entry);filename=sprintf('case_%02d.mat',numel(record.cases)+1);
                file=fullfile(output_root,filename);save(file,'traces','record_json','-v7.3');
                entry.file=filename;entry.sha256=file_hash(file);record.cases{end+1}=entry;
                clear close_fixture output node traces
            end
        end
        assert(strcmp(file_hash(options.model_path),record.canonical_model_sha256),'Canonical source changed.');
        assert(strcmp(file_hash(fullfile(source_root,'native','diagnostic_complete_operating_point.mat')),record.source_operating_point_sha256) && ...
            strcmp(file_hash(fullfile(source_root,'native','diagnostic_state_observation.mat')),record.source_history_sha256),'C62 state changed.');
        record.collection_pass=numel(record.cases)==8;clear close_source
    catch exception
        record.error_message=getReport(exception,'extended','hyperlinks','off');
    end
    fid=fopen(fullfile(output_root,'fixture_execution.json'),'w','n','UTF-8');assert(fid>=0);
    cleanup=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    fprintf('FINAL_JSON=%s\n',jsonencode(struct('collection_pass',record.collection_pass, ...
        'completed_cases',numel(record.cases),'error_message',record.error_message,'coupled_simulation_executed',false)));
    assert(record.collection_pass,'HeatDriveECC:BufferGeometryFixtureFailed','%s',record.error_message);
end

function result=last_value(rows,path,name,unit)
    selected=rows(cellfun(@(r) strcmp(r.block_path,path) && strcmp(r.state_name,name),rows));
    assert(isscalar(selected) && selected{1}.time_s(end)==620,'Missing actual endpoint.');
    result=value(simscape.Value(selected{1}.values(end),selected{1}.unit),unit);
end
function name=only_port(block)
    p=simscape.connectionPortProperties(block);assert(isscalar(p));name=p.Name;
end
function result=number(value)
    result=num2str(value,'%.17g');
end
function result=file_hash(file)
    md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),md.update(fread(fid,8*1024*1024,'*uint8'));end
    result=upper(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
function restore_path(folder,oldpath)
    cd(folder);path(oldpath);
end
