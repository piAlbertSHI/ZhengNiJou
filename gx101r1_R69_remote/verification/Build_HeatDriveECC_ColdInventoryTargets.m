function [point,records]=Build_HeatDriveECC_ColdInventoryTargets(model,native,chamber_volume,buffers)
% Public target specification at t=0, not a ModelOperatingPoint or hidden state.
    if nargin<4, buffers={}; end
    point=simscape.op.OperatingPoint;records={};primary=0;
    types={'Pipe (TL)','Tank (TL)','Thermal Mass'};counts=[67 4 46];
    for kind=1:3
        paths=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block','MaskType',types{kind});
        if kind==2 && ~isempty(buffers)
            assert(isempty(paths) && numel(buffers)==4,'Expected four replaced buffers.');
            paths=cellfun(@(b) b.block_path,buffers,'UniformOutput',false);
        end
        assert(numel(paths)==counts(kind),'Incomplete cold inventory.');
        for k=1:numel(paths)
            p=paths{k};
            if kind==1
                assert(strcmp(get_param(p,'dynamic_compressibility'),'false'),'Only quasisteady pipes supported.');
                add(p,'u_I','kJ/kg','High');add(p,'T_I','K','Low');
            elseif kind==2
                if isempty(buffers)
                    add(p,'mass','kg','High');add(p,'T_I','K','High');add(p,'level','m','Low');
                else
                    b=buffers(cellfun(@(r) strcmp(r.block_path,p),buffers));assert(isscalar(b),'Duplicate buffer target.');
                    assert(strcmp(get_param(p,'SourceFile'),'ecc_buffer_coupled.conservative_buffer'),'Wrong candidate buffer.');
                    add_value(p,'stored_mass','kg','High',b{1}.initial_mass_kg);
                    add_value(p,'stored_energy','J','High',b{1}.initial_extended_energy_J);
                    add(p,'T_I','K','Low');add(p,'level','m','Low');
                end
            else
                add(p,'T','K','High');
            end
        end
    end
    for name={'SMA_PumpInletConnectingPipeVolume','SMA_PumpOutletConnectingPipeVolume'}
        p=[model '/' name{1}];
        assert(strcmp(get_param(p,'SourceFile'),'ecc_inventory.conservative_chamber'),'Wrong chamber.');
        mass=observed(p,'rho_I','kg/m^3')*chamber_volume;
        add_value(p,'stored_mass','kg','High',mass);
        add_value(p,'stored_energy','J','High',mass*observed(p,'u_I','J/kg'));
        add(p,'T_I','K','Low');add(p,'p_I','MPa','Low');
    end
    assert(primary==125 && numel(records)==200+numel(buffers) && ~hasPrivateData(point),'Invalid public cold target coverage.');

    function v=observed(p,n,u)
        rows=native(cellfun(@(r) strcmp(r.block_path,p) && strcmp(r.state_name,n),native));
        assert(isscalar(rows) && rows{1}.time_s(1)==0,'Require a unique actual cold initial sample.');
        v=value(simscape.Value(rows{1}.values(1),rows{1}.unit),u);
        assert(isfinite(v),'Nonfinite cold initial coordinate.');
    end
    function add(p,n,u,priority)
        add_value(p,n,u,priority,observed(p,n,u));
    end
    function add_value(p,n,u,priority,v)
        relative=[extractAfter(p,[model '/']) '/' n];
        point=set(point,relative,simscape.op.Target(v,u,priority));
        records{end+1}=struct('path',relative,'block_path',p,'state_name',n,'unit',u, ...
            'value',v,'priority',priority,'source_time_s',0);
        primary=primary+strcmp(priority,'High');
    end
end
