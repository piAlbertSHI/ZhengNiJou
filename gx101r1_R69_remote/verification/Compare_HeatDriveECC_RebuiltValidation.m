function [pass,record]=Compare_HeatDriveECC_RebuiltValidation(before,after,applied_branch)
% A rebuild consumes applied pressure limits, not the first build's requests.
% Permit only that history-field replacement; compare every executable bound.
    field='pressure_command_domain_contract';
    record=struct('original_requested',struct(),'rebuilt_requested',struct(), ...
        'applied_pressure_bounds_unchanged',false,'other_validation_identical',false);
    pass=false;
    if ~isfield(before,field) || ~isfield(after,field),return;end
    a=before.(field);b=after.(field);
    expected=struct('fallback_min_MPa',applied_branch.pressure_pi_min_MPa, ...
        'sma_min_MPa',applied_branch.sma_pressure_pi_min_MPa, ...
        'se_min_MPa',applied_branch.se_pressure_pi_min_MPa, ...
        'maximum_MPa',applied_branch.pressure_pi_max_MPa);
    if ~isequaln(b.requested,expected),return;end
    % Require stored applied bounds to agree with the input branch as well.
    applied=struct('fallback_min_MPa',a.fallback_interval_MPa(1), ...
        'sma_min_MPa',a.sma_interval_MPa(1),'se_min_MPa',a.se_interval_MPa(1), ...
        'maximum_MPa',min([a.fallback_interval_MPa(2),a.sma_interval_MPa(2),a.se_interval_MPa(2)]));
    if ~isequaln(applied,expected),return;end
    record.original_requested=a.requested;record.rebuilt_requested=b.requested;
    b.requested=a.requested;after.(field)=b;
    record.applied_pressure_bounds_unchanged=isequaln(a,b);
    record.other_validation_identical=isequaln(before,after);
    pass=record.applied_pressure_bounds_unchanged && record.other_validation_identical;
end
