function HeatDriveECC_ShortColdTimeObserver(block)
% Same stateless process-local observer; 1 ms samples for bounded cold probes.
    HeatDriveECC_ProcessLocalTimeObserver(block);
    block.SampleTimes=[.001 0];
end
