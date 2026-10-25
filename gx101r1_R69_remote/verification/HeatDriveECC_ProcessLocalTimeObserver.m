function HeatDriveECC_ProcessLocalTimeObserver(block)
% Stateless observer whose output directory is outside the physical OP contract.
    block.NumDialogPrms=0;
    block.NumInputPorts=0;block.NumOutputPorts=0;block.NumContStates=0;
    block.SampleTimes=[1 0];block.SimStateCompliance='HasNoSimState';
    block.SetSimViewingDevice(true);
    block.RegBlockMethod('Start',@start);
    block.RegBlockMethod('Outputs',@observe);
    block.RegBlockMethod('Terminate',@terminate);
end

function start(block)
    model=bdroot(block.BlockHandle);s=HeatDriveECC_ObserverContext('get',model);
    assert(~s.started && ~s.terminated);s.started=true;s.clock=tic;
    HeatDriveECC_ObserverContext('put',model,s);record(block,'solver_started',false);
end

function observe(block)
    s=HeatDriveECC_ObserverContext('get',bdroot(block.BlockHandle));
    if block.CurrentTime>s.last_time,record(block,'solver_time_sample',true);end
end

function terminate(block)
    record(block,'solver_terminated_not_yet_validated',false);
    model=bdroot(block.BlockHandle);s=HeatDriveECC_ObserverContext('get',model);
    s.terminated=true;HeatDriveECC_ObserverContext('put',model,s);
end

function record(block,phase,is_sample)
    model=bdroot(block.BlockHandle);s=HeatDriveECC_ObserverContext('get',model);
    s.last_time=double(block.CurrentTime);s.sample_count=s.sample_count+double(is_sample);
    HeatDriveECC_ObserverContext('put',model,s);
    evidence=struct('schema','heatdrive_ecc_process_local_time_observer_v1', ...
        'process_pid',s.process_pid,'run_id',s.run_id,'phase',phase, ...
        'simulation_time_s',s.last_time,'wall_elapsed_s',toc(s.clock), ...
        'sample_count',s.sample_count,'simulation_completed',false, ...
        'production_recovery_allowed',false);
    value=jsonencode(evidence);
    fid=fopen([s.path 'l'],'a','n','UTF-8');assert(fid>=0);
    c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',value);clear c
    fid=fopen([s.path '.tmp'],'w','n','UTF-8');assert(fid>=0);
    c=onCleanup(@() fclose(fid));fprintf(fid,'%s\n',value);clear c
    [ok,message]=movefile([s.path '.tmp'],s.path,'f');assert(ok,'%s',message);
end
