function Test_HeatDriveECC_TraceColumns()
% Pure serializer test, not a physics gate or a restart checkpoint.
    t=(0:10)'*.001;
    a=struct('block_path','fixture/one','state_name','T','unit','K', ...
        'time_s',t,'values',[t -t],'channel_count',2);
    b=a;b.block_path='fixture/two';
    p=Pack_HeatDriveECC_TraceColumns({a,b});
    assert(numel(p.time_grids)==1 && all(cellfun(@(r)r.grid_index==1,p.rows)));
    b.time_s(2)=b.time_s(2)+eps(b.time_s(2));
    p=Pack_HeatDriveECC_TraceColumns({a,b});assert(numel(p.time_grids)==2);
    file=[tempname '.mat'];c=onCleanup(@() delete(file));save(file,'p','-v7');
    r=load(file,'p');assert(isequaln(p,r.p));
    assert(isequal(typecast(p.rows{1}.values(:),'uint64'),typecast(a.values(:),'uint64')));
end
