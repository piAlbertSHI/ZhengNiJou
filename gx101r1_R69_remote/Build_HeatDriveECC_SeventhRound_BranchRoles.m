function roles = Build_HeatDriveECC_SeventhRound_BranchRoles(options)
% Four independent physical branch roles for the seventh-round ECC model.

    T0 = options.system.T0_K;
    Tc = options.system.Tc_K;
    Th = options.system.Th_K;
    roles = [
        role_struct('SMA_SHEX', 1, 'SMA', Th, T0, 'source_to_solid')
        role_struct('SMA_THE', 3, 'SMA', T0, Th - 3.0, 'solid_to_sink')
        role_struct('SE_THE', 2, 'SE', T0, T0 + 7.0, 'solid_to_sink')
        role_struct('SE_RHE', 4, 'SE', Tc, Tc - 5.0, 'source_to_solid')];
end

function role = role_struct(name, active_stage, solid, boundary_T_K, preflight_solid_T_K, heat_role)
    role = struct('name', name, 'active_stage', active_stage, ...
        'solid', solid, 'boundary_T_K', boundary_T_K, ...
        'preflight_solid_T_K', preflight_solid_T_K, ...
        'heat_role', heat_role);
end
