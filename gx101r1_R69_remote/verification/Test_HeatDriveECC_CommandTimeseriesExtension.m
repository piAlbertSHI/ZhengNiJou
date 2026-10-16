function result=Test_HeatDriveECC_CommandTimeseriesExtension()
% Synthetic command tests require neither a model nor an Operating Point.
    t=(0:.001:40).';u=double(mod(t,10)>=5);
    future=(0:.001:80).';v=double(mod(future,10)>=5);v(future<10)=7;
    old=timeseries([u,-u],t);generated=timeseries([v,-v],future);
    [actual,proof]=Extend_HeatDriveECC_CommandTimeseries(old,generated,10,20);
    assert(proof.prefix_and_interpolation_bracket_bitwise_equal && actual.Time(end)==80 && ...
        isequal(actual.Data(1:20002,:),old.Data(1:20002,:)));
    old=setinterpmethod(old,'zoh');generated=setinterpmethod(generated,'zoh');
    [actual,proof]=Extend_HeatDriveECC_CommandTimeseries(old,generated,10,20);
    assert(strcmp(getinterpmethod(actual),'zoh') && ~proof.resampling_used);
    a=timeseries([3;3],[0;40]);b=timeseries([3;3],[0;80]);
    [actual,proof]=Extend_HeatDriveECC_CommandTimeseries(a,b,10,20);
    assert(proof.constant_profile && isequal(actual.Time,[0;40;80]));
    rejected=0;
    try,Extend_HeatDriveECC_CommandTimeseries(old,generated,10,30);catch,rejected=rejected+1;end
    wrong=setinterpmethod(generated,'linear');
    try,Extend_HeatDriveECC_CommandTimeseries(old,wrong,10,20);catch,rejected=rejected+1;end
    try,Extend_HeatDriveECC_CommandTimeseries(old,old,10,20);catch,rejected=rejected+1;end
    assert(rejected==3);
    envelope=timeseries([0;.5;1;0],[0;1;2;3]);before=timeseries([1;1;0;1;1],(0:.75:3).');
    expected=double(before.Data).*interp1(envelope.Time,double(envelope.Data),before.Time,'linear');
    gate=Build_HeatDriveECC_CoherentReferenceCommand(envelope,before);
    target=Build_HeatDriveECC_CoherentReferenceCommand(envelope,before,.03);
    assert(isequal(gate.Time,before.Time) && isequal(gate.Data,expected));
    assert(isequal(target.Time,envelope.Time) && isequal(target.Data,.03*double(envelope.Data)));
    result=struct('cases_passed',8,'model_loaded',false,'simulation_executed',false);
    fprintf('COMMAND_EXTENSION_TEST_JSON=%s\n',jsonencode(result));
end
