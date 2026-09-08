function records = Apply_HeatDriveECC_ColdConservativeBuffers(model, native)
% Replace only four root buffers, preserving actual physical port geometry.
    assert(bdIsLoaded('ecc_buffer_coupled_lib'), 'Build aligned candidate library before replacement.');
    assert(strcmp(get_param(model, 'LoadInitialState'), 'off'), 'Independent cold replacement only.');
    lib = find_system('ecc_buffer_coupled_lib', 'SearchDepth', 1, 'Type', 'Block');
    lib = setdiff(lib, {'ecc_buffer_coupled_lib'}); assert(isscalar(lib), 'Expected one buffer component.');
    scratch='ecc_buffer_port_scratch';assert(~bdIsLoaded(scratch),'Scratch model is in use.');
    new_system(scratch);scratch_cleanup=onCleanup(@() close_system(scratch,0));
    records = {};
    for name = {'ColdFluidBuffer', 'HotFluidBuffer', 'SHEXFluidBuffer', 'SMAHotFluidBuffer'}
        path = [model '/' name{1}];
        matches = find_system(model, 'LookUnderMasks', 'all', 'FollowLinks', 'on', 'Type', 'Block', 'Name', name{1});
        assert(isscalar(matches) && strcmp(matches{1}, path), 'Replacement name must uniquely identify a root buffer.');
        assert(strcmp(get_param(path, 'MaskType'), 'Tank (TL)'), 'Expected original Tank.');
        dialog = get_param(path, 'DialogParameters'); parameters = struct();
        fields = fieldnames(dialog);
        for j = 1:numel(fields), parameters.(fields{j}) = get_param(path, fields{j}); end
        assert(endsWith(parameters.num_inlet, '.One') && endsWith(parameters.volume_spec, '.Constant') && ...
            endsWith(parameters.pressure_spec, '.Specified'), 'Unsupported buffer geometry or pressure mode.');
        area = resolved('tank_area', 'm^2'); port_area = resolved('inlet_area_A', 'm^2');
        height = resolved('inlet_height_A', 'm'); gravity = resolved('g', 'm/s^2'); pressure = resolved('tank_pressure', 'Pa');
        assert(area>0 && port_area>0 && height==0 && gravity>=0, 'Only a positive-area bottom inlet is supported.');
        ports_before = Map_HeatDriveECC_PhysicalPortHandles(path,scratch);
        assert(numel(ports_before)==2 && isequal(sort(cellfun(@(p) p.name,ports_before,'UniformOutput',false)),{'A','H'}), 'Unexpected buffer ports.');
        temp = observed('T_I','K'); mass = observed('mass','kg'); rho = observed('rho_I','kg/m^3'); u = observed('u_I','J/kg');
        volume = mass/rho;
        assert(abs(volume-observed('volume','m^3'))<1e-12 && abs(pressure-observed('p_I','Pa'))<1e-6, ...
            'Actual geometry and native cold inventory differ.');
        energy = mass*u+pressure*volume+mass*gravity*volume/area/2;
        position = get_param(path,'Position');
        replaced = replace_block(model,'Name',name{1},lib{1},'noprompt');
        assert(isscalar(replaced) && strcmp(replaced{1},path), 'Replacement did not identify exactly one buffer.');
        set_param(path,'Position',position,'tank_area',number(area),'tank_area_unit','m^2', ...
            'port_area',number(port_area),'port_area_unit','m^2','p_environment',number(pressure),'p_environment_unit','Pa', ...
            'gravity',number(gravity),'gravity_unit','m/s^2','auxiliary_depth','.001','auxiliary_depth_unit','m', ...
            'reference_temperature',number(temp),'reference_temperature_unit','K', ...
            'stored_mass_specify','on','stored_mass_priority','High','stored_mass',number(mass),'stored_mass_unit','kg', ...
            'stored_energy_specify','on','stored_energy_priority','High','stored_energy',number(energy),'stored_energy_unit','J', ...
            'T_I_specify','on','T_I_priority','Low','T_I',number(temp),'T_I_unit','K');
        ports_after = Map_HeatDriveECC_PhysicalPortHandles(path,scratch);
        for j=1:numel(ports_before)
            a=ports_before{j};selected=ports_after(cellfun(@(p) strcmp(p.name,a.name),ports_after));
            assert(isscalar(selected),'Missing unique physical port.');b=selected{1};
            assert(strcmp(a.side,b.side) && a.index==b.index && strcmp(a.domain,b.domain), ...
                'Physical port identity or layout changed.');
        end
        records{end+1}=struct('block_path',path,'original_parameters',parameters, ...
            'tank_area_m2',area,'port_area_m2',port_area,'inlet_height_m',height,'gravity_m_s2',gravity, ...
            'p_environment_Pa',pressure,'reference_temperature_K',temp,'initial_mass_kg',mass, ...
            'initial_volume_m3',volume,'initial_extended_energy_J',energy,'initial_source_time_s',0, ...
            'auxiliary_depth_m',.001,'mainline_recovery_allowed',false); %#ok<AGROW>
    end
    assert(numel(records)==4,'Incomplete buffer replacement.');
    clear scratch_cleanup

    function result=resolved(field,unit)
        result=value(simscape.Value(slResolve(parameters.(field),path),parameters.([field '_unit'])),unit);
        assert(isscalar(result) && isfinite(result),'Nonfinite geometry parameter.');
    end
    function result=observed(field,unit)
        selected=native(cellfun(@(r) strcmp(r.block_path,path) && strcmp(r.state_name,field),native));
        assert(isscalar(selected) && selected{1}.time_s(1)==0,'Require actual same-run cold initial source.');
        result=value(simscape.Value(selected{1}.values(1),selected{1}.unit),unit);
    end
end

function text=number(value)
    text=num2str(value,'%.17g');
end
