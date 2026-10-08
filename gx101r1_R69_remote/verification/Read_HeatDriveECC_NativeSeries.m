function [t, data, unit, timing] = Read_HeatDriveECC_NativeSeries(leaf)
% Read the native time/data once; querying series.points duplicates costly access.
    total=tic; started=tic; series=leaf.series;
    timing.series_access_s=toc(started);
    t=[]; data=[]; unit='';
    timing.points_access_s=0;
    timing.time_access_s=0; timing.values_access_s=0; timing.unit_access_s=0;
    timing.reshape_s=0;
    if ~isempty(series)
        started=tic; t=double(time(series)); timing.time_access_s=toc(started);
    end
    points=numel(t);
    if points>0
        started=tic; raw=double(values(series)); timing.values_access_s=toc(started);
        started=tic; data=reshape(raw,numel(t),[]); timing.reshape_s=toc(started);
        started=tic; unit=series.unit; timing.unit_access_s=toc(started);
    end
    timing.points=points; timing.total_s=toc(total);
end
