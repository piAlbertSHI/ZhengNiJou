function row=Build_HeatDriveECC_L8Case(index)
% Existing six-factor orthogonal design, plus a nominal cold control at index zero.
    validateattributes(index,{'numeric'},{'scalar','integer','>=',0,'<=',8});
    levels=[-1 -1 -1 -1 -1 -1;-1 -1 -1 1 1 1;-1 1 1 -1 -1 1;-1 1 1 1 1 -1; ...
        1 -1 1 -1 1 -1;1 -1 1 1 -1 1;1 1 -1 -1 1 1;1 1 -1 1 -1 -1];
    assert(isequal(levels'*levels,8*eye(6)) && all(sum(levels)==0));
    value=zeros(1,6);if index>0,value=levels(index,:);end
    fractions=[.05 .05 .10 .10 .03 .05];factors=1+fractions.*value;
    names={'UA_multiplier','endpoint_capacity_multiplier','SE_buffer_multiplier', ...
        'fluid_inventory_multiplier','regenerator_utilization_multiplier','latent_heat_multiplier'};
    row=struct('run_index',index,'levels',value,'fractions',fractions);
    for k=1:6,row.(names{k})=factors(k);end
end
