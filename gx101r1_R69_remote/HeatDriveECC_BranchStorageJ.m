function E = HeatDriveECC_BranchStorageJ(branch_state, options)
% Internal fluid storage for a finite-volume branch.

    E = options.branch.fluid_mass_kg * options.system.cp_fluid_J_per_kgK * ...
        branch_state.T_fluid_K;
end
