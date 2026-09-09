function record=Inspect_HeatDriveECC_CompiledAlgebraicStructure(model)
% Compile the declared diagnostic and collect loops without simulating time.
    assert(strcmp(get_param(model,'SimulationStatus'),'stopped'));
    assert(strcmp(get_param(model,'StopTime'),'0') && strcmp(get_param(model,'LoadInitialState'),'off') && ...
        strcmp(get_param(model,'SaveOperatingPoint'),'off'));
    assert(strcmp(get_param(model,'AlgebraicLoopMsg'),'warning'),'Do not weaken the diagnostic.');
    visibility=get(groot,'DefaultFigureVisible');set(groot,'DefaultFigureVisible','off');
    vc=onCleanup(@() set(groot,'DefaultFigureVisible',visibility));
    set_param(model,'SimulationCommand','update');
    [loops,viewer]=Simulink.BlockDiagram.getAlgebraicLoops(model);
    fc=onCleanup(@() delete(viewer));
    records=cell(numel(loops),1);
    for k=1:numel(loops)
        item=loops(k);handles=item.BlockHandles(:);blocks=cell(numel(handles),1);
        for j=1:numel(handles)
            h=handles(j);parameters=get_param(h,'ObjectParameters');
            b=struct('path',getfullname(h),'block_type',get_param(h,'BlockType'), ...
                'is_algebraic_variable',ismember(h,item.VariableBlockHandles));
            for key={'FunctionName','MaskType','ReferenceBlock'}
                if isfield(parameters,key{1}),b.(key{1})=get_param(h,key{1});end
            end
            connections=get_param(h,'PortConnectivity');inputs={};
            for p=1:numel(connections)
                sources=connections(p).SrcBlock;
                for s=1:numel(sources)
                    if sources(s)>0
                        inputs{end+1}=struct('port',connections(p).Type, ...
                            'source_block',getfullname(sources(s)),'source_port',connections(p).SrcPort); %#ok<AGROW>
                    end
                end
            end
            b.inputs=inputs;blocks{j}=b;
        end
        records{k}=struct('id',item.Id,'is_artificial',logical(item.IsArtificial),'blocks',{blocks});
    end
    record=struct('schema','heatdrive_ecc_compiled_algebraic_structure_v1', ...
        'matlab_release',version('-release'),'loop_count',numel(loops),'loops',{records}, ...
        'simulation_run',false,'trajectory_verified',false,'production_recovery_allowed',false);
end
