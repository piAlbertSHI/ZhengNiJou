function command=Build_HeatDriveECC_CoherentReferenceCommand(envelope,before,nominal)
% Shared numeric closure for actual model construction and future commands.
    if nargin==3
        command=timeseries(nominal*double(envelope.Data),envelope.Time);
    else
        alpha=interp1(envelope.Time,double(envelope.Data),before.Time,'linear');
        command=timeseries(double(before.Data).*alpha,before.Time);
    end
end
