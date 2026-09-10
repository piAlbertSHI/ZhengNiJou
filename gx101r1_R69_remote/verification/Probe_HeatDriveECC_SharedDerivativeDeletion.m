function record=Probe_HeatDriveECC_SharedDerivativeDeletion(output_root,explicit_rewire)
% Reproduce only the shared-source deletion topology, without simulation.
    if nargin<2,explicit_rewire=false;end
    assert(~isfolder(output_root));mkdir(output_root);
    model='ecc_shared_derivative_fixture';new_system(model);
    cleanup=onCleanup(@() close_system(model,0));
    add_block('simulink/Sources/Constant',[model '/Old'],'Value','0');
    for name={'Pump','Bias'}
        add_block('simulink/Sinks/Terminator',[model '/' name{1}]);
        add_line(model,'Old/1',[name{1} '/1']);
    end
    p=get_param([model '/Pump'],'PortHandles');
    delete_line(get_param(p.Inport(1),'Line'));
    if explicit_rewire
        b=get_param([model '/Bias'],'PortHandles');line=get_param(b.Inport(1),'Line');
        if line~=-1,delete_line(line);end
    end
    delete_block([model '/Old']);
    add_block('simulink/Sources/Constant',[model '/New'],'Value','1');
    add_line(model,'New/1','Pump/1');
    if explicit_rewire,add_line(model,'New/1','Bias/1');end
    b=get_param([model '/Bias'],'PortHandles');line=get_param(b.Inport(1),'Line');
    connected=line~=-1;
    if connected,connected=get_param(line,'SrcBlockHandle')~=-1;end
    record=struct('deleted_shared_source_disconnects_bias',~connected, ...
        'physical_model_simulated',false,'root_cause_proven',false);
    record.bias_line_handle=line;
    if connected,record.bias_source=getfullname(get_param(line,'SrcBlockHandle'));end
    record.explicit_rewire=explicit_rewire;
    if explicit_rewire,assert(connected && strcmp(record.bias_source,[model '/New']));end
    fid=fopen(fullfile(output_root,'shared_derivative_deletion.json'),'w');assert(fid>=0);
    c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',jsonencode(record));clear c
    disp(jsonencode(record));
end
