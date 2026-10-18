function y=HeatDriveECC_ConstitutiveStateVectorStep21_KernelCandidate(u)
% Explicit independent diagnostic backend, not a replacement of the original.
    options=evalin('base','EIGHTH_ROUND_OPTIONS');
    y=HeatDriveECC_StableKernelCandidate(u,options);
end
