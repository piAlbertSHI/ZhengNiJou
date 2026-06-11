function branch_state = Initialize_HeatDriveECC_FiniteVolumeBranchState(role, options)
% Initialize finite-volume branch fluid state at its physical boundary.

    branch_state = struct();
    branch_state.name = role.name;
    branch_state.T_fluid_K = role.boundary_T_K;
    branch_state.fluid_mass_kg = options.branch.fluid_mass_kg;
end
