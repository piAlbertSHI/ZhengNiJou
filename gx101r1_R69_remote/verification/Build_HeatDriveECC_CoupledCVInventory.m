function contract=Build_HeatDriveECC_CoupledCVInventory(model,variant,options)
% Exact native inventory for two declared topologies, not a relaxed count gate.
    assert(ismember(variant,{'dual','shared'}));
    hhex=unique_parent(model,'SMAHotPipe');chex=unique_parent(model,'ColdSinkPipe');
    hex={ [model '/SHEX/HotPipe'],'shex','SMA'; ...
        [hhex '/SMAHotPipe'],'hhex_sma','SMA'; ...
        [hhex '/HotPipe'],'hhex_se','SE'; ...
        [chex '/ColdSinkPipe'],'chex','SE'};
    expected={};
    for component={'SMA','SE'}
        for i=1:21
            expected{end+1}=sprintf('%s/%s/HoldPipe_%03d',model,component{1},i); %#ok<AGROW>
            expected{end+1}=sprintf('%s/%s/Subsystem2/NodeMass_%02d',model,component{1},i); %#ok<AGROW>
        end
    end
    if strcmp(variant,'dual')
        for i=1:21,expected{end+1}=sprintf('%s/SMA/CooldownPipe_%03d',model,i);end %#ok<AGROW>
    end
    expected=[expected,hex(:,1).', ...
        {[model '/ColdFluidBuffer'],[model '/HotFluidBuffer'],[model '/SHEXFluidBuffer'],[model '/SMAHotFluidBuffer'], ...
        [model '/SMA_PumpInletConnectingPipeVolume'],[model '/SMA_PumpOutletConnectingPipeVolume'], ...
        [model '/SHEX/HotSinkMass'],[hhex '/HotSinkMass'],[chex '/ColdSinkMass'],[chex '/ColdLoadMass']}];
    counts=[67 4 2 46];if strcmp(variant,'shared'),counts=[46 4 2 46];end
    types={'Pipe (TL)','Tank (TL)','Constant Volume Chamber (TL)','Thermal Mass'};
    paths={};rows={};
    modes={'dynamic_compressibility','inertia','mass_type','p_nominal','p_nominal_unit','T_nominal','T_nominal_unit','num_ports','num_inlet','volume_spec'};
    parameters={'area','length','volume','mass','sp_heat','tank_area','g','inlet_height_A','tank_pressure','T0','p0'};
    for kind=1:4
        found=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block','MaskType',types{kind});
        assert(numel(found)==counts(kind),'Declared native storage type coverage changed.');
        for k=1:numel(found)
            p=found{k};paths{end+1}=p;dialog=get_param(p,'DialogParameters'); %#ok<AGROW>
            row=struct('block_path',p,'mask_type',types{kind},'source_file',get_param(p,'SourceFile'), ...
                'reference_block',get_param(p,'ReferenceBlock'),'model_modes',struct(),'mask_parameters',struct());
            for j=1:numel(modes),n=modes{j};if isfield(dialog,n),row.model_modes.(n)=get_param(p,n);end;end
            for j=1:numel(parameters)
                n=parameters{j};if ~isfield(dialog,n),continue;end
                expr=get_param(p,n);row.mask_parameters.(n)=struct('expression',expr, ...
                    'value',slResolve(expr,p),'unit',get_param(p,[n '_unit']));
            end
            rows{end+1}=row; %#ok<AGROW>
        end
    end
    assert(numel(unique(paths))==sum(counts) && isequal(sort(paths),sort(expected)), ...
        'An unknown, duplicated or missing physical storage path cannot pass by count alone.');
    audit=options.validation.dual_fluid_domain_audit;
    settings_paths={audit.sma_settings_path,audit.se_settings_path};settings={};
    assert(audit.ok && numel(unique(settings_paths))==2);
    names={'table_dimensions','T_TLU','T_TLU_unit','T_min_1D','T_max_1D','p_min_1D','p_max_1D', ...
        'p_min_1D_unit','p_max_1D_unit','rho_parameterization_1D','rho_TLU_4','rho_TLU_4_unit', ...
        'beta_const_4','beta_const_4_unit','p_ref_4','p_ref_4_unit','u_parameterization_1D', ...
        'u_TLU_4','u_TLU_4_unit','cp_TLU_5','cp_TLU_5_unit'};
    for k=1:2
        row=struct('block_path',settings_paths{k},'parameters',struct());
        assert(strcmp(get_param(settings_paths{k},'SourceFile'),'foundation.thermal_liquid.utilities.thermal_liquid_settings'));
        for j=1:numel(names),row.parameters.(names{j})=get_param(settings_paths{k},names{j});end
        settings{end+1}=row; %#ok<AGROW>
    end
    contract=struct('schema','heatdrive_ecc_coupled_CV_inventory_v1','variant',variant, ...
        'storage_paths',{sort(expected)},'type_names',{types},'type_counts',counts, ...
        'storage_blocks',{rows},'settings_tables',{settings},'hex_channels',{hex}, ...
        'production_recovery_allowed',false,'compiled_minimal_state_count_claimed',false);
end

function parent=unique_parent(model,name)
    hit=find_system(model,'LookUnderMasks','all','FollowLinks','on','Type','Block','Name',name);
    assert(isscalar(hit),'Require exactly one named native exchanger channel.');parent=get_param(hit{1},'Parent');
end
