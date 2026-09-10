function record=Probe_HeatDriveECC_FailureExporter(repo,out)
% Verify the serializer against an actual short Simscape log, not a plant run.
    assert(~isfolder(out));mkdir(out);
    build=fullfile(repo,'outputs_storage_audit','pre_feedback_bridge_no_reference_reset_20260910','component_build');
    oldpath=path;pc=onCleanup(@() path(oldpath));addpath(build);load_system('ecc_bridge_probe_lib');
    blocks=find_system('ecc_bridge_probe_lib','SearchDepth',1,'Type','Block');assert(isscalar(blocks));
    model='ecc_export_fixture';new_system(model);mc=onCleanup(@() close_system(model,0));
    add_block(blocks{1},[model '/Consumer']);
    add_block('simulink/Sources/Constant',[model '/Input'],'Value','1');
    add_block('nesl_utility/Simulink-PS Converter',[model '/PS'],'Unit','MPa');
    add_block('nesl_utility/Solver Configuration',[model '/Solver'],'UseLocalSolver','off');
    add_line(model,'Input/1','PS/1');
    simscape.addConnection([model '/PS'],port([model '/PS']),[model '/Consumer'],'p');
    simscape.addConnection([model '/PS'],port([model '/PS']),[model '/Solver'],port([model '/Solver']));
    add_block('simulink/Sinks/To Workspace',[model '/SignalLog'],'VariableName','fixture_signal','SaveFormat','Timeseries');
    add_line(model,'Input/1','SignalLog/1');
    set_param(model,'Solver','ode23t','StopTime','0.001','MaxStep','0.0001','ReturnWorkspaceOutputs','on', ...
        'SimscapeLogType','all','SimscapeLogName','simlog','SaveState','on','StateSaveName','states');
    output=sim(model);metadata=struct('storage_blocks',{{struct('block_path',[model '/Consumer'])}});
    destination=fullfile(out,'fixture_export.mat');
    exported=Export_HeatDriveECC_FailedColdObservations(output,model,metadata,destination);
    saved=load(destination);node=simscape.logging.findNode(output.simlog,[model '/Consumer']);
    assert(exported.native_leaf_count>0 && isempty(exported.native_read_errors));
    for k=1:numel(saved.native)
        row=saved.native{k};series=node.child(row.state_name).series;
        times=double(time(series));assert(isequal(row.time_s,times(:)));
        data=double(values(series));assert(isequal(row.values,reshape(data,numel(row.time_s),[])));
    end
    assert(isequal(saved.signals.fixture_signal.values,output.fixture_signal.Data));
    assert(~saved.record.valid_simulation && ~saved.record.production_recovery_allowed);
    record=struct('serializer_fixture_pass',true,'full_plant_run',false,'native_leaf_count',exported.native_leaf_count, ...
        'collection_seconds',exported.collection_seconds,'full_plant_speedup_measured',false);
    fid=fopen(fullfile(out,'exporter_probe.json'),'w');assert(fid>=0);fc=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record));clear fc;disp(jsonencode(record));
end

function name=port(block)
    p=simscape.connectionPortProperties(block);assert(isscalar(p));name=p.Name;
end
