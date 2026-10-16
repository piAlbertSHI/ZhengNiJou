function record=Compare_HeatDriveECC_ObservationPackets(reference,candidate,path)
% Existing numerical trajectory tolerances, not a new physical steady gate.
    assert(~isfile(path));
    a=load(fullfile(reference,'observed_states.mat'),'observation');
    b=load(fullfile(candidate,'observed_states.mat'),'observation');
    states=Compare_HeatDriveECC_DiagnosticTraces(a.observation.states,b.observation.states);clear a b
    a=load(fullfile(reference,'native','observations.mat'),'native','source_traces','signals');
    b=load(fullfile(candidate,'native','observations.mat'),'native','source_traces','signals');
    native=Compare_HeatDriveECC_DiagnosticTraces(a.native,b.native);
    sources=Compare_HeatDriveECC_DiagnosticTraces(a.source_traces,b.source_traces);
    public=Compare_HeatDriveECC_DiagnosticTraces(as_traces(a.signals),as_traces(b.signals));
    record=struct('states',states,'native',native,'sources',sources,'public',public, ...
        'pass',states.pass && native.pass && sources.pass && public.pass, ...
        'comparison_scope','Actual matched samples; original diagnostic tolerances; no interpolation.');
    fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));
    assert(record.pass,'HeatDriveECC:CommandHorizonTrajectoryMismatch','Actual trajectories differ.');
end
function traces=as_traces(signals)
    names=fieldnames(signals);traces=cell(size(names));
    for k=1:numel(names)
        row=signals.(names{k});traces{k}=struct('block_path',names{k},'state_name','', ...
            'time_s',row.time_s,'values',row.values,'unit','');
    end
end
