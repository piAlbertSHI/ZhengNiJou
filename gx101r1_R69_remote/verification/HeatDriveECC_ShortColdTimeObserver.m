function HeatDriveECC_ShortColdTimeObserver(block)
% Same stateless, process-local observer; 1 ms sampling for a 10 ms experiment.
    HeatDriveECC_ProcessLocalTimeObserver(block);
    block.SampleTimes=[.001 0];
end
