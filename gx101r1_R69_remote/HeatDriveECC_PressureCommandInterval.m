function interval = HeatDriveECC_PressureCommandInterval(datum, p_min, p_max, margin, requested, reference_port, reference_head)
% Native source B.p-A.p=P; account for the named reference face and head budget.
    if nargin<6,reference_port='A';end
    if nargin<7,reference_head=0;end
    assert(ismember(reference_port,{'A','B'}),'Require an explicitly named source reference port.');
    validateattributes(reference_head,{'numeric'},{'scalar','finite','real','nonnegative'});
    validateattributes([datum,p_min,p_max,margin,requested(:).'], {'numeric'}, {'finite','real'});
    assert(isscalar(datum) && isscalar(p_min) && isscalar(p_max) && ...
        isscalar(margin) && numel(requested)==2 && margin>0 && p_max>p_min && ...
        requested(1)<requested(2), 'Invalid pressure domain interval.');
    assert(datum-reference_head>p_min+margin && datum+reference_head<p_max-margin, ...
        'Network datum lacks declared domain headroom.');
    if strcmp(reference_port,'A')
        domain_interval=[p_min+margin-datum+reference_head,p_max-margin-datum-reference_head];
    else
        domain_interval=[datum+reference_head-p_max+margin,datum-reference_head-p_min-margin];
    end
    interval = [max(requested(1),domain_interval(1)),min(requested(2),domain_interval(2))];
    assert(interval(1)<interval(2) && interval(1)<0 && interval(2)>=0, ...
        'No admissible signed pumping interval in the declared domain.');
end
