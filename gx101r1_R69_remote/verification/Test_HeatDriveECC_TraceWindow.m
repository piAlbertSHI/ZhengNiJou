function Test_HeatDriveECC_TraceWindow()
    t=(0:20000)'*.001;
    row=struct('block_path','fixture','state_name','T','unit','K','time_s',t, ...
        'values',[t -t],'channel_count',2);
    selected=Select_HeatDriveECC_TraceWindow({row},10,20);s=selected{1};
    assert(isequal(typecast(s.time_s,'uint64'),typecast(t(10001:end),'uint64')) && ...
        isequal(typecast(s.values(:),'uint64'),typecast(reshape(row.values(10001:end,:),[],1),'uint64')));
    row.time_s=t(10002:end);row.values=row.values(10002:end,:);
    failed=false;
    try,Select_HeatDriveECC_TraceWindow({row},10,20);catch,failed=true;end
    assert(failed,'An absent endpoint must not be fabricated.');
end
