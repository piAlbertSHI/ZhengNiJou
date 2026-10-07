function [t, data, unit, timing] = Read_HeatDriveECC_NativeSeries(leaf)
% Measure opaque native API calls separately without changing their data.
    total=tic; started=tic; series=leaf.series;
    timing.series_access_s=toc(started);
    t=[]; data=[]; unit='';
    started=tic;
    if isempty(series),points=0;else,points=series.points;end
    timing.points_access_s=toc(started);
    timing.time_access_s=0; timing.values_access_s=0; timing.unit_access_s=0;
    timing.reshape_s=0;
    if points>0
        started=tic; t=double(time(series)); timing.time_access_s=toc(started);
        started=tic; raw=double(values(series)); timing.values_access_s=toc(started);
        started=tic; data=reshape(raw,numel(t),[]); timing.reshape_s=toc(started);
        started=tic; unit=series.unit; timing.unit_access_s=toc(started);
    end
    timing.points=points; timing.total_s=toc(total);
end
