function selected=Select_HeatDriveECC_TraceWindow(traces,start,stop)
% Select retained original samples. Never interpolate, shift or hold a value.
    assert(isfinite(start) && isfinite(stop) && start>=0 && stop>start);
    selected=traces;
    for k=1:numel(traces)
        row=traces{k};t=row.time_s(:);
        assert(size(row.values,1)==numel(t) && all(diff(t)>=0));
        tolerance=max(2e-14,8*eps(max(abs([start stop 1]))));
        assert(t(1)<=start+tolerance && t(end)>=stop-tolerance,'Bounded recording lost a required endpoint.');
        mask=t>=start-tolerance & t<=stop+tolerance;
        assert(any(mask) && abs(t(find(mask,1))-start)<=tolerance && ...
            abs(t(find(mask,1,'last'))-stop)<=tolerance,'No actual recorded window endpoint.');
        row.time_s=t(mask);row.values=row.values(mask,:);selected{k}=row;
    end
end
