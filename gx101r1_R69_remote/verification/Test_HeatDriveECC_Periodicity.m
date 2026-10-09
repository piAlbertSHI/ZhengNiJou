function record = Test_HeatDriveECC_Periodicity(output_file)
% Counterexamples preserve the ten-cycle guard, exchanger coverage and phase extrema.
    assert(~isfile(output_file),'Never overwrite a regression receipt.');
    options=struct('cycle_count',10,'schedule',struct('tau_cycle_s',10, ...
        'stage_start_s',[0,2.5,5,7.5],'stage_end_s',[2.5,5,7.5,10]));
    t=(0:.001:100).';
    physical=struct('time_s',t,'cycle_index',HeatDriveECC_CycleStageFromTime(t,options), ...
        'SMA_T_21_K',300*ones(numel(t),21),'SE_T_21_K',300*ones(numel(t),21), ...
        'SHEX_T_K',300*ones(size(t)),'HHEX_T_K',300*ones(size(t)),'CHEX_T_K',300*ones(size(t)), ...
        'xM_SMA_21',.5*ones(numel(t),21),'xM_SE_21',.5*ones(numel(t),21));
    p=Evaluate_HeatDriveECC_Periodicity(physical,options);assert(p.periodic_steady_state);
    short=options;short.cycle_count=2;
    mask=t<=20;pair=physical;names=fieldnames(pair);
    for k=1:numel(names),pair.(names{k})=pair.(names{k})(mask,:);end
    pair.cycle_index=HeatDriveECC_CycleStageFromTime(pair.time_s,short);
    p=Evaluate_HeatDriveECC_Periodicity(pair,short);assert(~p.periodic_steady_state && p.periodic_window_cycles==2);
    exchanger=physical;exchanger.CHEX_T_K=300+.006*t;
    p=Evaluate_HeatDriveECC_Periodicity(exchanger,options);
    assert(~p.periodic_steady_state && p.last_cycle_endpoint_drift_K>p.periodic_endpoint_limit_K);
    extrema=physical;
    waveform=.5+.01*floor(t/10).*sin(2*pi*mod(t,10)/10);
    extrema.xM_SE_21=repmat(waveform,1,21);
    p=Evaluate_HeatDriveECC_Periodicity(extrema,options);
    last=find(physical.cycle_index==10,1,'last');previous=find(physical.cycle_index==9,1,'last');
    assert(abs(waveform(last)-waveform(previous))<p.periodic_phase_limit && ...
        p.last_cycle_phase_drift>p.periodic_phase_limit && ~p.periodic_steady_state);
    record=struct('schema','heatdrive_ecc_periodic_statistic_regression_v1', ...
        'constant_ten_cycles_pass',true,'constant_pair_not_promoted',true, ...
        'exchanger_drift_blocks',true,'phase_extrema_not_replaced_by_endpoint',true, ...
        'simulation_executed',false,'operating_point_loaded',false,'physical_tolerances_changed',false);
    fid=fopen(output_file,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'%s\n',jsonencode(record,'PrettyPrint',true));fprintf('%s\n',jsonencode(record));
end
