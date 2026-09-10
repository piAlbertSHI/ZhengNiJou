function [point,runtime_targets,contract]=Apply_HeatDriveECC_NonlinearColdInventory(repo,model,physical_targets,out)
% Translate public cold targets only; never import or manufacture a ModelOP.
    assert(strcmp(get_param(model,'LoadInitialState'),'off'));
    assert(strcmp(get_param(model,'SimscapeNormalizeSystem'),'on'));
    assert(numel(physical_targets)==204);
    qualification=fullfile(repo,'outputs_storage_audit','nonlinear_mass_qualification_package_20260910','nonlinear_mass_probe_audit.json');
    assert(strcmp(file_hash(qualification),'137768091C382BEF495FB9A948F8350800819C25342F2D7AAC6489985BC5EC1C'));
    q=jsondecode(fileread(qualification));
    assert(q.physical_equivalence_verified && q.nonlinear_flow_fixture_pass && ...
        q.mass_coordinate_numeric_identity_cases==4 && ~q.production_recovery_allowed);
    build=fullfile(out,'nonlinear_component_build');
    variants=Build_HeatDriveECC_ShiftedInventoryVariants(repo,build,'nonlinear_mass');addpath(build);
    libraries=cell(1,2);
    for k=1:2
        library=[variants{k}.package '_lib'];path=fullfile(build,[library '.slx']);load_system(path);
        assert(strcmp(get_param(library,'FileName'),path));
        blocks=find_system(library,'SearchDepth',1,'Type','Block');blocks=setdiff(blocks,{library});assert(isscalar(blocks));
        libraries{k}=blocks{1};variants{k}.library_path=path;variants{k}.library_sha256=file_hash(path);
    end
    domains={'foundation.thermal_liquid.thermal_liquid','foundation.thermal.thermal'};
    net_before=cell(1,2);
    for k=1:2,net_before{k}=net_signature(Export_HeatDriveECC_TLConnectivity(model,domains{k}));end
    names={'SMA_PumpInletConnectingPipeVolume','SMA_PumpOutletConnectingPipeVolume', ...
        'ColdFluidBuffer','HotFluidBuffer','SHEXFluidBuffer','SMAHotFluidBuffer'};
    components=cell(1,6);
    for k=1:6
        path=[model '/' names{k}];kind=1;if k>2,kind=2;end
        source=get_param(path,'SourceFile');
        if kind==1
            assert(strcmp(source,'ecc_inventory_specific.conservative_chamber'));
            parameters={'volume','area'};
        else
            assert(strcmp(source,'ecc_buffer_coupled.conservative_buffer'));
            parameters={'tank_area','port_area','p_environment','gravity','reference_temperature','auxiliary_depth'};
        end
        mt=target(physical_targets,path,'stored_mass');et=target(physical_targets,path,'stored_energy');
        assert(strcmp(mt.priority,'High') && strcmp(et.priority,'High') && strcmp(mt.unit,'kg') && strcmp(et.unit,'J'));
        assert(mt.value>0 && et.value>0 && isfinite(mt.value) && isfinite(et.value));
        keys={};
        for j=1:numel(parameters),keys=[keys parameters(j) {[parameters{j} '_unit']}];end %#ok<AGROW>
        for name={'T_I','p_I'}
            for suffix={'','_unit','_specify','_priority','_nominal_specify','_nominal_value','_nominal_unit'}
                keys{end+1}=[name{1} suffix{1}]; %#ok<AGROW>
            end
        end
        values=cell(size(keys));for j=1:numel(keys),values{j}=get_param(path,keys{j});end
        physical_parameters=cell2struct(values,keys,2);
        nominal=struct();
        for choice={'stored_mass','stored_energy'}
            name=choice{1};nominal.(name)=struct('specify',get_param(path,[name '_nominal_specify']), ...
                'value',get_param(path,[name '_nominal_value']),'unit',get_param(path,[name '_nominal_unit']));
        end
        if kind==1
            assert(strcmp(nominal.stored_mass.specify,'on') && strcmp(nominal.stored_energy.specify,'on'));
            mass_nominal=mt.value;energy_nominal=et.value;
        else
            assert(strcmp(nominal.stored_mass.specify,'off') && strcmp(nominal.stored_energy.specify,'off'));
            mass_nominal=1;energy_nominal=1;
        end
        assert(value(simscape.Value(slResolve(nominal.stored_mass.value,path),nominal.stored_mass.unit),'kg')==mass_nominal);
        assert(value(simscape.Value(slResolve(nominal.stored_energy.value,path),nominal.stored_energy.unit),'J')==energy_nominal);
        position=get_param(path,'Position');replaced=replace_block(model,'Name',names{k},libraries{kind},'noprompt');
        assert(isscalar(replaced) && strcmp(replaced{1},path));set_param(path,'Position',position);
        for j=1:numel(keys),set_param(path,keys{j},values{j});end
        set_param(path,'mass_reference',number(mt.value),'mass_reference_unit','kg', ...
            'mass_scale',number(mt.value),'mass_scale_unit','kg','energy_reference',number(et.value),'energy_reference_unit','J', ...
            'mass_coordinate_specify','on','mass_coordinate','0','mass_coordinate_unit','1','mass_coordinate_priority','High', ...
            'energy_delta_specify','on','energy_delta','0','energy_delta_unit','J','energy_delta_priority','High', ...
            'mass_coordinate_nominal_specify','on','mass_coordinate_nominal_value',number(mass_nominal/mt.value),'mass_coordinate_nominal_unit','1', ...
            'energy_delta_nominal_specify','on','energy_delta_nominal_value',number(energy_nominal),'energy_delta_nominal_unit','J');
        for j=1:numel(keys),assert(isequal(get_param(path,keys{j}),values{j}),'Physical geometry or T/p declaration changed.');end
        components{k}=struct('block_path',path,'kind',variants{kind}.kind,'original_source',source, ...
            'source_file',get_param(path,'SourceFile'),'physical_parameters',physical_parameters, ...
            'mass_reference_kg',mt.value,'mass_scale_kg',mt.value,'energy_reference_J',et.value, ...
            'original_nominals',nominal,'mass_nominal_kg',mass_nominal,'energy_nominal_J',energy_nominal, ...
            'mass_coordinate_nominal',mass_nominal/mt.value,'source_time_s',0);
    end
    for k=1:2
        assert(isequal(net_before{k},net_signature(Export_HeatDriveECC_TLConnectivity(model,domains{k}))), ...
            'Typed physical wire nets or hierarchy bridges changed.');
    end
    point=simscape.op.OperatingPoint;runtime_targets=cell(size(physical_targets));translated=0;
    for k=1:numel(physical_targets)
        t=physical_targets{k};r=t;
        if any(strcmp(t.state_name,{'stored_mass','stored_energy'}))
            assert(any(cellfun(@(c) strcmp(c.block_path,t.block_path),components)));
            if strcmp(t.state_name,'stored_mass'),r.state_name='mass_coordinate';r.unit='1';
            else,r.state_name='energy_delta';r.unit='J';end
            r.path=[extractAfter(t.block_path,[model '/']) '/' r.state_name];r.value=0;translated=translated+1;
        end
        point=set(point,r.path,simscape.op.Target(r.value,r.unit,r.priority));runtime_targets{k}=r;
    end
    assert(translated==12 && ~hasPrivateData(point));
    contract=struct('qualification_sha256',file_hash(qualification),'variants',{variants},'components',{components}, ...
        'physical_targets',{physical_targets},'runtime_targets',{runtime_targets},'translated_count',translated, ...
        'unchanged_count',204-translated,'typed_nets_preserved',true,'net_signatures',{net_before}, ...
        'initial_physical_nominal_scales_matched',true,'full_solver_error_weights_verified',false, ...
        'source_time_s',0,'private_state_imported',false,'production_recovery_allowed',false);
end

function t=target(rows,path,name)
    selected=rows(cellfun(@(r) strcmp(r.block_path,path) && strcmp(r.state_name,name),rows));assert(isscalar(selected));t=selected{1};
end

function signature=net_signature(topology)
    signature=cell(1,numel(topology.edges)+numel(topology.vertices));
    for k=1:numel(topology.edges)
        e=topology.edges{k};ends=sort({topology.vertices{e.a}.key,topology.vertices{e.b}.key});
        signature{k}=[e.kind ':' ends{1} '|' ends{2}];
    end
    for k=1:numel(topology.vertices),signature{numel(topology.edges)+k}=['vertex:' topology.vertices{k}.key];end
    signature=sort(signature);
end

function text=number(x)
    text=num2str(x,'%.17g');
end

function hash=file_hash(file)
    d=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(file,'rb');assert(fid>=0);c=onCleanup(@() fclose(fid));
    while ~feof(fid),d.update(fread(fid,8*1024*1024,'*uint8'));end
    hash=upper(reshape(dec2hex(typecast(d.digest(),'uint8'),2).',1,[]));
end
